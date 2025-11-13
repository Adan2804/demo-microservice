#!/bin/bash

# Script para probar Zero Downtime al cambiar la imagen del deployment
# Cambia de stable a experiment y monitorea que nunca haya 0 pods disponibles
set -e

echo "🧪 PRUEBA DE ZERO DOWNTIME - CAMBIO DE IMAGEN"
echo "=============================================="

cd "$(dirname "$0")/.."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Variables
DEPLOYMENT_NAME="demo-microservice-keda"
NAMESPACE="default"
CURRENT_IMAGE=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')

echo ""
echo "📋 CONFIGURACIÓN ACTUAL:"
echo "• Deployment: $DEPLOYMENT_NAME"
echo "• Namespace: $NAMESPACE"
echo "• Imagen actual: $CURRENT_IMAGE"

# Detectar si está en stable o experiment
if [[ $CURRENT_IMAGE == *"stable"* ]]; then
    NEW_IMAGE="zadan04/demo-microservice:experiment"
    echo "• Cambio: stable → experiment"
elif [[ $CURRENT_IMAGE == *"experiment"* ]]; then
    NEW_IMAGE="zadan04/demo-microservice:stable"
    echo "• Cambio: experiment → stable"
else
    echo "⚠️  Imagen no reconocida, usando experiment"
    NEW_IMAGE="zadan04/demo-microservice:experiment"
fi

echo "• Nueva imagen: $NEW_IMAGE"

# Verificar estado inicial
echo ""
echo "📊 ESTADO INICIAL:"
INITIAL_PODS=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME --field-selector=status.phase=Running --no-headers | wc -l)
echo "• Pods Running: $INITIAL_PODS"

if [ "$INITIAL_PODS" -lt 2 ]; then
    echo -e "${RED}❌ ERROR: Debe haber al menos 2 pods running antes de la prueba${NC}"
    exit 1
fi

# Crear archivo de log
LOG_FILE="/tmp/zero-downtime-test-$(date +%Y%m%d-%H%M%S).log"
echo "• Log file: $LOG_FILE"

# Función para contar pods running
count_running_pods() {
    kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l
}

# Función para monitorear pods
monitor_pods() {
    local min_pods=999
    local zero_downtime=true
    local start_time=$(date +%s)
    
    echo ""
    echo "🔍 MONITOREANDO PODS (Ctrl+C para detener)..."
    echo "Timestamp                | Running | Ready | Status"
    echo "-------------------------|---------|-------|---------------------------"
    
    while true; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local running_count=$(count_running_pods)
        local ready_count=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
        local pod_status=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq | tr '\n' ',' | sed 's/,$//')
        
        # Actualizar mínimo
        if [ "$running_count" -lt "$min_pods" ]; then
            min_pods=$running_count
        fi
        
        # Verificar zero downtime
        if [ "$running_count" -eq 0 ]; then
            zero_downtime=false
            echo -e "$timestamp | ${RED}$running_count${NC}       | $ready_count     | $pod_status ${RED}⚠️  DOWNTIME!${NC}"
        else
            echo "$timestamp | $running_count       | $ready_count     | $pod_status"
        fi
        
        # Log to file
        echo "$timestamp,$running_count,$ready_count,$pod_status" >> "$LOG_FILE"
        
        # Verificar si el rollout terminó
        local rollout_status=$(kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=1s 2>&1 || echo "in progress")
        if [[ $rollout_status == *"successfully rolled out"* ]]; then
            echo ""
            echo "✅ Rollout completado"
            break
        fi
        
        sleep 2
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "📊 RESULTADOS:"
    echo "• Duración: ${duration}s"
    echo "• Pods mínimos durante rollout: $min_pods"
    
    if [ "$zero_downtime" = true ] && [ "$min_pods" -gt 0 ]; then
        echo -e "${GREEN}✅ ZERO DOWNTIME EXITOSO - Nunca hubo 0 pods${NC}"
        return 0
    else
        echo -e "${RED}❌ DOWNTIME DETECTADO - Hubo 0 pods en algún momento${NC}"
        return 1
    fi
}

