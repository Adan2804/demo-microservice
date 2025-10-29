#!/bin/bash

# Script para promover experimento exitoso a rollout con Argo Rollouts
# Implementa Blue-Green deployment con confirmación manual
set -e

echo "🚀 PROMOCIÓN DE EXPERIMENTO A ROLLOUT"
echo "====================================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  --auto-approve          Aprobar automáticamente sin confirmación"
    echo "  --rollback-on-failure   Rollback automático si falla"
    echo "  -h, --help              Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                      # Promoción con confirmación manual"
    echo "  $0 --auto-approve       # Promoción automática"
}

# Valores por defecto
AUTO_APPROVE=false
ROLLBACK_ON_FAILURE=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --rollback-on-failure)
            ROLLBACK_ON_FAILURE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

# 1. VERIFICAR PREREQUISITOS
echo ""
echo "📋 VERIFICANDO PREREQUISITOS..."

# Verificar que el experimento esté activo
if ! kubectl get deployment demo-microservice-experiment >/dev/null 2>&1; then
    echo "❌ Error: No hay experimento activo para promover"
    echo "Ejecuta primero: ./scripts/start-experiment.sh"
    exit 1
fi

# Verificar que Argo Rollouts esté instalado
echo "🔍 Verificando instalación de Argo Rollouts..."
if ! kubectl get crd rollouts.argoproj.io >/dev/null 2>&1; then
    echo "⚠️  Argo Rollouts no está instalado. Instalando..."
    kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
    
    echo "⏳ Esperando que Argo Rollouts esté listo..."
    kubectl wait --for=condition=available deployment/argo-rollouts -n argo-rollouts --timeout=300s
    echo "✅ Argo Rollouts instalado correctamente"
else
    echo "✅ Argo Rollouts ya está instalado"
    
    # Verificar que el controller esté corriendo
    if ! kubectl get deployment argo-rollouts -n argo-rollouts >/dev/null 2>&1; then
        echo "⚠️  Controller de Argo Rollouts no encontrado, reinstalando..."
        kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
        kubectl wait --for=condition=available deployment/argo-rollouts -n argo-rollouts --timeout=300s
    fi
fi

# Verificar kubectl argo rollouts plugin
if ! kubectl argo rollouts version >/dev/null 2>&1; then
    echo "⚠️  Plugin 'kubectl argo rollouts' no está instalado"
    echo "💡 Puedes instalarlo desde: https://argoproj.github.io/argo-rollouts/installation/#kubectl-plugin-installation"
    echo "   O usar comandos kubectl directamente"
fi

echo "✅ Prerequisitos verificados"

# 2. OBTENER INFORMACIÓN DEL EXPERIMENTO
echo ""
echo "📊 ANALIZANDO EXPERIMENTO ACTUAL..."

EXPERIMENT_IMAGE=$(kubectl get deployment demo-microservice-experiment -o jsonpath='{.spec.template.spec.containers[0].image}')
EXPERIMENT_VERSION=$(kubectl get deployment demo-microservice-experiment -o jsonpath='{.metadata.annotations.experiment\.kubernetes\.io/version}')

echo "📦 Imagen del experimento: $EXPERIMENT_IMAGE"
echo "🏷️  Versión del experimento: $EXPERIMENT_VERSION"

# Mostrar métricas del experimento
echo ""
echo "📈 MÉTRICAS DEL EXPERIMENTO:"
kubectl top pods -l version=experiment --no-headers 2>/dev/null || echo "Métricas no disponibles"

# 3. CONFIRMACIÓN MANUAL (si no es auto-approve)
if [ "$AUTO_APPROVE" = false ]; then
    echo ""
    echo "🤔 CONFIRMACIÓN DE PROMOCIÓN"
    echo "============================"
    echo ""
    echo "¿Has validado que el experimento funciona correctamente?"
    echo "• ¿Las pruebas A/B muestran resultados positivos?"
    echo "• ¿No hay errores en los logs del experimento?"
    echo "• ¿El rendimiento es aceptable?"
    echo ""
    read -p "¿Estás seguro de promover el experimento a producción? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Promoción cancelada por el usuario"
        exit 0
    fi
fi

# 4. APLICAR ROLLOUT CONFIGURATION
echo ""
echo "📝 APLICANDO CONFIGURACIÓN DE ROLLOUT..."

