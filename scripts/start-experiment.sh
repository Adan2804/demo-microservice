#!/bin/bash

# Script simple para iniciar experimento A/B
set -e

echo "🧪 INICIANDO EXPERIMENTO A/B"
echo "============================"

cd "$(dirname "$0")/.."

echo "🚀 Desplegando versión experimental..."
kubectl apply -f experiments/experiment-deployment.yaml

echo ""
echo "⏳ Esperando que los pods estén listos..."
kubectl wait --for=condition=available deployment/demo-microservice-experiment --timeout=300s

echo ""
echo "📊 ESTADO:"
kubectl get pods -l version=experiment
kubectl get pods -l version=stable

echo ""
echo "🎉 EXPERIMENTO INICIADO"
echo "======================"
echo ""
echo "🧪 PRUEBAS:"
echo "• Tráfico normal (stable):"
echo "  curl http://localhost:8080/demo/info"
echo ""
echo "• Tráfico experimental:"
echo "  curl -H 'aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400' \\"
echo "       http://localhost:8080/demo/info"
echo ""
echo "🧹 LIMPIAR EXPERIMENTO:"
echo "  kubectl delete deployment demo-microservice-experiment"
echo "  kubectl delete virtualservice demo-microservice-ab-routing"
