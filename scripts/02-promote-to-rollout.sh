#!/bin/bash

# Script para promover experimento a Argo Rollout con confirmación
# Implementa Blue-Green deployment con Istio para promoción segura
set -e

echo "🚀 PROMOCIÓN DE EXPERIMENTO A ROLLOUT"
echo "====================================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  -f, --force             Saltar confirmaciones (modo automático)"
    echo "  -s, --strategy STRATEGY Estrategia de rollout (canary|bluegreen) [default: canary]"
    echo "  -h, --help             Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                      # Promoción interactiva con canary"
    echo "  $0 -f                   # Promoción automática"
    echo "  $0 -s bluegreen         # Usar estrategia blue-green"
}

# Valores por defecto
FORCE_MODE=false
ROLLOUT_STRATEGY="canary"

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -s|--strategy)
            ROLLOUT_STRATEGY="$2"
            shift 2
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

# 1. VERIFICAR PREREQUISITOS
echo ""
echo "📋 VERIFICANDO PREREQUISITOS..."

# Verificar que el experimento exista
if ! kubectl get deployment demo-microservice-experiment >/dev/null 2>&1; then
    echo "❌ Error: Experimento no encontrado"
    echo "Ejecuta primero: ./scripts/01-create-experiment.sh"
    exit 1
fi

# Verificar que Argo Rollouts esté instalado
if ! kubectl get deployment argo-rollouts-controller -n argo-rollouts >/dev/null 2>&1; then
    echo "❌ Error: Argo Rollouts no está instalado"
    echo "Ejecuta primero: ./scripts/00-init-complete-environment.sh"
    exit 1
fi

# Verificar que el experimento esté funcionando
EXPERIMENT_READY=$(kubectl get deployment demo-microservice-experiment -o jsonpath='{.status.readyReplicas}')
if [ "$EXPERIMENT_READY" != "1" ]; then
    echo "❌ Error: El experimento no está listo (pods: $EXPERIMENT_READY/1)"
    exit 1
fi

echo "✅ Prerequisitos verificados"

# 2. OBTENER INFORMACIÓN DEL EXPERIMENTO
echo ""
echo "🔍 ANALIZANDO EXPERIMENTO ACTUAL..."

