#!/bin/bash

# Script para limpiar y resetear el entorno completo
set -e

echo "🧹 LIMPIEZA DEL ENTORNO DE TESTING"
echo "=================================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  -f, --force      Forzar limpieza sin confirmación"
    echo "  --keep-minikube  Mantener Minikube corriendo"
    echo "  --only-apps      Solo limpiar aplicaciones, mantener infraestructura"
    echo "  -h, --help       Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                    # Limpieza interactiva completa"
    echo "  $0 -f                 # Limpieza automática completa"
    echo "  $0 --only-apps        # Solo limpiar aplicaciones"
    echo "  $0 --keep-minikube    # Limpiar todo excepto Minikube"
}

# Valores por defecto
FORCE_MODE=false
KEEP_MINIKUBE=false
ONLY_APPS=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --keep-minikube)
            KEEP_MINIKUBE=true
            shift
            ;;
        --only-apps)
            ONLY_APPS=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Confirmación si no está en modo forzado
if [ "$FORCE_MODE" = false ]; then
    echo ""
    echo "⚠️  ADVERTENCIA: Esta operación eliminará:"
    echo "• Todos los deployments de la aplicación"
    echo "• Experimentos activos"
    echo "• Rollouts de Argo"
    echo "• Configuración de Istio"
    if [ "$ONLY_APPS" = false ]; then
        echo "• Argo Rollouts (si --only-apps no está especificado)"
        if [ "$KEEP_MINIKUBE" = false ]; then
            echo "• Istio Service Mesh (si --keep-minikube no está especificado)"
            echo "• Minikube cluster (si --keep-minikube no está especificado)"
        fi
    fi
    echo ""
    read -p "¿Continuar con la limpieza? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operación cancelada"
        exit 0
    fi
fi

# 1. DETENER PORT-FORWARDS
echo ""
echo "🔌 DETENIENDO PORT-FORWARDS..."
pkill -f "kubectl port-forward" 2>/dev/null || true
echo "✅ Port-forwards detenidos"

# 2. LIMPIAR APLICACIONES
echo ""
echo "🗑️  ELIMINANDO APLICACIONES..."

# Eliminar rollouts
if kubectl get rollout demo-microservice-rollout-istio >/dev/null 2>&1; then
    echo "Eliminando Argo Rollout..."
    kubectl delete rollout demo-microservice-rollout-istio
fi

# Eliminar experimentos
if kubectl get deployment demo-microservice-experiment >/dev/null 2>&1; then
    echo "Eliminando experimento..."
    kubectl delete deployment demo-microservice-experiment
fi

# Eliminar deployment de producción
if kubectl get deployment demo-microservice-production >/dev/null 2>&1; then
    echo "Eliminando deployment de producción..."
    kubectl delete deployment demo-microservice-production
fi

# Eliminar servicios
if kubectl get service demo-microservice >/dev/null 2>&1; then
    echo "Eliminando servicio..."
    kubectl delete service demo-microservice
fi

if kubectl get service demo-microservice-unified >/dev/null 2>&1; then
    echo "Eliminando servicio unificado..."
    kubectl delete service demo-microservice-unified
fi

echo "✅ Aplicaciones eliminadas"

# 3. LIMPIAR CONFIGURACIÓN DE ISTIO
echo ""
echo "🌐 ELIMINANDO CONFIGURACIÓN DE ISTIO..."

# Eliminar VirtualServices
if kubectl get virtualservice demo-microservice-routing >/dev/null 2>&1; then
    echo "Eliminando VirtualService principal..."
    kubectl delete virtualservice demo-microservice-routing
fi

if kubectl get virtualservice demo-microservice-rollout >/dev/null 2>&1; then
    echo "Eliminando VirtualService de rollout..."
    kubectl delete virtualservice demo-microservice-rollout
fi

# Eliminar DestinationRule
if kubectl get destinationrule demo-microservice-destination >/dev/null 2>&1; then
    echo "Eliminando DestinationRule..."
    kubectl delete destinationrule demo-microservice-destination
fi

# Restaurar configuración base de Istio
echo "Restaurando configuración base de Istio..."
kubectl apply -f istio/02-service-unified.yaml
kubectl apply -f istio/03-destination-rule.yaml
kubectl apply -f istio/04-virtual-service.yaml

