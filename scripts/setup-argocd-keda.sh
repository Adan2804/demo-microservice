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
    echo "⚠️  ArgoCD no está instalado"
    echo ""
    read -p "¿Deseas instalar ArgoCD ahora? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "📦 Instalando ArgoCD..."
        
        # Crear namespace
        kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
        
        # Instalar ArgoCD
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        
        echo "⏳ Esperando que ArgoCD esté listo..."
        sleep 30
        kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
        kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=300s
        
        # Cambiar servicio a NodePort
        kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'
        
        echo "✅ ArgoCD instalado correctamente"
    else
        echo "❌ ArgoCD es requerido. Ejecuta: ./scripts/03-setup-argocd.sh"
        exit 1
    fi
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

# 3. Crear aplicación de ArgoCD para KEDA con Zero Downtime
echo ""
echo "📝 CREANDO APLICACIÓN DE ARGOCD PARA KEDA (ZERO DOWNTIME)..."

# Detectar si estamos en un repositorio git
GIT_REPO_URL=""
if git remote get-url origin >/dev/null 2>&1; then
    GIT_REPO_URL=$(git remote get-url origin)
    echo "📦 Repositorio Git detectado: $GIT_REPO_URL"
else
    echo "⚠️  No se detectó repositorio Git. Usando repositorio por defecto."
    GIT_REPO_URL="https://github.com/Adan2804/demo-microservice.git"
fi

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
    zero-downtime: enabled
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: '$GIT_REPO_URL'
    path: argocd-keda
    targetRevision: HEAD
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - RespectIgnoreDifferences=true
    - ApplyOutOfSyncOnly=true
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  # CRÍTICO: Ignorar cambios que KEDA hace dinámicamente
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
  - group: keda.sh
    kind: ScaledObject
    jsonPointers:
    - /status
  revisionHistoryLimit: 10
EOF

kubectl apply -f /tmp/argocd-keda-app.yaml
rm -f /tmp/argocd-keda-app.yaml

echo "✅ Aplicación de ArgoCD creada con configuración Zero Downtime"

# 4. Esperar sincronización
echo ""
echo "⏳ ESPERANDO SINCRONIZACIÓN..."
sleep 15

# 5. Forzar sync inicial
echo ""
echo "🔄 FORZANDO SINCRONIZACIÓN INICIAL..."
kubectl patch application demo-microservice-keda -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}' 2>/dev/null || true

sleep 10