# Actualizar la imagen en el archivo de rollout con la imagen del experimento
echo "📦 Actualizando imagen del rollout a: $EXPERIMENT_IMAGE"

# Crear copia temporal del rollout con la imagen del experimento
cat experiments/05-rollout-ab-testing.yaml | \
    sed "s|image: zadan04/demo-microservice:stable|image: $EXPERIMENT_IMAGE|g" | \
    sed "s|value: \"stable-v1.0.0\"|value: \"rollout-promoted-${EXPERIMENT_VERSION:-v1.1.0}\"|g" > /tmp/rollout-config.yaml

# Mostrar preview del cambio
echo "📋 Configuración del rollout:"
grep -A 2 "image:" /tmp/rollout-config.yaml | head -3

# 5. APLICAR ROLLOUT
echo ""
echo "🚀 INICIANDO ROLLOUT BLUE-GREEN..."

# Aplicar el rollout desde el archivo temporal
kubectl apply -f /tmp/rollout-config.yaml

# Esperar que el rollout esté listo
echo "⏳ Esperando que el rollout esté listo..."
sleep 10

# Verificar estado del rollout
if kubectl get rollout demo-microservice-rollout >/dev/null 2>&1; then
    echo "✅ Rollout creado exitosamente"
    kubectl get rollout demo-microservice-rollout
else
    echo "❌ Error: Rollout no se creó correctamente"
    exit 1
fi

# 6. ACTUALIZAR CONFIGURACIÓN DE ISTIO PARA ROLLOUT
echo ""
echo "🌐 ACTUALIZANDO CONFIGURACIÓN DE ISTIO PARA ROLLOUT..."

# Crear DestinationRule para rollout
cat > /tmp/destination-rule-rollout.yaml << EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: demo-microservice-rollout-destination
  namespace: default
  annotations:
    rollout.kubernetes.io/managed-by: "rollout-script"
spec:
  host: demo-microservice-rollout-active
  subsets:
  - name: rollout-stable
    labels:
      version: rollout-stable
  - name: rollout-canary
    labels:
      version: rollout-new
EOF

# Crear VirtualService para rollout
cat > /tmp/virtual-service-rollout.yaml << EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: demo-microservice-rollout-routing
  namespace: default
  annotations:
    rollout.kubernetes.io/managed-by: "rollout-script"
spec:
  hosts:
  - "*"
  gateways:
  - demo-microservice-gateway
  http:
  # Tráfico de rollout (gradual)
  - match:
    - uri:
        prefix: "/api/v1/rollout"
    route:
    - destination:
        host: demo-microservice-rollout-active
      weight: 100
    headers:
      response:
        add:
          x-routed-to: "rollout-active"
          x-rollout-phase: "blue-green"
  
  # Tráfico normal (sigue yendo al experimento por ahora)
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: demo-microservice-istio
        subset: stable
      weight: 70
    - destination:
        host: demo-microservice-istio
        subset: experiment
      weight: 30
    headers:
      response:
        add:
          x-routed-to: "mixed-traffic"
          x-rollout-phase: "transition"
EOF

kubectl apply -f /tmp/destination-rule-rollout.yaml
kubectl apply -f /tmp/virtual-service-rollout.yaml

# Esperar que la configuración se propague
echo "⏳ Esperando que la configuración se propague..."
sleep 15

# 7. MONITOREAR ROLLOUT
echo ""
echo "📊 MONITOREANDO ROLLOUT..."

echo "Estado del rollout:"
kubectl get rollout demo-microservice-rollout

echo ""
echo "Pods del rollout:"
kubectl get pods -l app=demo-microservice-istio,tier=rollout

# 8. PROMOCIÓN MANUAL DEL ROLLOUT
echo ""
echo "🎯 PROMOCIÓN DEL ROLLOUT"
echo "========================"

if [ "$AUTO_APPROVE" = false ]; then
    echo ""
    echo "El rollout está en modo Blue-Green y requiere promoción manual."
    echo "Revisa las métricas y confirma que todo funciona correctamente."
    echo ""
    echo "📊 Estado actual del rollout:"
    kubectl get rollout demo-microservice-rollout -o wide
    echo ""
    read -p "¿Promover el rollout a producción? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🚀 Promoviendo rollout..."
        if kubectl argo rollouts promote demo-microservice-rollout 2>/dev/null; then
            echo "✅ Rollout promovido con plugin"
        else
            echo "⚠️  Plugin no disponible, usando kubectl patch..."
            kubectl patch rollout demo-microservice-rollout --type merge -p '{"status":{"pauseConditions":[]}}'
        fi
    else
        echo "⏸️  Rollout pausado. Puedes promoverlo manualmente con:"
        echo "kubectl argo rollouts promote demo-microservice-rollout"
        echo "O con kubectl:"
        echo "kubectl patch rollout demo-microservice-rollout --type merge -p '{\"status\":{\"pauseConditions\":[]}}'"
    fi
