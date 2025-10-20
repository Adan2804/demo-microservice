#!/bin/bash

# Script para crear experimento A/B Testing con Istio
# Versión mejorada que maneja mejor la configuración de Istio
set -e

echo "🧪 CREANDO EXPERIMENTO A/B TESTING CON ISTIO"
echo "============================================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  -v, --version VERSION    Versión del experimento (default: v1.1.0)"
    echo "  -i, --image IMAGE        Imagen Docker personalizada"
    echo "  -h, --help              Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                                    # Usar versión por defecto"
    echo "  $0 -v v2.0.0                        # Especificar versión"
    echo "  $0 -i myregistry/demo:latest         # Usar imagen personalizada"
}

# Valores por defecto
EXPERIMENT_VERSION="v1.1.0"
CUSTOM_IMAGE=""

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            EXPERIMENT_VERSION="$2"
            shift 2
            ;;
        -i|--image)
            CUSTOM_IMAGE="$2"
            shift 2
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

# 1. VERIFICAR PREREQUISITOS
echo ""
echo "📋 VERIFICANDO PREREQUISITOS..."

# Verificar que la aplicación base esté desplegada
if ! kubectl get deployment demo-microservice-production-istio >/dev/null 2>&1; then
    echo "❌ Error: Aplicación base no encontrada"
    echo "Ejecuta primero: ./scripts/00-init-minikube-istio.sh"
    exit 1
fi

# Verificar que Istio esté configurado
if ! kubectl get virtualservice demo-microservice-gateway-routing >/dev/null 2>&1; then
    echo "❌ Error: Configuración de Istio no encontrada"
    echo "Ejecuta primero: ./scripts/00-init-minikube-istio.sh"
    exit 1
fi

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

echo "✅ Prerequisitos verificados"

# 2. LIMPIAR EXPERIMENTOS ANTERIORES
echo ""
echo "🧹 LIMPIANDO EXPERIMENTOS ANTERIORES..."

# Eliminar deployment del experimento anterior
kubectl delete deployment demo-microservice-experiment --ignore-not-found=true

# Restaurar configuración base de Istio
echo "🔄 Restaurando configuración base de Istio..."
kubectl apply -f argocd-production/03-destination-rule.yaml
kubectl apply -f argocd-production/04-virtual-service.yaml

# Esperar que se propague la configuración
sleep 5

echo "✅ Limpieza completada"

# 3. CREAR DEPLOYMENT DEL EXPERIMENTO
echo ""
echo "🚀 CREANDO DEPLOYMENT DEL EXPERIMENTO..."

# Usar imagen que ya se creó en el script de inicialización
EXPERIMENT_IMAGE="demo-microservice:experiment-candidate-v1.1.0"
echo "📦 Imagen del experimento: $EXPERIMENT_IMAGE"

# Crear deployment del experimento
cat > /tmp/experiment-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-microservice-experiment
  namespace: default
  labels:
    app: demo-microservice-istio
    tier: experiment
    version: experiment
  annotations:
    # Experimento temporal - NO gestionado por ArgoCD
    kubernetes.io/managed-by: "kubectl"
    experiment.kubernetes.io/created-by: "experiment-script"
    experiment.kubernetes.io/version: "$EXPERIMENT_VERSION"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-microservice-istio
      tier: experiment
  template:
    metadata:
      labels:
        app: demo-microservice-istio
        tier: experiment
        traffic-type: experiment
        version: experiment
        sidecar.istio.io/inject: "true"
      annotations:
        # Anotaciones para experimento
        experiment.kubernetes.io/version: "$EXPERIMENT_VERSION"
        experiment.kubernetes.io/created-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
          value: "experiment-candidate-$EXPERIMENT_VERSION"
        - name: ENVIRONMENT
          value: "experiment-istio"
        - name: EXPERIMENT_ENABLED
          value: "true"
        - name: ISTIO_ENABLED
          value: "true"
        - name: EXPERIMENT_FEATURES
          value: "new-api,enhanced-ui,performance-boost"
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
EOF

kubectl apply -f /tmp/experiment-deployment.yaml

# Esperar que el deployment esté listo
echo "⏳ Esperando que el experimento esté listo..."
kubectl wait --for=condition=available deployment/demo-microservice-experiment --timeout=300s

echo "✅ Deployment del experimento creado"

# 4. ACTUALIZAR CONFIGURACIÓN DE ISTIO PARA EXPERIMENTO
echo ""
echo "🌐 ACTUALIZANDO CONFIGURACIÓN DE ISTIO PARA EXPERIMENTO..."

# Crear DestinationRule con subset para experimento
cat > /tmp/destination-rule-experiment.yaml << EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: demo-microservice-destination-rule
  namespace: default
  annotations:
    # Configuración temporal de experimento - ArgoCD la ignora
    argocd.argoproj.io/sync-options: Prune=false
    argocd.argoproj.io/compare-options: IgnoreExtraneous
    experiment.kubernetes.io/managed-by: "experiment-script"
spec:
  host: demo-microservice-unified
  subsets:
  - name: stable
    labels:
      version: stable
  - name: experiment
    labels:
      version: experiment
EOF

# Crear VirtualService con enrutamiento por headers
cat > /tmp/virtual-service-experiment.yaml << EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: demo-microservice-gateway-routing
  namespace: default
  annotations:
    # Configuración temporal de experimento - ArgoCD la ignora
    argocd.argoproj.io/sync-options: Prune=false
    argocd.argoproj.io/compare-options: IgnoreExtraneous
    experiment.kubernetes.io/managed-by: "experiment-script"
