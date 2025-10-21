#!/bin/bash

# Script para configurar ArgoCD apuntando a argocd-production
# Para pruebas simples con sync manual

APP_NAME="demo-microservice-production"
NAMESPACE="default"
REPO_URL="https://github.com/Adan2804/demo-microservice.git"
REPO_PATH="argocd-production"
TARGET_REVISION="HEAD"
ARGOCD_NAMESPACE="argocd"

echo "🚀 CONFIGURACIÓN DE ARGOCD - PRODUCCIÓN"
echo "======================================="
echo ""

echo "📋 Configuración:"
echo "  • Nombre de aplicación: $APP_NAME"
echo "  • Namespace destino: $NAMESPACE"
echo "  • Repositorio: $REPO_URL"
echo "  • Path en repo: $REPO_PATH"
echo "  • Sync Mode: MANUAL"
echo ""

# Verificar conexión a Kubernetes y ArgoCD
echo "🔍 Verificando conexión a Kubernetes..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Error: No hay conexión al cluster"
    exit 1
fi

echo "🔍 Verificando ArgoCD..."
if ! kubectl get deployment argocd-server -n $ARGOCD_NAMESPACE >/dev/null 2>&1; then
    echo "❌ Error: ArgoCD no está instalado en el namespace $ARGOCD_NAMESPACE"
    exit 1
fi

echo "✅ Verificaciones OK"

# Crear namespace destino si no existe
echo "📁 Verificando namespace destino..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "✅ Namespace $NAMESPACE listo"

# Eliminar aplicación anterior si existe
echo "🧹 Limpiando aplicación anterior..."
kubectl delete application $APP_NAME -n $ARGOCD_NAMESPACE --ignore-not-found=true
kubectl delete application demo-microservice-versioned-app -n $ARGOCD_NAMESPACE --ignore-not-found=true
sleep 5

# Crear manifiesto de aplicación ArgoCD con SYNC MANUAL
echo "📝 Creando aplicación ArgoCD con sync manual..."

cat > /tmp/argocd-production-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: $ARGOCD_NAMESPACE
  labels:
    app: demo-microservice-production
    managed-by: argocd
    sync-mode: manual
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: '$REPO_URL'
    path: $REPO_PATH
    targetRevision: $TARGET_REVISION
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: $NAMESPACE
  syncPolicy:
    # SYNC MANUAL - Sin automated
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    - RespectIgnoreDifferences=true
    - ApplyOutOfSyncOnly=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 1m
  revisionHistoryLimit: 10
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /metadata/annotations/deployment.kubernetes.io~1revision
    - /spec/replicas
  - group: ""
    kind: Service
    jsonPointers:
    - /spec/clusterIP
    - /spec/clusterIPs
EOF

# Aplicar manifiesto
kubectl apply -f /tmp/argocd-production-app.yaml
if [ $? -eq 0 ]; then
    echo "✅ Aplicación creada en ArgoCD (SYNC MANUAL)"
    rm -f /tmp/argocd-production-app.yaml
else
    echo "❌ Error aplicando manifiesto de aplicación"
    rm -f /tmp/argocd-production-app.yaml
    exit 1
fi

# Verificar estado de la aplicación
echo ""
echo "🔍 Verificando estado de la aplicación..."
sleep 5

