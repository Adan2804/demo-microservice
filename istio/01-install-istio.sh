#!/bin/bash

# Script para instalar Istio en minikube
set -e

echo "=== INSTALANDO ISTIO SERVICE MESH ==="

cd "$(dirname "$0")/.."

# 1. Descargar Istio
echo "Descargando Istio..."
if [ ! -d "istio-1.20.0" ]; then
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
fi

# 2. Agregar istioctl al PATH
export PATH=$PWD/istio-1.20.0/bin:$PATH

# 3. Verificar instalación
echo "Verificando istioctl..."
istioctl version --remote=false

# 4. Instalar Istio en el cluster
echo "Instalando Istio en el cluster..."
istioctl install --set values.defaultRevision=default -y

# 5. Habilitar inyección automática de sidecar
echo "Habilitando inyección automática de sidecar..."
kubectl label namespace default istio-injection=enabled --overwrite

# 6. Verificar instalación
echo "Verificando instalación de Istio..."
kubectl get pods -n istio-system

# 7. Instalar addons (opcional)
echo "Instalando addons de Istio..."
kubectl apply -f istio-1.20.0/samples/addons/prometheus.yaml
kubectl apply -f istio-1.20.0/samples/addons/grafana.yaml
kubectl apply -f istio-1.20.0/samples/addons/jaeger.yaml
kubectl apply -f istio-1.20.0/samples/addons/kiali.yaml

echo ""
echo "✅ ISTIO INSTALADO EXITOSAMENTE"
echo ""
echo "Comandos útiles:"
echo "istioctl proxy-status"
echo "istioctl analyze"
echo "kubectl get pods -n istio-system"
echo ""
echo "Dashboards:"
echo "kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "kubectl port-forward -n istio-system svc/grafana 3000:3000"