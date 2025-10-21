#!/bin/bash

# Script para cambiar la versión del deployment y simular rollout
# Simula el cambio de producción a experimento

CURRENT_VERSION=""
NEW_VERSION=""
MODE=""

# Función para mostrar ayuda
show_help() {
    echo "Uso: $0 [production|experiment]"
    echo ""
    echo "Modos:"
    echo "  production   - Cambiar a versión de producción estable"
    echo "  experiment   - Cambiar a versión experimental"
    echo ""
    echo "Ejemplos:"
    echo "  $0 production    # Cambiar a producción estable"
    echo "  $0 experiment    # Cambiar a versión experimental"
}

# Procesar argumentos
case $1 in
    production)
        MODE="production"
        NEW_VERSION="production-stable-istio-v1.0.0"
        IMAGE="demo-microservice:v1.0.0"
        DEPLOYMENT_VERSION="v1.0.0"
        NEW_FEATURE="false"
        EXPERIMENT_ENABLED="false"
        ;;
    experiment)
        MODE="experiment"
        NEW_VERSION="production-stable-istio-v1.1.0"
        IMAGE="demo-microservice:v1.0.0"  # Misma imagen pero diferentes variables
        DEPLOYMENT_VERSION="v1.1.0"
        NEW_FEATURE="true"
        EXPERIMENT_ENABLED="true"
        ;;
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        echo "❌ Modo no válido: $1"
        show_help
        exit 1
        ;;
esac

echo "🔄 CAMBIO DE VERSIÓN - MODO: $MODE"
echo "=================================="
echo ""

echo "📋 Cambios a aplicar:"
echo "  • APP_VERSION: $NEW_VERSION"
echo "  • DEPLOYMENT_VERSION: $DEPLOYMENT_VERSION"
echo "  • NEW_FEATURE_ENABLED: $NEW_FEATURE"
echo "  • EXPERIMENT_ENABLED: $EXPERIMENT_ENABLED"
echo ""

# Hacer backup del archivo original
cp argocd-production/01-production-deployment-istio.yaml argocd-production/01-production-deployment-istio.yaml.backup

echo "💾 Backup creado: 01-production-deployment-istio.yaml.backup"

# Aplicar cambios usando sed
echo "🔧 Aplicando cambios al deployment..."

sed -i "s/value: \"production-stable-istio-v[0-9]\+\.[0-9]\+\.[0-9]\+\"/value: \"$NEW_VERSION\"/g" argocd-production/01-production-deployment-istio.yaml
sed -i "s/value: \"v[0-9]\+\.[0-9]\+\.[0-9]\+\"/value: \"$DEPLOYMENT_VERSION\"/g" argocd-production/01-production-deployment-istio.yaml
sed -i "s/value: \"true\"/value: \"$NEW_FEATURE\"/g; s/value: \"false\"/value: \"$NEW_FEATURE\"/g" argocd-production/01-production-deployment-istio.yaml

# Aplicar cambio específico para EXPERIMENT_ENABLED
sed -i "/name: EXPERIMENT_ENABLED/,/value:/ s/value: \"[^\"]*\"/value: \"$EXPERIMENT_ENABLED\"/" argocd-production/01-production-deployment-istio.yaml

echo "✅ Cambios aplicados al deployment"

# Mostrar diferencias
echo ""
echo "📊 Diferencias aplicadas:"
diff argocd-production/01-production-deployment-istio.yaml.backup argocd-production/01-production-deployment-istio.yaml || true

echo ""
echo "🚀 PRÓXIMOS PASOS:"
echo "  1. Revisar cambios:"
echo "     cat argocd-production/01-production-deployment-istio.yaml | grep -A1 -B1 'APP_VERSION\\|DEPLOYMENT_VERSION\\|NEW_FEATURE\\|EXPERIMENT_ENABLED'"
echo "  2. Hacer commit (si usas Git):"
echo "     git add argocd-production/01-production-deployment-istio.yaml"
echo "     git commit -m 'Change to $MODE mode - $NEW_VERSION'"
echo "  3. Hacer sync en ArgoCD:"
echo "     ./scripts/sync-production.sh"
echo "  4. Verificar cambios:"
echo "     ./scripts/status-production.sh"

echo ""
echo "🔄 Para revertir cambios:"
echo "  cp argocd-production/01-production-deployment-istio.yaml.backup argocd-production/01-production-deployment-istio.yaml"

echo ""
echo "✅ Cambio de versión completado - Modo: $MODE"