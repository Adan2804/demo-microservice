# 🚀 Sistema de Escalado Inteligente - Prueba de Concepto

**Fecha:** 21 de Octubre de 2025  
**Autor:** Adan Moreto Enrriquez

## 📋 Resumen Ejecutivo

Sistema de escalado dual que optimiza recursos durante horarios de baja demanda (ahorro de hasta 33%) mientras garantiza capacidad durante horarios críticos.

### Beneficios Clave
- ✅ **Reducción de Costos:** Hasta 33% de ahorro en horario nocturno
- ✅ **Garantía de Rendimiento:** Capacidad mínima asegurada en horario laboral
- ✅ **Decisiones Inteligentes:** Basadas en métricas reales (CPU y Memoria)

---

## 🏗️ Arquitectura

### Componente 1: Escalado de Prueba (Downscale)
**Archivo:** `05-scaled-object-intelligent-downscale.yaml`

- **Periodo:** 5:00 PM - 6:00 PM (UTC-5, Colombia) ⏰ **HORARIO DE PRUEBA**
- **Lógica:** Reduce de 3 a 2 pods SOLO si CPU y Memoria < 50%
- **Seguridad:** Nunca baja de 2 pods (umbral mínimo)
- **Duración:** 1 hora para pruebas rápidas

### Componente 2: Escalado de Prueba (Upscale)
**Archivo:** `06-scaled-object-intelligent-upscale.yaml`

- **Periodo:** 6:00 PM - 5:00 PM (UTC-5, Colombia) ⏰ **Todo el día excepto 5PM-6PM**
- **Lógica:** Garantiza mínimo 3 pods de forma incondicional
- **Escalado Adicional:** Puede llegar hasta 10 pods si CPU o Memoria > 70%
- **Propósito:** Restaurar capacidad después del periodo de downscale

---

## 🔄 Flujo de Operación de Prueba (Diario)

```
⏰ HORARIO DE PRUEBA CONFIGURADO: 5:00 PM - 6:00 PM

00:00 ──────────────────────────────────────────────── 17:00 (5PM)
    │                                                      │
    │         MODO UPSCALE (Capacidad Normal)             │
    │         • Mínimo: 3 pods SIEMPRE                    │
    │         • Máximo: 10 pods (si hay demanda)          │
    │                                                      │
    └──────────────────────────────────────────────────────┘
                                                           │
17:00 (5PM) ──────────────────────────────────────── 18:00 (6PM)
    │                                                      │
    │         MODO DOWNSCALE (Prueba de Ahorro) ⏰        │
    │         • Evalúa CPU y Memoria                      │
    │         • Si < 50%: Reduce a 2 pods (ahorro 33%)    │
    │         • Si >= 50%: Mantiene 3 pods (seguridad)    │
    │         • Duración: 1 hora                          │
    │                                                      │
    └──────────────────────────────────────────────────────┘
                                                           │
18:00 (6PM) ──────────────────────────────────────── 24:00
    │                                                      │
    │         MODO UPSCALE (Capacidad Restaurada)         │
    │         • Restaura a 3 pods automáticamente         │
    │         • Máximo: 10 pods (si hay demanda)          │
    │                                                      │
    └──────────────────────────────────────────────────────┘
```

---

## 📊 Escenarios de Operación (Horario de Prueba)

### Escenario 1: 5:00 PM - Tráfico Bajo ✅
```
Hora: 17:00 (5:00 PM)
CPU: 35% | Memoria: 40%
Decisión: ✅ Escalar de 3 → 2 pods
Ahorro: 33% en recursos
Duración: Hasta las 6:00 PM
```

### Escenario 2: 5:00 PM - Tráfico Alto 🛡️
```
Hora: 17:00 (5:00 PM)
CPU: 65% | Memoria: 45%
Decisión: 🛡️ Mantener 3 pods
Razón: CPU supera el umbral del 50%
```

### Escenario 3: 6:00 PM - Restauración de Capacidad 🚀
```
Hora: 18:00 (6:00 PM)
Estado Actual: 2 pods
Decisión: 🚀 Escalar de 2 → 3 pods
Razón: Fin del periodo de downscale (sin evaluar métricas)
```

