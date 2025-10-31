#!/bin/bash

# Script para monitorear el Sistema de Escalado Inteligente
# Muestra en tiempo real el comportamiento del escalado basado en horarios

set -e

echo "📊 MONITOR DE ESCALADO INTELIGENTE"
echo "===================================="
echo ""

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para obtener la hora actual en Colombia
get_colombia_time() {
    TZ='America/Bogota' date '+%H:%M:%S'
}

# Función para determinar el periodo activo
get_active_period() {
    local hour=$(TZ='America/Bogota' date '+%H')
    
    if [ $hour -eq 17 ]; then
        echo "PRUEBA DOWNSCALE (5PM-6PM) ⏰"
    else
        echo "UPSCALE (Resto del día)"
    fi
}

# Función para mostrar el estado de los ScaledObjects
show_scaledobjects_status() {
    echo -e "${BLUE}📋 Estado de ScaledObjects:${NC}"
    echo "----------------------------"
    
    # Downscale (nocturno)
    if kubectl get scaledobject demo-microservice-intelligent-downscale -n default >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Downscale (Nocturno):${NC} Activo"
        kubectl get scaledobject demo-microservice-intelligent-downscale -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True" && echo "   Estado: Ready" || echo "   Estado: Not Ready"
    else
        echo -e "${RED}❌ Downscale (Nocturno):${NC} No encontrado"
    fi
    
    # Upscale (diurno)
    if kubectl get scaledobject demo-microservice-intelligent-upscale -n default >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Upscale (Diurno):${NC} Activo"
        kubectl get scaledobject demo-microservice-intelligent-upscale -n default -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True" && echo "   Estado: Ready" || echo "   Estado: Not Ready"
    else
        echo -e "${RED}❌ Upscale (Diurno):${NC} No encontrado"
    fi
    
    echo ""
}

# Función para mostrar métricas actuales
show_current_metrics() {
    echo -e "${BLUE}📈 Métricas Actuales:${NC}"
    echo "---------------------"
    
    # Obtener métricas de CPU y Memoria
    local cpu_usage=$(kubectl top pods -n default -l app=demo-microservice-istio --no-headers 2>/dev/null | awk '{sum+=$2} END {print sum}' | sed 's/m//')
    local mem_usage=$(kubectl top pods -n default -l app=demo-microservice-istio --no-headers 2>/dev/null | awk '{sum+=$3} END {print sum}' | sed 's/Mi//')
    
    if [ -n "$cpu_usage" ] && [ "$cpu_usage" != "0" ]; then
        echo "CPU Total: ${cpu_usage}m"
        
        # Determinar si está por encima o debajo del umbral
        if [ "$cpu_usage" -lt 500 ]; then
            echo -e "   ${GREEN}✅ Por debajo del umbral (< 50%)${NC}"
        else
            echo -e "   ${YELLOW}⚠️  Por encima del umbral (>= 50%)${NC}"
        fi
    else
        echo "CPU: No disponible (instalar metrics-server)"
    fi
    
    if [ -n "$mem_usage" ] && [ "$mem_usage" != "0" ]; then
        echo "Memoria Total: ${mem_usage}Mi"
        
        # Determinar si está por encima o debajo del umbral
        if [ "$mem_usage" -lt 512 ]; then
            echo -e "   ${GREEN}✅ Por debajo del umbral (< 50%)${NC}"
        else
            echo -e "   ${YELLOW}⚠️  Por encima del umbral (>= 50%)${NC}"
        fi
    else
        echo "Memoria: No disponible (instalar metrics-server)"
    fi
    
    echo ""
}