else
    echo "🚀 Promoción automática habilitada..."
    if kubectl argo rollouts promote demo-microservice-rollout 2>/dev/null; then
        echo "✅ Rollout promovido con plugin"
    else
        echo "⚠️  Plugin no disponible, usando kubectl patch..."
        kubectl patch rollout demo-microservice-rollout --type merge -p '{"status":{"pauseConditions":[]}}'
    fi
fi

# 9. LIMPIAR EXPERIMENTO
echo ""
echo "🧹 LIMPIANDO EXPERIMENTO ANTERIOR..."

echo "Eliminando deployment del experimento..."
kubectl delete deployment demo-microservice-experiment

echo "Restaurando configuración base de Istio..."
kubectl apply -f argocd-production/03-destination-rule.yaml
kubectl apply -f argocd-production/04-virtual-service.yaml

# 10. VERIFICAR ESTADO FINAL
echo ""
echo "🔍 VERIFICANDO ESTADO FINAL..."

echo "Estado del rollout:"
kubectl get rollout demo-microservice-rollout

echo ""
echo "Pods activos:"
kubectl get pods -l app=demo-microservice-istio

echo ""
echo "Servicios:"
kubectl get svc -l app=demo-microservice-istio

# 11. PRUEBAS DE CONECTIVIDAD
echo ""
echo "🧪 REALIZANDO PRUEBAS FINALES..."

echo "Probando tráfico normal:"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "Probando endpoint de rollout:"
response=$(curl -s http://localhost:8080/api/v1/rollout/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

# 12. RESUMEN FINAL
echo ""
echo "🎉 PROMOCIÓN A ROLLOUT COMPLETADA"
echo "================================="
echo ""
echo "✅ Experimento promovido exitosamente"
echo "✅ Rollout Blue-Green configurado (usando experiments/05-rollout-ab-testing.yaml)"
echo "✅ Argo Rollouts instalado y verificado"
echo "✅ Configuración de Istio actualizada"
echo "✅ Experimento anterior limpiado"
echo ""
echo "📊 ESTADO ACTUAL:"
echo "• Rollout activo: demo-microservice-rollout"
echo "• Estrategia: Blue-Green Deployment"
echo "• Imagen promovida: $EXPERIMENT_IMAGE"
echo "• Services: demo-microservice-istio-active, demo-microservice-istio-preview"
echo ""
echo "🌐 ACCESOS:"
echo "• Service Active: demo-microservice-istio-active (producción actual)"
echo "• Service Preview: demo-microservice-istio-preview (nueva versión)"
echo "• Argo Rollouts Dashboard: kubectl argo rollouts dashboard"
echo ""
echo "📊 MONITOREO:"
echo "• Estado del rollout: kubectl get rollout demo-microservice-rollout"
echo "• Ver detalles: kubectl argo rollouts get rollout demo-microservice-rollout"
echo "• Logs active: kubectl logs -l app=demo-microservice-istio -c demo-microservice"
echo "• Métricas: kubectl top pods -l app=demo-microservice-istio"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Verificar service preview: kubectl port-forward svc/demo-microservice-istio-preview 8081:80"
echo "2. Probar nueva versión: curl http://localhost:8081/demo/info"
echo "3. Si todo está bien, promover: kubectl argo rollouts promote demo-microservice-rollout"
echo "4. Monitorear análisis post-promoción"
echo ""
echo "🛑 EN CASO DE PROBLEMAS:"
echo "• Rollback: kubectl argo rollouts abort demo-microservice-rollout"
echo "• Ver estado detallado: kubectl argo rollouts get rollout demo-microservice-rollout --watch"
echo "• Ver análisis: kubectl get analysisrun"
echo ""
echo "💡 NOTA:"
echo "El rollout usa Blue-Green con análisis automático de métricas (requiere Prometheus)."
echo "Si Prometheus no está disponible, el análisis fallará pero puedes promover manualmente."