### Escenario 4: Resto del Día - Capacidad Normal 📈
```
Hora: Cualquier hora excepto 5PM-6PM
Estado: 3 pods mínimo
Comportamiento: Puede escalar hasta 10 pods si hay demanda
```

---

## 🚀 Guía de Implementación

### Paso 1: Verificar Prerequisitos

```bash
# Verificar que KEDA esté instalado
kubectl get deployment keda-operator -n keda

# Verificar que metrics-server esté instalado (para métricas de CPU/Memoria)
kubectl get deployment metrics-server -n kube-system

# Si no está instalado:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Paso 2: Desplegar con ArgoCD

Los archivos ya están en `argocd-production/`, ArgoCD los sincronizará automáticamente:

```bash
# Ejecutar el script de setup de ArgoCD
cd demo-microservice
./scripts/03-setup-argocd.sh

# Verificar que ArgoCD sincronizó los ScaledObjects
kubectl get scaledobject -n default
```

### Paso 3: Verificar Despliegue

```bash
# Verificar ScaledObjects
kubectl get scaledobject -n default

# Verificar HPAs generados por KEDA
kubectl get hpa -n default | grep intelligent

# Ver detalles del ScaledObject de downscale
kubectl describe scaledobject demo-microservice-intelligent-downscale -n default

# Ver detalles del ScaledObject de upscale
kubectl describe scaledobject demo-microservice-intelligent-upscale -n default
```

---

## 📈 Monitoreo y Validación

### Monitoreo en Tiempo Real

```bash
# Monitoreo continuo (actualiza cada 30s)
./scripts/monitor-intelligent-scaling.sh --continuous

# Snapshot único del estado actual
./scripts/monitor-intelligent-scaling.sh --snapshot

# Ver solo eventos recientes
./scripts/monitor-intelligent-scaling.sh --events
```

### Métricas Clave a Observar

1. **Número de Réplicas vs. Tiempo**
   ```bash
   kubectl get deployment demo-microservice-production-istio -n default -w
   ```

2. **Utilización de CPU y Memoria**
   ```bash
   kubectl top pods -n default -l app=demo-microservice-istio
   ```

3. **Eventos de Escalado**
   ```bash
   kubectl get events -n default --sort-by='.lastTimestamp' | grep -E "ScaledObject|HorizontalPodAutoscaler"
   ```

4. **Estado de los HPAs**
   ```bash
   kubectl get hpa -n default -w
   ```

### Dashboard de ArgoCD

```bash
# Iniciar ArgoCD Dashboard
./scripts/start-argocd.sh

# Abrir en navegador: https://localhost:8081
# Usuario: admin
# Password: (mostrado en el script)
```

---

## 🧪 Plan de Validación de la PoC

### Semana 1-2: Observación y Recolección de Datos

#### Día 1-3: Validación de Comportamiento Básico
- [ ] Verificar que a las 6:00 AM escala a 3 pods
- [ ] Verificar que a las 10:00 PM evalúa las métricas
- [ ] Confirmar que no baja de 2 pods nunca
- [ ] Confirmar que no baja de 3 pods durante el día

#### Día 4-7: Validación de Decisiones Inteligentes
- [ ] Simular carga baja nocturna (< 50%) y verificar downscale
- [ ] Simular carga alta nocturna (>= 50%) y verificar que mantiene 3 pods
- [ ] Verificar la verificación de las 3:00 AM
- [ ] Medir tiempos de respuesta durante transiciones

#### Día 8-14: Validación de Rendimiento
- [ ] Medir latencia p95 durante todo el día
- [ ] Verificar que no hay degradación en horarios de transición
- [ ] Documentar eventos de escalado inesperados
- [ ] Calcular ahorro real de recursos

### Comandos de Simulación

```bash
# Simular carga alta (para probar que NO escala hacia abajo)
kubectl run load-generator --image=busybox --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://demo-microservice-istio.default.svc.cluster.local; done"

# Detener simulación de carga
kubectl delete pod load-generator

