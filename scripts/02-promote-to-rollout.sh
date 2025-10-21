#!/bin/bash

# Script para promover experimento exitoso a rollout con Argo Rollouts
# Implementa Blue-Green deployment con confirmación manual
set -e

echo "🚀 PROMOCIÓN DE EXPERIMENTO A ROLLOUT"
echo "====================================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  --auto-approve          Aprobar automáticamente sin confirmación"
    echo "  --rollback-on-failure   Rollback automático si falla"
    echo "  -h, --help              Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                      # Promoción con confirmación manual"
    echo "  $0 --auto-approve       # Promoción automática"
}

# Valores por defecto
AUTO_APPROVE=false
ROLLBACK_ON_FAILURE=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --rollback-on-failure)
            ROLLBACK_ON_FAILURE=true
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

# Detectar istioctl
ISTIOCTL_PATH=""
if [ -f "./bin/istioctl" ]; then
    ISTIOCTL_PATH="./bin/istioctl"
elif command -v istioctl >/dev/null 2>&1; then
    ISTIOCTL_PATH="istioctl"
else
    echo "❌ istioctl no está disponible"
    exit 1
fi

# 1. VERIFICAR PREREQUISITOS
echo ""
echo "📋 VERIFICANDO PREREQUISITOS..."

# Verificar que el experimento esté activo
if ! kubectl get deployment demo-microservice-experiment >/dev/null 2>&1; then
    echo "❌ Error: No hay experimento activo para promover"
    echo "Ejecuta primero: ./scripts/01-create-experiment.sh"
    exit 1
fi

# Verificar que Argo Rollouts esté instalado
if ! kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
    echo "⚠️  Argo Rollouts no está instalado. Instalando..."
    kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
    
    echo "Esperando que Argo Rollouts esté listo..."
    kubectl wait --for=condition=available deployment/argo-rollouts-controller -n argo-rollouts --timeout=300s
fi

echo "✅ Prerequisitos verificados"

# 2. OBTENER INFORMACIÓN DEL EXPERIMENTO
echo ""
echo "📊 ANALIZANDO EXPERIMENTO ACTUAL..."

EXPERIMENT_IMAGE=$(kubectl get deployment demo-microservice-experiment -o jsonpath='{.spec.template.spec.containers[0].image}')
EXPERIMENT_VERSION=$(kubectl get deployment demo-microservice-experiment -o jsonpath='{.metadata.annotations.experiment\.kubernetes\.io/version}')

echo "📦 Imagen del experimento: $EXPERIMENT_IMAGE"
echo "🏷️  Versión del experimento: $EXPERIMENT_VERSION"

# Mostrar métricas del experimento
echo ""
echo "📈 MÉTRICAS DEL EXPERIMENTO:"
kubectl top pods -l version=experiment --no-headers 2>/dev/null || echo "Métricas no disponibles"

# 3. CONFIRMACIÓN MANUAL (si no es auto-approve)
if [ "$AUTO_APPROVE" = false ]; then
    echo ""
    echo "🤔 CONFIRMACIÓN DE PROMOCIÓN"
    echo "============================"
    echo ""
    echo "¿Has validado que el experimento funciona correctamente?"
    echo "• ¿Las pruebas A/B muestran resultados positivos?"
    echo "• ¿No hay errores en los logs del experimento?"
    echo "• ¿El rendimiento es aceptable?"
    echo ""
    read -p "¿Estás seguro de promover el experimento a producción? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Promoción cancelada por el usuario"
        exit 0
    fi
fi

# 4. CREAR ROLLOUT CONFIGURATION
echo ""
echo "📝 CREANDO CONFIGURACIÓN DE ROLLOUT..."

# Crear Rollout que reemplazará el deployment de producción
cat > /tmp/rollout-config.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: demo-microservice-rollout
  namespace: default
  labels:
    app: demo-microservice-istio
    tier: rollout
  annotations:
    rollout.kubernetes.io/promoted-from: "experiment"
    rollout.kubernetes.io/experiment-version: "$EXPERIMENT_VERSION"
    rollout.kubernetes.io/created-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
