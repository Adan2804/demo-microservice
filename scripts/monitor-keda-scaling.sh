#!/bin/bash

# Script para monitorear el escalado con KEDA
set -e

echo "📊 MONITOREO DE ESCALADO CON KEDA"
echo "=================================="

while true; do
    clear
    echo "📊 MONITOREO DE ESCALADO CON KEDA"
    echo "=================================="
    echo ""
    echo "🕐 Hora Colombia: $(TZ='America/Bogota' date '+%H:%M:%S %d/%m/%Y')"
    echo ""
    
    echo "📦 PODS:"
    kubectl get pods -l app=demo-microservice-keda --no-headers 2>/dev/null | wc -l | xargs echo "  Pods actuales:"
    kubectl get deployment demo-microservice-keda -o jsonpath='{.spec.replicas}' 2>/dev/null | xargs echo "  Pods deseados:"
    echo ""
    
    echo "📊 SCALEDOBJECT:"
    kubectl get scaledobject demo-microservice-keda-scaler 2>/dev/null || echo "  No encontrado"
    echo ""
    
    echo "📈 HPA:"
    kubectl get hpa demo-microservice-keda-hpa 2>/dev/null || echo "  No encontrado"
    echo ""
    
    echo "💻 MÉTRICAS:"
    kubectl top pods -l app=demo-microservice-keda 2>/dev/null || echo "  Métricas no disponibles"
    echo ""
    
    echo "Actualizando en 10 segundos... (Ctrl+C para salir)"
    sleep 10
done
