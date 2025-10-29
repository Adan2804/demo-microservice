#!/bin/bash

# Script para iniciar el dashboard de Argo Rollouts
set -e

echo "🎛️  INICIANDO DASHBOARD DE ARGO ROLLOUTS"
echo "========================================"

cd "$(dirname "$0")/.."

# Verificar que Argo Rollouts esté instalado
if ! kubectl get deployment argo-rollouts -n argo-rollouts >/dev/null 2>&1; then
    echo "❌ Argo Rollouts no está instalado"
    echo "Ejecuta primero: ./scripts/02-promote-to-rollout.sh"
    exit 1
fi

echo "✅ Argo Rollouts encontrado"

# Verificar si hay rollouts activos
echo ""
echo "📊 ROLLOUTS ACTIVOS:"
kubectl get rollouts --all-namespaces

# Intentar usar el plugin
if kubectl argo rollouts version >/dev/null 2>&1; then
    echo ""
    echo "🚀 Iniciando dashboard con plugin..."
    echo "📍 Dashboard disponible en: http://localhost:3100"
    echo ""
    echo "💡 TIPS:"
    echo "• Verás el estado del rollout en tiempo real"
    echo "• Puedes promover o abortar desde la UI"
    echo "• Presiona Ctrl+C para detener"
    echo ""
    kubectl argo rollouts dashboard
else
    echo ""
    echo "⚠️  Plugin 'kubectl argo rollouts' no está instalado"
    echo ""
    echo "📥 INSTALACIÓN DEL PLUGIN:"
    echo "• Linux/WSL:"
    echo "  curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64"
    echo "  chmod +x kubectl-argo-rollouts-linux-amd64"
    echo "  sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts"
    echo ""
    echo "• macOS:"
    echo "  brew install argoproj/tap/kubectl-argo-rollouts"
    echo ""
    echo "• Windows:"
    echo "  Descarga desde: https://github.com/argoproj/argo-rollouts/releases"
    echo ""
    echo "🔄 ALTERNATIVA - Ver estado con kubectl:"
    echo "  kubectl get rollout demo-microservice-rollout -w"
    echo "  kubectl argo rollouts get rollout demo-microservice-rollout --watch"
    echo ""
    
    # Ofrecer alternativa con port-forward
    read -p "¿Deseas ver el estado del rollout en modo watch? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "📊 Monitoreando rollout (Ctrl+C para salir)..."
        kubectl get rollout demo-microservice-rollout -w
    fi
fi
