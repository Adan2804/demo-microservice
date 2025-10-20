#!/bin/bash

# Script para limpiar experimentos y restaurar configuración base
set -e

echo "🧹 LIMPIANDO EXPERIMENTO Y RESTAURANDO CONFIGURACIÓN BASE"
echo "========================================================="

cd "$(dirname "$0")/.."

# 1. ELIMINAR DEPLOYMENT DEL EXPERIMENTO
echo ""
echo "🗑️  ELIMINANDO DEPLOYMENT DEL EXPERIMENTO..."

if kubectl get deployment demo-microservice-experiment >/dev/null 2>&1; then
    kubectl delete deployment demo-microservice-experiment
    echo "✅ Deployment del experimento eliminado"
else
    echo "ℹ️  No hay deployment de experimento para eliminar"
fi

# 2. RESTAURAR CONFIGURACIÓN BASE DE ISTIO
echo ""
echo "🔄 RESTAURANDO CONFIGURACIÓN BASE DE ISTIO..."

echo "📝 Restaurando DestinationRule base..."
kubectl apply -f argocd-production/03-destination-rule.yaml

echo "📝 Restaurando VirtualService base..."
kubectl apply -f argocd-production/04-virtual-service.yaml

# Esperar que la configuración se propague
echo "⏳ Esperando que la configuración se propague..."
sleep 10

echo "✅ Configuración base restaurada"

# 3. VERIFICAR ESTADO
echo ""
echo "🔍 VERIFICANDO ESTADO DESPUÉS DE LA LIMPIEZA..."

echo "📊 Estado de los pods:"
kubectl get pods -l app=demo-microservice-istio -o wide

echo ""
echo "🚀 Estado de los deployments:"
kubectl get deployments -l app=demo-microservice-istio

echo ""
echo "🌐 Configuración de Istio:"
kubectl get destinationrule,virtualservice

# 4. PRUEBA DE CONECTIVIDAD
echo ""
echo "🧪 VERIFICANDO CONECTIVIDAD..."

echo "🔍 Probando tráfico normal (debe ir a producción):"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "📝 Respuesta: $response"

echo ""
echo "🔍 Probando tráfico con header (debe ir a producción - experimento eliminado):"
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "📝 Respuesta: $response"

# 5. LIMPIAR ARCHIVOS TEMPORALES
echo ""
echo "🧹 LIMPIANDO ARCHIVOS TEMPORALES..."

rm -f /tmp/experiment-deployment.yaml
rm -f /tmp/destination-rule-experiment.yaml
rm -f /tmp/virtual-service-experiment.yaml
rm -f /tmp/generate_traffic.sh

echo "✅ Archivos temporales eliminados"

# 6. RESUMEN FINAL
echo ""
echo "🎉 LIMPIEZA COMPLETADA EXITOSAMENTE"
echo "==================================="
echo ""
echo "✅ Deployment del experimento eliminado"
echo "✅ Configuración base de Istio restaurada"
echo "✅ Todo el tráfico dirigido a producción"
echo "✅ Archivos temporales limpiados"
echo ""
echo "🌐 ESTADO ACTUAL:"
echo "• Solo pods de producción activos (3 pods)"
echo "• Configuración base de Istio aplicada"
echo "• ArgoCD puede gestionar normalmente los recursos"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "• Crear nuevo experimento: ./scripts/01-create-experiment-istio.sh"
echo "• Configurar ArgoCD: ./scripts/03-setup-argocd.sh"
echo ""
echo "💡 NOTA:"
echo "El sistema ha vuelto al estado base de producción."
echo "ArgoCD puede ahora gestionar los recursos sin conflictos."