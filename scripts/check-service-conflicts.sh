#!/bin/bash

# Script para verificar conflictos de servicios antes de desplegar
set -e

echo "=== VERIFICANDO CONFLICTOS DE SERVICIOS ==="

cd "$(dirname "$0")/.."

# 1. Verificar LoadBalancers existentes
echo "LoadBalancers existentes:"
LOADBALANCERS=$(kubectl get svc --field-selector spec.type=LoadBalancer --no-headers 2>/dev/null | wc -l)
if [ "$LOADBALANCERS" -gt 0 ]; then
    echo "⚠️  Encontrados $LOADBALANCERS LoadBalancers:"
    kubectl get svc --field-selector spec.type=LoadBalancer
    echo ""
    echo "💡 Recomendación: Usar ClusterIP para evitar conflictos"
else
    echo "✅ No hay LoadBalancers conflictivos"
fi

# 2. Verificar servicios en puerto 80
echo ""
echo "Servicios usando puerto 80:"
PORT_80_SERVICES=$(kubectl get svc -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.ports[?(@.port==80)].port}{"\n"}{end}' | grep -c "80" || echo "0")
if [ "$PORT_80_SERVICES" -gt 0 ]; then
    echo "⚠️  Servicios en puerto 80:"
    kubectl get svc -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,PORTS:.spec.ports[*].port | grep "80"
else
    echo "✅ No hay conflictos en puerto 80"
fi

# 3. Verificar servicios con nombres similares
echo ""
echo "Servicios con nombres similares a 'proxy':"
PROXY_SERVICES=$(kubectl get svc | grep -i proxy | wc -l || echo "0")
if [ "$PROXY_SERVICES" -gt 0 ]; then
    echo "⚠️  Servicios proxy existentes:"
    kubectl get svc | grep -i proxy
else
    echo "✅ No hay servicios proxy conflictivos"
fi

# 4. Verificar recursos del cluster
echo ""
echo "Recursos del cluster:"
echo "Pods: $(kubectl get pods --no-headers | wc -l)"
echo "Services: $(kubectl get svc --no-headers | wc -l)"
echo "Deployments: $(kubectl get deployments --no-headers | wc -l)"

# 5. Recomendaciones
echo ""
echo "=== RECOMENDACIONES ==="
if [ "$LOADBALANCERS" -gt 1 ]; then
    echo "🔧 Usar ClusterIP en lugar de LoadBalancer"
    echo "🔧 Considerar usar namespace dedicado"
fi

if [ "$PORT_80_SERVICES" -gt 1 ]; then
    echo "🔧 Cambiar puerto del proxy (ej: 8080)"
    echo "🔧 Usar Ingress para múltiples servicios"
fi

echo ""
echo "✅ VERIFICACIÓN COMPLETA"