#!/bin/bash

# Script 1: Desplegar infraestructura base
set -e

echo "=== PASO 1: DESPLEGANDO INFRAESTRUCTURA BASE ==="

cd "$(dirname "$0")/.."

# Verificar minikube
if ! minikube status >/dev/null 2>&1; then
    echo "Iniciando minikube..."
    minikube start
    sleep 30
fi

# Limpiar
echo "Limpiando recursos anteriores..."
kubectl delete -f k7s/ --ignore-not-found=true 2>/dev/null || true
sleep 5

# Verificar imágenes
if ! minikube image ls | grep -q demo-microservice:stable; then
    echo "Construyendo imágenes con versiones diferentes..."
    
    # Imagen STABLE
    docker build -t demo-microservice:stable \
      --build-arg NODE_ENV=production \
      --build-arg APP_VERSION=stable-v1.0.0 \
      --build-arg EXPERIMENT_ENABLED=false \
      .
    
    # Imagen EXPERIMENTAL
    docker build -t demo-microservice:experiment \
      --build-arg NODE_ENV=production \
      --build-arg APP_VERSION=experiment-v1.1.0 \
      --build-arg EXPERIMENT_ENABLED=true \
      .
    
    minikube image load demo-microservice:stable
    minikube image load demo-microservice:experiment
    
    echo "✅ Imágenes construidas con versiones diferentes"
fi

# Desplegar base
echo "Desplegando infraestructura base..."
kubectl apply -f k7s/01-production-deployment.yaml
kubectl apply -f k7s/02-services.yaml
# Verificar que existe el archivo nginx.conf
if [ ! -f "proxy/nginx.conf" ]; then
    echo "❌ Error: No se encuentra proxy/nginx.conf"
    exit 1
fi

# Eliminar ConfigMap anterior si existe
echo "Eliminando ConfigMap anterior..."
kubectl delete configmap intelligent-proxy-config --ignore-not-found=true

# Crear ConfigMap desde archivo
echo "Creando ConfigMap desde proxy/nginx.conf..."
kubectl create configmap intelligent-proxy-config --from-file=nginx.conf=proxy/nginx.conf
kubectl apply -f k7s/03-proxy-intelligent-clean.yaml

# Esperar
kubectl wait --for=condition=available deployment/demo-microservice-production --timeout=120s
kubectl wait --for=condition=available deployment/intelligent-proxy --timeout=60s

# Port-forward
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2
kubectl port-forward svc/intelligent-proxy 8080:80 > /dev/null 2>&1 &
echo "Port-forward iniciado (PID: $!)"

echo ""
echo "✅ INFRAESTRUCTURA BASE DESPLEGADA"
echo ""
echo "Estado:"
kubectl get pods -l app=demo-microservice
kubectl get pods -l app=intelligent-proxy

echo ""
echo "Prueba:"
curl -s http://localhost:8080/api/v1/experiment/version | jq '{version, pod}' 2>/dev/null || curl -s http://localhost:8080/api/v1/experiment/version

echo ""
echo "Siguiente paso: ./scripts/02-setup-argo.sh"