#!/bin/bash

# Script para desplegar con PAUSA automática después del primer pod
# Permite probar el pod nuevo con header antes de continuar

set -e

echo "🚀 DEPLOYMENT CON PAUSA PARA TESTING"
echo "====================================="
echo ""

# Verificar que existe el deployment
if ! kubectl get deployment demo-microservice-keda -n default >/dev/null 2>&1; then
    echo "❌ Deployment demo-microservice-keda no encontrado"
    exit 1
fi

# Obtener configuración actual
CURRENT_IMAGE=$(kubectl get deployment demo-microservice-keda -n default -o jsonpath='{.spec.template.spec.containers[0].image}')
CURRENT_VERSION=$(kubectl get deployment demo-microservice-keda -n default -o jsonpath='{.spec.template.metadata.labels.version}')
CURRENT_REPLICAS=$(kubectl get deployment demo-microservice-keda -n default -o jsonpath='{.spec.replicas}')

echo "📊 Configuración actual:"
echo "  Imagen:   $CURRENT_IMAGE"
echo "  Version:  $CURRENT_VERSION"
echo "  Replicas: $CURRENT_REPLICAS"
echo ""

# Solicitar nueva configuración
read -p "Nueva imagen (Enter para 'zadan04/demo-microservice:experiment'): " NEW_IMAGE
NEW_IMAGE=${NEW_IMAGE:-zadan04/demo-microservice:experiment}

read -p "Nueva version label (Enter para 'canary'): " NEW_VERSION
NEW_VERSION=${NEW_VERSION:-canary}

echo ""
echo "🔄 Aplicando cambios..."
echo "  Nueva imagen:  $NEW_IMAGE"
echo "  Nueva version: $NEW_VERSION"
echo ""

# Aplicar cambios
kubectl set image deployment/demo-microservice-keda \
    demo-microservice-v2=$NEW_IMAGE \
    -n default

kubectl patch deployment demo-microservice-keda -n default --type=json \
    -p='[{"op": "replace", "path": "/spec/template/metadata/labels/version", "value": "'$NEW_VERSION'"}]'

echo "✅ Cambios aplicados"
echo ""
echo "⏳ Esperando que el primer pod nuevo esté READY..."
echo ""

# Esperar a que aparezca un pod con la nueva version
TIMEOUT=300
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    NEW_PODS=$(kubectl get pods -n default -l app=demo-microservice-keda,version=$NEW_VERSION --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    
    if [ "$NEW_PODS" -gt 0 ]; then
        echo "✅ Primer pod nuevo detectado!"
        break
    fi
    
    echo "Esperando... ($ELAPSED/$TIMEOUT segundos)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "❌ Timeout esperando pod nuevo"
    exit 1
fi

# Pausar el rollout
echo ""
echo "⏸️  PAUSANDO el rolling update..."
kubectl rollout pause deployment/demo-microservice-keda -n default

echo ""
echo "✅ DEPLOYMENT PAUSADO"
echo ""
echo "📊 Estado actual:"
kubectl get pods -l app=demo-microservice-keda -n default
echo ""

# Obtener IP y puerto
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "192.168.49.2")
NODE_PORT=$(kubectl get svc demo-microservice-keda -n default -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")

echo "🧪 PRUEBAS:"
echo ""
if [ -n "$NODE_PORT" ]; then
    echo "Tráfico NORMAL (pods stable):"
    echo "  curl http://${MINIKUBE_IP}:${NODE_PORT}/actuator/info"
    echo ""
    echo "Tráfico CANARY (pod nuevo):"
    echo "  curl -H 'x-test-new: true' http://${MINIKUBE_IP}:${NODE_PORT}/actuator/info"
else
    echo "Port-forward necesario:"
    echo "  kubectl port-forward svc/demo-microservice-keda 8080:8080"
    echo ""
    echo "Tráfico NORMAL: curl http://localhost:8080/actuator/info"
    echo "Tráfico CANARY: curl -H 'x-test-new: true' http://localhost:8080/actuator/info"
fi

echo ""
echo "⏱️  Tómate el tiempo que necesites para probar..."
echo ""
echo "📋 Cuando termines de probar:"
echo ""
echo "  ✅ Si todo OK, continuar el rollout:"
echo "     kubectl rollout resume deployment/demo-microservice-keda -n default"
echo ""
echo "  ❌ Si hay problemas, hacer rollback:"
echo "     kubectl rollout undo deployment/demo-microservice-keda -n default"
echo ""
echo "  📊 Ver estado:"
echo "     kubectl rollout status deployment/demo-microservice-keda -n default"
echo "     kubectl get pods -l app=demo-microservice-keda -w"
