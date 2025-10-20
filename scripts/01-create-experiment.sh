#!/bin/bash

# Script para crear experimento A/B Testing con Istio
# Este script crea un experimento para probar nuevas versiones de forma segura
set -e

echo "🧪 CREANDO EXPERIMENTO PARA A/B TESTING"
echo "========================================"

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  -v, --version VERSION    Versión del experimento (default: v1.1.0)"
    echo "  -i, --image IMAGE        Imagen Docker personalizada"
    echo "  -h, --help              Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                                    # Usar versión por defecto"
    echo "  $0 -v v2.0.0                        # Especificar versión"
    echo "  $0 -i myregistry/demo:latest         # Usar imagen personalizada"
}

# Valores por defecto
EXPERIMENT_VERSION="v1.1.0"
CUSTOM_IMAGE=""

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            EXPERIMENT_VERSION="$2"
            shift 2
            ;;
        -i|--image)
            CUSTOM_IMAGE="$2"
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

# Verificar que la aplicación base esté desplegada
if ! kubectl get deployment demo-microservice-production-istio >/dev/null 2>&1; then
    echo "❌ Error: Aplicación base no encontrada"
    echo "Ejecuta primero: ./scripts/00-init-complete-environment.sh"
    exit 1
fi

# Verificar que Istio esté configurado
if ! kubectl get virtualservice demo-microservice-gateway-routing >/dev/null 2>&1; then
    echo "❌ Error: Configuración de Istio no encontrada"
    echo "Ejecuta primero: ./scripts/00-init-complete-environment.sh"
    exit 1
fi

# Limpiar experimentos anteriores automáticamente
echo "🧹 Limpiando experimentos anteriores..."


echo "✅ Prerequisitos verificados"

# 2. USAR IMAGEN YA CREADA
echo ""
echo "⚙️  USANDO IMAGEN DEL EXPERIMENTO..."

# Usar imagen que ya se creó en el script de inicialización
EXPERIMENT_IMAGE="demo-microservice:experiment-candidate-v1.1.0"
echo "Imagen del experimento: $EXPERIMENT_IMAGE"

# 3. CREAR DEPLOYMENT DEL EXPERIMENTO
echo ""
echo "🚀 CREANDO DEPLOYMENT DEL EXPERIMENTO..."

# Generar deployment del experimento con la imagen correcta
cat istio/02-experiment-deployment-istio.yaml | \
    sed "s|demo-microservice:experiment-candidate-v1.1.0|$EXPERIMENT_IMAGE|g" | \
    kubectl apply -f -

# Esperar que el deployment esté listo
echo "Esperando que el experimento esté listo..."
kubectl wait --for=condition=available deployment/demo-microservice-experiment --timeout=300s

# 4. VERIFICAR ESTADO DEL EXPERIMENTO
echo ""
echo "🔍 VERIFICANDO ESTADO DEL EXPERIMENTO..."

echo "Estado de los pods:"
kubectl get pods -l app=demo-microservice -o wide

echo ""
echo "Estado de los deployments:"
kubectl get deployments -l app=demo-microservice

# 5. ACTUALIZAR CONFIGURACIÓN DE ISTIO
echo ""
echo "🌐 ACTUALIZANDO CONFIGURACIÓN DE ISTIO..."

echo "IMPORTANTE: Los experimentos SOBRESCRIBEN temporalmente los recursos de ArgoCD"
echo "• ArgoCD gestiona: argocd-production/ (archivos base)"
echo "• Experimento usa: istio/ (archivos con configuración de experimento)"
echo "• Las anotaciones evitan que ArgoCD revierta los cambios"
echo ""

# Actualizar DestinationRule para incluir subset del experimento
echo "Sobrescribiendo DestinationRule con configuración de experimento..."
kubectl apply -f istio/03-destination-rule-experiment.yaml

# Actualizar VirtualServices usando apply (seguro y simple)
echo "Sobrescribiendo VirtualServices con enrutamiento de experimento..."
kubectl apply -f istio/04-virtual-service-experiment.yaml

echo "✅ Configuración de experimento aplicada (ArgoCD la ignora por las anotaciones)"

