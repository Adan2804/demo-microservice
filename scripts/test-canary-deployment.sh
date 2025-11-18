#!/bin/bash
# Script para probar el deployment con canary usando header
# 
# USO:
#   ./test-canary-deployment.sh

set -e

NAMESPACE="default"
APP="demo-microservice-keda"
SERVICE="demo-microservice-keda"

echo "🚀 Test de Canary Deployment con Header"
echo "========================================"
echo ""

# Función para hacer request con o sin header
test_request() {
  local header=$1
  local description=$2
  
  echo "📡 $description"
  if [ -z "$header" ]; then
    kubectl exec -n $NAMESPACE deploy/$APP -- curl -s http://$SERVICE:8080/actuator/health | jq -r '.status, .version // "N/A"'
  else
    kubectl exec -n $NAMESPACE deploy/$APP -- curl -s -H "$header" http://$SERVICE:8080/actuator/health | jq -r '.status, .version // "N/A"'
  fi
  echo ""
}

# Verificar estado actual
echo "📊 Estado actual del deployment:"
kubectl get pods -n $NAMESPACE -l app=$APP -o wide
echo ""

# Verificar si VirtualService está activo
echo "🔍 Verificando VirtualService:"
if kubectl get virtualservice demo-microservice-keda-canary -n $NAMESPACE &>/dev/null; then
  echo "✅ VirtualService ACTIVO - Modo canary habilitado"
  echo ""
  
  # Hacer pruebas con y sin header
  echo "🧪 Pruebas de routing:"
  echo ""
  
  test_request "" "Tráfico NORMAL (sin header) → pods OLD:"
  test_request "x-canary-test: true" "Tráfico CANARY (con header) → pod NEW:"
  
  echo "💡 TIP: Puedes hacer múltiples requests para verificar el routing"
  echo "   Normal:  for i in {1..5}; do curl http://$SERVICE:8080/actuator/health; done"
  echo "   Canary:  for i in {1..5}; do curl -H 'x-canary-test: true' http://$SERVICE:8080/actuator/health; done"
else
  echo "❌ VirtualService NO activo - Modo normal"
  echo ""
  test_request "" "Tráfico normal (sin routing especial):"
fi

echo ""
echo "✅ Test completado"
