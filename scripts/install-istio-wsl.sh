#!/bin/bash

# Script para instalar Istio en WSL/Linux
# Descarga e instala la última versión estable de Istio
set -e

echo "🕸️  INSTALACIÓN DE ISTIO SERVICE MESH"
echo "====================================="

cd "$(dirname "$0")/.."

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [OPCIONES]"
    echo ""
    echo "Opciones:"
    echo "  -v, --version VERSION   Versión específica de Istio (default: latest)"
    echo "  --local-only           Instalar solo localmente (no en PATH)"
    echo "  --with-addons          Instalar addons (Kiali, Grafana, Jaeger)"
    echo "  -h, --help             Mostrar esta ayuda"
    echo ""
    echo "Ejemplos:"
    echo "  $0                     # Instalar última versión"
    echo "  $0 -v 1.20.1           # Instalar versión específica"
    echo "  $0 --with-addons       # Instalar con addons de monitoreo"
}

# Valores por defecto
ISTIO_VERSION=""
LOCAL_ONLY=false
WITH_ADDONS=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            ISTIO_VERSION="$2"
            shift 2
            ;;
        --local-only)
            LOCAL_ONLY=true
            shift
            ;;
        --with-addons)
            WITH_ADDONS=true
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

# 1. VERIFICAR DEPENDENCIAS
echo ""
echo "📋 VERIFICANDO DEPENDENCIAS..."

if ! command -v curl >/dev/null 2>&1; then
    echo "❌ curl no está instalado"
    echo "Instala con: sudo apt update && sudo apt install curl"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl no está instalado"
    echo "Instala kubectl primero"
    exit 1
fi

# Verificar conexión a cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ No hay conexión a un cluster de Kubernetes"
    echo "Inicia minikube primero: minikube start"
    exit 1
fi

echo "✅ Dependencias verificadas"

# 2. DETERMINAR VERSIÓN DE ISTIO
echo ""
echo "🔍 DETERMINANDO VERSIÓN DE ISTIO..."

