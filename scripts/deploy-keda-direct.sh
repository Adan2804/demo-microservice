#!/bin/bash

# Script para desplegar KEDA directamente sin ArgoCD
# Útil para pruebas locales o cuando ArgoCD tiene problemas con el repositorio
set -e

echo "🚀 DESPLEGANDO KEDA DIRECTAMENTE (SIN ARGOCD)"
echo "=============================================="

cd "$(dirname "$0")/.."

# 1. Verificar prerequisitos
echo ""
echo "📋 VERIFICANDO PREREQUISITOS..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Cluster de Kubernetes no disponible"
    exit 1
fi

if ! kubectl get namespace keda >/dev/null 2>&1; then
    echo "❌ KEDA no está instalado"
    echo ""
    read -p "¿Deseas instalar KEDA ahora? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "📦 Instalando KEDA..."
        kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml
        echo "⏳ Esperando que KEDA esté listo..."
        sleep 30
        kubectl wait --for=condition=available deployment/keda-operator -n keda --timeout=300s
        echo "✅ KEDA instalado"
    else
        echo "❌ KEDA es requerido"
        exit 1
    fi
fi

echo "✅ Prerequisitos verificados"

# 2. Limpiar recursos anteriores
echo ""
echo "🧹 LIMPIANDO RECURSOS ANTERIORES..."
kubectl delete -f argocd-keda/03-scaled-object.yaml --ignore-not-found=true
kubectl delete -f argocd-keda/04-pdb.yaml --ignore-not-found=true
kubectl delete -f argocd-keda/02-service.yaml --ignore-not-found=true
kubectl delete -f argocd-keda/01-deployment-with-hpa.yaml --ignore-not-found=true
sleep 5

# 3. Aplicar manifiestos
echo ""
echo "📦 APLICANDO MANIFIESTOS..."

echo "1/4 Aplicando Deployment..."
kubectl apply -f argocd-keda/01-deployment-with-hpa.yaml

echo "2/4 Aplicando Service..."
kubectl apply -f argocd-keda/02-service.yaml

echo "3/4 Aplicando PodDisruptionBudget..."
kubectl apply -f argocd-keda/04-pdb.yaml

echo "4/4 Aplicando ScaledObject..."
kubectl apply -f argocd-keda/03-scaled-object.yaml

echo "✅ Manifiestos aplicados"

# 4. Esperar que los pods estén listos
echo ""
echo "⏳ ESPERANDO QUE LOS PODS ESTÉN LISTOS..."
kubectl wait --for=condition=available deployment/demo-microservice-keda -n default --timeout=300s

# 5. Configurar port-forwards
echo ""
echo "🔌 CONFIGURANDO PORT-FORWARDS..."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward.*demo-microservice-keda" 2>/dev/null || true
sleep 2

# Port-forward para el microservicio
echo "Configurando port-forward para demo-microservice-keda..."
kubectl port-forward svc/demo-microservice-keda -n default 8082:8080 > /dev/null 2>&1 &
MICRO_PF_PID=$!
sleep 3

echo "✅ Port-forward configurado (PID: $MICRO_PF_PID)"

# 6. Verificar estado
echo ""
echo "📊 VERIFICANDO ESTADO..."

echo ""
echo "Deployment:"
kubectl get deployment demo-microservice-keda -n default

echo ""
echo "Pods:"
kubectl get pods -n default -l app=demo-microservice-keda

echo ""
echo "Service:"
kubectl get svc demo-microservice-keda -n default

echo ""
echo "PodDisruptionBudget:"
kubectl get pdb demo-microservice-keda-pdb -n default

echo ""
echo "ScaledObject:"
kubectl get scaledobject demo-microservice-keda-scaler -n default

echo ""
echo "HPA (creado por KEDA):"
kubectl get hpa demo-microservice-keda-hpa -n default 2>/dev/null || echo "HPA aún no creado"

# 7. Resumen final
echo ""
echo "🎉 KEDA DESPLEGADO EXITOSAMENTE"
echo "==============================="
echo ""
echo "✅ RECURSOS CREADOS:"
echo "• Deployment: demo-microservice-keda"
echo "• Service: demo-microservice-keda"
echo "• PodDisruptionBudget: demo-microservice-keda-pdb"
echo "• ScaledObject: demo-microservice-keda-scaler"
echo ""
echo "🛡️  CONFIGURACIÓN ZERO DOWNTIME:"
echo "• maxUnavailable: 0"
echo "• minAvailable: 1 (PDB)"
echo "• minReplicaCount: 2 (KEDA)"
echo ""
echo "🌐 ACCESO AL MICROSERVICIO:"
echo "• URL: http://localhost:8082"
echo "• Health: http://localhost:8082/actuator/health"
echo "• Info: http://localhost:8082/actuator/info"
echo "• Port-forward activo (PID: $MICRO_PF_PID)"
echo ""
echo "📊 MONITOREO:"
echo "• Ver pods: kubectl get pods -l app=demo-microservice-keda -w"
echo "• Ver ScaledObject: kubectl describe scaledobject demo-microservice-keda-scaler"
echo "• Ver HPA: kubectl get hpa demo-microservice-keda-hpa"
echo "• Ver PDB: kubectl get pdb demo-microservice-keda-pdb"
echo ""
echo "⏰ HORARIOS DE ESCALADO:"
echo "• 5:55 PM - 6:00 PM: 2 pods (downscale)"
echo "• 6:00 PM - 5:55 PM: 3 pods (normal)"
echo "• Timezone: America/Bogota"
echo ""
echo "🧪 PROBAR EL MICROSERVICIO:"
echo "• curl http://localhost:8082/actuator/health"
echo "• curl http://localhost:8082/actuator/info"
echo ""
echo "🛑 DETENER PORT-FORWARD:"
echo "• kill $MICRO_PF_PID"
echo "• O: pkill -f 'kubectl port-forward'"
echo ""
echo "🗑️  PARA ELIMINAR:"
echo "• kubectl delete -f argocd-keda/"
echo ""
echo "💡 NOTA: Este despliegue NO está gestionado por ArgoCD"
echo "   Para gestión con ArgoCD, usa: ./scripts/setup-argocd-keda.sh"
