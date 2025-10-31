#!/bin/bash

# Script para probar el Sistema de Escalado Inteligente
# Simula diferentes escenarios de carga para validar el comportamiento

set -e

echo "🧪 PRUEBA DEL SISTEMA DE ESCALADO INTELIGENTE"
echo "=============================================="
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Función para mostrar la hora actual
show_time() {
    echo -e "${BLUE}🕐 Hora Colombia: $(TZ='America/Bogota' date '+%H:%M:%S')${NC}"
}

# Función para verificar el estado actual
check_current_state() {
    echo ""
    echo -e "${BLUE}📊 Estado Actual:${NC}"
    echo "----------------"
    
    local pod_count=$(kubectl get pods -n default -l app=demo-microservice-istio --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    local desired_count=$(kubectl get deployment demo-microservice-production-istio -n default -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    echo "Pods Actuales: $pod_count"
    echo "Pods Deseados: $desired_count"
    
    # Verificar ScaledObjects
    if kubectl get scaledobject demo-microservice-intelligent-downscale -n default >/dev/null 2>&1; then
        echo -e "${GREEN}✅ ScaledObject Downscale: Activo${NC}"
    else
        echo -e "${RED}❌ ScaledObject Downscale: No encontrado${NC}"
    fi
    
    if kubectl get scaledobject demo-microservice-intelligent-upscale -n default >/dev/null 2>&1; then
        echo -e "${GREEN}✅ ScaledObject Upscale: Activo${NC}"
    else
        echo -e "${RED}❌ ScaledObject Upscale: No encontrado${NC}"
    fi
    
    echo ""
}

# Función para simular carga baja
simulate_low_load() {
    echo -e "${YELLOW}📉 Simulando Carga Baja...${NC}"
    echo "Deteniendo generadores de carga existentes..."
    
    kubectl delete pod load-generator-high --ignore-not-found=true
    kubectl delete pod load-generator-medium --ignore-not-found=true
    
    echo -e "${GREEN}✅ Carga baja simulada (sin generadores activos)${NC}"
    echo "Esperado: CPU y Memoria < 50%"
    echo ""
}

# Función para simular carga alta
simulate_high_load() {
    echo -e "${YELLOW}📈 Simulando Carga Alta...${NC}"
    
    # Detener generadores anteriores
    kubectl delete pod load-generator-high --ignore-not-found=true 2>/dev/null || true
    kubectl delete pod load-generator-medium --ignore-not-found=true 2>/dev/null || true
    
    # Crear generador de carga alta
    echo "Creando generador de carga..."
    kubectl run load-generator-high --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://demo-microservice-istio.default.svc.cluster.local; done" 2>/dev/null || true
    
    echo -e "${GREEN}✅ Carga alta simulada${NC}"
    echo "Esperado: CPU aumentará gradualmente"
    echo ""
}

# Función para limpiar generadores de carga
cleanup_load_generators() {
    echo -e "${BLUE}🧹 Limpiando generadores de carga...${NC}"
    kubectl delete pod load-generator-high --ignore-not-found=true 2>/dev/null || true
    kubectl delete pod load-generator-medium --ignore-not-found=true 2>/dev/null || true
    echo -e "${GREEN}✅ Limpieza completada${NC}"
    echo ""
}

# Función para mostrar métricas
show_metrics() {
    echo -e "${BLUE}📊 Métricas Actuales:${NC}"
    echo "--------------------"
    
    echo "Pods:"
    kubectl get pods -n default -l app=demo-microservice-istio
    
    echo ""
    echo "Uso de Recursos (requiere metrics-server):"
    kubectl top pods -n default -l app=demo-microservice-istio 2>/dev/null || echo "⚠️  metrics-server no disponible"
    
    echo ""
    echo "HPAs:"
    kubectl get hpa -n default | grep "demo-microservice-intelligent" || echo "No hay HPAs activos"
    
    echo ""
}

# Función para esperar y monitorear
wait_and_monitor() {
    local duration=$1
    local message=$2
    
    echo -e "${YELLOW}⏳ $message${NC}"
    echo "Duración: ${duration}s"
    echo ""
    
    for i in $(seq 1 $duration); do
        if [ $((i % 30)) -eq 0 ]; then
            echo "Transcurridos: ${i}s / ${duration}s"
            show_metrics
        fi
        sleep 1
    done
    
    echo -e "${GREEN}✅ Periodo de espera completado${NC}"
    echo ""
}

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIÓN]"
    echo ""
    echo "Opciones:"
    echo "  --test-low       Probar escalado con carga baja"
    echo "  --test-high      Probar que NO escala con carga alta"
    echo "  --test-full      Prueba completa (baja → alta → baja)"
    echo "  --status         Mostrar estado actual"
    echo "  --cleanup        Limpiar generadores de carga"
    echo "  --help           Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0 --status      # Ver estado actual"
    echo "  $0 --test-low    # Probar downscale con carga baja"
    echo "  $0 --test-high   # Verificar que mantiene 3 pods con carga alta"
    echo "  $0 --test-full   # Prueba completa de todos los escenarios"
}