if [ -z "$ISTIO_VERSION" ]; then
    echo "Obteniendo última versión de Istio..."
    ISTIO_VERSION=$(curl -s https://api.github.com/repos/istio/istio/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    echo "📦 Última versión disponible: $ISTIO_VERSION"
else
    echo "📦 Versión especificada: $ISTIO_VERSION"
fi

# 3. DESCARGAR ISTIO
echo ""
echo "⬇️  DESCARGANDO ISTIO $ISTIO_VERSION..."

# Crear directorio temporal
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Descargar Istio
echo "Descargando desde GitHub..."
ISTIO_URL="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz"

if ! curl -L "$ISTIO_URL" -o "istio-${ISTIO_VERSION}-linux-amd64.tar.gz"; then
    echo "❌ Error al descargar Istio"
    echo "Verifica que la versión $ISTIO_VERSION existe"
    exit 1
fi

# Extraer archivo
echo "Extrayendo archivo..."
tar -xzf "istio-${ISTIO_VERSION}-linux-amd64.tar.gz"

echo "✅ Istio descargado exitosamente"

# 4. INSTALAR ISTIOCTL
echo ""
echo "📦 INSTALANDO ISTIOCTL..."

# Volver al directorio del proyecto
cd "$(dirname "$0")/.."

# Crear directorio bin si no existe
mkdir -p bin

# Copiar istioctl al directorio local
cp "$TEMP_DIR/istio-${ISTIO_VERSION}/bin/istioctl" ./bin/istioctl
chmod +x ./bin/istioctl

echo "✅ istioctl instalado en ./bin/istioctl"

# Instalar en PATH del sistema (si no es local-only)
if [ "$LOCAL_ONLY" = false ]; then
    if [ -w "/usr/local/bin" ] || sudo -n true 2>/dev/null; then
        echo "Instalando istioctl en el sistema..."
        sudo cp ./bin/istioctl /usr/local/bin/istioctl
        echo "✅ istioctl instalado en /usr/local/bin"
    else
        echo "⚠️  No se pudo instalar en el sistema (permisos insuficientes)"
        echo "Usando instalación local: ./bin/istioctl"
    fi
fi

# 5. VERIFICAR INSTALACIÓN
echo ""
echo "🔍 VERIFICANDO INSTALACIÓN..."

# Verificar versión
ISTIOCTL_PATH="./bin/istioctl"
if command -v istioctl >/dev/null 2>&1; then
    ISTIOCTL_PATH="istioctl"
fi

echo "Versión instalada:"
"$ISTIOCTL_PATH" version --client

echo "✅ Instalación verificada"

# 6. INSTALAR ISTIO EN EL CLUSTER
echo ""
echo "🚀 INSTALANDO ISTIO EN EL CLUSTER..."

# Verificar si Istio ya está instalado
if kubectl get namespace istio-system >/dev/null 2>&1; then
    echo "⚠️  Istio ya está instalado en el cluster"
    read -p "¿Reinstalar Istio? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Desinstalando Istio anterior..."
        "$ISTIOCTL_PATH" uninstall --purge -y || true
        kubectl delete namespace istio-system --ignore-not-found=true
        sleep 10
    else
        echo "⏭️  Manteniendo instalación existente"
    fi
fi

# Instalar Istio con configuración demo
echo "Instalando Istio con perfil demo..."
"$ISTIOCTL_PATH" install --set values.defaultRevision=default -y

# Habilitar inyección automática de sidecar en namespace default
echo "Habilitando inyección automática de sidecar..."
kubectl label namespace default istio-injection=enabled --overwrite

echo "✅ Istio instalado en el cluster"

# 7. INSTALAR ADDONS (si se especifica)
if [ "$WITH_ADDONS" = true ]; then
    echo ""
    echo "🔧 INSTALANDO ADDONS DE MONITOREO..."
    
    # Descargar manifiestos de addons
    ADDONS_DIR="$TEMP_DIR/istio-${ISTIO_VERSION}/samples/addons"
    
    echo "Instalando Kiali (Service Mesh Dashboard)..."
    kubectl apply -f "$ADDONS_DIR/kiali.yaml"
    
    echo "Instalando Grafana (Métricas)..."
    kubectl apply -f "$ADDONS_DIR/grafana.yaml"
    
    echo "Instalando Jaeger (Tracing)..."
    kubectl apply -f "$ADDONS_DIR/jaeger.yaml"
    
    echo "Instalando Prometheus (Métricas)..."
    kubectl apply -f "$ADDONS_DIR/prometheus.yaml"
    
    echo "Esperando que los addons estén listos..."
    sleep 30
    
    # Verificar que los addons estén funcionando
    echo "Verificando estado de los addons..."
    kubectl get pods -n istio-system
    
    echo "✅ Addons instalados"
fi

# 8. VERIFICAR ESTADO DEL CLUSTER
echo ""
echo "🔍 VERIFICANDO ESTADO DEL CLUSTER..."

echo "Pods de Istio:"
kubectl get pods -n istio-system

echo ""
echo "Servicios de Istio:"
kubectl get svc -n istio-system

echo ""
echo "Análisis de configuración:"
"$ISTIOCTL_PATH" analyze

# 9. CREAR SCRIPTS DE GESTIÓN
echo ""
echo "📝 CREANDO SCRIPTS DE GESTIÓN..."

# Script para iniciar dashboards
cat > ./scripts/start-istio-dashboards.sh << 'EOF'
#!/bin/bash
echo "🚀 Iniciando dashboards de Istio..."

# Detectar istioctl
ISTIOCTL_PATH=""
if [ -f "./bin/istioctl" ]; then
    ISTIOCTL_PATH="./bin/istioctl"
elif command -v istioctl >/dev/null 2>&1; then
    ISTIOCTL_PATH="istioctl"
else
    echo "❌ istioctl no encontrado"
    exit 1
fi

# Limpiar port-forwards existentes
pkill -f "kubectl port-forward.*istio-system" 2>/dev/null || true
sleep 2

echo "Iniciando Kiali Dashboard..."
kubectl port-forward -n istio-system svc/kiali 20001:20001 > /dev/null 2>&1 &
KIALI_PID=$!

echo "Iniciando Grafana Dashboard..."
kubectl port-forward -n istio-system svc/grafana 3000:3000 > /dev/null 2>&1 &
GRAFANA_PID=$!

echo "Iniciando Jaeger Dashboard..."
kubectl port-forward -n istio-system svc/jaeger 16686:16686 > /dev/null 2>&1 &
JAEGER_PID=$!

sleep 5

echo ""
echo "✅ Dashboards iniciados:"
echo "• Kiali (Service Mesh): http://localhost:20001"
echo "• Grafana (Métricas): http://localhost:3000"
echo "• Jaeger (Tracing): http://localhost:16686"
echo ""
echo "PIDs: Kiali=$KIALI_PID, Grafana=$GRAFANA_PID, Jaeger=$JAEGER_PID"
echo "Para detener: pkill -f 'kubectl port-forward.*istio-system'"
EOF

chmod +x ./scripts/start-istio-dashboards.sh

# Script para detener dashboards
cat > ./scripts/stop-istio-dashboards.sh << 'EOF'
#!/bin/bash
echo "🛑 Deteniendo dashboards de Istio..."

# Detener port-forwards
pkill -f "kubectl port-forward.*istio-system" 2>/dev/null || true

echo "✅ Dashboards detenidos"
EOF

chmod +x ./scripts/stop-istio-dashboards.sh

# 10. LIMPIAR ARCHIVOS TEMPORALES
echo ""
echo "🧹 LIMPIANDO ARCHIVOS TEMPORALES..."

rm -rf "$TEMP_DIR"

echo "✅ Archivos temporales eliminados"

# 11. RESUMEN FINAL
echo ""
echo "🎉 INSTALACIÓN DE ISTIO COMPLETADA"
echo "=================================="
echo ""
echo "✅ Istio $ISTIO_VERSION instalado"
echo "✅ istioctl disponible en ./bin/istioctl"
if [ "$LOCAL_ONLY" = false ] && command -v istioctl >/dev/null 2>&1; then
    echo "✅ istioctl disponible en el sistema"
fi
echo "✅ Istio instalado en el cluster"
echo "✅ Inyección automática habilitada en namespace default"
if [ "$WITH_ADDONS" = true ]; then
    echo "✅ Addons de monitoreo instalados"
fi
echo ""
echo "🌐 COMPONENTES INSTALADOS:"
echo "• Istio Control Plane (istiod)"
echo "• Istio Ingress Gateway"
if [ "$WITH_ADDONS" = true ]; then
    echo "• Kiali (Service Mesh Dashboard)"
    echo "• Grafana (Métricas)"
    echo "• Jaeger (Distributed Tracing)"
    echo "• Prometheus (Métricas)"
fi
echo ""
echo "🛠️  COMANDOS ÚTILES:"
echo "• Verificar instalación: $ISTIOCTL_PATH version"
echo "• Analizar configuración: $ISTIOCTL_PATH analyze"
echo "• Estado de proxies: $ISTIOCTL_PATH proxy-status"
if [ "$WITH_ADDONS" = true ]; then
    echo "• Iniciar dashboards: ./scripts/start-istio-dashboards.sh"
    echo "• Detener dashboards: ./scripts/stop-istio-dashboards.sh"
fi
echo ""
echo "📁 ARCHIVOS CREADOS:"
echo "• bin/istioctl - Cliente de Istio"
if [ "$WITH_ADDONS" = true ]; then
    echo "• scripts/start-istio-dashboards.sh - Iniciar dashboards"
    echo "• scripts/stop-istio-dashboards.sh - Detener dashboards"
fi
echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "1. Inicializar entorno: ./scripts/00-init-complete-environment.sh"
echo "2. Crear experimento: ./scripts/01-create-experiment.sh"
echo "3. Configurar ArgoCD: ./scripts/03-setup-argocd.sh"
echo ""
echo "💡 NOTA:"
echo "Istio está listo para usar con tu aplicación de microservicios."
echo "La inyección automática de sidecar está habilitada en el namespace default."