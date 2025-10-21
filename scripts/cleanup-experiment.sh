#!/bin/bash

# Script para limpiar experimentos y restaurar configuración base
# Restaura el estado original de producción
set -e

echo "🧹 LIMPIEZA DE EXPERIMENTOS"
echo "=========================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  --force                 Forzar limpieza sin confirmación"
    echo "  --keep-rollout         Mantener rollouts activos"
    echo "  --restore-argocd       Restaurar sincronización con ArgoCD"
    echo "  -h, --help             Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                     # Limpieza interactiva"
    echo "  $0 --force             # Limpieza automática"
    echo "  $0 --keep-rollout      # Limpiar solo experimentos"
}

# Valores por defecto
FORCE_CLEANUP=false
KEEP_ROLLOUT=false
RESTORE_ARGOCD=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --keep-rollout)
            KEEP_ROLLOUT=true
            shift
            ;;
        --restore-argocd)
            RESTORE_ARGOCD=true
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

# 1. MOSTRAR ESTADO ACTUAL
echo ""
echo "📊 ESTADO ACTUAL DEL SISTEMA"
echo "============================"

echo ""
echo "🔍 Deployments activos:"
kubectl get deployments -l app=demo-microservice-istio --no-headers 2>/dev/null || echo "No hay deployments"

echo ""
echo "🔍 Rollouts activos:"
kubectl get rollouts --no-headers 2>/dev/null || echo "No hay rollouts"

echo ""
echo "🔍 Experimentos activos:"
kubectl get deployments -l tier=experiment --no-headers 2>/dev/null || echo "No hay experimentos"

echo ""
echo "🔍 Configuración de Istio:"
kubectl get virtualservice,destinationrule --no-headers 2>/dev/null || echo "No hay configuración de Istio"

# 2. CONFIRMACIÓN (si no es force)
if [ "$FORCE_CLEANUP" = false ]; then
    echo ""
    echo "⚠️  CONFIRMACIÓN DE LIMPIEZA"
    echo "============================"
    echo ""
    echo "Esta operación eliminará:"
    echo "• Todos los experimentos activos"
    if [ "$KEEP_ROLLOUT" = false ]; then
        echo "• Todos los rollouts activos"
    fi
    echo "• Configuraciones temporales de Istio"
    echo "• Restaurará la configuración base de producción"
    echo ""
    read -p "¿Continuar con la limpieza? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Limpieza cancelada por el usuario"
        exit 0
    fi
fi

# 3. LIMPIAR EXPERIMENTOS
echo ""
echo "🧪 LIMPIANDO EXPERIMENTOS..."

# Eliminar deployments de experimentos
echo "Eliminando deployments de experimentos..."
kubectl delete deployment demo-microservice-experiment --ignore-not-found=true

# Eliminar pods huérfanos de experimentos
echo "Eliminando pods huérfanos de experimentos..."
kubectl delete pods -l tier=experiment --ignore-not-found=true

echo "✅ Experimentos eliminados"

# 4. LIMPIAR ROLLOUTS (si no se especifica --keep-rollout)
if [ "$KEEP_ROLLOUT" = false ]; then
    echo ""
    echo "🔄 LIMPIANDO ROLLOUTS..."
    
    # Eliminar rollouts
    echo "Eliminando rollouts..."
    kubectl delete rollout demo-microservice-rollout --ignore-not-found=true
    
    # Eliminar servicios de rollout
    echo "Eliminando servicios de rollout..."
    kubectl delete service demo-microservice-rollout-active --ignore-not-found=true
    kubectl delete service demo-microservice-rollout-preview --ignore-not-found=true
    
    # Eliminar AnalysisTemplates
    echo "Eliminando AnalysisTemplates..."
    kubectl delete analysistemplate success-rate --ignore-not-found=true
    
    echo "✅ Rollouts eliminados"
else
    echo ""
    echo "⏭️  Manteniendo rollouts activos (--keep-rollout especificado)"
fi

# 5. RESTAURAR CONFIGURACIÓN BASE DE ISTIO
echo ""
echo "🌐 RESTAURANDO CONFIGURACIÓN BASE DE ISTIO..."

echo "Aplicando DestinationRule base..."
kubectl apply -f argocd-production/03-destination-rule.yaml

echo "Aplicando VirtualService base..."
kubectl apply -f argocd-production/04-virtual-service.yaml

# Eliminar configuraciones temporales de experimentos/rollouts
echo "Eliminando configuraciones temporales..."
kubectl delete destinationrule demo-microservice-destination --ignore-not-found=true
kubectl delete destinationrule demo-microservice-rollout-destination --ignore-not-found=true
kubectl delete virtualservice demo-microservice-rollout-routing --ignore-not-found=true

# Esperar que la configuración se propague
echo "⏳ Esperando que la configuración se propague..."
sleep 10

echo "✅ Configuración base restaurada"

