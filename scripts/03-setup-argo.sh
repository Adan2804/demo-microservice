#!/bin/bash

# Script 2: Configurar Argo Rollouts (ANTES del experimento)
set -e

echo "=== PASO 2: CONFIGURANDO ARGO ROLLOUTS ==="

cd "$(dirname "$0")/.."

# Verificar que la infraestructura base esté desplegada
if ! kubectl get deployment demo-microservice-production >/dev/null 2>&1; then
    echo "❌ Error: Infraestructura base no encontrada"
    echo "Ejecuta primero: ./scripts/01-deploy-base.sh"
    exit 1
fi

# Instalar Argo Rollouts si no existe
if ! kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
    echo "Instalando Argo Rollouts..."
    kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
    kubectl wait --for=condition=available deployment/argo-rollouts-controller -n argo-rollouts --timeout=300s
    echo "✅ Argo Rollouts instalado"
fi

# Desplegar servicios y rollout
echo "Desplegando servicios del rollout..."
kubectl apply -f k7s/04-rollout-services.yaml

echo "Desplegando Argo Rollout..."
kubectl apply -f k7s/05-argo-rollout.yaml

# Esperar que el rollout esté listo
echo "Esperando que el rollout esté listo..."
sleep 15

# Verificar si hay pods
ROLLOUT_PODS=$(kubectl get pods -l app=demo-microservice-rollout --no-headers 2>/dev/null | wc -l)
if [ "$ROLLOUT_PODS" -eq 0 ]; then
    echo "⚠️  Rollout creado pero sin pods aún. Esperando más tiempo..."
    sleep 30
    
    # Verificar de nuevo
    ROLLOUT_PODS=$(kubectl get pods -l app=demo-microservice-rollout --no-headers 2>/dev/null | wc -l)
    if [ "$ROLLOUT_PODS" -eq 0 ]; then
        echo "⚠️  Rollout tardando en crear pods. Verificando estado..."
        kubectl describe rollout demo-microservice-rollout | tail -20
    fi
fi

echo ""
echo "✅ ARGO ROLLOUTS CONFIGURADO"
echo ""
echo "Estado del rollout:"
kubectl get rollouts

echo ""
echo "Pods del rollout:"
kubectl get pods -l app=demo-microservice-rollout

echo ""
echo "Estado detallado del rollout:"
kubectl argo rollouts get rollout demo-microservice-rollout 2>/dev/null || echo "Comando argo rollouts no disponible aún"

echo ""
echo "Siguiente paso: ./scripts/03-deploy-experiment.sh"