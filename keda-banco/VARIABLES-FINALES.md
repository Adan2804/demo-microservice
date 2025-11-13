# ✅ Variables Finales Confirmadas para KEDA

## 📋 Resumen de Variables

Basado en tu configuración del banco, estas son las **9 variables nuevas** que se añadieron para KEDA:

## 🆕 Variables Nuevas de KEDA (9 en total)

### 1. Configuración de KEDA

| Variable | Valor Actual | Descripción |
|----------|--------------|-------------|
| `polling-interval` | `10` | Frecuencia de evaluación (segundos) |
| `cooldown-period` | `30` | Tiempo de espera antes de escalar (segundos) |

### 2. Configuración de Timezone

| Variable | Valor Actual | Descripción |
|----------|--------------|-------------|
| `timezone` | `America/Bogota` | Zona horaria para cron triggers |

### 3. Configuración de Réplicas

| Variable | Valor Actual | Descripción |
|----------|--------------|-------------|
| `replicas-downscale` | `0` | Pods durante downscale |
| `replicas-upscale` | `1` | Pods durante upscale |

### 4. Configuración de Horarios (Cron)

| Variable | Valor Actual | Descripción |
|----------|--------------|-------------|
| `cron-downscale-start` | `0 14 * * *` | Inicio del downscale (2:00 PM) |
| `cron-downscale-end` | `10 14 * * *` | Fin del downscale (2:10 PM) |
| `cron-upscale-start` | `0 14 * * *` | Inicio del upscale (2:00 PM) |
| `cron-upscale-end` | `10 14 * * *` | Fin del upscale (2:10 PM) |

## 📊 Variables Completas del ScaledObject

### Variables que YA EXISTÍAN (18)

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

# Configuración de Réplicas Base
replicas
replicas-max

# HPA Behavior
hpa-period-upscaling-seconds
hpa-stabilization-upscaling-value
hpa-period-downscaling-seconds
hpa-stabilization-downscaling-value
hpa-stabilization-window-seconds
```

### Variables NUEVAS (9)

```yaml
# KEDA Configuration
polling-interval                # 🆕
cooldown-period                 # 🆕

# Timezone
timezone                        # 🆕

# Réplicas por Horario
replicas-downscale             # 🆕
replicas-upscale               # 🆕

# Horarios Cron
cron-downscale-start           # 🆕
cron-downscale-end             # 🆕
cron-upscale-start             # 🆕
cron-upscale-end               # 🆕
```

## 📝 Valores Actuales en tu Sistema

Según la imagen que compartiste:

```properties
# KEDA Configuration
polling-interval=10
cooldown-period=30

# Timezone
timezone=America/Bogota

# Réplicas
replicas-downscale=0
replicas-upscale=1

# Horarios Cron
cron-downscale-start=0 14 * * *
cron-downscale-end=10 14 * * *
cron-upscale-start=0 14 * * *
cron-upscale-end=10 14 * * *
```

## ⚠️ Observaciones Importantes

### 1. Réplicas en 0 y 1
```
replicas-downscale=0  ⚠️ Cuidado: 0 pods = servicio caído
replicas-upscale=1    ⚠️ Solo 1 pod = sin redundancia
```

**Recomendación para QA/PROD:**
```properties
replicas-downscale=2  # Mínimo 2 para redundancia
replicas-upscale=3    # 3 pods en horario normal
```

### 2. Horarios Solapados
```
Downscale: 2:00 PM - 2:10 PM
Upscale:   2:00 PM - 2:10 PM  ⚠️ Mismo horario
```

**Recomendación:** Los horarios deben ser complementarios:
```properties
# Ejemplo: Reducir de 6 PM a 8 AM (noche)
cron-downscale-start=0 18 * * *   # 6:00 PM - inicia downscale
cron-downscale-end=0 8 * * *      # 8:00 AM - termina downscale
cron-upscale-start=0 8 * * *      # 8:00 AM - inicia upscale
cron-upscale-end=0 18 * * *       # 6:00 PM - termina upscale
```

## 🎯 Configuración Recomendada para QA

```properties
# KEDA Configuration
polling-interval=10
cooldown-period=30

# Timezone
timezone=America/Bogota

# Réplicas (3 pods normalmente, 2 en horario bajo)
replicas-downscale=2
replicas-upscale=3

# Horarios (ejemplo: reducir de 6 PM a 8 AM)
cron-downscale-start=0 18 * * *
cron-downscale-end=0 8 * * *
cron-upscale-start=0 8 * * *
cron-upscale-end=0 18 * * *
```

## 📈 Comportamiento Esperado

Con la configuración recomendada:

```
Hora      | Pods | Trigger Activo
----------|------|----------------
8:00 AM   | 3    | Upscale (inicia)
12:00 PM  | 3    | Upscale
5:00 PM   | 3    | Upscale
6:00 PM   | 2    | Downscale (inicia)
10:00 PM  | 2    | Downscale
2:00 AM   | 2    | Downscale
8:00 AM   | 3    | Upscale (inicia)
```

## ✅ Checklist de Validación

- [x] `polling-interval` configurado (10 segundos)
- [x] `cooldown-period` configurado (30 segundos)
- [x] `timezone` configurado (America/Bogota)
- [ ] `replicas-downscale` >= 1 (actualmente 0 ⚠️)
- [ ] `replicas-upscale` >= 2 (actualmente 1 ⚠️)
- [ ] Horarios de cron no solapados (actualmente solapados ⚠️)
- [ ] Horarios tienen sentido para el negocio

## 🔧 Comandos de Verificación

```bash
# Ver configuración actual del ScaledObject
kubectl get scaledobject <service>-scaled-object -n <namespace> -o yaml

# Ver triggers activos
kubectl describe scaledobject <service>-scaled-object -n <namespace>

# Ver HPA generado por KEDA
kubectl get hpa <service>-hpa -n <namespace> -o yaml

# Monitorear cambios de réplicas
kubectl get pods -n <namespace> -w
```

## 📚 Formato de Cron - Referencia Rápida

```
Formato: "minuto hora día mes día-semana"
         ┌─────── minuto (0-59)
         │ ┌───── hora (0-23)
         │ │ ┌─── día del mes (1-31)
         │ │ │ ┌─ mes (1-12)
         │ │ │ │ ┌ día de la semana (0-6, 0=domingo)
         │ │ │ │ │
         * * * * *

Ejemplos:
0 8 * * *      → 8:00 AM todos los días
0 18 * * *     → 6:00 PM todos los días
0 8 * * 1-5    → 8:00 AM lunes a viernes
30 17 * * *    → 5:30 PM todos los días
0 0 * * 0      → Medianoche los domingos
*/15 * * * *   → Cada 15 minutos
```

## 💡 Próximos Pasos

1. ✅ Variables añadidas correctamente
2. ⚠️ Revisar valores de `replicas-downscale` y `replicas-upscale`
3. ⚠️ Ajustar horarios de cron para que no se solapen
4. ⏳ Probar en ambiente de desarrollo
5. ⏳ Validar comportamiento en QA
6. ⏳ Documentar horarios elegidos y justificación

---

**Última actualización**: Basado en variables del banco
**Estado**: ✅ Variables configuradas, ⚠️ Valores necesitan ajuste
