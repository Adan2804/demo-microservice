#!/bin/bash
echo "🔄 SYNC MANUAL DE ARGOCD"
echo "========================"

APP_NAME="demo-microservice-versioned-app"
ARGOCD_NAMESPACE="argocd"

echo "📊 Estado actual:"
kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE

echo ""
echo "🚀 Ejecutando sync manual..."
kubectl patch application $APP_NAME -n $ARGOCD_NAMESPACE --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

echo ""
echo "⏳ Esperando sincronización..."
sleep 10

echo ""
echo "📊 Estado después del sync:"
kubectl get application $APP_NAME -n $ARGOCD_NAMESPACE

echo ""
echo "✅ Sync manual completado"
