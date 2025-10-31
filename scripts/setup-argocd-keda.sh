#!/bin/bash

# Script para configurar ArgoCD para gestionar el escalado con KEDA
# Crea una aplicación separada de ArgoCD para no interferir con producción
set -e

echo "🚀 CONFIGURANDO ARGOCD PARA ESCALADO CON KEDA"
echo "=============================================="

cd "$(dirname "$0")/.."

# 1. Verificar prerequisitos
echo ""
echo "📋 VERIFICANDO PREREQUISITOS..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Cluster de Kubernetes no disponible"
    exit 1
fi

if ! kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    echo "❌ ArgoCD no está instalado"
    echo "Ejecuta primero: ./scripts/03-setup-argocd.sh"
    exit 1
fi

if ! kubectl get namespace keda >/dev/null 2>&1; then
    echo "❌ KEDA no está instalado"
    echo ""
    read -p "¿Deseas instalar KEDA ahora? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ./scripts/install-keda.sh
    else
        echo "❌ KEDA es requerido para el escalado inteligente"
        exit 1
    fi
fi

echo "✅ Prerequisitos verificados"

# 2. Limpiar aplicación anterior si existe
echo ""
echo "🧹 LIMPIANDO APLICACIÓN ANTERIOR..."
kubectl delete application demo-microservice-keda -n argocd --ignore-not-found=true
sleep 5

# 3. Crear aplicación de ArgoCD para KEDA
echo ""
echo "📝 CREANDO APLICACIÓN DE ARGOCD PARA KEDA..."

cat > /tmp/argocd-keda-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: demo-microservice-keda
  namespace: argocd
  labels:
    app: demo-microservice-keda
    managed-by: argocd
    type: scaling
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://github.com/Adan2804/demo-microservice.git'
    path: argocd-keda
    targetRevision: HEAD
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    automated:
      prune: true
      selfHeal: true
  revisionHistoryLimit: 10
EOF

kubectl apply -f /tmp/argocd-keda-app.yaml
rm -f /tmp/argocd-keda-app.yaml

echo "✅ Aplicación de ArgoCD creada"

# 4. Esperar sincronización
echo ""
echo "⏳ ESPERANDO SINCRONIZACIÓN..."
sleep 15

# 5. Forzar sync inicial
echo ""
echo "🔄 FORZANDO SINCRONIZACIÓN INICIAL..."
kubectl patch application demo-microservice-keda -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

sleep 10

# 6. Verificar estado
echo ""
echo "📊 VERIFICANDO ESTADO..."

echo ""
echo "Aplicación de ArgoCD:"
kubectl get application demo-microservice-keda -n argocd

echo ""
echo "Deployment:"
kubectl get deployment demo-microservice-keda 2>/dev/null || echo "Deployment aún no creado"

echo ""
echo "ScaledObject:"
kubectl get scaledobject demo-microservice-keda-scaler 2>/dev/null || echo "ScaledObject aún no creado"

echo ""
echo "HPA (creado por KEDA):"
kubectl get hpa 2>/dev/null || echo "HPA aún no creado"

# 7. Crear script de monitoreo
echo ""
echo "📝 CREANDO SCRIPT DE MONITOREO..."

cat > ./scripts/monitor-keda-scaling.sh << 'SCRIPT_EOF'
#!/bin/bash

# Script para monitorear el escalado con KEDA
set -e

echo "📊 MONITOREO DE ESCALADO CON KEDA"
echo "=================================="

while true; do
    clear
    echo "📊 MONITOREO DE ESCALADO CON KEDA"
    echo "=================================="
    echo ""
    echo "🕐 Hora Colombia: $(TZ='America/Bogota' date '+%H:%M:%S %d/%m/%Y')"
    echo ""
    
    echo "📦 PODS:"
    kubectl get pods -l app=demo-microservice-keda --no-headers 2>/dev/null | wc -l | xargs echo "  Pods actuales:"
    kubectl get deployment demo-microservice-keda -o jsonpath='{.spec.replicas}' 2>/dev/null | xargs echo "  Pods deseados:"
    echo ""
    
    echo "📊 SCALEDOBJECT:"
    kubectl get scaledobject demo-microservice-keda-scaler 2>/dev/null || echo "  No encontrado"
    echo ""
    
    echo "📈 HPA:"
    kubectl get hpa demo-microservice-keda-hpa 2>/dev/null || echo "  No encontrado"
    echo ""
    
    echo "💻 MÉTRICAS:"
    kubectl top pods -l app=demo-microservice-keda 2>/dev/null || echo "  Métricas no disponibles"
    echo ""
    
    echo "Actualizando en 10 segundos... (Ctrl+C para salir)"
    sleep 10
done
SCRIPT_EOF

chmod +x ./scripts/monitor-keda-scaling.sh

echo "✅ Script de monitoreo creado"

# 8. Resumen final
echo ""
echo "🎉 ARGOCD KEDA CONFIGURADO EXITOSAMENTE"
echo "======================================="
echo ""
echo "✅ Aplicación de ArgoCD: demo-microservice-keda"
echo "✅ Deployment: demo-microservice-keda"
echo "✅ Service: demo-microservice-keda"
echo "✅ ScaledObject: demo-microservice-keda-scaler"
echo ""
echo "📊 ARQUITECTURA:"
echo "• argocd-production → Aplicación principal (sin HPA)"
echo "• argocd-keda → Escalado inteligente (con KEDA)"
echo ""
echo "🌐 ACCESO A ARGOCD:"
echo "• URL: https://localhost:8081"
echo "• Aplicación principal: demo-microservice-istio"
echo "• Aplicación KEDA: demo-microservice-keda"
echo ""
echo "📊 MONITOREO:"
echo "• Ver estado: kubectl get application demo-microservice-keda -n argocd"
echo "• Ver pods: kubectl get pods -l app=demo-microservice-keda"
echo "• Ver ScaledObject: kubectl get scaledobject demo-microservice-keda-scaler"
echo "• Ver HPA: kubectl get hpa demo-microservice-keda-hpa"
echo "• Monitoreo continuo: ./scripts/monitor-keda-scaling.sh"
echo ""
echo "⏰ HORARIOS DE ESCALADO:"
echo "• 5:10 PM - 6:00 PM: 2 pods (downscale)"
echo "• 6:00 PM - 5:10 PM: 3 pods (upscale)"
echo "• Escalado adicional si CPU/Memoria > 70%"
echo ""
echo "🧪 PRUEBAS:"
echo "• Generar carga: kubectl run -it --rm load-generator --image=busybox --restart=Never -- /bin/sh"
echo "• Dentro del pod: while true; do wget -q -O- http://demo-microservice-keda/demo/info; done"
echo ""
echo "🗑️  PARA ELIMINAR:"
echo "• kubectl delete application demo-microservice-keda -n argocd"
