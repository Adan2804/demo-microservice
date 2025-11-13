#!/bin/bash

# Script para mantener el port-forward activo automáticamente
# Se reinicia automáticamente si se cae

SERVICE="demo-microservice-keda"
NAMESPACE="default"
LOCAL_PORT="8082"
REMOTE_PORT="8080"

echo "🔌 PORT-FORWARD PERSISTENTE"
echo "============================"
echo "Service: $SERVICE"
echo "Namespace: $NAMESPACE"
echo "Local: $LOCAL_PORT → Remote: $REMOTE_PORT"
echo ""
echo "Presiona Ctrl+C para detener"
echo ""

# Función para limpiar al salir
cleanup() {
    echo ""
    echo "🛑 Deteniendo port-forward..."
    pkill -P $$ 2>/dev/null
    exit 0
}

trap cleanup SIGINT SIGTERM

# Loop infinito que reinicia el port-forward
attempt=1
while true; do
    echo "[$attempt] $(date '+%H:%M:%S') - Iniciando port-forward..."
    
    kubectl port-forward svc/$SERVICE -n $NAMESPACE $LOCAL_PORT:$REMOTE_PORT 2>&1 | while read line; do
        # Filtrar mensajes de "Handling connection"
        if [[ ! "$line" =~ "Handling connection" ]]; then
            echo "  $line"
        fi
    done
    
    exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo "  ⚠️  Port-forward terminó (código: $exit_code)"
        echo "  🔄 Reintentando en 2 segundos..."
        sleep 2
        attempt=$((attempt + 1))
    else
        echo "  ✅ Port-forward terminó normalmente"
        break
    fi
done
