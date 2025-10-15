#!/bin/bash

# Script 5: Promover experimento exitoso a producción usando Argo Rollouts
set -e

echo "=== PASO 5: PROMOVIENDO EXPERIMENTO A PRODUCCIÓN ==="

cd "$(dirname "$0")/.."

# Verificar que el experimento esté funcionando
if ! kubectl get experiment demo-microservice-experiment >/dev/null 2>&1; then
    echo "❌ Error: Experimento no encontrado"
    exit 1
fi

# Verificar que el experimento esté saludable
EXPERIMENT_STATUS=$(kubectl get experiment demo-microservice-experiment -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
echo "Estado del experimento: $EXPERIMENT_STATUS"

# Obtener la imagen del experimento exitoso
EXPERIMENT_IMAGE=$(kubectl get experiment demo-microservice-experiment -o jsonpath='{.spec.templates[0].template.spec.containers[0].image}')
echo "Imagen del experimento: $EXPERIMENT_IMAGE"

# 1. Crear rollout con la imagen del experimento
echo "Creando Argo Rollout con imagen del experimento..."
kubectl apply -f k7s/04-rollout-services.yaml

# Aplicar rollout con la imagen del experimento
cat k7s/05-argo-rollout.yaml | sed "s|demo-microservice:stable|$EXPERIMENT_IMAGE|g" | kubectl apply -f -

# 2. Esperar que el rollout esté listo
echo "Esperando que el rollout esté listo..."
kubectl wait --for=condition=progressing rollout/demo-microservice-rollout --timeout=300s

# 3. Verificar estado del rollout
echo "Verificando estado del rollout..."
kubectl argo rollouts get rollout demo-microservice-rollout

# 4. Esperar que los pods estén listos
echo "Esperando pods del rollout..."
kubectl wait --for=condition=ready pod -l app=demo-microservice-rollout --timeout=300s

# 5. Probar el rollout antes de promover
echo "Probando rollout antes de promover..."
kubectl port-forward svc/demo-microservice-rollout-preview 3003:80 > /dev/null 2>&1 &
PREVIEW_PF_PID=$!
sleep 5

PREVIEW_RESPONSE=$(curl -s http://localhost:3003/api/v1/experiment/version 2>/dev/null || echo "Error")
echo "Respuesta del preview: $PREVIEW_RESPONSE"

kill $PREVIEW_PF_PID 2>/dev/null || true

# 6. Si el preview está bien, promover automáticamente
if [[ "$PREVIEW_RESPONSE" == *"healthy"* ]] || [[ "$PREVIEW_RESPONSE" == *"experiment"* ]]; then
    echo "Preview saludable, promoviendo a activo..."
    kubectl argo rollouts promote demo-microservice-rollout
    
    # Esperar promoción
    sleep 15
    
    # Verificar promoción
    echo "Verificando promoción..."
    kubectl argo rollouts get rollout demo-microservice-rollout
    
    # 7. Eliminar proxy inteligente (ya no es necesario)
    echo "Eliminando proxy inteligente (transición completa a rollout)..."
    kubectl delete deployment intelligent-proxy --ignore-not-found=true
    kubectl delete svc intelligent-proxy --ignore-not-found=true
    kubectl delete configmap intelligent-proxy-config --ignore-not-found=true
    
    # 8. Eliminar producción original (reemplazada por rollout)
    echo "Eliminando producción original (reemplazada por rollout)..."
    kubectl delete deployment demo-microservice-production --ignore-not-found=true
    kubectl delete svc demo-microservice-stable --ignore-not-found=true
    
    # 9. Configurar port-forward directo al rollout
    echo "Configurando acceso directo al rollout promovido..."
    pkill -f "kubectl port-forward.*8080" 2>/dev/null || true
    sleep 2
    kubectl port-forward svc/demo-microservice-rollout-active 8080:80 > /dev/null 2>&1 &
    ROLLOUT_PF_PID=$!
    sleep 3
    
    # 10. Limpiar experimento (ya promovido)
    echo "Limpiando experimento promovido..."
    kubectl delete experiment demo-microservice-experiment --ignore-not-found=true
    
    echo ""
    echo "✅ EXPERIMENTO PROMOVIDO Y TRANSICIÓN COMPLETA"
    echo ""
    echo "🔄 CAMBIOS REALIZADOS:"
    echo "  ✅ Rollout promovido exitosamente"
    echo "  ✅ Proxy inteligente eliminado (ya no necesario)"
    echo "  ✅ Producción original eliminada (reemplazada por rollout)"
    echo "  ✅ Experimento limpiado"
    echo "  ✅ Port-forward directo al rollout (PID: $ROLLOUT_PF_PID)"
    echo ""
    echo "Estado final:"
    kubectl get pods -l app=demo-microservice-rollout --show-labels
    
    echo ""
    echo "Rollout activo:"
    kubectl argo rollouts get rollout demo-microservice-rollout
    
    echo ""
    echo "Prueba final (acceso directo al rollout):"
    response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
    echo "Respuesta: $response"
    
    echo ""
    echo "🎉 TRANSICIÓN COMPLETA:"
    echo "  - El tráfico ahora va DIRECTAMENTE al rollout promovido"
    echo "  - No hay proxy intermedio"
    echo "  - No hay pods de producción original"
    echo "  - Solo el rollout con la nueva versión"
    
else
    echo "❌ Preview no está saludable, no se puede promover"
    echo "Revisa el estado del rollout y promueve manualmente si es necesario"
    exit 1
fi

echo ""
echo "Comandos útiles:"
echo "kubectl argo rollouts get rollout demo-microservice-rollout --watch"
echo "kubectl argo rollouts dashboard"
