#!/bin/bash

# Script para iniciar experimento A/B con Argo Experiment
# Duración: 24 horas
set -e

echo "🧪 INICIANDO EXPERIMENTO A/B CON ARGO EXPERIMENT"
echo "================================================"

cd "$(dirname "$0")/.."

# 1. Verificar que Argo Rollouts esté instalado
echo ""
echo "📋 VERIFICANDO PREREQUISITOS..."

if ! kubectl get crd experiments.argoproj.io >/dev/null 2>&1; then
    echo "⚠️  Argo Rollouts no está instalado. Instalando..."
    kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
    
    echo "⏳ Esperando que Argo Rollouts esté listo..."
    kubectl wait --for=condition=available deployment/argo-rollouts -n argo-rollouts --timeout=300s
    echo "✅ Argo Rollouts instalado"
else
    echo "✅ Argo Rollouts ya está instalado"
fi

# 2. Limpiar experimentos anteriores
echo ""
echo "🧹 LIMPIANDO EXPERIMENTOS ANTERIORES..."
kubectl delete experiment demo-microservice-experiment --ignore-not-found=true
sleep 2

# 3. Verificar que el deployment de producción esté corriendo
echo ""
echo "🔍 VERIFICANDO DEPLOYMENT DE PRODUCCIÓN..."
if ! kubectl get deployment demo-microservice-production-istio >/dev/null 2>&1; then
    echo "❌ El deployment de producción no existe. Ejecuta primero:"
    echo "   ./scripts/03-setup-argocd.sh"
    exit 1
fi
echo "✅ Deployment de producción encontrado"

# 4. Verificar que el service exista
echo ""
echo "🔍 VERIFICANDO SERVICE EXISTENTE..."
if ! kubectl get svc demo-microservice-istio >/dev/null 2>&1; then
    echo "❌ El service demo-microservice-istio no existe"
    exit 1
fi
echo "✅ Service demo-microservice-istio encontrado"

# 5. Crear el experimento
echo ""
echo "🚀 DESPLEGANDO EXPERIMENTO..."
kubectl apply -f experiments/experiment-deployment.yaml

echo ""
echo "⏳ ESPERANDO QUE EL EXPERIMENTO ESTÉ LISTO..."
sleep 15

# 6. Verificar estado del experimento
echo ""
echo "📊 ESTADO DEL EXPERIMENTO:"
kubectl get experiment demo-microservice-experiment

echo ""
echo "📦 PODS DEL EXPERIMENTO:"
kubectl get pods -l experiment=ab-test

echo ""
echo "🌐 SERVICE UNIFICADO (selecciona ambos: stable + experiment):"
kubectl get svc demo-microservice-istio

echo ""
echo "🔍 ENDPOINTS DEL SERVICE (debe incluir pods stable + experiment):"
kubectl get endpoints demo-microservice-istio -o jsonpath='{.subsets[*].addresses[*].targetRef.name}' && echo ""

# 7. Esperar propagación de Istio
echo ""
echo "⏳ Esperando propagación de configuración de Istio..."
sleep 10

# 7. Mostrar información del experimento
echo ""
echo "🎉 EXPERIMENTO INICIADO EXITOSAMENTE"
echo "===================================="
echo ""
echo "📋 INFORMACIÓN:"
echo "• Experiment: demo-microservice-experiment"
echo "• Duración: 24 horas"
echo "• Replicas experiment: 1"
echo "• Service: demo-microservice-experiment-experiment"
echo ""
echo "🧪 PRUEBAS A/B:"
echo ""
echo "• Tráfico NORMAL (va a producción stable):"
echo "  curl http://localhost:8080/demo/info"
echo ""
echo "• Tráfico EXPERIMENTAL (va al experimento):"
echo "  curl -H 'aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400' \\"
echo "       http://localhost:8080/demo/info"
echo ""
echo "📊 MONITOREO:"
echo "• Ver estado: kubectl get experiment demo-microservice-experiment"
echo "• Ver pods: kubectl get pods -l experiment=ab-test"
echo "• Ver logs: kubectl logs -l version=experiment -f"
echo "• Dashboard: kubectl argo rollouts dashboard"
echo ""
echo "🚀 PRÓXIMO PASO:"
echo "Si el experimento es exitoso, promover a rollout:"
echo "  ./scripts/02-promote-to-rollout.sh"
echo ""
echo "🧹 LIMPIAR EXPERIMENTO:"
echo "  kubectl delete experiment demo-microservice-experiment"
echo "  kubectl apply -f argocd-production/04-virtual-service.yaml"
echo ""
echo "⏰ NOTA:"
echo "El experimento se ejecutará durante 24 horas y luego se detendrá automáticamente."