spec:
  hosts:
  - "*"
  gateways:
  - demo-microservice-gateway
  http:
  # Ruta para tráfico experimental (con header específico)
  - match:
    - headers:
        aws-cf-cd-super-svp-9f8b7a6d:
          exact: "123e4567-e89b-12d3-a456-42661417400"
    route:
    - destination:
        host: demo-microservice-unified
        subset: experiment
      weight: 100
    fault:
      delay:
        percentage:
          value: 0.1
        fixedDelay: 5s
  # Ruta por defecto para tráfico normal (producción)
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: demo-microservice-unified
        subset: stable
      weight: 100
EOF

# Aplicar configuraciones de experimento
echo "📝 Aplicando DestinationRule con subset de experimento..."
kubectl apply -f /tmp/destination-rule-experiment.yaml

echo "📝 Aplicando VirtualService con enrutamiento de experimento..."
kubectl apply -f /tmp/virtual-service-experiment.yaml

# Esperar que la configuración se propague
echo "⏳ Esperando que la configuración de Istio se propague..."
sleep 15

echo "✅ Configuración de experimento aplicada"

# 5. VERIFICAR ESTADO DEL EXPERIMENTO
echo ""
echo "🔍 VERIFICANDO ESTADO DEL EXPERIMENTO..."

echo "📊 Estado de los pods:"
kubectl get pods -l app=demo-microservice-istio -o wide

echo ""
echo "🚀 Estado de los deployments:"
kubectl get deployments -l app=demo-microservice-istio

echo ""
echo "🌐 Configuración de Istio:"
kubectl get destinationrule,virtualservice

# 6. REALIZAR PRUEBAS DE CONECTIVIDAD
echo ""
echo "🧪 REALIZANDO PRUEBAS DE CONECTIVIDAD..."

echo "🔍 Probando tráfico normal (debe ir a producción):"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "📝 Respuesta: $response"

echo ""
echo "🔍 Probando tráfico experimental (debe ir al experimento):"
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "📝 Respuesta: $response"

# 7. CONFIGURAR MONITOREO
echo ""
echo "📊 CONFIGURANDO MONITOREO..."

echo "📝 Comandos de monitoreo disponibles:"
echo "• Ver logs del experimento: kubectl logs -l version=experiment -f"
echo "• Ver logs de producción: kubectl logs -l version=stable -f"
echo "• Métricas de CPU/Memoria: kubectl top pods -l app=demo-microservice-istio"
echo "• Estado de Istio: $ISTIOCTL_PATH proxy-status"
echo "• Análisis de configuración: $ISTIOCTL_PATH analyze"

# 8. GENERAR TRÁFICO DE PRUEBA (OPCIONAL)
echo ""
read -p "¿Deseas generar tráfico de prueba automático? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🔄 GENERANDO TRÁFICO DE PRUEBA..."
    
    # Crear script temporal para generar tráfico
    cat > /tmp/generate_traffic.sh << 'EOF'
#!/bin/bash
echo "🚀 Generando tráfico de prueba por 60 segundos..."
end_time=$((SECONDS + 60))

while [ $SECONDS -lt $end_time ]; do
    # Tráfico normal (80%)
    for i in {1..8}; do
        curl -s http://localhost:8080/api/v1/experiment/version > /dev/null &
    done
    
    # Tráfico experimental (20%)
    for i in {1..2}; do
        curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
            http://localhost:8080/api/v1/experiment/version > /dev/null &
    done
    
    sleep 1
done

wait
echo "✅ Tráfico de prueba completado"
EOF
    
    chmod +x /tmp/generate_traffic.sh
    /tmp/generate_traffic.sh &
    TRAFFIC_PID=$!
    
    echo "🔄 Tráfico de prueba iniciado (PID: $TRAFFIC_PID)"
    echo "📊 Puedes monitorear el impacto con: kubectl top pods -l app=demo-microservice-istio"
fi

# 9. RESUMEN FINAL
echo ""
echo "🎉 EXPERIMENTO CREADO EXITOSAMENTE"
echo "=================================="
echo ""
echo "✅ Experimento desplegado: $EXPERIMENT_IMAGE"
echo "✅ Configuración de Istio actualizada"
echo "✅ Enrutamiento por headers configurado"
echo ""
echo "🧪 DETALLES DEL EXPERIMENTO:"
echo "• Versión: $EXPERIMENT_VERSION"
echo "• Imagen: $EXPERIMENT_IMAGE"
echo "• Header de prueba: aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400"
echo ""
echo "🌐 ENRUTAMIENTO:"
echo "• Tráfico normal → Producción (3 pods)"
echo "• Tráfico con header → Experimento (1 pod)"
echo ""
echo "📊 MONITOREO:"
echo "• Kiali Dashboard: kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "• Grafana Métricas: kubectl port-forward -n istio-system svc/grafana 3000:3000"
echo "• Jaeger Tracing: kubectl port-forward -n istio-system svc/jaeger 16686:16686"
echo ""
echo "🚀 PRÓXIMO PASO:"
echo "Una vez validado el experimento, promover a rollout:"
echo "./scripts/02-promote-to-rollout.sh"
echo ""
echo "🛑 PARA ELIMINAR EL EXPERIMENTO:"
echo "./scripts/cleanup-experiment.sh"
echo ""
echo "💡 NOTA IMPORTANTE:"
echo "Este experimento SOBRESCRIBE temporalmente la configuración de ArgoCD."
echo "Las anotaciones evitan que ArgoCD revierta los cambios automáticamente."
echo "Esto simula el comportamiento real en entornos empresariales."