# 6. RESTAURAR SINCRONIZACIÓN CON ARGOCD (si se especifica)
if [ "$RESTORE_ARGOCD" = true ]; then
    echo ""
    echo "🔄 RESTAURANDO SINCRONIZACIÓN CON ARGOCD..."
    
    # Forzar sincronización de ArgoCD
    if kubectl get application demo-microservice-istio -n argocd >/dev/null 2>&1; then
        echo "Forzando sincronización con ArgoCD..."
        kubectl patch application demo-microservice-istio -n argocd --type='merge' -p='{"operation":{"sync":{"revision":"HEAD"}}}'
        
        echo "Esperando sincronización..."
        sleep 15
        
        echo "✅ Sincronización con ArgoCD restaurada"
    else
        echo "⚠️  Aplicación de ArgoCD no encontrada"
    fi
fi

# 7. LIMPIAR ARCHIVOS TEMPORALES
echo ""
echo "📁 LIMPIANDO ARCHIVOS TEMPORALES..."

# Limpiar archivos temporales del sistema
rm -f /tmp/experiment-deployment.yaml
rm -f /tmp/destination-rule-experiment.yaml
rm -f /tmp/virtual-service-experiment.yaml
rm -f /tmp/rollout-config.yaml
rm -f /tmp/destination-rule-rollout.yaml
rm -f /tmp/virtual-service-rollout.yaml
rm -f /tmp/generate_traffic.sh

echo "✅ Archivos temporales eliminados"

# 8. REINICIAR PODS DE PRODUCCIÓN
echo ""
echo "🔄 REINICIANDO PODS DE PRODUCCIÓN..."

echo "Reiniciando deployment de producción para aplicar configuración limpia..."
kubectl rollout restart deployment/demo-microservice-production-istio

echo "Esperando que el deployment esté listo..."
kubectl rollout status deployment/demo-microservice-production-istio

echo "✅ Pods de producción reiniciados"

# 9. VERIFICAR ESTADO FINAL
echo ""
echo "🔍 VERIFICANDO ESTADO FINAL..."

echo "📊 Deployments activos:"
kubectl get deployments -l app=demo-microservice-istio

echo ""
echo "📊 Pods activos:"
kubectl get pods -l app=demo-microservice-istio

echo ""
echo "📊 Servicios activos:"
kubectl get svc -l app=demo-microservice-istio

echo ""
echo "📊 Configuración de Istio:"
kubectl get virtualservice,destinationrule

# Detectar istioctl para análisis
ISTIOCTL_PATH=""
if [ -f "./bin/istioctl" ]; then
    ISTIOCTL_PATH="./bin/istioctl"
elif command -v istioctl >/dev/null 2>&1; then
    ISTIOCTL_PATH="istioctl"
fi

if [ -n "$ISTIOCTL_PATH" ]; then
    echo ""
    echo "📊 Análisis de configuración de Istio:"
    "$ISTIOCTL_PATH" analyze --no-default-config-map 2>/dev/null || echo "Análisis no disponible"
fi

# 10. PRUEBAS DE CONECTIVIDAD
echo ""
echo "🧪 REALIZANDO PRUEBAS DE CONECTIVIDAD..."

echo "Probando tráfico normal (debe ir solo a producción):"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "Probando tráfico con header experimental (debe ir a producción):"
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

# 11. LIMPIAR PROCESOS EN BACKGROUND
echo ""
echo "🔄 LIMPIANDO PROCESOS EN BACKGROUND..."

# Detener generadores de tráfico si existen
pkill -f "generate_traffic.sh" 2>/dev/null || true

echo "✅ Procesos en background limpiados"

# 12. RESUMEN FINAL
echo ""
echo "🎉 LIMPIEZA COMPLETADA EXITOSAMENTE"
echo "=================================="
echo ""
echo "✅ Experimentos eliminados"
if [ "$KEEP_ROLLOUT" = false ]; then
    echo "✅ Rollouts eliminados"
else
    echo "⏭️  Rollouts mantenidos"
fi
echo "✅ Configuración base de Istio restaurada"
echo "✅ Pods de producción reiniciados"
echo "✅ Archivos temporales eliminados"
if [ "$RESTORE_ARGOCD" = true ]; then
    echo "✅ Sincronización con ArgoCD restaurada"
fi
echo ""
echo "📊 ESTADO ACTUAL:"
echo "• Solo producción estable activa"
echo "• Configuración base de Istio aplicada"
echo "• Todo el tráfico dirigido a producción"
echo ""
echo "🌐 ACCESO:"
echo "• Aplicación: http://localhost:8080"
echo "• Solo responde la versión de producción estable"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Crear nuevo experimento: ./scripts/01-create-experiment.sh"
echo "2. Configurar ArgoCD: ./scripts/03-setup-argocd.sh"
echo "3. Monitorear producción: kubectl logs -l version=stable -f"
echo ""
echo "💡 NOTA:"
echo "El sistema ha vuelto al estado base de producción."
echo "Todos los experimentos y rollouts han sido eliminados."