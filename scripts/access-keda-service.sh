#!/bin/bash

# Script para acceder al servicio de KEDA
set -e

echo "🌐 ACCEDIENDO AL SERVICIO DE KEDA"
echo "=================================="

cd "$(dirname "$0")/.."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward.*demo-microservice-keda" 2>/dev/null || true
sleep 2

echo ""
echo "🔌 Iniciando port-forward..."
kubectl port-forward svc/demo-microservice-keda 8080:80 > /dev/null 2>&1 &
PF_PID=$!

sleep 3

echo "✅ Port-forward activo (PID: $PF_PID)"
echo ""
echo "🌐 ENDPOINTS DISPONIBLES:"
echo "• Health: http://localhost:8080/actuator/health"
echo "• Info: http://localhost:8080/demo/info"
echo "• Monetary: http://localhost:8080/api/v1/monetary"
echo ""
echo "🧪 PRUEBAS:"
echo ""
echo "# Health check"
echo "curl http://localhost:8080/actuator/health"
echo ""
echo "# Info del servicio"
echo "curl http://localhost:8080/demo/info"
echo ""
echo "# Endpoint de monetary"
echo "curl http://localhost:8080/api/v1/monetary"
echo ""
echo "🛑 Para detener el port-forward:"
echo "kill $PF_PID"
echo ""
echo "Presiona Ctrl+C para salir (el port-forward seguirá activo)"

# Mantener el script corriendo
trap "echo ''; echo '✅ Port-forward sigue activo en background (PID: $PF_PID)'; exit 0" INT
sleep infinity
