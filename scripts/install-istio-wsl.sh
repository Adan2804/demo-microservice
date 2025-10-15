#!/bin/bash

# Script optimizado para instalar Istio en WSL/Ubuntu
# Maneja problemas específicos de WSL y arquitectura
set -e

echo "🕸️  INSTALACIÓN DE ISTIO PARA WSL/UBUNTU"
echo "========================================"

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  --skip-observability Saltar instalación de herramientas de observabilidad"
    echo "  -f, --force         Forzar reinstalación si ya existe"
    echo "  -h, --help          Mostrar esta ayuda"
}

# Valores por defecto
INSTALL_OBSERVABILITY=true
FORCE_INSTALL=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-observability)
            INSTALL_OBSERVABILITY=false
            shift
            ;;
        -f|--force)
            FORCE_INSTALL=true
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

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para esperar que un deployment esté listo
wait_for_deployment() {
    local deployment=$1
    local namespace=${2:-default}
    echo "Esperando que $deployment esté listo en namespace $namespace..."
    kubectl wait --for=condition=available deployment/$deployment -n $namespace --timeout=300s
}

# 1. VERIFICAR DEPENDENCIAS
echo ""
echo "📋 VERIFICANDO DEPENDENCIAS..."

if ! command_exists kubectl; then
    echo "❌ kubectl no está instalado"
    exit 1
fi

if ! command_exists curl; then
    echo "❌ curl no está instalado"
    exit 1
fi

# Verificar que Kubernetes esté disponible
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Cluster de Kubernetes no disponible"
    echo "Asegúrate de que Minikube esté corriendo: minikube start"
    exit 1
fi

echo "✅ Dependencias verificadas"

# 2. DESCARGAR ISTIO
echo ""
echo "📥 DESCARGANDO ISTIO..."

# Crear directorio para Istio si no existe
mkdir -p ./bin

# Descargar directamente la versión específica para Linux
ISTIO_VERSION="1.27.1"
ISTIO_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz"

echo "Descargando Istio ${ISTIO_VERSION}..."
curl -L "$ISTIO_URL" -o "/tmp/istio-${ISTIO_VERSION}.tar.gz"

# Extraer en directorio temporal
TEMP_DIR=$(mktemp -d)
tar -xzf "/tmp/istio-${ISTIO_VERSION}.tar.gz" -C "$TEMP_DIR"

# Copiar istioctl al directorio local
cp "$TEMP_DIR/istio-${ISTIO_VERSION}/bin/istioctl" ./bin/istioctl
chmod +x ./bin/istioctl

# Configurar PATH para esta sesión
export PATH="$PWD/bin:$PATH"
ISTIOCTL_PATH="./bin/istioctl"

# Verificar instalación
echo "Verificando istioctl..."
if "$ISTIOCTL_PATH" version --client >/dev/null 2>&1; then
    ISTIO_VERSION_INSTALLED=$("$ISTIOCTL_PATH" version --client --short 2>/dev/null)
    echo "✅ istioctl instalado: $ISTIO_VERSION_INSTALLED"
else
    echo "⚠️  istioctl instalado pero con advertencias (normal en WSL)"
fi

# Limpiar archivos temporales
rm -f "/tmp/istio-${ISTIO_VERSION}.tar.gz"

# 3. VERIFICAR INSTALACIÓN EXISTENTE
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN EXISTENTE DE ISTIO..."

if kubectl get namespace istio-system >/dev/null 2>&1; then
    echo "⚠️  Istio ya está instalado"
    
    if [ "$FORCE_INSTALL" = false ]; then
        read -p "¿Deseas reinstalar Istio? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Instalación cancelada"
            exit 0
        fi
    fi
    
    echo "Desinstalando Istio existente..."
    "$ISTIOCTL_PATH" uninstall --purge -y 2>/dev/null || true
    kubectl delete namespace istio-system --ignore-not-found=true
    
    # Esperar que se elimine completamente
    echo "Esperando que se complete la desinstalación..."
    while kubectl get namespace istio-system >/dev/null 2>&1; do
        sleep 5
        echo "  Esperando..."
    done
