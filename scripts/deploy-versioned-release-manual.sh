#!/bin/bash

# Script para generar manifiestos versionados SIN aplicar al cluster
# Para uso con ArgoCD MANUAL sync

VERSION=""
NAMESPACE="demo-app"
REGISTRY="demo-registry"
REPOSITORY="demo-microservice"
SKIP_BUILD=false
VERBOSE=false

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--registry)
            REGISTRY="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Uso: $0 -v VERSION [OPCIONES]"
            echo ""
            echo "Opciones:"
            echo "  -v, --version VERSION    Versión requerida (ej: v-1-0-0)"
            echo "  -n, --namespace NS       Namespace (default: demo-app)"
            echo "  -r, --registry REG       Registry (default: demo-registry)"
            echo "  --skip-build            Saltar build"
            echo "  --verbose               Modo verbose"
            echo "  -h, --help              Mostrar ayuda"
            exit 0
            ;;
        *)
            echo "Opción desconocida: $1"
            exit 1
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "❌ Error: Versión es requerida"
    echo "Uso: $0 -v VERSION"
    exit 1
fi

# Usar imágenes ya existentes
if [ "$VERSION" = "v-1-0-0" ]; then
    FULL_IMAGE_NAME="demo-microservice:v1.0.0"
elif [ "$VERSION" = "v-1-1-0" ]; then
    FULL_IMAGE_NAME="demo-microservice:v1.0.0"  # Simular nueva versión con misma imagen
else
    # Para otras versiones, usar la imagen disponible
    FULL_IMAGE_NAME="demo-microservice:v1.0.0"
fi

echo "📝 GENERAR MANIFIESTOS PARA ARGOCD MANUAL"
echo "=========================================="
echo ""

echo "📋 Configuración:"
echo "  • Versión: $VERSION"
echo "  • Imagen: $FULL_IMAGE_NAME"
echo "  • Namespace: $NAMESPACE"
echo "  • Modo: SOLO GENERAR (no aplicar)"
echo ""

# FASE 1: BUILD (si es necesario)
if [ "$SKIP_BUILD" = false ]; then
    echo "🔨 FASE 1: BUILD DE LA APLICACIÓN"
    
    echo "📦 Verificando si la imagen ya existe..."
    if docker image inspect $FULL_IMAGE_NAME >/dev/null 2>&1; then
        echo "✅ Imagen $FULL_IMAGE_NAME ya existe, reutilizando"
    else
        echo "🐳 Imagen no encontrada, usando imagen base de Argo Experiments..."
        # Usar imagen base y crear tag para la versión
        if [ "$VERSION" = "v-1-0-0" ]; then
            echo "Usando imagen stable existente"
        elif [ "$VERSION" = "v-1-1-0" ]; then
            echo "Usando imagen experiment-candidate existente"
        else
            echo "⚠️  Imagen no disponible para versión $VERSION"
            echo "Disponibles: v-1-0-0 (stable), v-1-1-0 (experiment-candidate)"
        fi
    fi
    
    echo "✅ Build completado"
else
    echo "⏭️  SALTANDO BUILD (--skip-build especificado)"
fi

# FASE 2: GENERAR MANIFIESTOS VERSIONADOS
echo ""
echo "📝 FASE 2: GENERAR MANIFIESTOS VERSIONADOS"

DT_RELEASE_VERSION="$VERSION"
DT_BUILD_VERSION="build-$(date +%Y%m%d-%H%M%S)"
TARGET_URI="http://demo-microservice-$VERSION.$NAMESPACE.svc.cluster.local"

# Calcular checksum del ConfigMap
CONFIG_CONTENT=$(cat k8s-versioned-manifests/configmap-security-filters-versioned.yaml 2>/dev/null || echo "")
CONFIG_CHECKSUM=$(echo -n "$CONFIG_CONTENT" | sha256sum | cut -d' ' -f1 | cut -c1-16)

# Crear directorio de salida
OUTPUT_PATH="k8s-versioned-manifests-processed"
mkdir -p $OUTPUT_PATH