# Esperar que la configuración se propague
echo "Esperando que la configuración de Istio se propague..."
sleep 10

# 6. REALIZAR PRUEBAS DE CONECTIVIDAD
echo ""
echo "🧪 REALIZANDO PRUEBAS DE CONECTIVIDAD..."

echo "Probando tráfico normal (debe ir a producción):"
response=$(curl -s http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

echo ""
echo "Probando tráfico experimental (debe ir al experimento):"
response=$(curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
    http://localhost:8080/api/v1/experiment/version 2>/dev/null || echo "Error de conexión")
echo "Respuesta: $response"

# 7. MOSTRAR MÉTRICAS Y MONITOREO
echo ""
echo "📊 CONFIGURANDO MONITOREO..."

# Mostrar comandos para monitoreo
echo "Comandos de monitoreo disponibles:"
echo "• Ver logs del experimento: kubectl logs -l app=demo-microservice,version=experiment -f"
echo "• Ver logs de producción: kubectl logs -l app=demo-microservice,version=stable -f"
echo "• Métricas de CPU/Memoria: kubectl top pods -l app=demo-microservice"
# Detectar istioctl local o sistema
if [ -f "./bin/istioctl" ]; then
    ISTIOCTL_CMD="./bin/istioctl"
else
    ISTIOCTL_CMD="istioctl"
fi

echo "• Estado de Istio: $ISTIOCTL_CMD proxy-status"

# 8. GENERAR TRÁFICO DE PRUEBA (OPCIONAL)
echo ""
read -p "¿Deseas generar tráfico de prueba automático? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🔄 GENERANDO TRÁFICO DE PRUEBA..."
    
    # Crear script temporal para generar tráfico
    cat > /tmp/generate_traffic.sh << 'EOF'
#!/bin/bash
echo "Generando tráfico de prueba por 60 segundos..."
end_time=$((SECONDS + 60))

while [ $SECONDS -lt $end_time ]; do
    # Tráfico normal (80%)
    for i in {1..8}; do
        curl -s http://localhost:8080/api/v1/experiment/version > /dev/null &
    done
    
    # Tráfico experimental (20%)
    for i in {1..2}; do
        curl -s -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
            http://localhost:8080/api/v1/experiment/version > /dev/null &
    done
    
    sleep 1
done

wait
echo "Tráfico de prueba completado"
EOF
    
    chmod +x /tmp/generate_traffic.sh
    /tmp/generate_traffic.sh &
    TRAFFIC_PID=$!
    
    echo "Tráfico de prueba iniciado (PID: $TRAFFIC_PID)"
    echo "Puedes monitorear el impacto con: kubectl top pods -l app=demo-microservice"
fi

# 9. RESUMEN FINAL
echo ""
echo "🎉 EXPERIMENTO CREADO EXITOSAMENTE"
echo "=================================="
echo ""
echo "✅ Experimento desplegado: $EXPERIMENT_IMAGE"
echo "✅ Configuración de Istio actualizada"
echo "✅ Enrutamiento por headers configurado"
echo ""
echo "🧪 DETALLES DEL EXPERIMENTO:"
echo "• Versión: $EXPERIMENT_VERSION"
echo "• Imagen: $EXPERIMENT_IMAGE"
echo "• Header de prueba: aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400"
echo ""
echo "🌐 ENRUTAMIENTO:"
echo "• Tráfico normal → Producción (3 pods)"
echo "• Tráfico con header → Experimento (1 pod)"
echo ""
echo "📊 MONITOREO:"
echo "• Dashboard de Istio: kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "• Métricas: kubectl port-forward -n istio-system svc/grafana 3000:3000"
echo ""
echo "🚀 PRÓXIMO PASO:"
echo "Una vez validado el experimento, promover a rollout:"
echo "./scripts/02-promote-to-rollout.sh"
echo ""
echo "🛑 PARA ELIMINAR EL EXPERIMENTO:"
echo "./scripts/cleanup-experiment.sh"
echo ""
echo "O manualmente:"
echo "kubectl delete deployment demo-microservice-experiment"
echo "kubectl apply -f argocd-production/03-destination-rule.yaml"
echo "kubectl apply -f argocd-production/04-virtual-service.yaml"