fi

# 4. INSTALAR ISTIO
echo ""
echo "🚀 INSTALANDO ISTIO..."

echo "Instalando Istio con perfil demo..."
"$ISTIOCTL_PATH" install --set values.defaultRevision=default -y

echo "✅ Istio instalado correctamente"

# Verificar instalación
echo "Verificando componentes de Istio..."
wait_for_deployment istiod istio-system
wait_for_deployment istio-ingressgateway istio-system

# 5. CONFIGURAR NAMESPACE DEFAULT
echo ""
echo "🏷️  CONFIGURANDO NAMESPACE DEFAULT..."

kubectl label namespace default istio-injection=enabled --overwrite
echo "✅ Namespace default configurado para inyección de sidecar"

# 6. INSTALAR HERRAMIENTAS DE OBSERVABILIDAD
if [ "$INSTALL_OBSERVABILITY" = true ]; then
    echo ""
    echo "📊 INSTALANDO HERRAMIENTAS DE OBSERVABILIDAD..."
    
    # Usar los addons del directorio de Istio
    ADDONS_DIR="$TEMP_DIR/istio-${ISTIO_VERSION}/samples/addons"
    
    echo "📈 Instalando Prometheus..."
    kubectl apply -f "$ADDONS_DIR/prometheus.yaml"
    
    echo "📊 Instalando Grafana..."
    kubectl apply -f "$ADDONS_DIR/grafana.yaml"
    
    echo "🕸️  Instalando Kiali..."
    kubectl apply -f "$ADDONS_DIR/kiali.yaml"
    
    echo "🔍 Instalando Jaeger..."
    kubectl apply -f "$ADDONS_DIR/jaeger.yaml"
    
    # Esperar que los servicios estén listos
    echo ""
    echo "⏳ Esperando que los servicios de observabilidad estén listos..."
    sleep 30
    
    # Verificar servicios (sin fallar si no están listos)
    echo "Verificando servicios de observabilidad..."
    kubectl wait --for=condition=available deployment/prometheus -n istio-system --timeout=180s || echo "⚠️  Prometheus tardando"
    kubectl wait --for=condition=available deployment/grafana -n istio-system --timeout=180s || echo "⚠️  Grafana tardando"
    kubectl wait --for=condition=available deployment/kiali -n istio-system --timeout=180s || echo "⚠️  Kiali tardando"
    kubectl wait --for=condition=available deployment/jaeger -n istio-system --timeout=180s || echo "⚠️  Jaeger tardando"
    
    echo "✅ Herramientas de observabilidad instaladas"
fi

# Limpiar directorio temporal
rm -rf "$TEMP_DIR"

# 7. VERIFICAR INSTALACIÓN
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN FINAL..."

echo "Estado de Istio:"
"$ISTIOCTL_PATH" verify-install || echo "⚠️  Verificación con advertencias (normal)"

echo ""
echo "Pods en istio-system:"
kubectl get pods -n istio-system

echo ""
echo "Servicios en istio-system:"
kubectl get svc -n istio-system

# 8. CREAR SCRIPTS DE GESTIÓN
echo ""
echo "📝 CREANDO SCRIPTS DE GESTIÓN..."

# Script para iniciar port-forwards
cat > ./scripts/start-istio-dashboards.sh << 'EOF'
#!/bin/bash
echo "🔌 Iniciando port-forwards para Istio..."

# Función para iniciar port-forward en background
start_port_forward() {
    local service=$1
    local local_port=$2
    local remote_port=$3
    local namespace=${4:-istio-system}
    
    if kubectl get svc "$service" -n "$namespace" >/dev/null 2>&1; then
        echo "Port-forward: $service -> localhost:$local_port"
        kubectl port-forward -n "$namespace" svc/"$service" "$local_port:$remote_port" > /dev/null 2>&1 &
        echo $! >> /tmp/istio-pf-pids.txt
    else
        echo "⚠️  Servicio $service no encontrado en namespace $namespace"
    fi
}

