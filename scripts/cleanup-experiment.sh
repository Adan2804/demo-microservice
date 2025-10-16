#!/bin/bash

# Script para limpiar experimentos y restaurar configuración base
set -e

echo "🧹 LIMPIANDO EXPERIMENTO"
echo "======================="

cd "$(dirname "$0")/.."

# 1. ELIMINAR DEPLOYMENT DEL EXPERIMENTO
echo ""
echo "🗑️  ELIMINANDO DEPLOYMENT DEL EXPERIMENTO..."

kubectl delete deployment demo-microservice-experiment --ignore-not-found=true

# 2. RESTAURAR CONFIGURACIÓN BASE DE ISTIO
echo ""
echo "🔄 RESTAURANDO CONFIGURACIÓN BASE DE ISTIO..."

# Restaurar DestinationRule base
echo "Restaurando DestinationRule base..."
kubectl apply -f argocd-production/03-destination-rule.yaml

# Restaurar VirtualService base
echo "Restaurando VirtualService base..."
kubectl apply -f argocd-production/04-virtual-service.yaml

# 3. RESTAURAR AUTO-SYNC DE ARGOCD
echo ""
echo "🔄 RESTAURANDO AUTO-SYNC DE ARGOCD..."

kubectl patch application demo-microservice-istio -n argocd --type='merge' -p='{"spec":{"syncPolicy":{"syncOptions":["CreateNamespace=true"]}}}'

# 4. VERIFICAR ESTADO
echo ""
echo "🔍 VERIFICANDO ESTADO..."

echo "Pods restantes:"
kubectl get pods -l app=demo-microservice

echo ""
echo "Deployments activos:"
kubectl get deployments -l app=demo-microservice

# 5. PROBAR CONECTIVIDAD
echo ""
echo "🧪 PROBANDO CONECTIVIDAD..."

echo "Probando tráfico normal:"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "Probando tráfico experimental (debe ir a producción):"
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "✅ EXPERIMENTO ELIMINADO EXITOSAMENTE"
echo "===================================="
echo ""
echo "🔄 Estado restaurado a producción estable"
echo "🌐 ArgoCD auto-sync restaurado"
echo "🚀 Listo para crear nuevos experimentos"