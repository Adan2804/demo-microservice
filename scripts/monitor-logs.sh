#!/bin/bash

# Script para monitorear logs de producción y experimento en tiempo real
# Muestra los logs lado a lado para comparar comportamiento
set -e

echo "📋 MONITOR DE LOGS - PRODUCCIÓN vs EXPERIMENTO"
echo "=============================================="

cd "$(dirname "$0")/.."

# Función para limpiar al salir
cleanup() {
    echo ""
    echo "🛑 Deteniendo monitoreo..."
    kill $(jobs -p) 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM

# Función para mostrar logs con colores
show_logs_with_color() {
    local label=$1
    local selector=$2
    local color=$3
    
    echo -e "\033[${color}m=== $label ===\033[0m"
    kubectl logs -l $selector --tail=10 -f 2>/dev/null | while read line; do
        echo -e "\033[${color}m[$label]\033[0m $line"
    done
}

# Verificar que los pods existan
echo "🔍 Verificando pods disponibles..."

PROD_PODS=$(kubectl get pods -l app=demo-microservice-istio,tier=production --no-headers 2>/dev/null | wc -l)
EXP_PODS=$(kubectl get pods -l app=demo-microservice-istio,tier=experiment --no-headers 2>/dev/null | wc -l)

echo "• Pods de producción: $PROD_PODS"
echo "• Pods de experimento: $EXP_PODS"

if [ "$PROD_PODS" -eq 0 ]; then
    echo "⚠️  No hay pods de producción. Ejecuta: ./scripts/00-init-complete-environment.sh"
fi

if [ "$EXP_PODS" -eq 0 ]; then
    echo "⚠️  No hay pods de experimento. Ejecuta: ./scripts/01-create-experiment.sh"
fi

echo ""
echo "🚀 INICIANDO MONITOREO EN TIEMPO REAL..."
echo "Presiona Ctrl+C para detener"
echo ""

# Crear archivos temporales para logs
PROD_LOG="/tmp/prod_logs.txt"
EXP_LOG="/tmp/exp_logs.txt"

# Función para mostrar logs lado a lado
show_side_by_side() {
    while true; do
        clear
        echo "📊 LOGS EN TIEMPO REAL - $(date)"
        echo "=================================="
        echo ""
        
        # Mostrar logs de producción
        echo -e "\033[32m🟢 PRODUCCIÓN (stable)\033[0m                    \033[34m🔵 EXPERIMENTO (experimental)\033[0m"
        echo "----------------------------------------        ----------------------------------------"
        
        # Obtener logs recientes
        kubectl logs -l app=demo-microservice-istio,tier=production --tail=15 2>/dev/null > $PROD_LOG || echo "No logs" > $PROD_LOG
        kubectl logs -l app=demo-microservice-istio,tier=experiment --tail=15 2>/dev/null > $EXP_LOG || echo "No logs" > $EXP_LOG
        
        # Mostrar logs lado a lado usando paste
        paste <(cat $PROD_LOG | cut -c1-40) <(cat $EXP_LOG | cut -c1-40) | while read line; do
            prod_part=$(echo "$line" | cut -f1)
            exp_part=$(echo "$line" | cut -f2)
            printf "\033[32m%-40s\033[0m \033[34m%-40s\033[0m\n" "$prod_part" "$exp_part"
        done
        
        echo ""
        echo "🔄 Actualizando cada 3 segundos... (Ctrl+C para detener)"
        sleep 3
    done
}

# Función para generar tráfico automático
generate_auto_traffic() {
    while true; do
        # Tráfico normal cada 5 segundos
        curl -s http://localhost:8080/api/v1/experiment/version > /dev/null 2>&1 || true
        sleep 2
        
        # Tráfico experimental cada 8 segundos
        curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
            http://localhost:8080/api/v1/experiment/version > /dev/null 2>&1 || true
        sleep 3
    done
}

# Preguntar si quiere generar tráfico automático
echo "¿Deseas generar tráfico automático para ver logs activos? (y/N): "
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔄 Generando tráfico automático en background..."
    generate_auto_traffic &
    TRAFFIC_PID=$!
    
    # Limpiar tráfico al salir
    cleanup_traffic() {
        kill $TRAFFIC_PID 2>/dev/null || true
        cleanup
    }
    trap cleanup_traffic SIGINT SIGTERM
fi

# Mostrar logs lado a lado
show_side_by_side

# Limpiar archivos temporales
rm -f $PROD_LOG $EXP_LOG