# Función para mostrar el estado de los pods
show_pods_status() {
    echo -e "${BLUE}🔷 Estado de Pods:${NC}"
    echo "------------------"
    
    local pod_count=$(kubectl get pods -n default -l app=demo-microservice-istio --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local desired_count=$(kubectl get deployment demo-microservice-production-istio -n default -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    echo "Pods Actuales: $pod_count"
    echo "Pods Deseados: $desired_count"
    
    if [ "$pod_count" -eq "$desired_count" ]; then
        echo -e "${GREEN}✅ Estado: Estable${NC}"
    else
        echo -e "${YELLOW}⚠️  Estado: Escalando...${NC}"
    fi
    
    echo ""
    echo "Detalle de Pods:"
    kubectl get pods -n default -l app=demo-microservice-istio -o wide 2>/dev/null || echo "No hay pods disponibles"
    
    echo ""
}

# Función para mostrar los HPAs generados por KEDA
show_hpa_status() {
    echo -e "${BLUE}⚙️  HPAs Generados por KEDA:${NC}"
    echo "---------------------------"
    
    kubectl get hpa -n default | grep "demo-microservice-intelligent" || echo "No hay HPAs activos"
    
    echo ""
}

# Función para mostrar eventos recientes
show_recent_events() {
    echo -e "${BLUE}📝 Eventos Recientes (últimos 10):${NC}"
    echo "-----------------------------------"
    
    kubectl get events -n default --sort-by='.lastTimestamp' | grep -E "demo-microservice|ScaledObject|HorizontalPodAutoscaler" | tail -10 || echo "No hay eventos recientes"
    
    echo ""
}

# Función para mostrar predicción del próximo cambio
show_next_change_prediction() {
    local current_hour=$(TZ='America/Bogota' date '+%H')
    local current_minute=$(TZ='America/Bogota' date '+%M')
    
    echo -e "${BLUE}🔮 Próximo Cambio de Periodo:${NC}"
    echo "-----------------------------"
    
    if [ $current_hour -eq 17 ]; then
        echo "Periodo Actual: PRUEBA DOWNSCALE (5:00 PM - 6:00 PM) ⏰"
        echo "Próximo Cambio: 18:00 (6:00 PM) - Activación de Upscale"
        echo "Comportamiento Esperado:"
        echo "  • Escalar a 3 pods de forma inmediata"
        echo "  • Sin evaluar métricas"
        echo ""
        echo "Comportamiento Actual (5PM-6PM):"
        echo "  • Si CPU y Memoria < 50%: Reducir a 2 pods"
        echo "  • Si CPU o Memoria >= 50%: Mantener 3 pods"
        echo "  • Cooldown: 10 minutos para estabilización"
    elif [ $current_hour -lt 17 ]; then
        echo "Periodo Actual: UPSCALE (Capacidad Normal)"
        echo "Próximo Cambio: 17:00 (5:00 PM) - Activación de Downscale"
        local hours_until=$((17 - current_hour))
        echo "Tiempo restante: ~${hours_until} horas"
        echo "Comportamiento Esperado:"
        echo "  • Si CPU y Memoria < 50%: Reducir a 2 pods"
        echo "  • Si CPU o Memoria >= 50%: Mantener 3 pods"
    else
        echo "Periodo Actual: UPSCALE (Capacidad Restaurada)"
        echo "Próximo Cambio: 17:00 (5:00 PM) - Activación de Downscale"
        local hours_until=$((24 - current_hour + 17))
        echo "Tiempo restante: ~${hours_until} horas"
        echo "Comportamiento Esperado:"
        echo "  • Mantener mínimo 3 pods"
        echo "  • Puede escalar hasta 10 pods si hay demanda"
    fi
    
    echo ""
}

# Función principal de monitoreo continuo
monitor_continuous() {
    echo "Iniciando monitoreo continuo (Ctrl+C para detener)..."
    echo ""
    
    while true; do
        clear
        echo "📊 MONITOR DE ESCALADO INTELIGENTE"
        echo "===================================="
        echo ""
        echo "🕐 Hora Colombia: $(get_colombia_time)"
        echo "📅 Periodo Activo: $(get_active_period)"
        echo ""
        
        show_scaledobjects_status
        show_current_metrics
        show_pods_status
        show_hpa_status
        show_next_change_prediction
        
        echo "Actualizando en 30 segundos... (Ctrl+C para detener)"
        sleep 30
    done
}

# Función para mostrar un snapshot único
show_snapshot() {
    echo "🕐 Hora Colombia: $(get_colombia_time)"
    echo "📅 Periodo Activo: $(get_active_period)"
    echo ""
    
    show_scaledobjects_status
    show_current_metrics
    show_pods_status
    show_hpa_status
    show_recent_events
    show_next_change_prediction
}

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  --continuous, -c    Monitoreo continuo (actualiza cada 30s)"
    echo "  --snapshot, -s      Muestra un snapshot único del estado actual"
    echo "  --events, -e        Muestra solo eventos recientes"
    echo "  --help, -h          Muestra esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                  # Snapshot único (por defecto)"
    echo "  $0 --continuous     # Monitoreo continuo"
    echo "  $0 --events         # Solo eventos"
}

# Procesar argumentos
case "${1:-}" in
    --continuous|-c)
        monitor_continuous
        ;;
    --snapshot|-s)
        show_snapshot
        ;;
    --events|-e)
        show_recent_events
        ;;
    --help|-h)
        show_help
        ;;
    "")
        show_snapshot
        ;;
    *)
        echo "❌ Opción desconocida: $1"
        show_help
        exit 1
        ;;
esac
