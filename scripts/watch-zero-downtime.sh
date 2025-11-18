#!/bin/bash

# Script para monitorear en tiempo real el rolling update con MÁXIMO DETALLE
# Muestra cada cambio de estado de los pods
set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

DEPLOYMENT_NAME="demo-microservice-keda"
NAMESPACE="default"

echo -e "${CYAN}  MONITOR DE ZERO DOWNTIME EN TIEMPO REAL                      ${NC}"

echo ""
echo -e "${YELLOW}INSTRUCCIONES:${NC}"
echo "1. Este script monitoreará los pods en tiempo real"
echo "2. En otra terminal, ejecuta el cambio de imagen:"
echo -e "   ${GREEN}kubectl set image deployment/$DEPLOYMENT_NAME demo-microservice=zadan04/demo-microservice:stable${NC}"
echo "3. O haz un sync desde ArgoCD UI"
echo ""
echo -e "${YELLOW}Presiona ENTER para iniciar el monitoreo...${NC}"
read

# Función para obtener info detallada de pods
get_pod_details() {
    kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
READY:.status.conditions[?\(@.type==\"Ready\"\)].status,\
CONTAINER_READY:.status.containerStatuses[0].ready,\
RESTARTS:.status.containerStatuses[0].restartCount,\
IMAGE:.spec.containers[0].image,\
NODE:.spec.nodeName,\
AGE:.metadata.creationTimestamp \
--no-headers 2>/dev/null | while read line; do
        echo "$line"
    done
}

# Función para contar pods por estado
count_pods_by_status() {
    local status=$1
    kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME --field-selector=status.phase=$status --no-headers 2>/dev/null | wc -l
}

# Variables para tracking
declare -A previous_pods
min_running=999
had_zero_downtime=true
start_time=$(date +%s)

echo ""
echo -e "${GREEN}[OK] MONITOREO INICIADO - Esperando cambios...${NC}"
echo ""

# Loop de monitoreo
iteration=0
while true; do
    clear
    iteration=$((iteration + 1))
    current_time=$(date '+%H:%M:%S')
    elapsed=$(($(date +%s) - start_time))
    

    echo -e "${CYAN}  MONITOR DE ZERO DOWNTIME - Iteración #$iteration${NC}"
    echo -e "${CYAN}  Tiempo: $current_time | Transcurrido: ${elapsed}s${NC}"

    
    # Contar pods por estado
    running=$(count_pods_by_status "Running")
    pending=$(count_pods_by_status "Pending")
    terminating=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME --no-headers 2>/dev/null | grep -c "Terminating" || echo "0")
    total=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME --no-headers 2>/dev/null | wc -l)
    
    # Actualizar mínimo
    if [ "$running" -lt "$min_running" ]; then
        min_running=$running
    fi
    
    # Verificar zero downtime
    if [ "$running" -eq 0 ]; then
        had_zero_downtime=false
    fi
    
    # Mostrar resumen
    echo ""
    echo -e "${YELLOW}RESUMEN DE PODS:${NC}"

    
    if [ "$running" -eq 0 ]; then
        echo -e "│ ${RED}[!] Running:     $running${NC} ${RED}<- DOWNTIME DETECTADO!${NC}"
    else
        echo -e "│ ${GREEN}[OK] Running:     $running${NC}"
    fi
    
    echo -e "│ ${YELLOW}[WAIT] Pending:     $pending${NC}"
    echo -e "│ ${MAGENTA}[TERM] Terminating: $terminating${NC}"
    echo -e "│ ${BLUE}[INFO] Total:       $total${NC}"
    echo -e "│ ${CYAN}[MIN]  Mínimo:      $min_running${NC}"
    
    # Obtener detalles de pods
    echo ""
    echo -e "${YELLOW}DETALLE DE PODS:${NC}"

    printf "│ %-35s │ %-10s │ %-5s │ %-8s │ %-20s │\n" "NOMBRE" "STATUS" "READY" "RESTARTS" "IMAGEN"

    
    declare -A current_pods
    
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            name=$(echo "$line" | awk '{print $1}')
            status=$(echo "$line" | awk '{print $2}')
            ready=$(echo "$line" | awk '{print $3}')
            container_ready=$(echo "$line" | awk '{print $4}')
            restarts=$(echo "$line" | awk '{print $5}')
            image=$(echo "$line" | awk '{print $6}' | sed 's/.*://')
            
            current_pods[$name]="$status"
            
            # Detectar si es nuevo o cambió
            is_new=""
            if [ -z "${previous_pods[$name]}" ]; then
                is_new="${GREEN}[NEW]${NC}"
            elif [ "${previous_pods[$name]}" != "$status" ]; then
                is_new="${YELLOW}[CHG]${NC}"
            fi
            
            # Colorear según estado
            if [ "$status" = "Running" ] && [ "$ready" = "True" ]; then
                status_color="${GREEN}$status${NC}"
                ready_color="${GREEN}$ready${NC}"
            elif [ "$status" = "Running" ]; then
                status_color="${YELLOW}$status${NC}"
                ready_color="${YELLOW}$ready${NC}"
            elif [ "$status" = "Pending" ]; then
                status_color="${YELLOW}$status${NC}"
                ready_color="${YELLOW}$ready${NC}"
            elif [ "$status" = "Terminating" ]; then
                status_color="${MAGENTA}$status${NC}"
                ready_color="${MAGENTA}$ready${NC}"
            else
                status_color="${RED}$status${NC}"
                ready_color="${RED}$ready${NC}"
            fi
            
            # Acortar nombre para display
            short_name=$(echo "$name" | sed 's/demo-microservice-keda-//')
            
            printf "│ %-35s │ %-10s │ %-5s │ %-8s │ %-20s │ %s\n" \
                "$short_name" \
                "$(echo -e $status_color)" \
                "$(echo -e $ready_color)" \
                "$restarts" \
                "$image" \
                "$(echo -e $is_new)"
        fi
    done < <(get_pod_details)
    
    # Detectar pods eliminados
    for pod in "${!previous_pods[@]}"; do
        if [ -z "${current_pods[$pod]}" ]; then
            short_name=$(echo "$pod" | sed 's/demo-microservice-keda-//')
            echo -e "${RED}[DEL] Pod eliminado: $short_name${NC}"
        fi
    done
    
    # Actualizar previous_pods
    previous_pods=()
    for pod in "${!current_pods[@]}"; do
        previous_pods[$pod]="${current_pods[$pod]}"
    done
    
    # Mostrar eventos recientes
    echo ""
    echo -e "${YELLOW}EVENTOS RECIENTES (últimos 5):${NC}"

    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' 2>/dev/null | \
        grep "$DEPLOYMENT_NAME" | tail -5 | \
        awk '{printf "│ %-98s │\n", substr($0, 1, 98)}'

    
    # Mostrar estado del deployment
    echo ""
    echo -e "${YELLOW}ESTADO DEL DEPLOYMENT:${NC}"

    kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o custom-columns=\
