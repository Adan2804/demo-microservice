#!/bin/bash

# Script para probar el Canary Deployment
# Simula un cambio de versión para activar el canary manager

set -e

echo "🧪 PRUEBA DE CANARY DEPLOYMENT"
echo "=============================="
echo ""

# Verificar que todo esté listo
echo "📋 Verificando prerequisitos..."

if ! kubectl get deployment demo-microservice-keda -n default >/dev/null 2>&1; then
    echo "❌ Deployment demo-microservice-keda no encontrado"
    exit 1
fi

if ! kubectl get job canary-manager -n default >/dev/null 2>&1; then
    echo "⚠️  Job canary-manager no existe, creándolo..."
    kubectl apply -f argocd-keda/07-canary-job.yaml
fi

# Obtener imagen actual
CURRENT_IMAGE=$(kubectl get deployment demo-microservice-keda -n default -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "📦 Imagen actual: $CURRENT_IMAGE"

# Proponer nueva imagen
echo ""
echo "Para probar el canary deployment, necesitas cambiar la imagen."
echo "Opciones:"
echo "  1. zadan04/demo-microservice:experiment"
echo "  2. zadan04/demo-microservice:latest"
echo "  3. zadan04/demo-microservice:v1.0.0"
echo ""
read -p "Ingresa la nueva imagen (o Enter para usar 'experiment'): " NEW_IMAGE

if [ -z "$NEW_IMAGE" ]; then
    NEW_IMAGE="zadan04/demo-microservice:experiment"
fi

echo ""
echo "🚀 Iniciando Canary Deployment..."
echo "   Imagen actual: $CURRENT_IMAGE"
echo "   Imagen nueva:  $NEW_IMAGE"
echo ""

# Actualizar el deployment
echo "📝 Actualizando deployment..."
kubectl set image deployment/demo-microservice-keda \
    demo-microservice=$NEW_IMAGE \
    -n default

echo ""
echo "✅ Deployment actualizado"
echo ""
echo "📊 MONITOREO:"
echo "• Ver pods:        kubectl get pods -l app=demo-microservice-keda -w"
echo "• Ver job canary:  kubectl logs -f job/canary-manager -n default"
echo "• Ver eventos:     kubectl get events -n default --sort-by='.lastTimestamp'"
echo ""
echo "🧪 PRUEBAS (cuando el canary esté activo):"
echo "• Tráfico normal:  kubectl run -it --rm test --image=curlimages/curl --restart=Never -- curl http://demo-microservice-keda:8080/actuator/health"
echo "• Tráfico canary:  kubectl run -it --rm test --image=curlimages/curl --restart=Never -- curl -H 'x-canary-test: true' http://demo-microservice-keda:8080/actuator/health"
echo ""
echo "⏱️  El canary estará activo por 10 minutos, luego continuará el rolling update normal"
