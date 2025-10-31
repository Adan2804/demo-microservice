#!/bin/bash

# Script para instalar KEDA (Kubernetes Event-Driven Autoscaling)
set -e

echo "📦 INSTALANDO KEDA"
echo "=================="

cd "$(dirname "$0")/.."

# 1. Verificar que Kubernetes esté disponible
echo ""
echo "📋 VERIFICANDO PREREQUISITOS..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Cluster de Kubernetes no disponible"
    exit 1
fi

echo "✅ Kubernetes disponible"

# 2. Verificar si KEDA ya está instalado
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN DE KEDA..."

if kubectl get namespace keda >/dev/null 2>&1; then
    echo "⚠️  KEDA ya está instalado"
    
    # Verificar versión
    KEDA_VERSION=$(kubectl get deployment keda-operator -n keda -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    echo "   Versión actual: $KEDA_VERSION"
    
    read -p "¿Deseas reinstalar KEDA? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "✅ Manteniendo instalación actual de KEDA"
        exit 0
    fi
    
    echo "🗑️  Eliminando instalación anterior..."
    kubectl delete namespace keda --ignore-not-found=true
    sleep 10
fi

# 3. Instalar KEDA usando Helm (método recomendado)
echo ""
echo "🔧 INSTALANDO KEDA..."

# Verificar si Helm está instalado
if ! command -v helm >/dev/null 2>&1; then
    echo "⚠️  Helm no está instalado, usando kubectl apply..."
    
    # Método alternativo: kubectl apply
    echo "📥 Descargando manifiestos de KEDA..."
    kubectl apply --server-side -f https://github.com/kedacore/keda/releases/download/v2.15.1/keda-2.15.1.yaml
    
else
    echo "✅ Helm encontrado, usando instalación con Helm..."
    
    # Agregar repositorio de KEDA
    helm repo add kedacore https://kedacore.github.io/charts
    helm repo update
    
    # Instalar KEDA
    helm install keda kedacore/keda --namespace keda-system --create-namespace
fi

# 4. Esperar que KEDA esté listo
echo ""
echo "⏳ ESPERANDO QUE KEDA ESTÉ LISTO..."

kubectl wait --for=condition=available deployment/keda-operator -n keda --timeout=300s
kubectl wait --for=condition=available deployment/keda-metrics-apiserver -n keda --timeout=300s

echo "✅ KEDA instalado correctamente"

# 5. Verificar instalación
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN..."

echo ""
echo "📊 Pods de KEDA:"
kubectl get pods -n keda

echo ""
echo "📋 CRDs de KEDA instalados:"
kubectl get crd | grep keda || echo "No se encontraron CRDs de KEDA"

echo ""
echo "🔧 Versión de KEDA:"
kubectl get deployment keda-operator -n keda -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

# 6. Verificar que los ScaledObjects se puedan crear
echo ""
echo "🧪 VERIFICANDO QUE SCALEDOBJECTS FUNCIONEN..."

if kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1; then
    echo "✅ CRD ScaledObject disponible"
else
    echo "❌ CRD ScaledObject NO disponible"
    exit 1
fi

# 7. Resumen final
echo ""
echo "🎉 KEDA INSTALADO EXITOSAMENTE"
echo "=============================="
echo ""
echo "✅ Namespace: keda"
echo "✅ Operator: keda-operator"
echo "✅ Metrics Server: keda-metrics-apiserver"
echo "✅ CRDs instalados"
echo ""
echo "📊 COMPONENTES:"
kubectl get all -n keda
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Aplicar los ScaledObjects:"
echo "   kubectl apply -f argocd-production/05-scaled-object-intelligent-downscale.yaml"
echo "   kubectl apply -f argocd-production/06-scaled-object-intelligent-upscale.yaml"
echo ""
echo "2. Verificar ScaledObjects:"
echo "   kubectl get scaledobjects"
echo ""
echo "3. Monitorear escalado:"
echo "   ./scripts/monitor-intelligent-scaling.sh"
echo ""
echo "📚 DOCUMENTACIÓN:"
echo "• KEDA Docs: https://keda.sh/docs/"
echo "• ScaledObject Spec: https://keda.sh/docs/latest/concepts/scaling-deployments/"
