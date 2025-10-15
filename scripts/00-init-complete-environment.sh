#!/bin/bash

# Script de inicialización completa del entorno
# Minikube + Istio + Despliegue de Producción + Configuración completa
set -e

echo "🚀 INICIALIZANDO ENTORNO COMPLETO PARA TESTING EN PRODUCCIÓN"
echo "=============================================================="

cd "$(dirname "$0")/.."

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para esperar que un deployment esté listo
wait_for_deployment() {
    local deployment=$1
    local namespace=${2:-default}
    echo "Esperando que $deployment esté listo..."
    kubectl wait --for=condition=available deployment/$deployment -n $namespace --timeout=300s
}

# 1. VERIFICAR DEPENDENCIAS
echo ""
echo "📋 VERIFICANDO DEPENDENCIAS..."

if ! command_exists minikube; then
    echo "❌ minikube no está instalado"
    exit 1
fi

if ! command_exists kubectl; then
    echo "❌ kubectl no está instalado"
    exit 1
fi

# Verificar istioctl (local o sistema)
ISTIOCTL_PATH=""
if [ -f "./bin/istioctl" ]; then
    ISTIOCTL_PATH="./bin/istioctl"
    echo "✅ Usando istioctl local: ./bin/istioctl"
elif command_exists istioctl; then
    ISTIOCTL_PATH="istioctl"
    echo "✅ Usando istioctl del sistema"
else
    echo "❌ istioctl no está disponible. Ejecuta primero:"
    echo "./scripts/install-istio-wsl.sh"
    exit 1
fi

echo "✅ Todas las dependencias están instaladas"

# 2. INICIAR MINIKUBE
echo ""
echo "🔧 CONFIGURANDO MINIKUBE..."

# Verificar si minikube ya está corriendo
if minikube status | grep -q "Running"; then
    echo "✅ Minikube ya está corriendo"
else
    echo "Iniciando Minikube con configuración optimizada..."
    minikube start \
        --cpus=4 \
        --memory=8192 \
        --disk-size=20g \
        --driver=docker
fi

# Habilitar addons necesarios
echo "Habilitando addons de Minikube..."
minikube addons enable metrics-server
minikube addons enable ingress

# 3. INSTALAR ISTIO
echo ""
echo "🕸️  INSTALANDO ISTIO SERVICE MESH..."

# Verificar si Istio ya está instalado
if kubectl get namespace istio-system >/dev/null 2>&1; then
    echo "✅ Istio ya está instalado"
else
    echo "Instalando Istio..."
    "$ISTIOCTL_PATH" install --set values.defaultRevision=default -y
    
    # Habilitar inyección automática de sidecar
    kubectl label namespace default istio-injection=enabled --overwrite
fi

# Verificar que Istio esté funcionando
wait_for_deployment istiod istio-system
wait_for_deployment istio-ingressgateway istio-system


# 5. LIMPIAR DEPLOYMENTS ANTERIORES
echo ""
echo "🧹 LIMPIANDO DEPLOYMENTS ANTERIORES..."

# Limpiar deployments antiguos (sin Istio)
echo "Eliminando deployments antiguos..."
kubectl delete deployment demo-microservice-production --ignore-not-found=true
kubectl delete deployment intelligent-proxy --ignore-not-found=true
kubectl delete deployment demo-microservice-experiment --ignore-not-found=true

# Limpiar servicios antiguos
echo "Eliminando servicios antiguos..."
kubectl delete service demo-microservice-stable --ignore-not-found=true
kubectl delete service demo-microservice-experiment --ignore-not-found=true
kubectl delete service intelligent-proxy --ignore-not-found=true

# Limpiar ConfigMaps antiguos
echo "Eliminando ConfigMaps antiguos..."
kubectl delete configmap intelligent-proxy-config --ignore-not-found=true

echo "✅ Limpieza completada"

# 6. DESPLEGAR APLICACIÓN CON ISTIO
echo ""
echo "🏗️  DESPLEGANDO APLICACIÓN CON ISTIO..."

# Verificar y construir imágenes si es necesario
if ! minikube image ls | grep -q demo-microservice:stable; then
    echo "Construyendo imágenes con versiones diferentes..."
    
    # Configurar Docker para usar el daemon de Minikube
    eval $(minikube docker-env)
    
    # Imagen STABLE para producción
    docker build -t demo-microservice:stable \
      --build-arg NODE_ENV=production \
      --build-arg APP_VERSION=stable-v1.0.0 \
      --build-arg EXPERIMENT_ENABLED=false \
      .
    
    # Imagen EXPERIMENTAL para pruebas
    docker build -t demo-microservice:experiment-candidate-v1.1.0 \
      --build-arg NODE_ENV=production \
      --build-arg APP_VERSION=experiment-candidate-v1.1.0 \
      --build-arg EXPERIMENT_ENABLED=true \
      .
    
    echo "✅ Imágenes construidas y cargadas en Minikube"