DESIRED:.spec.replicas,\
CURRENT:.status.replicas,\
UP-TO-DATE:.status.updatedReplicas,\
AVAILABLE:.status.availableReplicas,\
READY:.status.readyReplicas \
--no-headers 2>/dev/null | \
        awk '{printf "│ Desired: %-3s │ Current: %-3s │ Updated: %-3s │ Available: %-3s │ Ready: %-3s │\n", $1, $2, $3, $4, $5}'

    
    # Probar conectividad a la API
    echo ""
    echo -e "${YELLOW}PRUEBA DE CONECTIVIDAD API:${NC}"

    
    API_URL="http://127.0.0.1:34023/demo/info"
    API_RESPONSE=$(curl -s -w "\n%{http_code}" --connect-timeout 2 --max-time 3 "$API_URL" 2>/dev/null)
    HTTP_CODE=$(echo "$API_RESPONSE" | tail -n1)
    API_BODY=$(echo "$API_RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        # Extraer versión de la respuesta JSON
        VERSION=$(echo "$API_BODY" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "unknown")
        echo -e "│ ${GREEN}[OK] API Responde: HTTP $HTTP_CODE${NC}"
        echo -e "│ ${GREEN}     Versión: $VERSION${NC}"
        
        # Mostrar respuesta completa (primera línea)
        FIRST_LINE=$(echo "$API_BODY" | head -c 90)
        echo -e "│ ${CYAN}     Response: $FIRST_LINE...${NC}"
    elif [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
        echo -e "│ ${RED}[ERROR] API No Responde: Connection refused o timeout${NC}"
        echo -e "│ ${YELLOW}        Posible downtime detectado en la API${NC}"
    else
        echo -e "│ ${YELLOW}[WARN] API Responde: HTTP $HTTP_CODE (no 200)${NC}"
    fi
    
    
    # Resultado final
    echo ""
    if [ "$had_zero_downtime" = true ]; then
        echo -e "${GREEN}[OK] ZERO DOWNTIME: SI - Nunca hubo 0 pods running${NC}"
    else
        echo -e "${RED}[FAIL] ZERO DOWNTIME: NO - Se detectó 0 pods running${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Presiona Ctrl+C para detener el monitoreo${NC}"
    echo -e "${CYAN}API URL: $API_URL${NC}"
    
    sleep 2
done
