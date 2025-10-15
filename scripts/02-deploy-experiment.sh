#!/bin/bash

# Script 3: Desplegar experimento (DESPUÉS de Argo Rollouts)
set -e

echo "=== PASO 3: DESPLEGANDO EXPERIMENTO ==="

cd "$(dirname "$0")/.."


# Limpiar experimentos anteriores
echo "Limpiando experimentos anteriores..."
kubectl delete experiment demo-microservice-experiment --ignore-not-found=true
kubectl delete deployment demo-microservice-experiment --ignore-not-found=true
kubectl delete pods -l tier=experiment --ignore-not-found=true
sleep 5

# Desplegar nuevo experimento (Argo Experiment)
echo "Desplegando Argo Experiment..."
kubectl apply -f k7s/experiment-deployment.yaml

# Esperar que el experimento esté listo
echo "Esperando que el experimento esté listo..."
sleep 30

# Verificar pods del experimento
EXPERIMENT_PODS=$(kubectl get pods -l tier=experiment --no-headers 2>/dev/null | wc -l)
if [ "$EXPERIMENT_PODS" -eq 0 ]; then
    echo "⚠️  Experimento creado pero sin pods aún. Esperando más..."
    sleep 30
fi

echo ""
echo "✅ EXPERIMENTO DESPLEGADO"
echo ""
echo "Estado:"
kubectl get pods -l app=demo-microservice --show-labels

echo ""
echo "Pruebas:"
echo ""
echo "Producción (sin header):"
curl -s http://localhost:8080/api/v1/experiment/version | jq '{version, pod, experimentEnabled}' 2>/dev/null || curl -s http://localhost:8080/api/v1/experiment/version

echo ""
echo "Experimento (con header):"
curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version | jq '{version, pod, experimentEnabled}' 2>/dev/null || \
    curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" http://localhost:8080/api/v1/experiment/version

echo ""
echo "Siguiente paso: ./scripts/04-start-dashboard.sh"