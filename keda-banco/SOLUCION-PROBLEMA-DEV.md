# 🔧 Solución al Problema en DEV

## 🔴 Problema Actual

Tu ScaledObject muestra:
```
READY: False
ACTIVE: Unknown
```

## 📋 Configuración Actual (INCORRECTA)

```yaml
triggers:
  # Downscale: 3:00 PM - 3:10 PM → 0 pods ⚠️
  - type: cron
    metadata:
      timezone: "America/Bogota"
      start: "0 15 * * *"      # 3:00 PM
      end: "10 15 * * *"       # 3:10 PM
      desiredReplicas: "0"     # ⚠️ SERVICIO CAÍDO
  
  # Upscale: 3:10 PM - 3:00 PM → 1 pod
  - type: cron
    metadata:
      timezone: "America/Bogota"
      start: "10 15 * * *"     # 3:10 PM
      end: "0 15 * * *"        # ⚠️ 3:00 PM (confuso)
      desiredReplicas: "1"
```

## ❌ Problemas

1. **Réplicas en 0**: De 3:00 PM a 3:10 PM el servicio estará CAÍDO
2. **Horarios confusos**: El segundo trigger tiene end < start
3. **KEDA confundido**: No sabe qué trigger aplicar → Estado "Unknown"

## ✅ Configuración CORRECTA

### Opción 1: Reducir en Horario Nocturno (RECOMENDADO)

```yaml
triggers:
  # Downscale: 6:00 PM - 8:00 AM → 1 pod (horario nocturno)
  - type: cron
    metadata:
      timezone: "America/Bogota"
      start: "0 18 * * *"      # 6:00 PM
      end: "0 8 * * *"         # 8:00 AM del día siguiente
      desiredReplicas: "1"     # ✅ Mínimo 1 pod
  
  # Upscale: 8:00 AM - 6:00 PM → 2 pods (horario laboral)
  - type: cron
    metadata:
      timezone: "America/Bogota"
      start: "0 8 * * *"       # 8:00 AM
      end: "0 18 * * *"        # 6:00 PM
      desiredReplicas: "2"     # ✅ 2 pods para redundancia
```

**Comportamiento:**
```
8:00 AM - 6:00 PM:  2 pods (horario laboral)
6:00 PM - 8:00 AM:  1 pod (horario nocturno)
```

### Opción 2: Reducir Solo en Madrugada

```yaml
triggers:
  # Downscale: 12:00 AM - 6:00 AM → 1 pod (madrugada)
  - type: cron
    metadata:
      timezone: "America/Bogota"
      start: "0 0 * * *"       # 12:00 AM
      end: "0 6 * * *"         # 6:00 AM
      desiredReplicas: "1"
  
  # Upscale: 6:00 AM - 12:00 AM → 2 pods (resto del día)
  - type: cron
    metadata:
      timezone: "America/Bogota"
      start: "0 6 * * *"       # 6:00 AM
      end: "0 0 * * *"         # 12:00 AM
      desiredReplicas: "2"
```

### Opción 3: Para Pruebas Rápidas (10 minutos)

Si solo quieres probar que funciona:

```yaml
triggers:
  # Downscale: Minuto 0-5 de cada hora → 1 pod
  - type: cron
    metadata:
      timezone: "America/Bogota"
      start: "0 * * * *"       # Minuto 0 de cada hora
      end: "5 * * * *"         # Minuto 5 de cada hora
      desiredReplicas: "1"
  
  # Upscale: Minuto 5-59 de cada hora → 2 pods
  - type: cron
    metadata:
      timezone: "America/Bogota"
      start: "5 * * * *"       # Minuto 5 de cada hora
      end: "0 * * * *"         # Minuto 0 de la siguiente hora
      desiredReplicas: "2"
```

**Comportamiento:**
```
Cada hora:
  Minuto 0-5:   1 pod
  Minuto 5-60:  2 pods
```

## 🔧 Cómo Corregir

### Paso 1: Actualizar Variables

Cambia estos valores en tu sistema de variables:

```properties
# ANTES (INCORRECTO)
replicas-downscale=0
replicas-upscale=1
cron-downscale-start=0 15 * * *
cron-downscale-end=10 15 * * *
cron-upscale-start=10 15 * * *
cron-upscale-end=0 15 * * *

# DESPUÉS (CORRECTO - Opción 1)
replicas-downscale=1
replicas-upscale=2
cron-downscale-start=0 18 * * *
cron-downscale-end=0 8 * * *
cron-upscale-start=0 8 * * *
cron-upscale-end=0 18 * * *
```

### Paso 2: Regenerar y Aplicar

```bash
# 1. Eliminar ScaledObject actual
kubectl delete scaledobject ch-ms-cross-catalogues-scaled-object -n super-svp-dev

# 2. Aplicar con nueva configuración
kubectl apply -f scaled-object-pods.yaml -n super-svp-dev

# 3. Verificar estado
kubectl get scaledobject -n super-svp-dev
kubectl describe scaledobject ch-ms-cross-catalogues-scaled-object -n super-svp-dev
```

