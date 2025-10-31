# ArgoCD KEDA - Escalado Inteligente

Esta carpeta contiene los manifiestos para una aplicación separada de ArgoCD que gestiona el escalado inteligente con KEDA.

## Arquitectura

```
argocd-production/          → Aplicación principal (sin HPA)
  ├── Deployment: demo-microservice-production-istio
  ├── Service: demo-microservice-istio
  └── VirtualServices, DestinationRules, etc.

argocd-keda/               → Aplicación de escalado (con KEDA)
  ├── Deployment: demo-microservice-keda
  ├── Service: demo-microservice-keda
  └── ScaledObject: demo-microservice-keda-scaler
```

## Componentes

### 01-deployment-with-hpa.yaml
- Deployment independiente para pruebas de KEDA
- Labels: `app: demo-microservice-keda`
- Preparado para ser gestionado por HPA

### 02-service.yaml
- Service para el deployment de KEDA
- Nombre: `demo-microservice-keda`

### 03-scaled-object.yaml
- ScaledObject que gestiona el escalado
- Horarios:
  - 5:10 PM - 6:00 PM: 2 pods
  - 6:00 PM - 5:10 PM: 3 pods
- Escalado adicional por CPU/Memoria > 70%

## Instalación

```bash
# 1. Instalar KEDA (si no está instalado)
./scripts/install-keda.sh

# 2. Configurar ArgoCD para gestionar esta aplicación
./scripts/setup-argocd-keda.sh

# 3. Monitorear el escalado
./scripts/monitor-keda-scaling.sh
```

## Ventajas de esta arquitectura

✅ **Separación de responsabilidades**
- `argocd-production`: Gestiona la aplicación principal
- `argocd-keda`: Gestiona solo el escalado

✅ **No interfiere con producción**
- Deployment separado para pruebas
- Puedes probar KEDA sin afectar producción

✅ **Fácil de activar/desactivar**
- Elimina la aplicación de ArgoCD para desactivar
- Reactiva cuando quieras probar

## Migración a producción

Cuando estés listo para usar KEDA en producción:

1. Elimina la aplicación `argocd-keda`
2. Mueve el ScaledObject a `argocd-production/`
3. Cambia `scaleTargetRef.name` a `demo-microservice-production-istio`
4. Actualiza la aplicación de ArgoCD principal
