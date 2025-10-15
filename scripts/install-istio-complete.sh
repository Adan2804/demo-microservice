#!/bin/bash

# Script para instalar Istio completo con observabilidad
# Descarga e instala automáticamente istioctl y todas las herramientas
# Incluye: Istio, Prometheus, Grafana, Kiali, Jaeger
set -e

echo "🕸️  INSTALACIÓN COMPLETA DE ISTIO CON OBSERVABILIDAD"
echo "===================================================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  --sidecar           Instalar Istio en modo Sidecar (default)"
    echo "  --skip-observability Saltar instalación de herramientas de observabilidad"
    echo "  -f, --force         Forzar reinstalación si ya existe"
    echo "  -h, --help          Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                  # Instalación completa"
    echo "  $0 --skip-observability # Solo Istio, sin herramientas de observabilidad"
}

# Valores por defecto
INSTALL_OBSERVABILITY=true
FORCE_INSTALL=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --sidecar)
            # Mantener compatibilidad, pero siempre usar sidecar
            shift
            ;;
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

# 1. VERIFICAR DEPENDENCIAS BÁSICAS
echo ""
echo "📋 VERIFICANDO DEPENDENCIAS BÁSICAS..."

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
    exit 1
fi

echo "✅ Dependencias básicas verificadas"

# 2. DESCARGAR E INSTALAR ISTIOCTL
echo ""
echo "📥 DESCARGANDO E INSTALANDO ISTIOCTL..."

# Crear directorio temporal
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Descargar Istio
echo "Descargando la última versión de Istio..."
curl -L https://istio.io/downloadIstio | sh -

# Encontrar el directorio de Istio
ISTIO_DIR=$(find . -name "istio-*" -type d | head -1)
if [ -z "$ISTIO_DIR" ]; then
    echo "❌ Error: No se pudo encontrar el directorio de Istio"
    exit 1
fi

# Configurar PATH para esta sesión
export PATH="$PWD/$ISTIO_DIR/bin:$PATH"
ISTIOCTL_PATH="$PWD/$ISTIO_DIR/bin/istioctl"

# Hacer istioctl ejecutable
chmod +x "$ISTIOCTL_PATH"

# Verificar que istioctl funciona
echo "Verificando istioctl..."
if ! "$ISTIOCTL_PATH" version --client >/dev/null 2>&1; then
    echo "⚠️  Problema con istioctl, intentando solucionar..."
    
    # Verificar si es problema de arquitectura
    if file "$ISTIOCTL_PATH" | grep -q "x86-64"; then
        echo "Arquitectura correcta detectada"
    else
        echo "❌ Error: Arquitectura incorrecta"
        exit 1
    fi
    
    # Intentar ejecutar con más información
    echo "Intentando ejecutar istioctl con debug..."
    "$ISTIOCTL_PATH" version --client 2>&1 || {
        echo "❌ Error: istioctl no puede ejecutarse"
        echo "Esto puede ser un problema de WSL. Intentando continuar..."
    }
fi

ISTIO_VERSION=$("$ISTIOCTL_PATH" version --client --short 2>/dev/null || echo "1.27.1")
echo "✅ istioctl descargado e instalado: $ISTIO_VERSION"

# Volver al directorio original
cd - > /dev/null

# 3. VERIFICAR INSTALACIÓN EXISTENTE
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN EXISTENTE..."

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
    done
fi

# 4. INSTALAR ISTIO CORE
echo ""
echo "🚀 INSTALANDO ISTIO CORE..."

echo "Instalando Istio con perfil demo (incluye ingress gateway)..."

# Instalar Istio con perfil demo
"$ISTIOCTL_PATH" install --set values.defaultRevision=default -y

echo "✅ Istio instalado correctamente"

# Verificar instalación
wait_for_deployment istiod istio-system
wait_for_deployment istio-ingressgateway istio-system

# 5. CONFIGURAR NAMESPACE DEFAULT
echo ""
echo "🏷️  CONFIGURANDO NAMESPACE DEFAULT..."

# Habilitar inyección automática de sidecar
kubectl label namespace default istio-injection=enabled --overwrite
echo "✅ Namespace default configurado para inyección de sidecar"

