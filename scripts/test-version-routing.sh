#!/bin/bash

# Script para probar el enrutamiento por versiones
# Simula el comportamiento de Bancolombia con headers de versión

GATEWAY_URL="http://localhost:8080"
TEST_VERSION=""
REQUEST_COUNT=50
DELAY_MS=100
TEST_HEADERS=true
VERBOSE=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--url)
            GATEWAY_URL="$2"
            shift 2
            ;;
        -v|--version)
            TEST_VERSION="$2"
            shift 2
            ;;
        -c|--count)
            REQUEST_COUNT="$2"
            shift 2
            ;;
        -d|--delay)
            DELAY_MS="$2"
            shift 2
            ;;
        --no-headers)
            TEST_HEADERS=false
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Uso: $0 [OPCIONES]"
            echo ""
            echo "Opciones:"
            echo "  -u, --url URL           Gateway URL (default: http://localhost:8080)"
            echo "  -v, --version VERSION   Versión de prueba"
            echo "  -c, --count COUNT       Número de requests (default: 50)"
            echo "  -d, --delay MS          Delay entre requests en ms (default: 100)"
            echo "  --no-headers           No probar headers de versión"
            echo "  --verbose              Modo verbose"
            echo "  -h, --help             Mostrar ayuda"
            exit 0
            ;;
        *)
            if [ -z "$TEST_VERSION" ]; then
                TEST_VERSION="$1"
            fi
            shift
            ;;
    esac
done

echo "🧪 TEST DE ENRUTAMIENTO POR VERSIONES"
echo "======================================"
echo ""

echo "📋 Configuración de pruebas:"
echo "  • Gateway URL: $GATEWAY_URL"
echo "  • Versión de prueba: $TEST_VERSION"
echo "  • Número de requests: $REQUEST_COUNT"
echo "  • Delay entre requests: ${DELAY_MS}ms"
echo ""

# Contadores
SUCCESS_COUNT=0
ERROR_COUNT=0
declare -A VERSION_COUNTS
declare -A GATEWAY_VERSION_COUNTS
RESPONSE_TIMES=()

echo "🚀 INICIANDO PRUEBAS DE ENRUTAMIENTO..."
echo ""

# PRUEBA 1: Tráfico normal (sin headers especiales)
echo "📡 PRUEBA 1: Tráfico Normal"
echo "============================"

NORMAL_REQUESTS=$((REQUEST_COUNT / 2))

for ((i=1; i<=NORMAL_REQUESTS; i++)); do
    START_TIME=$(date +%s%3N)
    
    RESPONSE=$(curl -s -w "%{http_code}" "$GATEWAY_URL/demo/monetary" 2>/dev/null || echo "000")
    HTTP_CODE="${RESPONSE: -3}"
    
    END_TIME=$(date +%s%3N)
    RESPONSE_TIME=$((END_TIME - START_TIME))
    RESPONSE_TIMES+=($RESPONSE_TIME)
    
    if [ "$HTTP_CODE" = "200" ]; then
        # Extraer headers (simulado - curl no puede extraer headers fácilmente en bash)
        APP_VERSION=$(curl -s -I "$GATEWAY_URL/demo/monetary" 2>/dev/null | grep -i "x-app-version" | cut -d: -f2 | tr -d ' \r\n' || echo "unknown")
        GATEWAY_VERSION=$(curl -s -I "$GATEWAY_URL/demo/monetary" 2>/dev/null | grep -i "x-gateway-version" | cut -d: -f2 | tr -d ' \r\n' || echo "unknown")
        
        # Contar versiones
        if [ -n "$APP_VERSION" ] && [ "$APP_VERSION" != "unknown" ]; then
            VERSION_COUNTS["$APP_VERSION"]=$((${VERSION_COUNTS["$APP_VERSION"]:-0} + 1))
        fi
        
        if [ -n "$GATEWAY_VERSION" ] && [ "$GATEWAY_VERSION" != "unknown" ]; then
            GATEWAY_VERSION_COUNTS["$GATEWAY_VERSION"]=$((${GATEWAY_VERSION_COUNTS["$GATEWAY_VERSION"]:-0} + 1))
        fi
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        
        if [ "$VERBOSE" = true ]; then
            echo "✅ Request $i - App: $APP_VERSION, Gateway: $GATEWAY_VERSION - ${RESPONSE_TIME}ms"
        else
            if [ $((i % 10)) -eq 0 ]; then
                echo "📈 Progreso normal: $i/$NORMAL_REQUESTS - Última versión: $APP_VERSION"
            fi
        fi
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        if [ "$VERBOSE" = true ]; then
            echo "❌ Request $i - HTTP Code: $HTTP_CODE"
        fi
    fi
    
    if [ "$DELAY_MS" -gt 0 ]; then
        sleep $(echo "scale=3; $DELAY_MS/1000" | bc -l 2>/dev/null || sleep 0.1)
    fi
done

# PRUEBA 2: Tráfico con headers de versión (si está habilitado)
if [ "$TEST_HEADERS" = true ]; then
    echo ""
    echo "📡 PRUEBA 2: Tráfico con Headers de Versión"
    echo "==========================================="
    
    # Pruebas con diferentes headers
    HEADER_TESTS=("app-version:1.0.0" "app-version:1.1.0" "staging:true")
    
    for header_test in "${HEADER_TESTS[@]}"; do
        IFS=':' read -r header_name header_value <<< "$header_test"
        echo "🔍 Probando header: $header_name = $header_value"
        
        for ((i=1; i<=10; i++)); do
            RESPONSE=$(curl -s -w "%{http_code}" -H "$header_name: $header_value" "$GATEWAY_URL/demo/monetary" 2>/dev/null || echo "000")
            HTTP_CODE="${RESPONSE: -3}"
            
            if [ "$HTTP_CODE" = "200" ]; then
                APP_VERSION=$(curl -s -I -H "$header_name: $header_value" "$GATEWAY_URL/demo/monetary" 2>/dev/null | grep -i "x-app-version" | cut -d: -f2 | tr -d ' \r\n' || echo "unknown")
                
                if [ "$VERBOSE" = true ]; then
                    echo "  ✅ Header test $i - App: $APP_VERSION"
                fi
                
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                ERROR_COUNT=$((ERROR_COUNT + 1))
                if [ "$VERBOSE" = true ]; then
                    echo "  ❌ Header test $i - HTTP Code: $HTTP_CODE"
                fi
            fi
        done
    done
