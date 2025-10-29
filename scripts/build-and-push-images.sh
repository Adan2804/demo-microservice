#!/bin/bash

# Script para construir y subir imágenes a Docker Hub
set -e

echo "🐳 CONSTRUYENDO Y SUBIENDO IMÁGENES A DOCKER HUB"
echo "================================================"

cd "$(dirname "$0")/.."

DOCKER_USER="zadan04"

# Verificar que estés logueado en Docker Hub
echo "Verificando login en Docker Hub..."
if ! docker info | grep -q "Username: $DOCKER_USER"; then
    echo "⚠️  No estás logueado en Docker Hub"
    echo "Ejecuta: docker login"
    read -p "¿Quieres hacer login ahora? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker login
    else
        exit 1
    fi
fi

echo "✅ Login verificado"

# Construir imagen STABLE
echo ""
echo "🏗️  CONSTRUYENDO IMAGEN STABLE..."
docker build -t $DOCKER_USER/demo-microservice:stable \
  --build-arg APP_VERSION=stable-v1.0.0 \
  --build-arg EXPERIMENT_ENABLED=false \
  .

echo "📤 SUBIENDO IMAGEN STABLE..."
docker push $DOCKER_USER/demo-microservice:stable

# Construir imagen EXPERIMENT
echo ""
echo "🏗️  CONSTRUYENDO IMAGEN EXPERIMENT..."
docker build -t $DOCKER_USER/demo-microservice:experiment \
  --build-arg APP_VERSION=experiment-v2.0.0 \
  --build-arg EXPERIMENT_ENABLED=true \
  .

echo "📤 SUBIENDO IMAGEN EXPERIMENT..."
docker push $DOCKER_USER/demo-microservice:experiment

# También crear tag latest
echo ""
echo "🏷️  CREANDO TAG LATEST..."
docker tag $DOCKER_USER/demo-microservice:stable $DOCKER_USER/demo-microservice:latest
docker push $DOCKER_USER/demo-microservice:latest

echo ""
echo "🎉 IMÁGENES SUBIDAS EXITOSAMENTE"
echo "================================"
echo ""
echo "✅ Imágenes disponibles en Docker Hub:"
echo "• $DOCKER_USER/demo-microservice:stable"
echo "• $DOCKER_USER/demo-microservice:experiment"
echo "• $DOCKER_USER/demo-microservice:latest"
echo ""
echo "🔗 Ver en: https://hub.docker.com/r/$DOCKER_USER/demo-microservice"
echo ""
echo "💡 PRÓXIMOS PASOS:"
echo "1. Commit y push de los cambios:"
echo "   git add ."
echo "   git commit -m 'Use Docker Hub images'"
echo "   git push origin main"
echo ""
echo "2. Ejecutar setup de ArgoCD:"
echo "   ./scripts/03-setup-argocd.sh"
