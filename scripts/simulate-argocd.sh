#!/bin/bash

# Script para simular Argo CD - Despliegue continuo y monitoreo
# Simula cómo Argo CD detecta cambios y despliega automáticamente
set -e

echo "🚀 SIMULANDO ARGO CD - DESPLIEGUE CONTINUO"
echo "=========================================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  --watch             Modo continuo (simula Argo CD sync)"
    echo "  --deploy-prod       Desplegar solo producción"
    echo "  --deploy-exp        Desplegar solo experimento"
    echo "  --show-logs         Mostrar logs en tiempo real"
    echo "  -h, --help          Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0 --watch          # Modo continuo como Argo CD"
    echo "  $0 --show-logs      # Ver logs de ambas versiones"
}

# Valores por defecto
WATCH_MODE=false
DEPLOY_PROD=false
DEPLOY_EXP=false
SHOW_LOGS=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --deploy-prod)
            DEPLOY_PROD=true
            shift
            ;;
        --deploy-exp)
            DEPLOY_EXP=true
            shift
            ;;
        --show-logs)
            SHOW_LOGS=true
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

# Función para mostrar estado de la aplicación
show_app_status() {
    echo ""
    echo "📊 ESTADO ACTUAL DE LA APLICACIÓN"
    echo "=================================="
    
    echo ""
    echo "🏗️  Deployments:"
    kubectl get deployments -l app=demo-microservice-istio -o wide
    
    echo ""
    echo "🚀 Pods:"
    kubectl get pods -l app=demo-microservice-istio -o wide
    
    echo ""
    echo "🌐 Servicios:"
    kubectl get svc -l app=demo-microservice-istio
    
    echo ""
    echo "🔀 VirtualServices:"
    kubectl get virtualservice
    
    echo ""
    echo "🎯 DestinationRules:"
    kubectl get destinationrule
}

# Función para simular detección de cambios (como Argo CD)
simulate_change_detection() {
    echo ""
    echo "🔍 SIMULANDO DETECCIÓN DE CAMBIOS (como Argo CD)..."
    echo "=================================================="
    
    # Simular cambios en el repositorio
    echo "• Verificando repositorio Git... ✅"
    echo "• Comparando manifiestos YAML... ✅"
    echo "• Detectando diferencias... ✅"
    
    # Mostrar cambios simulados
    echo ""
    echo "📝 CAMBIOS DETECTADOS:"
    echo "• demo-microservice-production-istio: stable → stable (sin cambios)"
    echo "• demo-microservice-experiment: nueva versión disponible"
    echo "• VirtualService: configuración actualizada"
}

# Función para mostrar logs en tiempo real
show_live_logs() {
    echo ""
    echo "📋 LOGS EN TIEMPO REAL"
    echo "======================"
    echo ""
    echo "🟢 PRODUCCIÓN (stable):"
    echo "------------------------"
    
    # Logs de producción (últimas 5 líneas)
    kubectl logs -l app=demo-microservice-istio,tier=production --tail=5 2>/dev/null || echo "No hay logs de producción disponibles"
    
    echo ""
    echo "🔵 EXPERIMENTO (experimental):"
    echo "------------------------------"
    
    # Logs de experimento (últimas 5 líneas)
    kubectl logs -l app=demo-microservice-istio,tier=experiment --tail=5 2>/dev/null || echo "No hay logs de experimento disponibles"
}

# Función para generar tráfico de prueba
generate_test_traffic() {
    echo ""
    echo "🔄 GENERANDO TRÁFICO DE PRUEBA..."
    echo "================================="
    
    # Tráfico normal (producción)
    echo "Enviando tráfico normal..."
    for i in {1..3}; do
        response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error")
        echo "[$i] Normal: $(echo $response | jq -r '.version // "Error"' 2>/dev/null || echo $response)"
        sleep 1
    done
    
    echo ""
    echo "Enviando tráfico experimental..."
    for i in {1..3}; do
        response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
            http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error")
        echo "[$i] Experimental: $(echo $response | jq -r '.version // "Error"' 2>/dev/null || echo $response)"
        sleep 1
    done
}

# Función para simular sync de Argo CD
simulate_argocd_sync() {
    echo ""
    echo "🔄 SIMULANDO ARGO CD SYNC..."
    echo "============================"
    
    echo "• Iniciando sincronización..."
    echo "• Aplicando manifiestos..."
    echo "• Verificando estado de salud..."
    
    # Simular aplicación de cambios
    sleep 2
    
    echo "• Sync completado ✅"
    
    # Mostrar estado después del sync
    show_app_status
}

# Función principal para modo watch
watch_mode() {
    echo ""
    echo "👁️  MODO WATCH ACTIVADO (simula Argo CD)"
    echo "========================================"
    echo "Presiona Ctrl+C para detener"
    echo ""
    
    local counter=0
    while true; do
        counter=$((counter + 1))
        
        echo ""
        echo "🔄 CICLO $counter - $(date)"
        echo "=========================="
        
        # Simular detección de cambios cada 30 segundos
        simulate_change_detection
        
        # Mostrar estado actual
        show_app_status
        
        # Generar tráfico de prueba
        generate_test_traffic
        
        # Mostrar logs
        show_live_logs
        
        echo ""
        echo "⏳ Esperando próximo ciclo (30s)..."
        echo "   (Ctrl+C para detener)"
        
        sleep 30
    done
}

# 1. MOSTRAR ESTADO INICIAL
show_app_status

# 2. EJECUTAR SEGÚN OPCIONES
if [ "$WATCH_MODE" = true ]; then
    watch_mode
elif [ "$DEPLOY_PROD" = true ]; then
    echo ""
    echo "🏗️  DESPLEGANDO SOLO PRODUCCIÓN..."
    kubectl apply -f istio/01-production-deployment-istio.yaml
    simulate_argocd_sync
elif [ "$DEPLOY_EXP" = true ]; then
    echo ""
    echo "🧪 DESPLEGANDO SOLO EXPERIMENTO..."
    kubectl apply -f istio/02-experiment-deployment-istio.yaml
    simulate_argocd_sync
elif [ "$SHOW_LOGS" = true ]; then
    echo ""
    echo "📋 MOSTRANDO LOGS CONTINUOS..."
    echo "Presiona Ctrl+C para detener"
    while true; do
        clear
        show_live_logs
        sleep 5
    done
else
    # Modo por defecto: simular un ciclo completo
    simulate_change_detection
    generate_test_traffic
    show_live_logs
    simulate_argocd_sync
fi

echo ""
echo "🎉 SIMULACIÓN DE ARGO CD COMPLETADA"
echo ""
echo "💡 COMANDOS ÚTILES:"
echo "• Ver estado: kubectl get pods,svc,virtualservice"
echo "• Ver logs producción: kubectl logs -l tier=production -f"
echo "• Ver logs experimento: kubectl logs -l tier=experiment -f"
echo "• Modo watch: $0 --watch"