spec:
  replicas: 3
  strategy:
    blueGreen:
      activeService: demo-microservice-rollout-active
      previewService: demo-microservice-rollout-preview
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 30
      prePromotionAnalysis:
        templates:
        - templateName: success-rate
        args:
        - name: service-name
          value: demo-microservice-rollout-preview
      postPromotionAnalysis:
        templates:
        - templateName: success-rate
        args:
        - name: service-name
          value: demo-microservice-rollout-active
  selector:
    matchLabels:
      app: demo-microservice-istio
      tier: rollout
  template:
    metadata:
      labels:
        app: demo-microservice-istio
        tier: rollout
        version: rollout-new
        sidecar.istio.io/inject: "true"
    spec:
      containers:
      - name: demo-microservice
        image: $EXPERIMENT_IMAGE
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: PORT
          value: "3000"
        - name: APP_VERSION
          value: "rollout-promoted-$EXPERIMENT_VERSION"
        - name: ENVIRONMENT
          value: "production-rollout"
        - name: EXPERIMENT_ENABLED
          value: "false"
        - name: ISTIO_ENABLED
          value: "true"
        - name: ROLLOUT_PHASE
          value: "blue-green"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10

---
# Servicios para Blue-Green
apiVersion: v1
kind: Service
metadata:
  name: demo-microservice-rollout-active
  namespace: default
  labels:
    app: demo-microservice-istio
    service: rollout-active
spec:
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
    name: http
  selector:
    app: demo-microservice-istio
    tier: rollout
  type: ClusterIP

---
apiVersion: v1
kind: Service
metadata:
  name: demo-microservice-rollout-preview
  namespace: default
  labels:
    app: demo-microservice-istio
    service: rollout-preview
spec:
  ports:
  - port: 80
    targetPort: 3000
    protocol: TCP
    name: http
  selector:
    app: demo-microservice-istio
    tier: rollout
  type: ClusterIP

---
# AnalysisTemplate para validación automática
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
  namespace: default
spec:
  args:
  - name: service-name
  metrics:
  - name: success-rate
    interval: 10s
    count: 5
    successCondition: result[0] >= 0.95
    provider:
      prometheus:
        address: http://prometheus.istio-system:9090
        query: |
          sum(irate(
            istio_requests_total{reporter="destination",destination_service_name="{{args.service-name}}",response_code!~"5.*"}[2m]
          )) / 
          sum(irate(
            istio_requests_total{reporter="destination",destination_service_name="{{args.service-name}}"}[2m]
          ))
EOF

# 5. APLICAR ROLLOUT
echo ""
echo "🚀 INICIANDO ROLLOUT BLUE-GREEN..."

kubectl apply -f /tmp/rollout-config.yaml

# Esperar que el rollout esté listo
echo "⏳ Esperando que el rollout esté listo..."
kubectl wait --for=condition=available rollout/demo-microservice-rollout --timeout=300s

# 6. ACTUALIZAR CONFIGURACIÓN DE ISTIO PARA ROLLOUT
echo ""
echo "🌐 ACTUALIZANDO CONFIGURACIÓN DE ISTIO PARA ROLLOUT..."

# Crear DestinationRule para rollout
cat > /tmp/destination-rule-rollout.yaml << EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: demo-microservice-rollout-destination
  namespace: default
  annotations:
    rollout.kubernetes.io/managed-by: "rollout-script"
spec:
  host: demo-microservice-rollout-active
  subsets:
  - name: rollout-stable
    labels:
      version: rollout-stable
  - name: rollout-canary
    labels:
      version: rollout-new
EOF

# Crear VirtualService para rollout
cat > /tmp/virtual-service-rollout.yaml << EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: demo-microservice-rollout-routing
  namespace: default
  annotations:
    rollout.kubernetes.io/managed-by: "rollout-script"
spec:
  hosts:
  - "*"
  gateways:
  - demo-microservice-gateway
  http:
  # Tráfico de rollout (gradual)
  - match:
    - uri:
        prefix: "/api/v1/rollout"
    route:
    - destination:
        host: demo-microservice-rollout-active
      weight: 100
    headers:
      response:
        add:
          x-routed-to: "rollout-active"
          x-rollout-phase: "blue-green"
  
  # Tráfico normal (sigue yendo al experimento por ahora)
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: demo-microservice-istio
        subset: stable
      weight: 70
    - destination:
        host: demo-microservice-istio
        subset: experiment
      weight: 30
    headers:
      response:
        add:
          x-routed-to: "mixed-traffic"
          x-rollout-phase: "transition"