# Forzar evaluación inmediata (para pruebas)
kubectl patch scaledobject demo-microservice-intelligent-downscale -n default --type='json' -p='[{"op": "replace", "path": "/spec/pollingInterval", "value": 10}]'
```

---

## ✅ Criterios de Éxito

La PoC se considerará exitosa si:

1. **Ahorro de Recursos**
   - ✅ Reducción de al menos 20% en consumo nocturno
   - ✅ Pods se reducen a 2 durante horario de baja demanda

2. **Garantía de Rendimiento**
   - ✅ Latencia p95 se mantiene dentro del SLA
   - ✅ No hay degradación durante transiciones
   - ✅ Capacidad mínima garantizada a las 6:00 AM

3. **Decisiones Inteligentes**
   - ✅ No escala hacia abajo si la carga es alta
   - ✅ Responde rápidamente a picos de demanda
   - ✅ Estabilización adecuada (sin flapping)

4. **Operación Confiable**
   - ✅ Sin errores en logs de KEDA
   - ✅ HPAs funcionan correctamente
   - ✅ Transiciones suaves entre periodos

---

## 🔧 Troubleshooting

### Problema: ScaledObject no se crea

```bash
# Verificar que KEDA esté instalado
kubectl get deployment keda-operator -n keda

# Ver logs de KEDA
kubectl logs -n keda deployment/keda-operator
```

### Problema: No escala según el horario

```bash
# Verificar la zona horaria del cluster
kubectl get scaledobject demo-microservice-intelligent-upscale -n default -o yaml | grep timezone

# Verificar la hora actual en el pod de KEDA
kubectl exec -n keda deployment/keda-operator -- date
```

### Problema: Métricas no disponibles

```bash
# Verificar metrics-server
kubectl get deployment metrics-server -n kube-system

# Instalar metrics-server si no está
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Para Minikube, habilitar metrics-server
minikube addons enable metrics-server
```

### Problema: Conflicto entre los dos ScaledObjects

```bash
# Verificar que solo uno esté activo a la vez
kubectl get scaledobject -n default -o wide

# Ver eventos de conflicto
kubectl get events -n default | grep -i conflict
```

---

## 📝 Notas Importantes

### Consideraciones de Zona Horaria
- Los horarios están configurados para **America/Bogota (UTC-5)**
- **Horario de Prueba:** 5:00 PM - 6:00 PM (1 hora)
- Ajustar si el cluster está en otra zona horaria
- Verificar que KEDA soporte la zona horaria configurada

### Periodo de Estabilización
- **Downscale:** 10 minutos (600s) - Conservador para evitar flapping
- **Upscale:** Sin espera (0s) - Respuesta inmediata a demanda
- **Nota:** Con 1 hora de prueba, el downscale puede tardar hasta 10 minutos en activarse

### Umbrales de Escalado
- **Periodo 5PM-6PM:** CPU y Memoria < 50% para reducir
- **Resto del día:** CPU o Memoria > 70% para escalar más allá de 3 pods

### Interacción con ArgoCD
- ArgoCD gestiona los ScaledObjects como cualquier otro recurso
- Los cambios manuales serán revertidos por ArgoCD
- Para modificar, editar los archivos en `argocd-production/` y hacer commit

---

## 📚 Referencias

- [KEDA Documentation](https://keda.sh/docs/)
- [KEDA Cron Scaler](https://keda.sh/docs/scalers/cron/)
- [KEDA CPU Scaler](https://keda.sh/docs/scalers/cpu/)
- [KEDA Memory Scaler](https://keda.sh/docs/scalers/memory/)
- [HPA Behavior Configuration](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#configurable-scaling-behavior)

---

## 🎯 Próximos Pasos

1. **Desplegar la PoC**
   ```bash
   ./scripts/03-setup-argocd.sh
   ```

2. **Iniciar Monitoreo**
   ```bash
   ./scripts/monitor-intelligent-scaling.sh --continuous
   ```

3. **Observar Durante 2 Semanas**
   - Documentar comportamiento
   - Recolectar métricas
   - Ajustar umbrales si es necesario

4. **Evaluar Resultados**
   - Calcular ahorro real
   - Verificar cumplimiento de SLA
   - Decidir si se implementa en producción

---

**¡Buena suerte con la Prueba de Concepto! 🚀**
