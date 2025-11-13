# 📋 Nuevas Variables para Añadir a la Librería

## ✅ Variables que YA EXISTEN en tu librería

Estas variables ya las tienes definidas (vienen del HPA tradicional):

```
✓ service
✓ namespace
✓ env
✓ cost-center
✓ application-code
✓ project-name
✓ pmo
✓ work-team
✓ dt-release-version
✓ dt-build-version
✓ dt-release-product
✓ dt-release-stage
✓ replicas
✓ replicas-max
✓ hpa-period-upscaling-seconds
✓ hpa-stabilization-upscaling-value
✓ hpa-period-downscaling-seconds
✓ hpa-stabilization-downscaling-value
✓ hpa-stabilization-window-seconds
```

## 🆕 Variables NUEVAS para KEDA (Añadir a la librería)

### 1. Configuración de KEDA

```yaml
Variable: polling-interval
Tipo: Integer
Descripción: Frecuencia con la que KEDA evalúa los triggers (segundos)
Rango: 1 - 300
Ejemplo: 10
```

```yaml
Variable: cooldown-period
Tipo: Integer
Descripción: Tiempo de espera antes de permitir otro escalado (segundos)
Rango: 0 - 600
Ejemplo: 30
```

### 2. Configuración de Timezone

```yaml
Variable: timezone
Tipo: String
Descripción: Zona horaria para los triggers de cron
Valores comunes:
  - America/Bogota
  - America/New_York
  - UTC
Ejemplo: America/Bogota
```

### 3. Réplicas para Downscale

```yaml
Variable: replicas-downscale
Tipo: Integer
Descripción: Número de pods durante el horario de baja demanda
Rango: 1 - replicas-max
Ejemplo: 2
```

### 4. Réplicas para Upscale

```yaml
Variable: replicas-upscale
Tipo: Integer
Descripción: Número de pods durante el horario de alta demanda
Rango: replicas - replicas-max
Ejemplo: 3
```

### 5. Horario de Downscale - Inicio

```yaml
Variable: cron-downscale-start
Tipo: String (Cron expression)
Descripción: Hora de inicio del período de baja demanda
Formato: "minuto hora día mes día-semana"
Ejemplo: "55 17 * * *"  (5:55 PM todos los días)
```

### 6. Horario de Downscale - Fin

```yaml
Variable: cron-downscale-end
Tipo: String (Cron expression)
Descripción: Hora de fin del período de baja demanda
Formato: "minuto hora día mes día-semana"
Ejemplo: "0 18 * * *"  (6:00 PM todos los días)
```

### 7. Horario de Upscale - Inicio

```yaml
Variable: cron-upscale-start
Tipo: String (Cron expression)
Descripción: Hora de inicio del período de alta demanda
Formato: "minuto hora día mes día-semana"
Ejemplo: "0 18 * * *"  (6:00 PM todos los días)
```

### 8. Horario de Upscale - Fin

```yaml
Variable: cron-upscale-end
Tipo: String (Cron expression)
Descripción: Hora de fin del período de alta demanda
Formato: "minuto hora día mes día-semana"
Ejemplo: "55 17 * * *"  (5:55 PM todos los días)
```

## 📊 Resumen: 9 Variables Nuevas

| # | Variable | Tipo | Obligatoria | Valor por Defecto Sugerido |
|---|----------|------|-------------|----------------------------|
| 1 | `polling-interval` | Integer | ✅ Sí | `10` |
| 2 | `cooldown-period` | Integer | ✅ Sí | `30` |
| 3 | `timezone` | String | ✅ Sí | `America/Bogota` |
| 4 | `replicas-downscale` | Integer | ✅ Sí | `2` |
| 5 | `replicas-upscale` | Integer | ✅ Sí | `3` |
| 6 | `cron-downscale-start` | String | ✅ Sí | `0 18 * * *` |
| 7 | `cron-downscale-end` | String | ✅ Sí | `0 8 * * *` |
| 8 | `cron-upscale-start` | String | ✅ Sí | `0 8 * * *` |
| 9 | `cron-upscale-end` | String | ✅ Sí | `0 18 * * *` |

## 💡 Valores Sugeridos por Ambiente

### QA (3 pods normalmente)
```properties
timezone=America/Bogota
replicas-downscale=2
replicas-upscale=3
cron-downscale-start=55 17 * * *
cron-downscale-end=0 18 * * *
cron-upscale-start=0 18 * * *
cron-upscale-end=55 17 * * *
```

### DEV (2 pods normalmente)
```properties
timezone=America/Bogota
replicas-downscale=1
replicas-upscale=2
cron-downscale-start=0 18 * * *
cron-downscale-end=0 8 * * *
cron-upscale-start=0 8 * * *
cron-upscale-end=0 18 * * *
```

### PROD (5 pods normalmente)
```properties
timezone=America/Bogota
replicas-downscale=3
replicas-upscale=5
cron-downscale-start=0 0 * * *
cron-downscale-end=6 0 * * *
cron-upscale-start=6 0 * * *
cron-upscale-end=0 0 * * *
```

## 🔧 Validaciones Recomendadas

```javascript
// Validar que replicas-downscale < replicas-upscale
if (replicasDownscale >= replicasUpscale) {
  throw new Error("replicas-downscale debe ser menor que replicas-upscale");
}

// Validar que están dentro del rango
if (replicasDownscale < 1 || replicasDownscale > replicasMax) {
  throw new Error("replicas-downscale fuera de rango");
}

if (replicasUpscale < replicas || replicasUpscale > replicasMax) {
  throw new Error("replicas-upscale fuera de rango");
}

// Validar formato de cron (regex básico)
const cronRegex = /^(\*|([0-9]|[1-5][0-9])) (\*|([0-9]|1[0-9]|2[0-3])) (\*|([1-9]|[12][0-9]|3[01])) (\*|([1-9]|1[0-2])) (\*|([0-6]))$/;
if (!cronRegex.test(cronDownscaleStart)) {
  throw new Error("Formato de cron inválido");
}
```

## 📝 Notas para el Equipo de Librería

1. **Compatibilidad**: Estas variables solo se usan cuando se despliega con KEDA
2. **Opcionales**: Si no se usan KEDA, estas variables no son necesarias
3. **Documentación**: Incluir ejemplos de cron expressions en la documentación
4. **Validación**: Validar formato de cron antes de aplicar
5. **Timezone**: Validar que la timezone sea válida (lista IANA)

## 🎯 Ejemplo de Uso en Pipeline

```yaml
# Azure DevOps / Jenkins / GitLab CI
variables:
  - name: timezone
    value: America/Bogota
  - name: replicas-downscale
    value: 2
  - name: replicas-upscale
    value: 3
  - name: cron-downscale-start
    value: "55 17 * * *"
  - name: cron-downscale-end
    value: "0 18 * * *"
  - name: cron-upscale-start
    value: "0 18 * * *"
  - name: cron-upscale-end
    value: "55 17 * * *"
```
