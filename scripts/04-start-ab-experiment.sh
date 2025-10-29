#!/bin/bash

# Script para iniciar un experimento A/B con Argo Experiment
set -e

echo "🧪 INICIANDO EXPERIMENTO A/B CON ARGO EXPERIMENT"
echo "================================================"

cd "$(dirname "$0")/.."

if ! kubectl get crd experiments.argoproj.io >/dev/null 2>&1; then
    echo "📦 Instalando Argo Rollouts..."
    kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
    
    echo "Esperando que Argo Rollouts esté listo..."
    kubectl wait --for=condition=available deployment/argo-rollouts -n argo-rollouts --timeout=300s
fi

echo "✅ Argo Rollouts disponible"

echo ""
echo "🔧 CONFIGURANDO DOCKER PARA MINIKUBE..."
eval $(minikube docker-env)

echo ""
echo "🏗️  CONSTRUYENDO IMAGEN EXPERIMENTAL..."
docker build -t demo-microservice:experiment \
  --build-arg APP_VERSION=experiment-v2.0.0 \
  --build-arg EXPERIMENT_ENABLED=true \
  .

echo "✅ Imagen experimental construida"

if ! docker images | grep -q "demo-microservice.*stable"; then
    echo "⚠️  Imagen stable no encontrada, construyendo..."
    docker build -t demo-microservice:stable \
      --build-arg APP_VERSION=stable-v1.0.0 \
      --build-arg EXPERIMENT_ENABLED=false \
      .
fi

echo ""
echo "🚀 DESPLEGANDO ARGO EXPERIMENT..."
kubectl apply -f experiments/06-experiment-ab-testing.yaml

echo ""
echo "⏳ ESPERANDO QUE EL EXPERIMENT ESTÉ LISTO..."
sleep 15

echo ""
echo "📊 ESTADO DEL EXPERIMENT:"
kubectl get experiment demo-microservice-ab-experiment -o wide

echo ""
echo "📊 PODS DEL EXPERIMENT:"
kubectl get pods -l experiment=ab-test

echo ""
echo "🎉 EXPERIMENTO A/B INICIADO"
echo "=========================="
echo ""
echo "📋 INFORMACIÓN:"
echo "• Experiment: demo-microservice-ab-experiment"
echo "• Duración: 30 minutos"
echo "• Replicas Stable: 3"
echo "• Replicas Experiment: 3"
echo ""
echo "🧪 TESTING A/B (enrutamiento por header):"
echo ""
echo "• Tráfico NORMAL (va a stable):"
echo "  curl http://localhost:8080/demo/info"
echo ""
echo "• Tráfico EXPERIMENTAL (va a experiment):"
echo "  curl -H 'aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400' \\"
echo "       http://localhost:8080/demo/info"
echo ""
echo "🎛️  GESTIÓN DEL EXPERIMENT:"
echo "• Ver estado: kubectl get experiment demo-microservice-ab-experiment"
echo "• Ver análisis: kubectl get analysisrun -l experiment=ab-test"
echo "• Ver pods: kubectl get pods -l experiment=ab-test"
echo "• Ver logs stable: kubectl logs -l version=stable,experiment=ab-test"
echo "• Ver logs experiment: kubectl logs -l version=experiment,experiment=ab-test"
echo "• Eliminar experiment: kubectl delete experiment demo-microservice-ab-experiment"
echo ""
echo "📈 MONITOREO:"
echo "• Ver servicios: kubectl get svc | grep experiment"
echo "• Ver VirtualService: kubectl get virtualservice demo-microservice-experiment-routing"
echo "• Describir experiment: kubectl describe experiment demo-microservice-ab-experiment"
echo ""
echo "💡 PRÓXIMOS PASOS:"
echo "1. Probar ambas versiones con y sin el header"
echo "2. Revisar métricas y análisis (si Prometheus está configurado)"
echo "3. Si el experimento es exitoso, promover a Blue-Green Rollout:"
echo "   ./scripts/05-promote-to-bluegreen.sh"
echo ""
echo "⚠️  NOTA:"
echo "El experimento se ejecutará durante 30 minutos y luego se detendrá automáticamente."
echo "Los análisis requieren Prometheus configurado en Istio."
