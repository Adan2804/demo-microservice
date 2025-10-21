#!/bin/bash

# Script para configurar ArgoCD con SYNC MANUAL
# Para pruebas controladas sin auto-sync

APP_NAME="demo-microservice-versioned-app"
NAMESPACE="demo-app"
REPO_URL="https://github.com/Adan2804/demo-microservice.git"
REPO_PATH="k8s-versioned-manifests-processed"
TARGET_REVISION="HEAD"
ARGOCD_NAMESPACE="argocd"

echo "🚀 CONFIGURACIÓN DE ARGOCD - SYNC MANUAL"
echo "========================================="
echo ""

echo "📋 Configuración:"
echo "  • Nombre de aplicación: $APP_NAME"
echo "  • Namespace destino: $NAMESPACE"
echo "  • Repositorio: $REPO_URL"
echo "  • Path en repo: $REPO_PATH"
echo "  • Sync Mode: MANUAL (sin auto-sync)"
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
echo "📁 Creando namespace destino..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "✅ Namespace $NAMESPACE listo"

# Eliminar aplicación anterior si existe
echo "🧹 Limpiando aplicación anterior..."
kubectl delete application $APP_NAME -n $ARGOCD_NAMESPACE --ignore-not-found=true
kubectl delete application demo-microservice-app -n $ARGOCD_NAMESPACE --ignore-not-found=true
sleep 5

# Crear manifiesto de aplicación ArgoCD con SYNC MANUAL
echo "📝 Creando aplicación ArgoCD con sync manual..."

cat > /tmp/argocd-app-manual.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: $ARGOCD_NAMESPACE
  labels:
    app: demo-microservice-versioned
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
    # SYNC MANUAL - Comentado para evitar auto-sync
    # automated:
    #   prune: true
    #   selfHeal: true
    #   allowEmpty: false
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
    - /metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration
EOF

# Aplicar manifiesto
kubectl apply -f /tmp/argocd-app-manual.yaml
if [ $? -eq 0 ]; then
    echo "✅ Aplicación creada en ArgoCD (SYNC MANUAL)"
    rm -f /tmp/argocd-app-manual.yaml
else
    echo "❌ Error aplicando manifiesto de aplicación"
    rm -f /tmp/argocd-app-manual.yaml
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

if [ "$APP_STATUS" = "OutOfSync" ] || [ "$APP_STATUS" = "Unknown" ]; then
    echo "  ✅ Estado correcto para sync manual"
    echo "  La aplicación esperará sync manual"
else
    echo "  ℹ️  Estado: $APP_STATUS"
fi

# Configurar acceso a ArgoCD UI
echo ""
echo "🌐 Configurando acceso a ArgoCD UI..."

# Verificar si ya hay port-forward activo
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

if [ "$ARGOCD_PASSWORD" != "Ver documentación de ArgoCD" ]; then
    echo "✅ Credenciales obtenidas"
else
    echo "⚠️  No se pudieron obtener las credenciales automáticamente"
fi

# Crear scripts de gestión manual
echo ""
echo "📝 Creando scripts de gestión manual..."

# Script para sync manual
cat > ./scripts/manual-sync.sh << 'EOF'
#!/bin/bash
echo "🔄 SYNC MANUAL DE ARGOCD"
echo "========================"

APP_NAME="demo-microservice-versioned-app"
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
echo "✅ Sync manual completado"
EOF

chmod +x ./scripts/manual-sync.sh

# Script para ver estado
cat > ./scripts/check-status.sh << 'EOF'
#!/bin/bash
echo "📊 ESTADO DE ARGOCD"
echo "==================="

APP_NAME="demo-microservice-versioned-app"
ARGOCD_NAMESPACE="argocd"
NAMESPACE="demo-app"

echo ""
echo "🔍 Aplicación:"
kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o wide

echo ""
echo "📦 Recursos en el cluster:"
kubectl get all -n $NAMESPACE -l app=demo-microservice 2>/dev/null || echo "No hay recursos desplegados aún"

echo ""
echo "🌐 Services versionados:"
kubectl get svc -n $NAMESPACE -l app=demo-microservice 2>/dev/null || echo "No hay services versionados aún"

echo ""
echo "💡 Para hacer sync manual:"
echo "./scripts/manual-sync.sh"
EOF

chmod +x ./scripts/check-status.sh

echo "✅ Scripts de gestión creados"

# Resumen final
echo ""
echo "🎉 CONFIGURACIÓN MANUAL COMPLETADA"
echo "=================================="
echo ""

echo "✅ Aplicación '$APP_NAME' creada en ArgoCD"
echo "✅ Sync configurado como MANUAL"
echo "✅ Scripts de gestión creados"

echo ""
echo "🌐 Acceso a ArgoCD UI:"
echo "  • URL: https://localhost:8081"
echo "  • Usuario: admin"
echo "  • Password: $ARGOCD_PASSWORD"
echo "  • Aplicación: $APP_NAME"

echo ""
echo "🔧 FLUJO DE TRABAJO MANUAL:"
echo "  1. Generar manifiestos:"
echo "     ./scripts/deploy-versioned-release-manual.sh v-1-0-0"
echo "  2. Ver estado (debe mostrar OutOfSync):"
echo "     ./scripts/check-status.sh"
echo "  3. Hacer sync manual:"
echo "     ./scripts/manual-sync.sh"
echo "  4. Verificar deployment:"
echo "     ./scripts/test-version-routing.sh v-1-0-0"

echo ""
echo "📁 ARCHIVOS CREADOS:"
echo "  • scripts/manual-sync.sh - Sync manual"
echo "  • scripts/check-status.sh - Ver estado"

echo ""
echo "💡 VENTAJAS DEL SYNC MANUAL:"
echo "  • Control total sobre cuándo se aplican cambios"
echo "  • Puedes revisar diffs antes de aplicar"
echo "  • Ideal para pruebas y demos"
echo "  • Evita cambios inesperados durante presentaciones"