### Paso 3: Verificar que Funciona

```bash
# Ver estado del ScaledObject
kubectl get scaledobject ch-ms-cross-catalogues-scaled-object -n super-svp-dev

# Debería mostrar:
# READY: True
# ACTIVE: True

# Ver HPA generado
kubectl get hpa -n super-svp-dev

# Ver pods
kubectl get pods -n super-svp-dev -l app=ch-ms-cross-catalogues
```

## 📊 Entendiendo los Triggers de Cron

Los triggers de cron en KEDA funcionan así:

```yaml
- type: cron
  metadata:
    start: "A"
    end: "B"
    desiredReplicas: "X"
```

**Significado:**
- Desde la hora `A` hasta la hora `B` → mantener `X` réplicas
- Fuera de ese período → el otro trigger toma control

**Reglas:**
1. Los períodos NO deben solaparse
2. Los períodos deben ser complementarios (cubrir las 24 horas)
3. `desiredReplicas` debe ser >= 1 (nunca 0 en producción)

## ⚠️ Por Qué No Usar 0 Réplicas

```yaml
desiredReplicas: "0"  # ❌ NUNCA EN PRODUCCIÓN
```

**Consecuencias:**
- ✗ Servicio completamente caído
- ✗ Errores 503 Service Unavailable
- ✗ Pérdida de requests
- ✗ Tiempo de arranque cuando vuelve a 1 pod
- ✗ Cold start de la aplicación

**Mínimo recomendado:**
```yaml
desiredReplicas: "1"  # ✅ Mínimo para DEV
desiredReplicas: "2"  # ✅ Recomendado para QA/PROD
```

## 🎯 Configuración Recomendada para DEV

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  annotations:
    scaledobject.keda.sh/transfer-hpa-ownership: 'true'
  name: ch-ms-cross-catalogues-scaled-object
  namespace: super-svp-dev
  labels:
    app.bancolombia.com.co/env: dev
    # ... resto de labels
spec:
  maxReplicaCount: 2
  minReplicaCount: 1
  scaleTargetRef:
    name: ch-ms-cross-catalogues-deployment
  pollingInterval: 10
  cooldownPeriod: 30
  triggers:
    # Downscale: 6:00 PM - 8:00 AM → 1 pod
    - type: cron
      metadata:
        timezone: "America/Bogota"
        start: "0 18 * * *"
        end: "0 8 * * *"
        desiredReplicas: "1"
    
    # Upscale: 8:00 AM - 6:00 PM → 2 pods
    - type: cron
      metadata:
        timezone: "America/Bogota"
        start: "0 8 * * *"
        end: "0 18 * * *"
        desiredReplicas: "2"
  advanced:
    horizontalPodAutoscalerConfig:
      behavior:
        scaleDown:
          policies:
            - periodSeconds: 60
              type: Pods
              value: 1
          selectPolicy: Max
          stabilizationWindowSeconds: 120
        scaleUp:
          policies:
            - periodSeconds: 60
              type: Pods
              value: 2
          selectPolicy: Max
          stabilizationWindowSeconds: 0
      name: ch-ms-cross-catalogues-hpa
```

## 🔍 Comandos de Diagnóstico

```bash
# Ver detalles del ScaledObject
kubectl describe scaledobject ch-ms-cross-catalogues-scaled-object -n super-svp-dev

# Ver logs de KEDA
kubectl logs -n keda -l app=keda-operator --tail=50

# Ver eventos del namespace
kubectl get events -n super-svp-dev --sort-by='.lastTimestamp' | tail -20

# Ver HPA generado por KEDA
kubectl get hpa ch-ms-cross-catalogues-hpa -n super-svp-dev -o yaml
```

## ✅ Checklist de Validación

- [ ] `replicas-downscale` >= 1 (nunca 0)
- [ ] `replicas-upscale` >= 2 (para redundancia)
- [ ] Horarios no solapados
- [ ] `start` y `end` tienen sentido lógico
- [ ] Los dos triggers cubren las 24 horas
- [ ] ScaledObject muestra `READY: True`
- [ ] ScaledObject muestra `ACTIVE: True`
- [ ] HPA fue creado por KEDA
- [ ] Pods escalan según horario

## 📚 Recursos

- [KEDA Cron Scaler Docs](https://keda.sh/docs/latest/scalers/cron/)
- [Cron Expression Generator](https://crontab.guru/)
- [KEDA Troubleshooting](https://keda.sh/docs/latest/troubleshooting/)

---

**Resumen:** Cambia `replicas-downscale` de 0 a 1, y ajusta los horarios para que no se solapen. Con eso debería funcionar correctamente.