EXPERIMENT_IMAGE=$(kubectl get deployment demo-microservice-experiment -o jsonpath='{.spec.template.spec.containers[0].image}')
EXPERIMENT_VERSION=$(echo $EXPERIMENT_IMAGE | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")

echo "Imagen del experimento: $EXPERIMENT_IMAGE"
echo "Versión detectada: $EXPERIMENT_VERSION"

# Verificar que el experimento esté recibiendo tráfico
echo ""
echo "Probando conectividad del experimento..."
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error")

if [[ "$response" == *"Error"* ]]; then
    echo "⚠️  Advertencia: El experimento no responde correctamente"
    if [ "$FORCE_MODE" = false ]; then
        read -p "¿Continuar de todos modos? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operación cancelada"
            exit 0
        fi
    fi
else
    echo "✅ Experimento respondiendo correctamente: $response"
fi

# 3. CONFIRMACIÓN DEL USUARIO
if [ "$FORCE_MODE" = false ]; then
    echo ""
    echo "⚠️  CONFIRMACIÓN DE PROMOCIÓN"
    echo "=============================="
    echo ""
    echo "Estás a punto de promover el experimento a producción:"
    echo "• Imagen actual: $EXPERIMENT_IMAGE"
    echo "• Estrategia: $ROLLOUT_STRATEGY deployment"
    echo "• Esto reemplazará gradualmente la versión de producción actual"
    echo ""
    echo "¿Estás seguro de que quieres continuar?"
    echo ""
    read -p "Escribe 'PROMOVER' para confirmar: " confirmation
    
    if [ "$confirmation" != "PROMOVER" ]; then
        echo "Operación cancelada"
        exit 0
    fi
fi

# 4. PREPARAR ROLLOUT
echo ""
echo "⚙️  PREPARANDO ROLLOUT..."

# Verificar si ya existe un rollout activo
if kubectl get rollout demo-microservice-rollout-istio >/dev/null 2>&1; then
    echo "⚠️  Ya existe un rollout activo"
    
    ROLLOUT_STATUS=$(kubectl get rollout demo-microservice-rollout-istio -o jsonpath='{.status.phase}')
    echo "Estado actual del rollout: $ROLLOUT_STATUS"
    
    if [ "$ROLLOUT_STATUS" = "Progressing" ]; then
        echo "❌ Error: Hay un rollout en progreso. Espera a que termine o aborta:"
        echo "kubectl argo rollouts abort demo-microservice-rollout-istio"
        exit 1
    fi
    
    if [ "$FORCE_MODE" = false ]; then
        read -p "¿Deseas eliminar el rollout existente y crear uno nuevo? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kubectl delete rollout demo-microservice-rollout-istio
            sleep 5
        else
            echo "Operación cancelada"
            exit 0
        fi
    else
        kubectl delete rollout demo-microservice-rollout-istio
        sleep 5
    fi
fi

# 5. CREAR ARGO ROLLOUT
echo ""
echo "🎯 CREANDO ARGO ROLLOUT..."

# Seleccionar archivo de configuración según estrategia
if [ "$ROLLOUT_STRATEGY" = "bluegreen" ]; then
    ROLLOUT_FILE="istio/05-argo-rollout-istio-bluegreen.yaml"
    if [ ! -f "$ROLLOUT_FILE" ]; then
        echo "⚠️  Archivo de configuración Blue-Green no encontrado, usando Canary"
        ROLLOUT_FILE="istio/05-argo-rollout-istio.yaml"
    fi
else
    ROLLOUT_FILE="istio/05-argo-rollout-istio.yaml"
fi

# Aplicar rollout con la imagen del experimento
echo "Aplicando rollout con imagen: $EXPERIMENT_IMAGE"
cat $ROLLOUT_FILE | sed "s|demo-microservice:stable|$EXPERIMENT_IMAGE|g" | kubectl apply -f -

# Esperar que el rollout esté listo
echo "Esperando que el rollout esté listo..."
kubectl wait --for=condition=progressing rollout/demo-microservice-rollout-istio --timeout=300s

# 6. MONITOREAR PROGRESO
echo ""
echo "📊 MONITOREANDO PROGRESO DEL ROLLOUT..."

# Iniciar monitoreo en background
kubectl argo rollouts get rollout demo-microservice-rollout-istio --watch &
WATCH_PID=$!

# Función para limpiar al salir
cleanup() {
    kill $WATCH_PID 2>/dev/null || true
    echo ""
    echo "Monitoreo detenido"
}
trap cleanup EXIT

# 7. MOSTRAR INFORMACIÓN DEL ROLLOUT
echo ""
echo "🚀 ROLLOUT INICIADO"
echo "==================="
echo ""
echo "Estrategia: $ROLLOUT_STRATEGY deployment"
echo "Imagen: $EXPERIMENT_IMAGE"
echo ""

if [ "$ROLLOUT_STRATEGY" = "canary" ]; then
    echo "Progreso del Canary Deployment:"
    echo "• Fase 1: 10% del tráfico → Nueva versión"
    echo "• Fase 2: 25% del tráfico → Nueva versión"
    echo "• Fase 3: 50% del tráfico → Nueva versión"
    echo "• Fase 4: 75% del tráfico → Nueva versión"
    echo "• Fase 5: 100% del tráfico → Nueva versión"
else
    echo "Progreso del Blue-Green Deployment:"
    echo "• Fase 1: Desplegar nueva versión (Green)"
    echo "• Fase 2: Validar nueva versión"
    echo "• Fase 3: Cambiar tráfico a nueva versión"
    echo "• Fase 4: Eliminar versión anterior (Blue)"
fi

echo ""
echo "⏱️  El rollout progresará automáticamente con pausas para validación"
echo ""

# 8. COMANDOS DISPONIBLES
echo "🎛️  COMANDOS DISPONIBLES:"
echo "• Promover manualmente: kubectl argo rollouts promote demo-microservice-rollout-istio"
echo "• Abortar rollout: kubectl argo rollouts abort demo-microservice-rollout-istio"
echo "• Ver estado: kubectl argo rollouts get rollout demo-microservice-rollout-istio"
echo "• Rollback: kubectl argo rollouts undo demo-microservice-rollout-istio"
echo ""

# 9. PRUEBAS DURANTE EL ROLLOUT
echo "🧪 REALIZANDO PRUEBAS DURANTE EL ROLLOUT..."
echo ""

# Función para probar conectividad
test_connectivity() {
    local phase=$1
    echo "[$phase] Probando conectividad..."
    
    local normal_response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error")
    echo "[$phase] Tráfico normal: $normal_response"
    
    local experiment_response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
        http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error")
    echo "[$phase] Tráfico experimental: $experiment_response"
    echo ""
}

# Prueba inicial
test_connectivity "INICIO"

# 10. ESPERAR INTERACCIÓN DEL USUARIO
if [ "$FORCE_MODE" = false ]; then
    echo "💡 OPCIONES:"
    echo "• Presiona ENTER para continuar monitoreando"
    echo "• Presiona Ctrl+C para detener el monitoreo (el rollout continuará)"
    echo "• Escribe 'promote' para promover inmediatamente"
    echo "• Escribe 'abort' para abortar el rollout"
    echo ""
    
    while true; do
        read -t 30 -p "Comando (o ENTER para continuar): " user_input || true
        
        case "$user_input" in
            "promote")
                echo "Promoviendo rollout..."
                kubectl argo rollouts promote demo-microservice-rollout-istio
                ;;
            "abort")
                echo "Abortando rollout..."
                kubectl argo rollouts abort demo-microservice-rollout-istio
                break
                ;;
            "")
                # Continuar monitoreando
                test_connectivity "PROGRESO"
                ;;
            *)
                echo "Comando no reconocido"
                ;;
        esac
        
        # Verificar si el rollout ha terminado
        ROLLOUT_STATUS=$(kubectl get rollout demo-microservice-rollout-istio -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        if [ "$ROLLOUT_STATUS" = "Healthy" ]; then
            echo ""
            echo "✅ ROLLOUT COMPLETADO EXITOSAMENTE"
            break
        elif [ "$ROLLOUT_STATUS" = "Degraded" ]; then
            echo ""
            echo "❌ ROLLOUT FALLÓ"
            break
        fi
    done
else
    # Modo automático - esperar hasta que termine
    echo "Modo automático activado - esperando finalización..."
    kubectl argo rollouts wait demo-microservice-rollout-istio --timeout=600s
fi

# 11. ESTADO FINAL
echo ""
echo "📊 ESTADO FINAL DEL ROLLOUT"
echo "==========================="

FINAL_STATUS=$(kubectl get rollout demo-microservice-rollout-istio -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
echo "Estado: $FINAL_STATUS"

if [ "$FINAL_STATUS" = "Healthy" ]; then
    echo ""
    echo "🎉 PROMOCIÓN COMPLETADA EXITOSAMENTE"
    echo ""
    echo "✅ La nueva versión está ahora en producción"
    echo "✅ El experimento ha sido promovido exitosamente"
    echo ""
    
    # Prueba final
    test_connectivity "FINAL"
    
    echo "🧹 LIMPIEZA RECOMENDADA:"
    echo "• Eliminar deployment del experimento: kubectl delete deployment demo-microservice-experiment"
    echo "• Limpiar configuración de Istio si es necesario"
    
elif [ "$FINAL_STATUS" = "Degraded" ]; then
    echo ""
    echo "❌ PROMOCIÓN FALLÓ"
    echo ""
    echo "El rollout ha fallado. Revisa los logs y considera hacer rollback:"
    echo "kubectl argo rollouts undo demo-microservice-rollout-istio"
    
else
    echo ""
    echo "⏳ ROLLOUT AÚN EN PROGRESO"
    echo ""
    echo "El rollout continúa ejecutándose. Puedes monitorearlo con:"
    echo "kubectl argo rollouts get rollout demo-microservice-rollout-istio --watch"
fi

echo ""
echo "📊 DASHBOARDS DISPONIBLES:"
echo "• Argo Rollouts: http://localhost:3100"
echo "• Kiali (Istio): kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "• Grafana: kubectl port-forward -n istio-system svc/grafana 3000:3000"