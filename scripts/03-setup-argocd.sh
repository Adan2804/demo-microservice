#!/bin/bash

# Script para configurar ArgoCD y gestionar el proyecto desde la interfaz web
set -e

echo "🚀 CONFIGURANDO ARGOCD PARA GESTIÓN DEL PROYECTO"
echo "================================================"

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  --skip-install      Saltar instalación de ArgoCD (si ya está instalado)"
    echo "  -h, --help          Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                  # Instalación completa"
    echo "  $0 --skip-install   # Solo configurar proyecto (ArgoCD ya instalado)"
}

# Valores por defecto
SKIP_INSTALL=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-install)
            SKIP_INSTALL=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Función para esperar que un deployment esté listo
wait_for_deployment() {
    local deployment=$1
    local namespace=${2:-default}
    echo "Esperando que $deployment esté listo en namespace $namespace..."
    kubectl wait --for=condition=available deployment/$deployment -n $namespace --timeout=300s
}

# 1. VERIFICAR DEPENDENCIAS
echo ""
echo "📋 VERIFICANDO DEPENDENCIAS..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Cluster de Kubernetes no disponible"
    echo "Ejecuta primero: minikube start"
    exit 1
fi

echo "✅ Kubernetes disponible"

# 2. INSTALAR ARGOCD (si no está instalado)
if [ "$SKIP_INSTALL" = false ]; then
    echo ""
    echo "🔧 INSTALANDO ARGOCD..."
    
    # Crear namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Verificar si ArgoCD ya está instalado
    if kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
        echo "✅ ArgoCD ya está instalado"
    else
        echo "Instalando ArgoCD..."
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        
        echo "Esperando que ArgoCD esté listo..."
        sleep 30
        wait_for_deployment argocd-server argocd
        wait_for_deployment argocd-repo-server argocd
        wait_for_deployment argocd-dex-server argocd
    fi
else
    echo ""
    echo "⏭️  SALTANDO INSTALACIÓN DE ARGOCD..."
    
    # Verificar que ArgoCD esté disponible
    if ! kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
        echo "❌ ArgoCD no está instalado. Ejecuta sin --skip-install"
        exit 1
    fi
    echo "✅ ArgoCD encontrado"
fi

# 3. CONFIGURAR ACCESO A ARGOCD
echo ""
echo "🔌 CONFIGURANDO ACCESO A ARGOCD..."

# Cambiar el servicio a NodePort para acceso fácil
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'

# Limpiar port-forwards existentes de ArgoCD
pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true
sleep 2

# Configurar port-forward para ArgoCD
echo "Configurando port-forward para ArgoCD..."
kubectl port-forward svc/argocd-server -n argocd 8081:443 > /dev/null 2>&1 &
ARGOCD_PF_PID=$!

sleep 5

# 4. OBTENER CREDENCIALES
echo ""
echo "🔑 OBTENIENDO CREDENCIALES DE ARGOCD..."

# Obtener password inicial del admin
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "✅ Credenciales obtenidas"

# 5. CONFIGURAR ARGOCD PARA USAR ARCHIVOS DE PRODUCCIÓN
echo ""
echo "📝 CONFIGURANDO ARGOCD..."

echo "📋 ARQUITECTURA DE GESTIÓN:"
echo "=========================="
echo ""
echo "🏢 ArgoCD gestiona (SOLO producción estable):"
echo "• argocd-production/01-production-deployment-istio.yaml"
echo "• argocd-production/02-service-unified.yaml" 
echo "• argocd-production/03-destination-rule.yaml"
echo "• argocd-production/04-virtual-service.yaml"
echo ""
echo "🧪 Experimentos (FUERA de ArgoCD):"
echo "• Se crean dinámicamente con kubectl apply"
echo "• Usan archivos de istio/ (diferentes a argocd-production/)"
echo "• SOBRESCRIBEN temporalmente los recursos de ArgoCD"
echo "• ArgoCD los IGNORA por las anotaciones configuradas"
echo ""
echo "🔄 Flujo: ArgoCD despliega base → Experimento sobrescribe → Cleanup restaura base"

# Configurar ArgoCD para permitir repositorios locales
echo "Configurando ArgoCD para repositorios locales..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p='{"data":{"reposerver.enable.git.submodule":"true","reposerver.git.request.timeout":"60"}}'

# Reiniciar repo-server para aplicar cambios
kubectl rollout restart deployment/argocd-repo-server -n argocd
sleep 10

# Limpiar aplicaciones anteriores
kubectl delete application demo-microservice-experiment -n argocd --ignore-not-found=true
kubectl delete application demo-microservice-istio -n argocd --ignore-not-found=true

# Crear Application que apunta a argocd-production/
cat > /tmp/demo-microservice-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-microservice-istio
  namespace: argocd
  labels:
    app: demo-microservice