# 6. INSTALAR HERRAMIENTAS DE OBSERVABILIDAD
if [ "$INSTALL_OBSERVABILITY" = true ]; then
    echo ""
    echo "📊 INSTALANDO HERRAMIENTAS DE OBSERVABILIDAD..."
    
    # Usar los addons del directorio de Istio descargado
    cd "$TEMP_DIR/$ISTIO_DIR"
    
    # Instalar addons usando los archivos incluidos
    echo ""
    echo "📈 Instalando Prometheus..."
    kubectl apply -f samples/addons/prometheus.yaml
    
    echo ""
    echo "📊 Instalando Grafana..."
    kubectl apply -f samples/addons/grafana.yaml
    
    echo ""
    echo "🕸️  Instalando Kiali..."
    kubectl apply -f samples/addons/kiali.yaml
    
    echo ""
    echo "🔍 Instalando Jaeger..."
    kubectl apply -f samples/addons/jaeger.yaml
    
    # Volver al directorio original
    cd - > /dev/null
    
    # Esperar que los servicios estén listos
    echo ""
    echo "⏳ Esperando que los servicios de observabilidad estén listos..."
    
    # Esperar un poco antes de verificar
    sleep 30
    
    echo "Verificando Prometheus..."
    kubectl wait --for=condition=available deployment/prometheus -n istio-system --timeout=300s || echo "⚠️  Prometheus tardando en estar listo"
    
    echo "Verificando Grafana..."
    kubectl wait --for=condition=available deployment/grafana -n istio-system --timeout=300s || echo "⚠️  Grafana tardando en estar listo"
    
    echo "Verificando Kiali..."
    kubectl wait --for=condition=available deployment/kiali -n istio-system --timeout=300s || echo "⚠️  Kiali tardando en estar listo"
    
    echo "Verificando Jaeger..."
    kubectl wait --for=condition=available deployment/jaeger -n istio-system --timeout=300s || echo "⚠️  Jaeger tardando en estar listo"
    
    echo "✅ Herramientas de observabilidad instaladas"
fi

# 7. VERIFICAR INSTALACIÓN
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN..."

echo "Estado de Istio:"
"$ISTIOCTL_PATH" verify-install

echo ""
echo "Pods en istio-system:"
kubectl get pods -n istio-system

echo ""
echo "Servicios en istio-system:"
kubectl get svc -n istio-system

# 8. CONFIGURAR ACCESOS
echo ""
echo "🔌 CONFIGURANDO ACCESOS..."

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward.*istio-system" 2>/dev/null || true
sleep 2

# Crear script para port-forwards
cat > /tmp/istio-port-forwards.sh << 'EOF'
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

# Port-forward para Istio Gateway (si existe)
start_port_forward "istio-ingressgateway" "8080" "80"

echo ""
echo "✅ Port-forwards configurados"
echo "PIDs guardados en: /tmp/istio-pf-pids.txt"
EOF

chmod +x /tmp/istio-port-forwards.sh

# Ejecutar port-forwards si las herramientas están instaladas
if [ "$INSTALL_OBSERVABILITY" = true ]; then
    /tmp/istio-port-forwards.sh
    
    # Leer PIDs para mostrar información
    if [ -f "/tmp/istio-pf-pids.txt" ]; then
        PIDS=$(cat /tmp/istio-pf-pids.txt | tr '\n' ' ')
        echo "Port-forwards activos (PIDs: $PIDS)"
    fi
fi

# 9. CREAR SCRIPTS DE GESTIÓN Y COPIAR ISTIOCTL
echo ""
echo "📝 CREANDO SCRIPTS DE GESTIÓN..."

# Copiar istioctl al directorio local para uso futuro
echo "Copiando istioctl al directorio local..."
mkdir -p ./bin
cp "$ISTIOCTL_PATH" ./bin/istioctl
chmod +x ./bin/istioctl

# Script para iniciar port-forwards
cp /tmp/istio-port-forwards.sh ./scripts/start-istio-dashboards.sh

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

# Limpiar directorio temporal
rm -rf "$TEMP_DIR"

# 10. RESUMEN FINAL
echo ""
echo "🎉 ISTIO INSTALADO EXITOSAMENTE"
echo "==============================="
echo ""
echo "✅ Istio Core: Instalado y funcionando"
echo "✅ Sidecar Injection: Habilitado en namespace default"

if [ "$INSTALL_OBSERVABILITY" = true ]; then
    echo "✅ Herramientas de observabilidad: Instaladas"
fi

echo "✅ istioctl: Copiado a ./bin/istioctl"

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
echo "• Ver configuración de proxy: ./bin/istioctl proxy-config cluster <pod-name>"
echo "• Estado de proxies: ./bin/istioctl proxy-status"
echo ""
echo "� GESTMIÓN DE DASHBOARDS:"
echo "• Iniciar dashboards: ./scripts/start-istio-dashboards.sh"
echo "• Detener dashboards: ./scripts/stop-istio-dashboards.sh"
echo ""
echo "🔧 CONFIGURACIÓN:"
echo "• Para habilitar inyección en un namespace: kubectl label namespace <namespace> istio-injection=enabled"
echo "• Para deshabilitar inyección: kubectl label namespace <namespace> istio-injection-"
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Ejecutar aplicaciones en el mesh: ./scripts/00-init-complete-environment.sh"
echo "2. Configurar VirtualServices y DestinationRules"
echo "3. Monitorear tráfico en Kiali"
echo "4. Revisar métricas en Grafana"
echo ""
echo "📚 DOCUMENTACIÓN:"
echo "• Istio Docs: https://istio.io/latest/docs/"
echo "• Observability: https://istio.io/latest/docs/tasks/observability/"