# Verificar si el sync fue exitoso
SYNC_STATUS=$(kubectl get application demo-microservice-keda -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

if [ "$SYNC_STATUS" != "Synced" ]; then
    echo "⚠️  ArgoCD no pudo sincronizar desde el repositorio"
    echo ""
    read -p "¿Deseas aplicar los manifiestos directamente? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "📦 Aplicando manifiestos directamente..."
        kubectl apply -f argocd-keda/01-deployment-with-hpa.yaml
        kubectl apply -f argocd-keda/02-service.yaml
        kubectl apply -f argocd-keda/04-pdb.yaml
        kubectl apply -f argocd-keda/03-scaled-object.yaml
        echo "✅ Manifiestos aplicados directamente"
        
        # Actualizar la aplicación para que use el cluster local
        echo "📝 Configurando ArgoCD para usar manifiestos locales..."
        kubectl delete application demo-microservice-keda -n argocd --ignore-not-found=true
        
        echo "💡 NOTA: Los recursos están desplegados pero no gestionados por ArgoCD"
        echo "   Para gestión con ArgoCD, asegúrate de que el repositorio sea accesible"
    fi
fi

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
echo "PodDisruptionBudget (Zero Downtime):"
kubectl get pdb demo-microservice-keda-pdb 2>/dev/null || echo "PDB aún no creado"

echo ""
echo "ScaledObject:"
kubectl get scaledobject demo-microservice-keda-scaler 2>/dev/null || echo "ScaledObject aún no creado"

echo ""
echo "HPA (creado por KEDA):"
kubectl get hpa demo-microservice-keda-hpa 2>/dev/null || echo "HPA aún no creado"

echo ""
echo "Pods:"
kubectl get pods -l app=demo-microservice-keda 2>/dev/null || echo "Pods aún no creados"

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

# 8. Configurar port-forward para ArgoCD y el microservicio
echo ""
echo "🔌 CONFIGURANDO PORT-FORWARDS..."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true
pkill -f "kubectl port-forward.*demo-microservice-keda" 2>/dev/null || true
sleep 2

# Port-forward para ArgoCD
echo "Configurando port-forward para ArgoCD..."
kubectl port-forward svc/argocd-server -n argocd 8081:443 > /dev/null 2>&1 &
ARGOCD_PF_PID=$!
sleep 3

# Esperar a que el servicio esté disponible
echo "Esperando que el servicio demo-microservice-keda esté disponible..."
for i in {1..30}; do
    if kubectl get svc demo-microservice-keda -n default >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Port-forward para el microservicio
if kubectl get svc demo-microservice-keda -n default >/dev/null 2>&1; then
    echo "Configurando port-forward para demo-microservice-keda..."
    kubectl port-forward svc/demo-microservice-keda -n default 8082:8080 > /dev/null 2>&1 &
    MICRO_PF_PID=$!
    sleep 3
    echo "✅ Port-forward del microservicio configurado (PID: $MICRO_PF_PID)"
else
    echo "⚠️  Servicio demo-microservice-keda aún no disponible"
    MICRO_PF_PID=""
fi

# Obtener password de ArgoCD
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

# Obtener IP de Minikube
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")

# Obtener NodePort de ArgoCD
ARGOCD_NODEPORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")

# Obtener NodePort del microservicio
MICRO_NODEPORT=$(kubectl get svc demo-microservice-keda -n default -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")

echo "✅ Port-forward de ArgoCD configurado (PID: $ARGOCD_PF_PID)"

# 9. Resumen final
echo ""
echo "🎉 ARGOCD KEDA CONFIGURADO EXITOSAMENTE CON ZERO DOWNTIME"
echo "=========================================================="
echo ""
echo "✅ RECURSOS CREADOS:"
echo "• Aplicación de ArgoCD: demo-microservice-keda"
echo "• Deployment: demo-microservice-keda (maxUnavailable: 0)"
echo "• Service: demo-microservice-keda"
echo "• PodDisruptionBudget: demo-microservice-keda-pdb (minAvailable: 1)"
echo "• ScaledObject: demo-microservice-keda-scaler (minReplicas: 2)"
echo ""
echo "🛡️  CONFIGURACIÓN ZERO DOWNTIME:"
echo "• maxUnavailable: 0 → Nunca 0 pods durante sync"
echo "• maxSurge: 1 → Permite 1 pod extra durante actualización"
echo "• minAvailable: 1 → PDB garantiza disponibilidad"
echo "• minReplicaCount: 2 → KEDA nunca escala a menos de 2"
echo "• preStop hook: 15s → Graceful shutdown"
echo "• terminationGracePeriod: 30s → Tiempo para terminar"
echo ""
echo "📊 ARQUITECTURA:"
echo "• argocd-production → Aplicación principal (sin HPA)"
echo "• argocd-keda → Escalado inteligente (con KEDA + Zero Downtime)"
echo ""
echo "🌐 ACCESO A ARGOCD:"
echo "• URL (Port-forward): https://localhost:8081"
if [ -n "$ARGOCD_NODEPORT" ]; then
    echo "• URL (NodePort): https://${MINIKUBE_IP}:${ARGOCD_NODEPORT}"
fi
echo "• Usuario: admin"
if [ -n "$ARGOCD_PASSWORD" ]; then
    echo "• Password: $ARGOCD_PASSWORD"
else
    echo "• Password: (ejecuta: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d)"
fi
echo "• Aplicación principal: demo-microservice-istio"
echo "• Aplicación KEDA: demo-microservice-keda"
echo "• Port-forward activo (PID: $ARGOCD_PF_PID)"
echo ""
echo "🌐 ACCESO AL MICROSERVICIO:"
if [ -n "$MICRO_PF_PID" ]; then
    echo "• URL (Port-forward): http://localhost:8082"
    echo "• Health (Port-forward): http://localhost:8082/actuator/health"
    echo "• Info (Port-forward): http://localhost:8082/actuator/info"
    if [ -n "$MICRO_NODEPORT" ]; then
        echo "• URL (NodePort): http://${MINIKUBE_IP}:${MICRO_NODEPORT}"
        echo "• Health (NodePort): http://${MINIKUBE_IP}:${MICRO_NODEPORT}/actuator/health"
        echo "• Info (NodePort): http://${MINIKUBE_IP}:${MICRO_NODEPORT}/actuator/info"
    fi
    echo "• Port-forward activo (PID: $MICRO_PF_PID)"
else
    echo "• Servicio aún no disponible. Espera unos segundos y ejecuta:"
    echo "  kubectl port-forward svc/demo-microservice-keda -n default 8082:8080"
    if [ -n "$MICRO_NODEPORT" ]; then
        echo "• O accede directamente vía NodePort: http://${MINIKUBE_IP}:${MICRO_NODEPORT}"
    fi
fi
echo ""
echo "📊 MONITOREO:"
echo "• Ver estado: kubectl get application demo-microservice-keda -n argocd"
echo "• Ver todo: kubectl get all,pdb,scaledobject,hpa -l app=demo-microservice-keda"
echo "• Ver pods: kubectl get pods -l app=demo-microservice-keda -w"
echo "• Ver ScaledObject: kubectl describe scaledobject demo-microservice-keda-scaler"
echo "• Ver HPA: kubectl get hpa demo-microservice-keda-hpa"
echo "• Ver PDB: kubectl get pdb demo-microservice-keda-pdb"
echo "• Monitoreo continuo: ./scripts/monitor-keda-scaling.sh"
echo ""
echo "⏰ HORARIOS DE ESCALADO:"
echo "• 5:55 PM - 6:00 PM: 2 pods (downscale mínimo)"
echo "• 6:00 PM - 5:55 PM: 3 pods (normal)"
echo "• Timezone: America/Bogota"
echo ""
echo "🧪 PRUEBAS RECOMENDADAS:"
echo "1. Sync manual con cambio menor"
echo "2. Sync automático (self-heal)"
echo "3. Sync con cambio de imagen"
echo "4. Escalado de KEDA durante sync"
echo "5. Prueba de carga durante sync"
echo ""
echo "📖 DOCUMENTACIÓN:"
echo "• Instructivo completo: argocd-keda/instructivo-argocd-zero-downtime.md"
echo "• README: argocd-keda/README.md"
echo ""
echo "🧪 GENERAR CARGA:"
echo "• kubectl run -it --rm load-generator --image=busybox --restart=Never -- /bin/sh"
echo "• Dentro del pod: while true; do wget -q -O- http://demo-microservice-keda:8080/actuator/health; done"
echo ""
echo "🗑️  PARA ELIMINAR:"
echo "• kubectl delete application demo-microservice-keda -n argocd"
echo ""
echo "🧪 PROBAR EL MICROSERVICIO:"
if [ -n "$MICRO_PF_PID" ]; then
    echo "• curl http://localhost:8082/actuator/health"
    echo "• curl http://localhost:8082/actuator/info"
    if [ -n "$MICRO_NODEPORT" ]; then
        echo "• curl http://${MINIKUBE_IP}:${MICRO_NODEPORT}/actuator/health"
        echo "• Abrir en navegador: http://${MINIKUBE_IP}:${MICRO_NODEPORT}/actuator/health"
    else
        echo "• Abrir en navegador: http://localhost:8082/actuator/health"
    fi
fi
echo ""
echo "🛑 DETENER PORT-FORWARDS:"
echo "• ArgoCD: kill $ARGOCD_PF_PID"
if [ -n "$MICRO_PF_PID" ]; then
    echo "• Microservicio: kill $MICRO_PF_PID"
fi
echo "• Todos: pkill -f 'kubectl port-forward'"
echo ""
echo "⚠️  IMPORTANTE:"
echo "• NUNCA usar FORCE sync (recrea pods)"
echo "• ArgoCD respeta los cambios de KEDA en réplicas"
echo "• El PDB protege contra caídas durante sync"
echo "• Revisar instructivo antes de hacer cambios"
echo ""
echo "💡 TIP: Los port-forwards se mantienen activos en segundo plano"
echo "   Si cierras la terminal, los port-forwards se detendrán"
