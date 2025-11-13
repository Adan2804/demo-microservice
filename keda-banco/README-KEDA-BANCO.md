# KEDA para el Banco - Escalado por Horario

## 📋 Descripción

Este directorio contiene la configuración de KEDA adaptada al formato del banco para escalado automático basado en horarios (cron triggers).

## 🗂️ Archivos

- **scaled-object.yaml**: Template con variables del banco para KEDA
- **hpa-v2.yaml**: HPA tradicional (será reemplazado por KEDA)
- **variables-keda-qa.properties**: Variables para ambiente QA
- **valores-ejemplo-dev.md**: Documentación de variables disponibles

## 🚀 Uso Rápido

### 1. Configurar Variables para tu Ambiente

Crea o edita el archivo de variables para tu ambiente:

```bash
# Para QA
keda-banco/variables-keda-qa.properties

# Para DEV (crear nuevo)
keda-banco/variables-keda-dev.properties
```

### 2. Procesar el Template

Ejecuta el script de reemplazo de tokens:

```powershell
# Para QA
.\scripts\replace-tokens-keda.ps1 -Environment qa -Verbose

# Para DEV
.\scripts\replace-tokens-keda.ps1 -Environment dev -Verbose

# Para aplicar directamente al cluster
.\scripts\replace-tokens-keda.ps1 -Environment qa -ApplyToCluster
```

### 3. Verificar el Resultado

El archivo procesado se genera en:
```
keda-banco-processed/scaled-object.yaml
```

## 📝 Variables Principales

### Variables Obligatorias

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `service` | Nombre del servicio | `demo-microservice` |
| `namespace` | Namespace de Kubernetes | `qa-namespace` |
| `env` | Ambiente | `qa`, `dev`, `prod` |
| `replicas` | Réplicas mínimas | `3` |
| `replicas-max` | Réplicas máximas | `10` |

### Variables de KEDA (Nuevas)

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `timezone` | Zona horaria | `America/Bogota` |
| `replicas-downscale` | Pods en horario bajo | `2` |
| `replicas-upscale` | Pods en horario alto | `3` |
| `cron-downscale-start` | Inicio downscale | `55 17 * * *` (5:55 PM) |
| `cron-downscale-end` | Fin downscale | `0 18 * * *` (6:00 PM) |
| `cron-upscale-start` | Inicio upscale | `0 18 * * *` (6:00 PM) |
| `cron-upscale-end` | Fin upscale | `55 17 * * *` (5:55 PM) |

### Variables de HPA Behavior

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `hpa-period-upscaling-seconds` | Período de evaluación upscale | `30` |
| `hpa-stabilization-upscaling-value` | Pods a agregar por período | `2` |
| `hpa-period-downscaling-seconds` | Período de evaluación downscale | `30` |
| `hpa-stabilization-downscaling-value` | Pods a remover por período | `1` |
| `hpa-stabilization-window-seconds` | Ventana de estabilización | `30` |

### Variables de Labels del Banco

| Variable | Descripción |
|----------|-------------|
| `cost-center` | Centro de costos |
| `application-code` | Código de aplicación |
| `project-name` | Nombre del proyecto |
| `pmo` | PMO responsable |
| `work-team` | Equipo de trabajo |
| `dt-release-version` | Versión de release (Dynatrace) |
| `dt-build-version` | Versión de build (Dynatrace) |
| `dt-release-product` | Producto (Dynatrace) |
| `dt-release-stage` | Etapa (Dynatrace) |

## ⏰ Formato de Cron

```
Formato: "minuto hora día mes día-semana"

Ejemplos:
- "0 8 * * *"     → 8:00 AM todos los días
- "30 17 * * *"   → 5:30 PM todos los días
- "0 8 * * 1-5"   → 8:00 AM lunes a viernes
- "55 17 * * *"   → 5:55 PM todos los días
- "0 0 * * 0"     → Medianoche los domingos
```

## 🔄 Ejemplo de Configuración QA

```properties
# 3 pods normalmente, 2 pods de 5:55 PM a 6:00 PM
replicas=3
replicas-max=10
replicas-downscale=2
replicas-upscale=3

timezone=America/Bogota
cron-downscale-start=55 17 * * *
cron-downscale-end=0 18 * * *
cron-upscale-start=0 18 * * *
cron-upscale-end=55 17 * * *
```

## 🎯 Diferencias con HPA Tradicional

| Característica | HPA Tradicional | KEDA con Cron |
|----------------|-----------------|---------------|
| Trigger | CPU/Memoria | Horario (cron) |
| Escalado | Reactivo | Proactivo |
| Configuración | hpa-v2.yaml | scaled-object.yaml |
| Gestión | Manual | Automática por KEDA |

## ⚠️ Importante

1. **KEDA reemplaza el HPA**: No uses ambos al mismo tiempo
2. **KEDA debe estar instalado**: Verifica con `kubectl get crd scaledobjects.keda.sh`
3. **El deployment debe existir**: KEDA escala un deployment existente
4. **Horarios en UTC o timezone**: Configura correctamente la zona horaria

## 🔍 Comandos de Verificación

```bash
# Ver ScaledObject
kubectl get scaledobject -n <namespace>

# Ver HPA generado por KEDA
kubectl get hpa -n <namespace>

# Ver detalles del ScaledObject
kubectl describe scaledobject <service>-scaled-object -n <namespace>

# Ver logs de KEDA
kubectl logs -n keda -l app=keda-operator --tail=50

# Monitorear pods en tiempo real
kubectl get pods -n <namespace> -w
```

## 📚 Recursos

- [Documentación KEDA](https://keda.sh/)
- [Cron Trigger](https://keda.sh/docs/latest/scalers/cron/)
- [HPA Behavior](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