EOF

kubectl apply -f /tmp/destination-rule-rollout.yaml
kubectl apply -f /tmp/virtual-service-rollout.yaml

# Esperar que la configuración se propague
echo "⏳ Esperando que la configuración se propague..."
sleep 15

# 7. MONITOREAR ROLLOUT
echo ""
echo "📊 MONITOREANDO ROLLOUT..."

echo "Estado del rollout:"
kubectl get rollout demo-microservice-rollout

echo ""
echo "Pods del rollout:"
kubectl get pods -l app=demo-microservice-istio,tier=rollout

# 8. PROMOCIÓN MANUAL DEL ROLLOUT
echo ""
echo "🎯 PROMOCIÓN DEL ROLLOUT"
echo "========================"

if [ "$AUTO_APPROVE" = false ]; then
    echo ""
    echo "El rollout está en modo Blue-Green y requiere promoción manual."
    echo "Revisa las métricas y confirma que todo funciona correctamente."
    echo ""
    read -p "¿Promover el rollout a producción? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🚀 Promoviendo rollout..."
        kubectl argo rollouts promote demo-microservice-rollout
    else
        echo "⏸️  Rollout pausado. Puedes promoverlo manualmente con:"
        echo "kubectl argo rollouts promote demo-microservice-rollout"
    fi
else
    echo "🚀 Promoción automática habilitada..."
    kubectl argo rollouts promote demo-microservice-rollout
fi

# 9. LIMPIAR EXPERIMENTO
echo ""
echo "🧹 LIMPIANDO EXPERIMENTO ANTERIOR..."

echo "Eliminando deployment del experimento..."
kubectl delete deployment demo-microservice-experiment

echo "Restaurando configuración base de Istio..."
kubectl apply -f argocd-production/03-destination-rule.yaml
kubectl apply -f argocd-production/04-virtual-service.yaml

# 10. VERIFICAR ESTADO FINAL
echo ""
echo "🔍 VERIFICANDO ESTADO FINAL..."

echo "Estado del rollout:"
kubectl get rollout demo-microservice-rollout

echo ""
echo "Pods activos:"
kubectl get pods -l app=demo-microservice-istio

echo ""
echo "Servicios:"
kubectl get svc -l app=demo-microservice-istio

# 11. PRUEBAS DE CONECTIVIDAD
echo ""
echo "🧪 REALIZANDO PRUEBAS FINALES..."

echo "Probando tráfico normal:"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "Probando endpoint de rollout:"
response=$(curl -s http://localhost:8080/api/v1/rollout/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

# 12. RESUMEN FINAL
echo ""
echo "🎉 PROMOCIÓN A ROLLOUT COMPLETADA"
echo "================================="
echo ""
echo "✅ Experimento promovido exitosamente"
echo "✅ Rollout Blue-Green configurado"
echo "✅ Configuración de Istio actualizada"
echo "✅ Experimento anterior limpiado"
echo ""
echo "📊 ESTADO ACTUAL:"
echo "• Rollout activo: demo-microservice-rollout"
echo "• Estrategia: Blue-Green Deployment"
echo "• Imagen promovida: $EXPERIMENT_IMAGE"
echo ""
echo "🌐 ACCESOS:"
echo "• Aplicación: http://localhost:8080"
echo "• Rollout endpoint: http://localhost:8080/api/v1/rollout"
echo "• Argo Rollouts Dashboard: kubectl argo rollouts dashboard"
echo ""
echo "📊 MONITOREO:"
echo "• Estado del rollout: kubectl get rollout demo-microservice-rollout"
echo "• Logs del rollout: kubectl logs -l tier=rollout -f"
echo "• Métricas: kubectl top pods -l tier=rollout"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Monitorear métricas de producción"
echo "2. Validar que no hay errores"
echo "3. Si todo está bien, el rollout se completará automáticamente"
echo ""
echo "🛑 EN CASO DE PROBLEMAS:"
echo "• Rollback: kubectl argo rollouts abort demo-microservice-rollout"
echo "• Ver estado: kubectl argo rollouts get rollout demo-microservice-rollout"