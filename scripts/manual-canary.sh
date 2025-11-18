#!/bin/bash

# Script MANUAL para Canary Deployment
# Reemplaza el Job automático que falla en Minikube

set -e

echo "🧪 CANARY DEPLOYMENT MANUAL"
echo "==========================="
echo ""

# Paso 1: Aplicar VirtualService
echo "📝 Paso 1: Aplicando VirtualService canary..."
kubectl apply -f argocd-keda/06-virtualservice-canary.yaml
kubectl apply -f argocd-keda/05-destination-rule.yaml

echo "✅ VirtualService activo"
echo ""

# Paso 2: Obtener imagen actual
CURRENT_IMAGE=$(kubectl get deployment demo-microservice-keda -n default -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "📦 Imagen actual: $CURRENT_IMAGE"
echo ""

# Paso 3: Solicitar nueva imagen
echo "Ingresa la nueva imagen para el canary:"
echo "  Ejemplo: zadan04/demo-microservice:experiment"
read -p "Nueva imagen: " NEW_IMAGE

if [ -z "$NEW_IMAGE" ]; then
    echo "❌ Debes ingresar una imagen"
    exit 1
fi

echo ""
echo "🚀 Paso 2: Actualizando deployment..."
kubectl set image deployment/demo-microservice-keda \
    demo-microservice-v2=$NEW_IMAGE \
    -n default

echo "✅ Deployment actualizado"
echo ""

# Paso 4: Monitorear
echo "📊 Paso 3: Monitoreando pods..."
echo ""
kubectl get pods -l app=demo-microservice-keda -w &
WATCH_PID=$!

sleep 60

kill $WATCH_PID 2>/dev/null || true

echo ""
echo "✅ CANARY ACTIVO"
echo ""
echo "🧪 PRUEBAS:"
echo ""
echo "Obtener NodePort del servicio:"
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")
NODE_PORT=$(kubectl get svc demo-microservice-keda -n default -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")

if [ -n "$NODE_PORT" ]; then
    echo "  Tráfico normal:  curl http://${MINIKUBE_IP}:${NODE_PORT}/actuator/info"
    echo "  Tráfico canary:  curl -H 'x-canary-test: true' http://${MINIKUBE_IP}:${NODE_PORT}/actuator/info"
else
    echo "  Port-forward:    kubectl port-forward svc/demo-microservice-keda 8080:8080"
    echo "  Tráfico normal:  curl http://localhost:8080/actuator/info"
    echo "  Tráfico canary:  curl -H 'x-canary-test: true' http://localhost:8080/actuator/info"
fi

echo ""
echo "⏱️  ESPERA 10 MINUTOS para probar el canary"
echo ""
echo "📋 Después de probar:"
echo "  1. Si todo OK, elimina el VirtualService:"
echo "     kubectl delete virtualservice demo-microservice-keda-canary -n default"
echo ""
echo "  2. El rolling update continuará automáticamente"
echo ""
echo "  3. Monitorear: kubectl get pods -l app=demo-microservice-keda -w"
