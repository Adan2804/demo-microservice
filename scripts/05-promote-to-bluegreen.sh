#!/bin/bash

# Script para promover el experimento exitoso a Blue-Green Rollout
set -e

echo "🔄 PROMOVIENDO EXPERIMENTO A BLUE-GREEN ROLLOUT"
echo "==============================================="

cd "$(dirname "$0")/.."

if ! kubectl get experiment demo-microservice-ab-experiment >/dev/null 2>&1; then
    echo "❌ No hay experimento activo"
    echo "Ejecuta primero: ./scripts/04-start-ab-experiment.sh"
    exit 1
fi

EXPERIMENT_STATUS=$(kubectl get experiment demo-microservice-ab-experiment -o jsonpath='{.status.phase}')
echo "📊 Estado del experimento: $EXPERIMENT_STATUS"

if [ "$EXPERIMENT_STATUS" != "Successful" ] && [ "$EXPERIMENT_STATUS" != "Running" ]; then
    echo "⚠️  El experimento no está en estado exitoso o corriendo"
    echo "Estado actual: $EXPERIMENT_STATUS"
    read -p "¿Deseas continuar de todos modos? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

eval $(minikube docker-env)

echo ""
echo "🚀 DESPLEGANDO BLUE-GREEN ROLLOUT..."
kubectl apply -f experiments/05-rollout-ab-testing.yaml

echo ""
echo "⏳ ESPERANDO QUE EL ROLLOUT ESTÉ LISTO..."
sleep 10

echo ""
echo "📊 ESTADO DEL ROLLOUT:"
kubectl argo rollouts status demo-microservice-rollout --watch=false || \
    kubectl get rollout demo-microservice-rollout

echo ""
echo "🔄 ACTUALIZANDO A VERSIÓN EXPERIMENTAL..."
kubectl argo rollouts set image demo-microservice-rollout \
  demo-microservice=demo-microservice:experiment || \
    kubectl patch rollout demo-microservice-rollout --type='json' \
      -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value":"demo-microservice:experiment"}]'

echo ""
echo "⏳ ESPERANDO ANÁLISIS PRE-PROMOCIÓN..."
sleep 15

echo ""
echo "📊 ESTADO ACTUAL:"
kubectl argo rollouts get rollout demo-microservice-rollout || \
    kubectl get rollout demo-microservice-rollout -o wide

echo ""
echo "🎉 BLUE-GREEN ROLLOUT INICIADO"
echo "=============================="
echo ""
echo "📋 INFORMACIÓN:"
echo "• Rollout: demo-microservice-rollout"
echo "• Estrategia: Blue-Green"
echo "• Active Service: demo-microservice-istio-active"
echo "• Preview Service: demo-microservice-istio-preview"
echo ""
echo "🔍 VERIFICACIÓN:"
echo "• Ver servicios:"
echo "  kubectl get svc | grep demo-microservice-istio"
echo ""
echo "• Ver pods:"
echo "  kubectl get pods -l app=demo-microservice-istio"
echo ""
echo "• Probar versión PREVIEW (nueva):"
echo "  kubectl port-forward svc/demo-microservice-istio-preview 8081:80"
echo "  curl http://localhost:8081/demo/info"
echo ""
echo "• Probar versión ACTIVE (actual):"
echo "  kubectl port-forward svc/demo-microservice-istio-active 8082:80"
echo "  curl http://localhost:8082/demo/info"
echo ""
echo "🎛️  GESTIÓN DEL ROLLOUT:"
echo "• Ver estado detallado:"
echo "  kubectl argo rollouts get rollout demo-microservice-rollout"
echo ""
echo "• Ver dashboard:"
echo "  kubectl argo rollouts dashboard"
echo ""
echo "• PROMOVER (cambiar tráfico a nueva versión):"
echo "  kubectl argo rollouts promote demo-microservice-rollout"
echo ""
echo "• ABORTAR (volver a versión anterior):"
echo "  kubectl argo rollouts abort demo-microservice-rollout"
echo ""
echo "• Ver análisis:"
echo "  kubectl get analysisrun"
echo ""
echo "💡 FLUJO BLUE-GREEN:"
echo "1. ✅ Nueva versión desplegada en PREVIEW"
echo "2. ⏳ Análisis pre-promoción en curso"
echo "3. ⏸️  Esperando aprobación manual"
echo "4. 🚀 Ejecuta 'promote' para cambiar tráfico a nueva versión"
echo "5. ✅ Análisis post-promoción"
echo "6. 🗑️  Versión anterior se elimina después de 30s"
echo ""
echo "⚠️  IMPORTANTE:"
echo "El rollout está en pausa esperando tu aprobación."
echo "Revisa la versión preview y ejecuta promote cuando estés listo."
echo ""
echo "🧹 LIMPIEZA DEL EXPERIMENT:"
echo "Una vez que el rollout esté estable, puedes eliminar el experiment:"
echo "  kubectl delete experiment demo-microservice-ab-experiment"
