#!/bin/bash

# Script para promover experimento usando Istio + Argo Rollouts
set -e

echo "=== PROMOVIENDO EXPERIMENTO CON ISTIO ==="

cd "$(dirname "$0")/.."

# 1. Verificar que el experimento esté funcionando
if ! kubectl get experiment demo-microservice-experiment >/dev/null 2>&1; then
    echo "❌ Error: Experimento no encontrado"
    exit 1
fi

# 2. Obtener imagen del experimento
EXPERIMENT_IMAGE=$(kubectl get experiment demo-microservice-experiment -o jsonpath='{.spec.templates[0].template.spec.containers[0].image}')
echo "Imagen del experimento: $EXPERIMENT_IMAGE"

# 3. Activar VirtualService para rollouts
echo "Activando VirtualService para rollouts..."
kubectl patch virtualservice demo-microservice-rollout -p '{"metadata":{"labels":{"rollout-active":"true"}}}'

# 4. Crear Argo Rollout con Istio
echo "Creando Argo Rollout con integración Istio..."
cat istio/05-argo-rollout-istio.yaml | sed "s|demo-microservice:stable|$EXPERIMENT_IMAGE|g" | kubectl apply -f -

# 5. Esperar que el rollout esté listo
echo "Esperando que el rollout esté listo..."
kubectl wait --for=condition=progressing rollout/demo-microservice-rollout-istio --timeout=300s

# 6. Monitorear el progreso del canary
echo "Monitoreando progreso del canary deployment..."
kubectl argo rollouts get rollout demo-microservice-rollout-istio --watch &
WATCH_PID=$!

# 7. Esperar input del usuario para promoción
echo ""
echo "🚀 CANARY DEPLOYMENT INICIADO"
echo ""
echo "El rollout está progresando automáticamente:"
echo "- 10% → 25% → 50% → 75% → 100%"
echo ""
echo "Puedes:"
echo "1. Esperar promoción automática"
echo "2. Promover manualmente: kubectl argo rollouts promote demo-microservice-rollout-istio"
echo "3. Abortar: kubectl argo rollouts abort demo-microservice-rollout-istio"
echo ""
echo "Presiona Ctrl+C para detener el monitoreo (el rollout continuará)"

# 8. Trap para limpiar al salir
trap 'kill $WATCH_PID 2>/dev/null || true' EXIT

# 9. Esperar indefinidamente (usuario puede Ctrl+C)
wait $WATCH_PID 2>/dev/null || true

echo ""
echo "✅ PROMOCIÓN CON ISTIO COMPLETADA"
echo ""
echo "Estado final:"
kubectl argo rollouts get rollout demo-microservice-rollout-istio

echo ""
echo "Métricas de Istio disponibles en:"
echo "kubectl port-forward -n istio-system svc/grafana 3000:3000"