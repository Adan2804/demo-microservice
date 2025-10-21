#!/bin/bash
echo "📊 ESTADO DE ARGOCD"
echo "==================="

APP_NAME="demo-microservice-versioned-app"
ARGOCD_NAMESPACE="argocd"
NAMESPACE="demo-app"

echo ""
echo "🔍 Aplicación:"
kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE -o wide

echo ""
echo "📦 Recursos en el cluster:"
kubectl get all -n $NAMESPACE -l app=demo-microservice 2>/dev/null || echo "No hay recursos desplegados aún"

echo ""
echo "🌐 Services versionados:"
kubectl get svc -n $NAMESPACE -l app=demo-microservice 2>/dev/null || echo "No hay services versionados aún"

echo ""
echo "💡 Para hacer sync manual:"
echo "./scripts/manual-sync.sh"
