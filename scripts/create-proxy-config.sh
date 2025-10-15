#!/bin/bash

# Script para crear ConfigMap del proxy desde archivo nginx.conf
set -e

echo "=== CREANDO CONFIGMAP DEL PROXY INTELIGENTE ==="

cd "$(dirname "$0")/.."

# Verificar que existe el archivo nginx.conf
if [ ! -f "proxy/nginx.conf" ]; then
    echo "❌ Error: No se encuentra proxy/nginx.conf"
    exit 1
fi

# Eliminar ConfigMap anterior si existe
echo "Eliminando ConfigMap anterior..."
kubectl delete configmap intelligent-proxy-config --ignore-not-found=true

# Crear ConfigMap desde archivo
echo "Creando ConfigMap desde proxy/nginx.conf..."
kubectl create configmap intelligent-proxy-config --from-file=nginx.conf=proxy/nginx.conf

# Verificar creación
echo "Verificando ConfigMap..."
kubectl get configmap intelligent-proxy-config

echo ""
echo "✅ CONFIGMAP CREADO EXITOSAMENTE"
echo ""
echo "Para aplicar el proxy completo:"
echo "1. ./scripts/create-proxy-config.sh  (ya ejecutado)"
echo "2. kubectl apply -f k7s/03-proxy-intelligent-clean.yaml"