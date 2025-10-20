#!/bin/bash

# Script para mostrar qué archivos gestiona ArgoCD vs experimentos
echo "🔍 ARCHIVOS GESTIONADOS POR ARGOCD vs EXPERIMENTOS"
echo "=================================================="

cd "$(dirname "$0")/.."

echo ""
echo "📁 ARCHIVOS QUE ARGOCD GESTIONA (argocd-production/):"
echo "---------------------------------------------------"
if [ -d "argocd-production" ]; then
    ls -la argocd-production/
    echo ""
    echo "Estos archivos están bajo control de ArgoCD:"
    for file in argocd-production/*.yaml; do
        if [ -f "$file" ]; then
            echo "✅ $(basename "$file")"
        fi
    done
else
    echo "❌ Directorio argocd-production/ no existe"
fi

echo ""
echo "📁 ARCHIVOS DE EXPERIMENTOS (istio/ - NO gestionados por ArgoCD):"
echo "---------------------------------------------------------------"
echo "Estos archivos se usan dinámicamente para experimentos:"
echo "🧪 02-experiment-deployment-istio.yaml"
echo "🧪 03-destination-rule-experiment.yaml"
echo "🧪 04-virtual-service-experiment.yaml"
echo "🧪 05-argo-rollout-istio.yaml"

echo ""
echo "🎯 PARA PROBAR CAMBIOS EN ARGOCD:"
echo "================================"
echo "1. Modifica archivos en argocd-production/"
echo "2. Haz commit y push a Git"
echo "3. En ArgoCD UI: Haz clic en REFRESH"
echo "4. Verás los cambios en la pestaña DIFF"
echo "5. Haz clic en SYNC para aplicarlos"

echo ""
echo "🧪 PARA CREAR EXPERIMENTOS:"
echo "=========================="
echo "./scripts/01-create-experiment.sh"

echo ""
echo "📊 ESTADO ACTUAL DE ARGOCD:"
echo "=========================="
kubectl get application demo-microservice-istio -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null && echo " (Sync Status)" || echo "No encontrado"
kubectl get application demo-microservice-istio -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null && echo " (Health Status)" || echo "No encontrado"