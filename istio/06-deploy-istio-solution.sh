#!/bin/bash

# Script para desplegar la solución completa con Istio
set -e

echo "=== DESPLEGANDO SOLUCIÓN ISTIO ==="

cd "$(dirname "$0")/.."

# 1. Verificar que Istio esté instalado
if ! kubectl get namespace istio-system >/dev/null 2>&1; then
    echo "❌ Istio no está instalado. Ejecuta primero:"
    echo "./istio/01-install-istio.sh"
    exit 1
fi

# 2. Verificar que la infraestructura base esté desplegada
if ! kubectl get deployment demo-microservice-production >/dev/null 2>&1; then
    echo "❌ Infraestructura base no encontrada. Ejecuta primero:"
    echo "./scripts/01-deploy-base.sh"
    exit 1
fi

# 3. Aplicar servicio unificado
echo "Aplicando servicio unificado para Istio..."
kubectl apply -f istio/02-service-unified.yaml

# 4. Aplicar DestinationRule
echo "Aplicando DestinationRule (subsets)..."
kubectl apply -f istio/03-destination-rule.yaml

# 5. Aplicar VirtualService
echo "Aplicando VirtualService (enrutamiento)..."
kubectl apply -f istio/04-virtual-service.yaml

# 6. Esperar que todo esté listo
echo "Esperando que los recursos estén listos..."
sleep 10

# 7. Verificar configuración de Istio
echo "Verificando configuración de Istio..."
istioctl analyze

# 8. Configurar port-forward al Istio Gateway
echo "Configurando acceso a través de Istio Gateway..."
pkill -f "kubectl port-forward.*istio-ingressgateway" 2>/dev/null || true
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 > /dev/null 2>&1 &
GATEWAY_PF_PID=$!
sleep 3

# 9. Probar enrutamiento
echo ""
echo "✅ SOLUCIÓN ISTIO DESPLEGADA"
echo ""
echo "Probando enrutamiento:"

echo ""
echo "Tráfico normal (debe ir a producción):"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "Tráfico experimental (debe ir a experimento):"
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "🎉 ISTIO SERVICE MESH FUNCIONANDO"
echo ""
echo "Port-forward activo (PID: $GATEWAY_PF_PID)"
echo "URL: http://localhost:8080"
echo ""
echo "Dashboards disponibles:"
echo "kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "kubectl port-forward -n istio-system svc/grafana 3000:3000"
echo ""
echo "Comandos útiles:"
echo "istioctl proxy-status"
echo "istioctl analyze"
echo "kubectl get virtualservices"
echo "kubectl get destinationrules"