fi

# ANÁLISIS DE RESULTADOS
echo ""
echo "📊 ANÁLISIS DE RESULTADOS"
echo "========================="
echo ""

TOTAL_REQUESTS=$((NORMAL_REQUESTS + 30))
SUCCESS_RATE=$(echo "scale=2; $SUCCESS_COUNT * 100 / $TOTAL_REQUESTS" | bc -l 2>/dev/null || echo "0")

# Estadísticas generales
echo "📈 Estadísticas Generales:"
echo "  • Total de requests: $TOTAL_REQUESTS"
echo "  • Requests exitosos: $SUCCESS_COUNT"
echo "  • Requests fallidos: $ERROR_COUNT"
echo "  • Tasa de éxito: ${SUCCESS_RATE}%"

# Distribución de versiones de aplicación
if [ ${#VERSION_COUNTS[@]} -gt 0 ]; then
    echo ""
    echo "🏷️  Distribución de Versiones de Aplicación:"
    for version in "${!VERSION_COUNTS[@]}"; do
        count=${VERSION_COUNTS[$version]}
        percentage=$(echo "scale=2; $count * 100 / $SUCCESS_COUNT" | bc -l 2>/dev/null || echo "0")
        echo "  • $version : $count requests (${percentage}%)"
    done
fi

# Distribución de versiones de gateway
if [ ${#GATEWAY_VERSION_COUNTS[@]} -gt 0 ]; then
    echo ""
    echo "🌐 Distribución de Versiones de Gateway:"
    for version in "${!GATEWAY_VERSION_COUNTS[@]}"; do
        count=${GATEWAY_VERSION_COUNTS[$version]}
        percentage=$(echo "scale=2; $count * 100 / $SUCCESS_COUNT" | bc -l 2>/dev/null || echo "0")
        echo "  • $version : $count requests (${percentage}%)"
    done
fi

# Estadísticas de tiempo de respuesta
if [ ${#RESPONSE_TIMES[@]} -gt 0 ]; then
    # Calcular promedio (simple)
    total_time=0
    min_time=${RESPONSE_TIMES[0]}
    max_time=${RESPONSE_TIMES[0]}
    
    for time in "${RESPONSE_TIMES[@]}"; do
        total_time=$((total_time + time))
        if [ "$time" -lt "$min_time" ]; then
            min_time=$time
        fi
        if [ "$time" -gt "$max_time" ]; then
            max_time=$time
        fi
    done
    
    avg_time=$(echo "scale=2; $total_time / ${#RESPONSE_TIMES[@]}" | bc -l 2>/dev/null || echo "0")
    
    echo ""
    echo "⏱️  Tiempos de Respuesta:"
    echo "  • Promedio: ${avg_time}ms"
    echo "  • Mínimo: ${min_time}ms"
    echo "  • Máximo: ${max_time}ms"
fi

# Validaciones del patrón Bancolombia
echo ""
echo "✅ VALIDACIONES DEL PATRÓN BANCOLOMBIA:"

if [ ${#VERSION_COUNTS[@]} -eq 1 ]; then
    single_version=$(echo "${!VERSION_COUNTS[@]}" | head -n1)
    echo "  • ✅ Consistencia de versión: Todas las respuestas tienen la misma versión ($single_version)"
elif [ ${#VERSION_COUNTS[@]} -gt 1 ]; then
    echo "  • ⚠️  Múltiples versiones detectadas - Posible transición de versión"
    echo "    Esto es normal durante deployments con ArgoCD"
else
    echo "  • ❌ No se detectaron versiones en los headers"
fi

SUCCESS_RATE_INT=$(echo "$SUCCESS_RATE" | cut -d. -f1)
if [ "$SUCCESS_RATE_INT" -ge 95 ]; then
    echo "  • ✅ Alta disponibilidad: ${SUCCESS_RATE}% de requests exitosos"
elif [ "$SUCCESS_RATE_INT" -ge 80 ]; then
    echo "  • ⚠️  Disponibilidad aceptable: ${SUCCESS_RATE}%"
else
    echo "  • ❌ Baja disponibilidad: ${SUCCESS_RATE}% - Revisar configuración"
fi

# Verificar que el gateway está funcionando
if [ ${#GATEWAY_VERSION_COUNTS[@]} -gt 0 ]; then
    echo "  • ✅ Gateway funcionando: Headers de versión presentes"
else
    echo "  • ❌ Gateway no funcionando: No se detectaron headers de gateway"
fi

echo ""
echo "🎉 Pruebas de enrutamiento completadas"

echo ""
echo "💡 Comandos útiles para debugging:"
echo "  # Ver pods por versión:"
echo "  kubectl get pods -n demo-app -l version=$TEST_VERSION"
echo "  # Ver services versionados:"
echo "  kubectl get svc -n demo-app -l version=$TEST_VERSION"
echo "  # Ver logs del gateway:"
echo "  kubectl logs -n demo-app -l app=security-filters -f"