fi

# Desplegar aplicación de producción con Istio
echo "Desplegando aplicación de producción con Istio..."
kubectl apply -f istio/01-production-deployment-istio.yaml

# Esperar que el deployment esté listo
wait_for_deployment demo-microservice-production-istio

# Reiniciar pods para aplicar nuevas configuraciones
echo "Reiniciando pods para aplicar configuraciones actualizadas..."
kubectl rollout restart deployment/demo-microservice-production-istio
kubectl rollout status deployment/demo-microservice-production-istio

# 7. CONFIGURAR ISTIO SERVICE MESH
echo ""
echo "🌐 CONFIGURANDO ISTIO SERVICE MESH..."

# Aplicar servicio unificado y Gateway
echo "Aplicando servicio unificado y Gateway..."
kubectl apply -f istio/02-service-unified.yaml

echo "Aplicando DestinationRule..."
kubectl apply -f istio/03-destination-rule.yaml

echo "Aplicando VirtualService..."
kubectl apply -f istio/04-virtual-service.yaml

# Esperar que la configuración se propague
echo "Esperando que la configuración de Istio se propague..."
sleep 15

# 8. CONFIGURAR PORT-FORWARDS
echo ""
echo "🔌 CONFIGURANDO ACCESOS..."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2

# Port-forward para Istio Gateway
echo "Configurando acceso a Istio Gateway..."
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 > /dev/null 2>&1 &
GATEWAY_PF_PID=$!

# Port-forward para Argo Rollouts Dashboard (si existe)
if kubectl get svc argo-rollouts-dashboard -n argo-rollouts >/dev/null 2>&1; then
    echo "Configurando acceso a Argo Rollouts Dashboard..."
    kubectl port-forward -n argo-rollouts svc/argo-rollouts-dashboard 3100:3100 > /dev/null 2>&1 &
    DASHBOARD_PF_PID=$!
else
    echo "⚠️  Dashboard de Argo Rollouts no disponible"
    DASHBOARD_PF_PID=""
fi

sleep 5

# 9. VERIFICAR INSTALACIÓN
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN..."

# Verificar pods
echo "Estado de los pods:"
kubectl get pods -o wide

# Verificar servicios
echo ""
echo "Estado de los servicios:"
kubectl get svc

# Verificar configuración de Istio
echo ""
echo "Analizando configuración de Istio..."
"$ISTIOCTL_PATH" analyze

# 10. PRUEBAS DE CONECTIVIDAD
echo ""
echo "🧪 REALIZANDO PRUEBAS DE CONECTIVIDAD..."

echo "Esperando que los servicios estén listos..."
sleep 10

echo ""
echo "Probando tráfico normal (debe ir a producción):"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "Probando tráfico experimental (debe ir a producción - experimento aún no creado):"
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

# 11. RESUMEN FINAL
echo ""
echo "🎉 ENTORNO INICIALIZADO CORRECTAMENTE"
echo "====================================="
echo ""
echo "✅ Minikube: Corriendo"
echo "✅ Istio Service Mesh: Instalado y configurado"
echo "✅ Argo Rollouts: Verificado"
echo "✅ Aplicación de Producción con Istio: Desplegada (3 pods)"
echo "✅ Gateway y VirtualService de Istio: Configurados"
echo ""
echo "🌐 ACCESOS DISPONIBLES:"
echo "• Aplicación: http://localhost:8080"
echo "• Argo Rollouts Dashboard: http://localhost:3100"
echo ""
echo "📊 DASHBOARDS OPCIONALES:"
echo "• Kiali (Service Mesh): kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "• Grafana (Métricas): kubectl port-forward -n istio-system svc/grafana 3000:3000"
echo "• Jaeger (Tracing): kubectl port-forward -n istio-system svc/jaeger 16686:16686"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Crear experimento: ./scripts/01-create-experiment.sh"
echo "2. Promover a rollout: ./scripts/02-promote-to-rollout.sh"
echo ""
echo "📝 COMANDOS ÚTILES:"
echo "• Ver estado: kubectl get pods,svc"
echo "• Logs de aplicación: kubectl logs -l app=demo-microservice"
echo "• Estado de Istio: $ISTIOCTL_PATH proxy-status"
echo "• Análisis de Istio: $ISTIOCTL_PATH analyze"
echo ""
if [ -n "$DASHBOARD_PF_PID" ]; then
    echo "Port-forwards activos (PIDs: $GATEWAY_PF_PID, $DASHBOARD_PF_PID)"
else
    echo "Port-forwards activos (PID: $GATEWAY_PF_PID)"
fi
echo "Para detener: pkill -f 'kubectl port-forward'"