# Menú principal
case "${1:-}" in
    --test-low)
        show_time
        check_current_state
        
        echo -e "${BLUE}🧪 PRUEBA 1: Escalado con Carga Baja${NC}"
        echo "======================================"
        echo ""
        echo "Objetivo: Verificar que escala de 3 → 2 pods cuando CPU y Memoria < 50%"
        echo "Periodo: Solo activo entre 5:00 PM - 6:00 PM"
        echo ""
        
        simulate_low_load
        
        echo "Esperando 2 minutos para que las métricas se estabilicen..."
        wait_and_monitor 120 "Monitoreando métricas..."
        
        echo -e "${BLUE}📊 Resultado:${NC}"
        check_current_state
        show_metrics
        
        echo ""
        echo -e "${YELLOW}💡 Nota:${NC}"
        echo "• El downscale tiene un cooldown de 10 minutos"
        echo "• Solo se activa entre 5:00 PM - 6:00 PM"
        echo "• Verifica la hora actual con: TZ='America/Bogota' date"
        ;;
    
    --test-high)
        show_time
        check_current_state
        
        echo -e "${BLUE}🧪 PRUEBA 2: Protección con Carga Alta${NC}"
        echo "======================================="
        echo ""
        echo "Objetivo: Verificar que NO escala hacia abajo cuando CPU >= 50%"
        echo ""
        
        simulate_high_load
        
        echo "Esperando 2 minutos para que la carga aumente..."
        wait_and_monitor 120 "Generando carga..."
        
        echo -e "${BLUE}📊 Resultado:${NC}"
        check_current_state
        show_metrics
        
        echo ""
        echo -e "${YELLOW}💡 Nota:${NC}"
        echo "• Debería mantener 3 pods debido a la carga alta"
        echo "• Limpia la carga con: $0 --cleanup"
        ;;
    
    --test-full)
        show_time
        
        echo -e "${BLUE}🧪 PRUEBA COMPLETA: Todos los Escenarios${NC}"
        echo "=========================================="
        echo ""
        
        # Escenario 1: Carga baja
        echo -e "${BLUE}Escenario 1: Carga Baja${NC}"
        simulate_low_load
        wait_and_monitor 120 "Esperando estabilización con carga baja..."
        check_current_state
        
        # Escenario 2: Carga alta
        echo -e "${BLUE}Escenario 2: Carga Alta${NC}"
        simulate_high_load
        wait_and_monitor 120 "Esperando aumento de carga..."
        check_current_state
        
        # Escenario 3: Vuelta a carga baja
        echo -e "${BLUE}Escenario 3: Vuelta a Carga Baja${NC}"
        simulate_low_load
        wait_and_monitor 120 "Esperando estabilización con carga baja..."
        check_current_state
        
        echo ""
        echo -e "${GREEN}✅ Prueba completa finalizada${NC}"
        echo ""
        echo "Resumen:"
        show_metrics
        ;;
    
    --status)
        show_time
        check_current_state
        show_metrics
        
        echo -e "${BLUE}🔮 Información del Periodo:${NC}"
        echo "--------------------------"
        local hour=$(TZ='America/Bogota' date '+%H')
        if [ $hour -eq 17 ]; then
            echo -e "${YELLOW}⏰ PERIODO ACTIVO: Downscale (5PM-6PM)${NC}"
            echo "Comportamiento: Puede reducir a 2 pods si carga < 50%"
        else
            echo -e "${GREEN}✅ PERIODO ACTIVO: Upscale (Resto del día)${NC}"
            echo "Comportamiento: Mantiene mínimo 3 pods"
        fi
        ;;
    
    --cleanup)
        cleanup_load_generators
        ;;
    
    --help|-h)
        show_help
        ;;
    
    "")
        show_help
        ;;
    
    *)
        echo -e "${RED}❌ Opción desconocida: $1${NC}"
        show_help
        exit 1
        ;;
esac
