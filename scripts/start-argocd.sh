#!/bin/bash
echo "🚀 Iniciando ArgoCD Dashboard..."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true
sleep 2

# Iniciar port-forward
kubectl port-forward svc/argocd-server -n argocd 8081:443 > /dev/null 2>&1 &
ARGOCD_PF_PID=$!

echo "✅ ArgoCD Dashboard disponible en: https://localhost:8081"
echo "Port-forward activo (PID: $ARGOCD_PF_PID)"

# Mostrar credenciales
echo ""
echo "🔑 CREDENCIALES:"
echo "Usuario: admin"
echo "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
