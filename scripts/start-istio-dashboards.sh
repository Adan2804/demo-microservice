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