# Preguntar confirmación
echo ""
read -p "¿Deseas continuar con el cambio de imagen? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Prueba cancelada"
    exit 0
fi

# Iniciar monitoreo en background
monitor_pods &
MONITOR_PID=$!

# Esperar 2 segundos para que el monitoreo inicie
sleep 2

# Cambiar la imagen
echo ""
echo "🔄 CAMBIANDO IMAGEN..."
kubectl set image deployment/$DEPLOYMENT_NAME -n $NAMESPACE demo-microservice=$NEW_IMAGE

echo "✅ Comando de cambio ejecutado"
echo ""
echo "⏳ Esperando que el rollout complete..."

# Esperar que el monitoreo termine
wait $MONITOR_PID
MONITOR_RESULT=$?

# Verificar estado final
echo ""
echo "📊 ESTADO FINAL:"
FINAL_PODS=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME --field-selector=status.phase=Running --no-headers | wc -l)
FINAL_IMAGE=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')

echo "• Pods Running: $FINAL_PODS"
echo "• Imagen actual: $FINAL_IMAGE"

# Verificar que la imagen cambió
if [ "$FINAL_IMAGE" = "$NEW_IMAGE" ]; then
    echo -e "${GREEN}✅ Imagen actualizada correctamente${NC}"
else
    echo -e "${RED}❌ La imagen no se actualizó correctamente${NC}"
fi

# Probar conectividad
echo ""
echo "🧪 PROBANDO CONECTIVIDAD:"
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD_NAME" ]; then
    echo "• Pod: $POD_NAME"
    HEALTH_CHECK=$(kubectl exec -n $NAMESPACE $POD_NAME -- curl -s http://localhost:8080/actuator/health 2>/dev/null || echo "ERROR")
    
    if [[ $HEALTH_CHECK == *"UP"* ]]; then
        echo -e "${GREEN}✅ Health check: OK${NC}"
    else
        echo -e "${RED}❌ Health check: FAILED${NC}"
    fi
    
    INFO_CHECK=$(kubectl exec -n $NAMESPACE $POD_NAME -- curl -s http://localhost:8080/actuator/info 2>/dev/null || echo "ERROR")
    echo "• Info: $INFO_CHECK"
fi

# Resumen final
echo ""
echo "═══════════════════════════════════════════"
if [ $MONITOR_RESULT -eq 0 ]; then
    echo -e "${GREEN}🎉 PRUEBA EXITOSA - ZERO DOWNTIME CONFIRMADO${NC}"
    echo ""
    echo "✅ Configuraciones que funcionaron:"
    echo "• maxUnavailable: 0"
    echo "• maxSurge: 1"
    echo "• minAvailable: 1 (PDB)"
    echo "• minReplicaCount: 2 (KEDA)"
    echo "• preStop hook: 15s"
    echo "• terminationGracePeriod: 30s"
else
    echo -e "${RED}❌ PRUEBA FALLIDA - SE DETECTÓ DOWNTIME${NC}"
    echo ""
    echo "⚠️  Revisar configuraciones:"
    echo "• Verificar maxUnavailable: 0"
    echo "• Verificar PDB minAvailable: 1"
    echo "• Verificar readiness probes"
fi
echo "═══════════════════════════════════════════"

echo ""
echo "📄 Log guardado en: $LOG_FILE"
echo ""
echo "💡 COMANDOS ÚTILES:"
echo "• Ver log: cat $LOG_FILE"
echo "• Ver pods: kubectl get pods -l app=$DEPLOYMENT_NAME -w"
echo "• Rollback: kubectl rollout undo deployment/$DEPLOYMENT_NAME -n $NAMESPACE"
echo "• Cambiar de nuevo: $0"

exit $MONITOR_RESULT