APP_STATUS=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
HEALTH_STATUS=$(kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

echo "📊 Estado de la aplicación:"
echo "  • Sync Status: $APP_STATUS"
echo "  • Health Status: $HEALTH_STATUS"

# Crear scripts de gestión manual
echo ""
echo "📝 Creando scripts de gestión manual..."

# Script para sync manual
cat > ./scripts/sync-production.sh << 'EOF'
#!/bin/bash
echo "🔄 SYNC MANUAL DE PRODUCCIÓN"
echo "============================"

APP_NAME="demo-microservice-production"
ARGOCD_NAMESPACE="argocd"

echo "📊 Estado actual:"
kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE

echo ""
echo "🚀 Ejecutando sync manual..."
kubectl patch application $APP_NAME -n $ARGOCD_NAMESPACE --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

echo ""
echo "⏳ Esperando sincronización..."
sleep 10

echo ""
echo "📊 Estado después del sync:"
kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE

echo ""
echo "📦 Pods desplegados:"
kubectl get pods -l app=demo-microservice-istio

echo ""
echo "✅ Sync manual completado"
EOF

chmod +x ./scripts/sync-production.sh

# Script para ver estado
cat > ./scripts/status-production.sh << 'EOF'
#!/bin/bash
echo "📊 ESTADO DE PRODUCCIÓN"
echo "======================="

APP_NAME="demo-microservice-production"
ARGOCD_NAMESPACE="argocd"

echo ""
echo "🔍 Aplicación ArgoCD:"
kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o wide

echo ""
echo "📦 Deployment:"
kubectl get deployment demo-microservice-production-istio -o wide 2>/dev/null || echo "Deployment no encontrado"

echo ""
echo "📦 Pods:"
kubectl get pods -l app=demo-microservice-istio

echo ""
echo "🌐 Services:"
kubectl get svc -l app=demo-microservice-istio 2>/dev/null || echo "No hay services"

echo ""
echo "💡 Para hacer sync manual:"
echo "./scripts/sync-production.sh"
EOF

chmod +x ./scripts/status-production.sh

echo "✅ Scripts de gestión creados"

# Configurar acceso a ArgoCD UI
echo ""
echo "🌐 Configurando acceso a ArgoCD UI..."

if pgrep -f "kubectl.*port-forward.*argocd-server" >/dev/null; then
    echo "✅ Port-forward ya está activo"
else
    echo "🔌 Iniciando port-forward para ArgoCD..."
    kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8081:443 >/dev/null 2>&1 &
    sleep 3
    echo "✅ Port-forward iniciado en puerto 8081"
fi

# Obtener credenciales de ArgoCD
echo ""
echo "🔑 Obteniendo credenciales de ArgoCD..."

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "Ver documentación de ArgoCD")

# Resumen final
echo ""
echo "🎉 CONFIGURACIÓN DE PRODUCCIÓN COMPLETADA"
echo "========================================="
echo ""

echo "✅ Aplicación '$APP_NAME' creada en ArgoCD"
echo "✅ Apunta a directorio: $REPO_PATH"
echo "✅ Sync configurado como MANUAL"
echo "✅ Scripts de gestión creados"

echo ""
echo "🌐 Acceso a ArgoCD UI:"
echo "  • URL: https://localhost:8081"
echo "  • Usuario: admin"
echo "  • Password: $ARGOCD_PASSWORD"
echo "  • Aplicación: $APP_NAME"

echo ""
echo "🔧 FLUJO DE TRABAJO:"
echo "  1. Ver estado actual:"
echo "     ./scripts/status-production.sh"
echo "  2. Hacer sync inicial:"
echo "     ./scripts/sync-production.sh"
echo "  3. Modificar argocd-production/01-production-deployment-istio.yaml"
echo "  4. Hacer commit y push"
echo "  5. Sync manual otra vez:"
echo "     ./scripts/sync-production.sh"

echo ""
echo "📁 ARCHIVOS CREADOS:"
echo "  • scripts/sync-production.sh - Sync manual"
echo "  • scripts/status-production.sh - Ver estado"

echo ""
echo "🎯 PARA SIMULAR CAMBIOS:"
echo "  1. Editar: argocd-production/01-production-deployment-istio.yaml"
echo "  2. Cambiar: APP_VERSION, DEPLOYMENT_VERSION, imagen, etc."
echo "  3. Commit y push al repo"
echo "  4. Ejecutar: ./scripts/sync-production.sh"
echo "  5. Ver cambios: ./scripts/status-production.sh"