# Eliminar Gateway si existe
if kubectl get gateway demo-microservice-gateway >/dev/null 2>&1; then
    echo "Eliminando Gateway..."
    kubectl delete gateway demo-microservice-gateway
fi

echo "✅ Configuración de Istio eliminada"

# 4. LIMPIAR INFRAESTRUCTURA (si no es solo apps)
if [ "$ONLY_APPS" = false ]; then
    echo ""
    echo "🏗️  ELIMINANDO INFRAESTRUCTURA..."
    
    # Eliminar Argo Rollouts
    if kubectl get namespace argo-rollouts >/dev/null 2>&1; then
        echo "Eliminando Argo Rollouts..."
        kubectl delete namespace argo-rollouts
    fi
    
    # Eliminar Istio (si no se mantiene Minikube)
    if [ "$KEEP_MINIKUBE" = false ]; then
        if kubectl get namespace istio-system >/dev/null 2>&1; then
            echo "Eliminando Istio Service Mesh..."
            istioctl uninstall --purge -y 2>/dev/null || true
            kubectl delete namespace istio-system --ignore-not-found=true
        fi
        
        # Eliminar label de inyección de Istio
        kubectl label namespace default istio-injection- 2>/dev/null || true
    fi
    
    echo "✅ Infraestructura eliminada"
fi

# 5. DETENER MINIKUBE (si no se mantiene)
if [ "$KEEP_MINIKUBE" = false ]; then
    echo ""
    echo "🛑 DETENIENDO MINIKUBE..."
    
    if minikube status | grep -q "Running"; then
        echo "Deteniendo Minikube..."
        minikube stop
        
        if [ "$FORCE_MODE" = true ]; then
            echo "Eliminando cluster de Minikube..."
            minikube delete
        else
            read -p "¿Deseas eliminar completamente el cluster de Minikube? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                minikube delete
            fi
        fi
    else
        echo "Minikube no está corriendo"
    fi
    
    echo "✅ Minikube gestionado"
fi

# 6. LIMPIAR ARCHIVOS TEMPORALES
echo ""
echo "📁 LIMPIANDO ARCHIVOS TEMPORALES..."

# Limpiar archivos de backup
find . -name "*.bak" -delete 2>/dev/null || true

# Limpiar archivos temporales de Docker
if [ -f ".dockerignore.tmp" ]; then
    rm .dockerignore.tmp
fi

# Limpiar scripts temporales
rm -f /tmp/generate_traffic.sh 2>/dev/null || true

echo "✅ Archivos temporales eliminados"

# 7. VERIFICAR LIMPIEZA
echo ""
echo "🔍 VERIFICANDO LIMPIEZA..."

echo "Pods restantes:"
kubectl get pods 2>/dev/null || echo "No hay pods"

echo ""
echo "Servicios restantes:"
kubectl get services 2>/dev/null || echo "No hay servicios"

echo ""
echo "Deployments restantes:"
kubectl get deployments 2>/dev/null || echo "No hay deployments"

if [ "$ONLY_APPS" = false ]; then
    echo ""
    echo "Namespaces de infraestructura:"
    kubectl get namespaces | grep -E "(istio-system|argo-rollouts)" || echo "Infraestructura eliminada"
fi

# 8. RESUMEN FINAL
echo ""
echo "🎉 LIMPIEZA COMPLETADA"
echo "====================="
echo ""

if [ "$ONLY_APPS" = true ]; then
    echo "✅ Aplicaciones eliminadas"
    echo "✅ Configuración de Istio eliminada"
    echo "⚠️  Infraestructura mantenida (Istio, Argo Rollouts, Minikube)"
elif [ "$KEEP_MINIKUBE" = true ]; then
    echo "✅ Aplicaciones eliminadas"
    echo "✅ Configuración de Istio eliminada"
    echo "✅ Argo Rollouts eliminado"
    echo "⚠️  Minikube mantenido"
else
    echo "✅ Entorno completamente limpio"
    echo "✅ Todas las aplicaciones eliminadas"
    echo "✅ Infraestructura eliminada"
    echo "✅ Minikube gestionado"
fi

echo ""
echo "🚀 PARA REINICIAR EL ENTORNO:"
echo "./scripts/00-init-complete-environment.sh"
echo ""
echo "💡 COMANDOS ÚTILES:"
echo "• Ver estado de Minikube: minikube status"
echo "• Ver clusters de kubectl: kubectl config get-contexts"
echo "• Limpiar configuración de Docker: docker system prune"