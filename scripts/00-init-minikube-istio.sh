#!/bin/bash

# Script de inicialización completa: Minikube + Istio + Despliegue de Producción
# Este script reemplaza el 00-init-complete-environment.sh con mejor organización
set -e

echo "🚀 INICIALIZANDO ENTORNO: MINIKUBE + ISTIO + PRODUCCIÓN"
echo "======================================================="

cd "$(dirname "$0")/.."

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para esperar que un deployment esté listo
wait_for_deployment() {
    local deployment=$1
    local namespace=${2:-default}
    echo "⏳ Esperando que $deployment esté listo en $namespace..."
    kubectl wait --for=condition=available deployment/$deployment -n $namespace --timeout=300s
}

# 1. VERIFICAR DEPENDENCIAS
echo ""
echo "📋 VERIFICANDO DEPENDENCIAS..."

if ! command_exists minikube; then
    echo "❌ minikube no está instalado"
    echo "Instala desde: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
fi

if ! command_exists kubectl; then
    echo "❌ kubectl no está instalado"
    echo "Instala desde: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Verificar istioctl
ISTIOCTL_PATH=""
if [ -f "./bin/istioctl" ]; then
    ISTIOCTL_PATH="./bin/istioctl"
    echo "✅ Usando istioctl local: ./bin/istioctl"
elif command_exists istioctl; then
    ISTIOCTL_PATH="istioctl"
    echo "✅ Usando istioctl del sistema"
else
    echo "❌ istioctl no está disponible"
    echo "Descarga desde: https://istio.io/latest/docs/setup/getting-started/"
    exit 1
fi

echo "✅ Todas las dependencias están disponibles"

# 2. CONFIGURAR MINIKUBE
echo ""
echo "🔧 CONFIGURANDO MINIKUBE..."

# Verificar si minikube ya está corriendo
if minikube status | grep -q "Running"; then
    echo "✅ Minikube ya está corriendo"
else
    echo "🚀 Iniciando Minikube con configuración optimizada..."
    minikube start \
        --cpus=4 \
        --memory=8192 \
        --disk-size=20g \
        --driver=docker \
        --kubernetes-version=v1.28.3
fi

# Habilitar addons necesarios
echo "📦 Habilitando addons de Minikube..."
minikube addons enable metrics-server
minikube addons enable ingress

# 3. INSTALAR ISTIO SERVICE MESH
echo ""
echo "🕸️  INSTALANDO ISTIO SERVICE MESH..."

# Verificar si Istio ya está instalado
if kubectl get namespace istio-system >/dev/null 2>&1; then
    echo "✅ Istio ya está instalado"
else
    echo "📦 Instalando Istio..."
    "$ISTIOCTL_PATH" install --set values.defaultRevision=default -y
    
    # Habilitar inyección automática de sidecar en default namespace
    kubectl label namespace default istio-injection=enabled --overwrite
    echo "✅ Inyección automática de sidecar habilitada"
fi

# Verificar que Istio esté funcionando
wait_for_deployment istiod istio-system
wait_for_deployment istio-ingressgateway istio-system

echo "✅ Istio Service Mesh operativo"

# 4. LIMPIAR DEPLOYMENTS ANTERIORES
echo ""
echo "🧹 LIMPIANDO DEPLOYMENTS ANTERIORES..."

# Limpiar deployments antiguos (sin Istio)
kubectl delete deployment demo-microservice-production --ignore-not-found=true
kubectl delete deployment intelligent-proxy --ignore-not-found=true
kubectl delete deployment demo-microservice-experiment --ignore-not-found=true

# Limpiar servicios antiguos
kubectl delete service demo-microservice-stable --ignore-not-found=true
kubectl delete service demo-microservice-experiment --ignore-not-found=true
kubectl delete service intelligent-proxy --ignore-not-found=true

# Limpiar ConfigMaps antiguos
kubectl delete configmap intelligent-proxy-config --ignore-not-found=true

echo "✅ Limpieza completada"

# 5. CONSTRUIR IMÁGENES DOCKER
echo ""
echo "🏗️  CONSTRUYENDO IMÁGENES DOCKER..."

# Configurar Docker para usar el daemon de Minikube
eval $(minikube docker-env)

# Verificar si las imágenes ya existen
if ! minikube image ls | grep -q demo-microservice:stable; then
    echo "📦 Construyendo imagen STABLE para producción..."
    docker build -t demo-microservice:stable \
      --build-arg NODE_ENV=production \
      --build-arg APP_VERSION=stable-v1.0.0 \
      --build-arg EXPERIMENT_ENABLED=false \
      .
    echo "✅ Imagen stable construida"
