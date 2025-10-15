#!/bin/bash
echo "🛑 Deteniendo ArgoCD Dashboard..."

# Detener port-forwards
pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true

echo "✅ ArgoCD Dashboard detenido"