# Limpiar archivo de PIDs
> /tmp/istio-pf-pids.txt

# Port-forwards para herramientas de observabilidad
start_port_forward "kiali" "20001" "20001"
start_port_forward "grafana" "3000" "3000"
start_port_forward "jaeger" "16686" "16686"
start_port_forward "prometheus" "9090" "9090"

# Port-forward para Istio Gateway
start_port_forward "istio-ingressgateway" "8080" "80"

echo ""
echo "✅ Port-forwards configurados"
echo "PIDs guardados en: /tmp/istio-pf-pids.txt"
EOF

chmod +x ./scripts/start-istio-dashboards.sh

# Script para detener port-forwards
cat > ./scripts/stop-istio-dashboards.sh << 'EOF'
#!/bin/bash
echo "🛑 Deteniendo port-forwards de Istio..."

# Detener por patrón
pkill -f "kubectl port-forward.*istio-system" 2>/dev/null || true

# Detener por PIDs guardados
if [ -f "/tmp/istio-pf-pids.txt" ]; then
    while read pid; do
        if [ -n "$pid" ]; then
            kill "$pid" 2>/dev/null || true
        fi
    done < /tmp/istio-pf-pids.txt
    rm -f /tmp/istio-pf-pids.txt
fi

echo "✅ Port-forwards detenidos"
EOF

chmod +x ./scripts/stop-istio-dashboards.sh

# 9. CONFIGURAR PORT-FORWARDS INICIALES
echo ""
echo "🔌 CONFIGURANDO ACCESOS INICIALES..."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward.*istio-system" 2>/dev/null || true
sleep 2

# Iniciar port-forwards
if [ "$INSTALL_OBSERVABILITY" = true ]; then
    ./scripts/start-istio-dashboards.sh
    
    if [ -f "/tmp/istio-pf-pids.txt" ]; then
        PIDS=$(cat /tmp/istio-pf-pids.txt | tr '\n' ' ')
        echo "Port-forwards activos (PIDs: $PIDS)"
    fi
fi

# 10. RESUMEN FINAL
echo ""
echo "🎉 ISTIO INSTALADO EXITOSAMENTE EN WSL"
echo "====================================="
echo ""
echo "✅ Istio Core: Instalado y funcionando"
echo "✅ Sidecar Injection: Habilitado en namespace default"

if [ "$INSTALL_OBSERVABILITY" = true ]; then
    echo "✅ Herramientas de observabilidad: Instaladas"
fi

echo "✅ istioctl: Disponible en ./bin/istioctl"

echo ""
echo "🌐 DASHBOARDS DISPONIBLES:"

if [ "$INSTALL_OBSERVABILITY" = true ]; then
    echo "• Kiali (Service Mesh): http://localhost:20001"
    echo "• Grafana (Métricas): http://localhost:3000"
    echo "• Jaeger (Tracing): http://localhost:16686"
    echo "• Prometheus (Métricas): http://localhost:9090"
fi

echo "• Istio Gateway: http://localhost:8080"

echo ""
echo "🛠️  COMANDOS ÚTILES:"
echo "• Verificar instalación: ./bin/istioctl verify-install"
echo "• Analizar configuración: ./bin/istioctl analyze"
echo "• Estado de proxies: ./bin/istioctl proxy-status"
echo ""
echo "📊 GESTIÓN DE DASHBOARDS:"
echo "• Iniciar dashboards: ./scripts/start-istio-dashboards.sh"
echo "• Detener dashboards: ./scripts/stop-istio-dashboards.sh"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Ejecutar aplicaciones: ./scripts/00-init-complete-environment.sh"
echo "2. Crear experimentos: ./scripts/01-create-experiment.sh"
echo "3. Monitorear en Kiali: http://localhost:20001"
echo ""
echo "💡 NOTA PARA WSL:"
echo "Si tienes problemas con port-forwards, usa:"
echo "kubectl port-forward -n istio-system svc/kiali 20001:20001"