fi

if ! minikube image ls | grep -q demo-microservice:experiment-candidate-v1.1.0; then
    echo "📦 Construyendo imagen EXPERIMENTAL para pruebas..."
    docker build -t demo-microservice:experiment-candidate-v1.1.0 \
      --build-arg NODE_ENV=production \
      --build-arg APP_VERSION=experiment-candidate-v1.1.0 \
      --build-arg EXPERIMENT_ENABLED=true \
      .
    echo "✅ Imagen experimental construida"
fi

echo "✅ Imágenes Docker listas"

# 6. DESPLEGAR APLICACIÓN DE PRODUCCIÓN CON ISTIO
echo ""
echo "🚀 DESPLEGANDO APLICACIÓN DE PRODUCCIÓN CON ISTIO..."

# Desplegar aplicación de producción
echo "📦 Desplegando deployment de producción..."
kubectl apply -f argocd-production/01-production-deployment-istio.yaml

# Esperar que el deployment esté listo
wait_for_deployment demo-microservice-production-istio

# Desplegar servicio unificado
echo "🌐 Desplegando servicio unificado..."
kubectl apply -f argocd-production/02-service-unified.yaml

# Configurar Istio Gateway y VirtualService
echo "🌐 Configurando Istio Gateway..."
kubectl apply -f argocd-production/03-destination-rule.yaml
kubectl apply -f argocd-production/04-virtual-service.yaml

# Esperar que la configuración se propague
echo "⏳ Esperando que la configuración de Istio se propague..."
sleep 15

echo "✅ Aplicación de producción desplegada con Istio"

# 7. CONFIGURAR PORT-FORWARDS
echo ""
echo "🔌 CONFIGURANDO ACCESOS..."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2

# Port-forward para Istio Gateway
echo "🌐 Configurando acceso a Istio Gateway..."
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 > /dev/null 2>&1 &
GATEWAY_PF_PID=$!

sleep 5

# 8. VERIFICAR INSTALACIÓN
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN..."

echo "📊 Estado de los pods:"
kubectl get pods -o wide

echo ""
echo "🌐 Estado de los servicios:"
kubectl get svc

echo ""
echo "🕸️  Analizando configuración de Istio..."
"$ISTIOCTL_PATH" analyze

# 9. PRUEBAS DE CONECTIVIDAD
echo ""
echo "🧪 REALIZANDO PRUEBAS DE CONECTIVIDAD..."

echo "⏳ Esperando que los servicios estén listos..."
sleep 10

echo ""
echo "🔍 Probando tráfico normal (debe ir a producción):"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "📝 Respuesta: $response"

echo ""
echo "🔍 Probando tráfico experimental (debe ir a producción - experimento aún no creado):"
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "📝 Respuesta: $response"

# 10. RESUMEN FINAL
echo ""
echo "🎉 ENTORNO INICIALIZADO CORRECTAMENTE"
echo "====================================="
echo ""
echo "✅ Minikube: Corriendo"
echo "✅ Istio Service Mesh: Instalado y configurado"
echo "✅ Aplicación de Producción: Desplegada (3 pods)"
echo "✅ Gateway y VirtualService: Configurados"
echo ""
echo "🌐 ACCESOS DISPONIBLES:"
echo "• Aplicación: http://localhost:8080"
echo ""
echo "📊 DASHBOARDS OPCIONALES:"
echo "• Kiali (Service Mesh): kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "• Grafana (Métricas): kubectl port-forward -n istio-system svc/grafana 3000:3000"
echo "• Jaeger (Tracing): kubectl port-forward -n istio-system svc/jaeger 16686:16686"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Crear experimento: ./scripts/01-create-experiment.sh"
echo "2. Configurar ArgoCD: ./scripts/03-setup-argocd.sh"
echo ""
echo "📝 COMANDOS ÚTILES:"
echo "• Ver estado: kubectl get pods,svc"
echo "• Logs de aplicación: kubectl logs -l app=demo-microservice-istio"
echo "• Estado de Istio: $ISTIOCTL_PATH proxy-status"
echo "• Análisis de Istio: $ISTIOCTL_PATH analyze"
echo ""
echo "🔌 Port-forward activo (PID: $GATEWAY_PF_PID)"
echo "Para detener: pkill -f 'kubectl port-forward'"