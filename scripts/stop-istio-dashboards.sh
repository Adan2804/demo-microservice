#!/bin/bash
echo "🛑 Deteniendo port-forwards de Istio..."

# Detener por patrón
pkill -f "kubectl port-forward.*istio-system" 2>/dev/null || true

# Detener por PIDs guardados
if [ -f "/tmp/istio-pf-pids.txt" ]; then
    while read pid; do
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
        fi
    done < /tmp/istio-pf-pids.txt
    rm -f /tmp/istio-pf-pids.txt
fi

echo "✅ Port-forwards detenidos"