spec:
  project: default
  source:
    repoURL: 'https://github.com/Adan2804/demo-microservice.git'
    path: argocd-production
    targetRevision: HEAD
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    # NO auto-sync - Solo sincronización manual
EOF

echo "✅ Configuraciones creadas"

# 6. APLICAR CONFIGURACIONES A ARGOCD
echo ""
echo "🚀 APLICANDO CONFIGURACIONES A ARGOCD..."

# Esperar que ArgoCD esté completamente listo
echo "Esperando que ArgoCD esté completamente operativo..."
sleep 15

# Aplicar configuración temporal
kubectl apply -f /tmp/demo-microservice-app.yaml

# Verificar el estado de la aplicación con logs detallados
echo "Verificando estado de la aplicación en ArgoCD..."
sleep 10

# Forzar sincronización inmediata
echo "Forzando sincronización de la aplicación..."
kubectl patch application demo-microservice-istio -n argocd --type='merge' -p='{"operation":{"sync":{"revision":"HEAD"}}}'

echo "✅ Aplicaciones configuradas en ArgoCD"

# 7. CREAR SCRIPT DE GESTIÓN
echo ""
echo "📝 CREANDO SCRIPTS DE GESTIÓN..."

# Script para iniciar ArgoCD
cat > ./scripts/start-argocd.sh << 'EOF'
#!/bin/bash
echo "🚀 Iniciando ArgoCD Dashboard..."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true
sleep 2

# Iniciar port-forward
kubectl port-forward svc/argocd-server -n argocd 8081:443 > /dev/null 2>&1 &
ARGOCD_PF_PID=$!

echo "✅ ArgoCD Dashboard disponible en: https://localhost:8081"
echo "Port-forward activo (PID: $ARGOCD_PF_PID)"

# Mostrar credenciales
echo ""
echo "🔑 CREDENCIALES:"
echo "Usuario: admin"
echo "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
EOF

chmod +x ./scripts/start-argocd.sh

# Script para detener ArgoCD
cat > ./scripts/stop-argocd.sh << 'EOF'
#!/bin/bash
echo "🛑 Deteniendo ArgoCD Dashboard..."

# Detener port-forwards
pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true

echo "✅ ArgoCD Dashboard detenido"
EOF

chmod +x ./scripts/stop-argocd.sh

# 8. VERIFICAR ESTADO
echo ""
echo "🔍 VERIFICANDO ESTADO DE ARGOCD..."

echo "Pods de ArgoCD:"
kubectl get pods -n argocd

echo ""
echo "Aplicaciones en ArgoCD:"
kubectl get applications -n argocd

echo ""
echo "Estado detallado de la aplicación:"
kubectl get application demo-microservice-istio -n argocd -o jsonpath='{.status.sync.status}' && echo " (Sync Status)"
kubectl get application demo-microservice-istio -n argocd -o jsonpath='{.status.health.status}' && echo " (Health Status)"

echo ""
echo "Recursos gestionados por ArgoCD:"
kubectl get pods,svc,deployment -l app=demo-microservice-istio

# 9. RESUMEN FINAL
echo ""
echo "🎉 ARGOCD CONFIGURADO EXITOSAMENTE"
echo "=================================="
echo ""
echo "✅ ArgoCD instalado y funcionando"
echo "✅ Aplicaciones configuradas"
echo "✅ Port-forward activo"
echo ""
echo "🌐 ACCESO A ARGOCD:"
echo "• URL: https://localhost:8081"
echo "• Usuario: admin"
echo "• Password: $ARGOCD_PASSWORD"
echo ""
echo "📱 APLICACIONES CONFIGURADAS:"
echo "• demo-microservice-istio (Solo producción estable)"
echo "• Experimentos se gestionan FUERA de ArgoCD (como en la empresa)"
echo ""
echo "🛠️  GESTIÓN:"
echo "• Iniciar ArgoCD: ./scripts/start-argocd.sh"
echo "• Detener ArgoCD: ./scripts/stop-argocd.sh"
echo ""
echo "📁 ARCHIVOS CREADOS:"
echo "• scripts/start-argocd.sh - Iniciar dashboard"
echo "• scripts/stop-argocd.sh - Detener dashboard"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Abrir https://localhost:8081 en tu navegador"
echo "2. Iniciar sesión con las credenciales mostradas"
echo "3. Crear experimentos: ./scripts/01-create-experiment.sh"
echo "4. Promover a rollout: ./scripts/02-promote-to-rollout.sh"
echo ""
echo "🏢 SIMULACIÓN EMPRESARIAL:"
echo "• ArgoCD gestiona SOLO producción estable"
echo "• Experimentos se crean/eliminan dinámicamente SIN ArgoCD"
echo "• Esto simula el comportamiento real de Bancolombia"
echo ""
echo "💡 NOTA:"
echo "ArgoCD gestiona solo aplicaciones estables."
echo "Los experimentos se manejan externamente (como en la empresa)."
echo ""
echo "Port-forward activo (PID: $ARGOCD_PF_PID)"