# 🔄 Comparación: HPA Tradicional vs KEDA

## 📊 Diferencias Principales

| Aspecto | HPA Tradicional | KEDA con Cron |
|---------|-----------------|---------------|
| **Archivo** | `hpa-v2.yaml` | `scaled-object.yaml` |
| **Trigger** | CPU/Memoria | Horario (cron) |
| **Tipo de Escalado** | Reactivo (responde a carga) | Proactivo (anticipa demanda) |
| **Variables Necesarias** | 18 variables | 25 variables (+7 nuevas) |
| **Gestión** | Manual | Automática por KEDA |
| **Conflictos** | Puede coexistir con otros HPAs | Toma control del HPA |

## 📝 Variables: Antes y Después

### ✅ Variables que SE MANTIENEN (18)

Estas variables ya existen en tu librería y se siguen usando:

```yaml
# Identificación
service
namespace
env

# Labels del Banco
cost-center
application-code
project-name
pmo
work-team
dt-release-version
dt-build-version
dt-release-product
dt-release-stage

# Configuración de Réplicas
replicas
replicas-max

# HPA Behavior
hpa-period-upscaling-seconds
hpa-stabilization-upscaling-value
hpa-period-downscaling-seconds
hpa-stabilization-downscaling-value
hpa-stabilization-window-seconds
```

### ❌ Variables que SE ELIMINAN (2)

Estas variables del HPA tradicional NO se usan en KEDA con cron:

```yaml
cpu-utilization-percentage      # ❌ No se usa (no hay trigger de CPU)
memory-utilization-percentage   # ❌ No se usa (no hay trigger de memoria)
hpa-scaleup-type               # ❌ No se usa (siempre es "Pods")
hpa-scaledown-type             # ❌ No se usa (siempre es "Pods")
```

### 🆕 Variables NUEVAS para KEDA (7)

Estas son las variables que debes añadir a tu librería:

```yaml
timezone                    # 🆕 Zona horaria
replicas-downscale         # 🆕 Pods en horario bajo
replicas-upscale           # 🆕 Pods en horario alto
cron-downscale-start       # 🆕 Inicio downscale
cron-downscale-end         # 🆕 Fin downscale
cron-upscale-start         # 🆕 Inicio upscale
cron-upscale-end           # 🆕 Fin upscale
```

## 📋 Ejemplo Completo: QA con 3 Pods

### ANTES: HPA Tradicional (hpa-v2.yaml)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: demo-microservice-hpa
  namespace: qa-namespace
spec:
  scaleTargetRef:
    name: demo-microservice-deployment
  minReplicas: 3                    # ← Siempre 3 pods mínimo
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70      # ← Escala cuando CPU > 70%
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80      # ← Escala cuando Memoria > 80%
```

**Comportamiento:**
- ✅ Escala automáticamente según CPU/Memoria
- ❌ No puede reducir a menos de 3 pods (aunque no haya carga)
- ❌ Reactivo: espera a que suba la carga para escalar

### DESPUÉS: KEDA con Cron (scaled-object.yaml)

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: demo-microservice-scaled-object
  namespace: qa-namespace
spec:
  scaleTargetRef:
    name: demo-microservice-deployment
  minReplicaCount: 2                # ← Puede bajar a 2 pods
  maxReplicaCount: 10
  pollingInterval: 10
  cooldownPeriod: 30
  triggers:
    # Downscale: 5:55 PM - 6:00 PM → 2 pods
    - type: cron
      metadata:
        timezone: "America/Bogota"
        start: "55 17 * * *"
        end: "0 18 * * *"
        desiredReplicas: "2"        # ← Reduce a 2 pods
    
    # Upscale: 6:00 PM - 5:55 PM → 3 pods
    - type: cron
      metadata:
        timezone: "America/Bogota"
        start: "0 18 * * *"
        end: "55 17 * * *"
        desiredReplicas: "3"        # ← Vuelve a 3 pods
```

**Comportamiento:**
- ✅ Escala proactivamente según horario
- ✅ Reduce a 2 pods de 5:55 PM a 6:00 PM (ahorro de recursos)
- ✅ Mantiene 3 pods el resto del día
- ✅ Proactivo: anticipa la demanda

## 📈 Ejemplo de Escalado en el Tiempo

```
Hora    | HPA Tradicional | KEDA con Cron | Ahorro
--------|-----------------|---------------|--------
8:00 AM | 3 pods          | 3 pods        | 0%
12:00 PM| 3 pods          | 3 pods        | 0%
5:00 PM | 3 pods          | 3 pods        | 0%
5:55 PM | 3 pods          | 2 pods ⬇️     | 33%
6:00 PM | 3 pods          | 3 pods ⬆️     | 0%
11:00 PM| 3 pods          | 3 pods        | 0%
```

**Ahorro diario:** 5 minutos con 1 pod menos = ~0.35% de ahorro
**Ahorro mensual:** Si se configura para horarios más largos, puede ser significativo

## 🎯 Casos de Uso Recomendados

### Usar HPA Tradicional cuando:
- ✅ La carga es impredecible
- ✅ Necesitas escalar según CPU/Memoria
- ✅ No hay patrones de horario claros
- ✅ Quieres escalado reactivo

### Usar KEDA con Cron cuando:
- ✅ Hay patrones de horario predecibles
- ✅ Quieres reducir costos en horarios de baja demanda
- ✅ Necesitas escalado proactivo
- ✅ Quieres optimizar recursos

### Usar KEDA con otros triggers cuando:
- ✅ Escalado basado en colas (RabbitMQ, Kafka, SQS)
- ✅ Escalado basado en métricas custom
- ✅ Escalado basado en eventos externos

## 🔧 Migración: Pasos para Cambiar de HPA a KEDA

### Paso 1: Preparar Variables
```bash
# Añadir las 7 nuevas variables a tu librería
timezone=America/Bogota
replicas-downscale=2
replicas-upscale=3
cron-downscale-start=55 17 * * *
cron-downscale-end=0 18 * * *
cron-upscale-start=0 18 * * *
cron-upscale-end=55 17 * * *
```

### Paso 2: Procesar Template
```powershell
.\scripts\replace-tokens-keda.ps1 -Environment qa -Verbose
```

### Paso 3: Eliminar HPA Tradicional
```bash
kubectl delete hpa demo-microservice-hpa -n qa-namespace
```

### Paso 4: Aplicar KEDA
```bash
kubectl apply -f keda-banco-processed/scaled-object.yaml
```

### Paso 5: Verificar
```bash
# Ver ScaledObject
kubectl get scaledobject -n qa-namespace

# Ver HPA generado por KEDA
kubectl get hpa -n qa-namespace

# Monitorear pods
kubectl get pods -n qa-namespace -w
```

## ⚠️ Consideraciones Importantes

1. **No mezclar HPA y KEDA**: KEDA toma control del HPA
2. **KEDA debe estar instalado**: Verificar antes de aplicar
3. **Probar en DEV primero**: Validar comportamiento antes de QA/PROD
4. **Monitorear el primer día**: Asegurar que el escalado funciona correctamente
5. **Documentar horarios**: Mantener registro de por qué se eligieron esos horarios

## 📚 Recursos Adicionales

- [KEDA Documentation](https://keda.sh/)
- [Cron Trigger Docs](https://keda.sh/docs/latest/scalers/cron/)
- [HPA Behavior](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Cron Expression Generator](https://crontab.guru/)