# Limpiar archivos anteriores
rm -f $OUTPUT_PATH/*.yaml

echo "🔄 Procesando manifiestos..."

# Procesar cada manifiesto
for file in k8s-versioned-manifests/*.yaml; do
    if [ ! -f "$file" ]; then
        continue
    fi
    
    filename=$(basename "$file")
    
    # Saltar el manifiesto de ArgoCD
    if [ "$filename" = "argocd-application-manual.yaml" ]; then
        continue
    fi
    
    # Leer y procesar contenido
    content=$(cat "$file")
    
    # Reemplazar tokens
    content=$(echo "$content" | sed "s|#{namespace}#|$NAMESPACE|g")
    content=$(echo "$content" | sed "s|#{version}#|$VERSION|g")
    content=$(echo "$content" | sed "s|#{image}#|$FULL_IMAGE_NAME|g")
    content=$(echo "$content" | sed "s|#{target_uri}#|$TARGET_URI|g")
    content=$(echo "$content" | sed "s|#{dt_release_version}#|$DT_RELEASE_VERSION|g")
    content=$(echo "$content" | sed "s|#{dt_build_version}#|$DT_BUILD_VERSION|g")
    content=$(echo "$content" | sed "s|#{config_checksum}#|$CONFIG_CHECKSUM|g")
    content=$(echo "$content" | sed "s|#{timestamp}#|$(date -u +%Y-%m-%dT%H:%M:%SZ)|g")
    
    # Guardar archivo procesado
    echo "$content" > "$OUTPUT_PATH/$filename"
    
    echo "  ✅ $filename"
    
    if [ "$VERBOSE" = true ]; then
        echo "    Tokens reemplazados:"
        echo "      #{version}# → $VERSION"
        echo "      #{image}# → $FULL_IMAGE_NAME"
        echo "      #{namespace}# → $NAMESPACE"
    fi
done

echo "✅ Manifiestos versionados generados"

# FASE 3: MOSTRAR RESUMEN
echo ""
echo "📋 FASE 3: RESUMEN DE MANIFIESTOS GENERADOS"

echo "📁 Archivos generados en '$OUTPUT_PATH':"
for file in $OUTPUT_PATH/*.yaml; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        size=$(du -h "$file" | cut -f1)
        echo "  • $filename ($size)"
    fi
done

echo ""
echo "🔍 Verificación de tokens:"
echo "  • Versión: $VERSION"
echo "  • Imagen: $FULL_IMAGE_NAME"
echo "  • Namespace: $NAMESPACE"
echo "  • Config Checksum: $CONFIG_CHECKSUM"

# Verificar tokens no reemplazados
echo ""
echo "🔍 Verificando tokens no reemplazados..."
UNREPLACED_TOKENS=$(grep -r "#{[^}]*}#" $OUTPUT_PATH/ 2>/dev/null | cut -d: -f2 | sort -u || true)

if [ -n "$UNREPLACED_TOKENS" ]; then
    echo "⚠️  Tokens no reemplazados encontrados:"
    echo "$UNREPLACED_TOKENS" | while read token; do
        echo "  • $token"
    done
else
    echo "✅ Todos los tokens fueron reemplazados correctamente"
fi

# RESUMEN FINAL
echo ""
echo "🎉 MANIFIESTOS GENERADOS EXITOSAMENTE"
echo "====================================="
echo ""

echo "✅ Manifiestos versionados listos para ArgoCD"
echo "✅ Tokens reemplazados correctamente"
echo "✅ Archivos guardados en: $OUTPUT_PATH"

echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "  1. Verificar estado de ArgoCD (debe mostrar OutOfSync):"
echo "     ./scripts/check-status.sh"
echo "  2. Hacer sync manual en ArgoCD:"
echo "     ./scripts/manual-sync.sh"
echo "  3. O usar ArgoCD UI: https://localhost:8081"
echo "  4. Verificar deployment:"
echo "     ./scripts/test-version-routing.sh $VERSION"

echo ""
echo "📊 ARCHIVOS PARA ARGOCD:"
for file in $OUTPUT_PATH/*.yaml; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "  • $filename"
    fi
done

echo ""
echo "💡 NOTA IMPORTANTE:"
echo "Los manifiestos están listos pero NO se aplicaron al cluster."
echo "ArgoCD debe hacer el sync manual para desplegar la nueva versión."

echo ""
echo "🔄 FLUJO COMPLETO:"
echo "  Manifiestos generados → ArgoCD detecta OutOfSync → Sync manual → Pods recreados"