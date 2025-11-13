# Valores de Ejemplo para KEDA con Cron en DEV

## Variables del ScaledObject

### Labels estándar del banco
```
service: demo-microservice
namespace: dev-namespace
env: dev
cost-center: 12345
application-code: APP001
project-name: proyecto-demo
pmo: PMO-001
dt-release-version: 1.0.0
dt-build-version: 1.0.0-SNAPSHOT
dt-release-product: producto-demo
dt-release-stage: development
work-team: equipo-desarrollo
```

### Configuración de réplicas
```
replicas: 2                    # Mínimo de pods (horario de baja demanda)
replicas-max: 10               # Máximo de pods permitido
replicas-downscale: 2          # Pods durante downscale (ej: 5:40PM-6PM)
replicas-upscale: 3            # Pods durante upscale (resto del día)
```

### Configuración de cron (Ejemplo: reducir de 5:40PM a 6PM)
```
timezone: America/Bogota
cron-downscale-start: 55 17 * * *    # 5:55 PM - inicio downscale
cron-downscale-end: 0 18 * * *       # 6:00 PM - fin downscale
cron-upscale-start: 0 18 * * *       # 6:00 PM - inicio upscale
cron-upscale-end: 55 17 * * *        # 5:55 PM - fin upscale
```

### Configuración de HPA behavior
```
hpa-period-downscaling-seconds: 30
hpa-stabilization-downscaling-value: 1
hpa-stabilization-window-seconds: 30
hpa-period-upscaling-seconds: 30
hpa-stabilization-upscaling-value: 2
```

### Configuración de KEDA (polling y cooldown)
```
polling-interval: 10          # Evalúa triggers cada 10 segundos
cooldown-period: 30           # Espera 30 segundos antes de escalar
```

## Formato de Cron
```
Formato: "minuto hora día mes día-semana"
Ejemplos:
- "0 8 * * *"     → 8:00 AM todos los días
- "30 17 * * *"   → 5:30 PM todos los días
- "0 8 * * 1-5"   → 8:00 AM lunes a viernes
- "55 17 * * *"   → 5:55 PM todos los días
```

## Notas importantes
- El ScaledObject reemplaza el HPA tradicional (hpa-v2.yaml)
- KEDA crea automáticamente un HPA gestionado
- Los triggers de cron NO interfieren con métricas de CPU/Memoria
- El pollingInterval está en 10 segundos para respuesta rápida
- El cooldownPeriod evita escalados muy frecuentes
