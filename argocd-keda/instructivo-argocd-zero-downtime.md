# 🚀 Instrucciones para Pruebas en ArgoCD-KEDA con Zero Downtime

## 🎯 Objetivo
Realizar pruebas de sincronización en ArgoCD con KEDA sin que los pods se caigan y sin perder conexión durante minutos mientras se recargan.

## 📁 Estructura de Archivos

```
argocd-keda/
├── 01-deployment-with-hpa.yaml    ← Deployment con configuración zero downtime
├── 02-service.yaml                ← Service para el deployment
├── 03-scaled-object.yaml          ← ScaledObject de KEDA
├── 04-pdb.yaml                    ← PodDisruptionBudget (NUEVO)
└── instructivo-argocd-zero-downtime.md
```

## ✅ Configuraciones Necesarias

### 1. Archivo: `01-deployment-with-hpa.yaml`
**Modificaciones críticas para ArgoCD con Zero Downtime:**
- ✅ `maxUnavailable: 0` - Nunca 0 pods disponibles durante sync
- ✅ `maxSurge: 1` - Permite crear 1 pod extra durante actualización
- ✅ `progressDeadlineSeconds: 600` - Timeout de 10 minutos
- ✅ `minReadySeconds: 10` - Esperar 10s antes de considerar ready
- ✅ `readinessProbe.successThreshold: 2` - Debe pasar 2 veces seguidas
- ✅ `readinessProbe.periodSeconds: 5` - Verificar cada 5 segundos
- ✅ `lifecycle.preStop` - Graceful shutdown (esperar 15s)
- ✅ `terminationGracePeriodSeconds: 30` - Tiempo para terminar correctamente

### 2. Archivo: `04-pdb.yaml` (PodDisruptionBudget) - NUEVO
**Propósito:** Garantizar que siempre haya al menos 1 pod disponible durante el sync de ArgoCD

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: demo-microservice-keda-pdb
  namespace: default
  labels:
    app: demo-microservice-keda
    managed-by: argocd-keda
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: demo-microservice-keda
      version: stable
```

### 3. Archivo: `03-scaled-object.yaml`
**Configuración de KEDA con ignoreDifferences para ArgoCD:**

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: demo-microservice-keda-scaler
  namespace: default
  annotations:
    scaledobject.keda.sh/transfer-hpa-ownership: "true"
spec:
  scaleTargetRef:
    name: demo-microservice-keda
  minReplicaCount: 2
  maxReplicaCount: 10
  # ... resto de configuración
```

### 4. Configuración de ArgoCD Application
**En el archivo de Application, agregar:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd-keda
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <tu-repo>
    targetRevision: HEAD
    path: demo-microservice/argocd-keda
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - RespectIgnoreDifferences=true
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
  - group: keda.sh
    kind: ScaledObject
    jsonPointers:
    - /status
```

## 🚀 Instalación Inicial

### Opción Recomendada: Usar el Script

```bash
# Ejecutar el script de configuración
./scripts/setup-argocd-keda.sh
```

El script configura automáticamente:
- ✅ Application de ArgoCD con Zero Downtime
- ✅ ignoreDifferences para réplicas (KEDA las gestiona)
- ✅ Auto-sync y self-heal
- ✅ Retry con backoff exponencial
- ✅ Script de monitoreo

## 📋 Pasos para Pruebas en ArgoCD-KEDA

### PASO 1: Verificar Estado Inicial

Antes de hacer cualquier cambio, verificar el estado actual:

```bash
# Ver estado de la aplicación en ArgoCD
argocd app get argocd-keda

# Ver pods actuales
kubectl get pods -n default -l app=demo-microservice-keda

# Verificar que el PDB existe
kubectl get pdb -n default

# Verificar ScaledObject de KEDA
kubectl get scaledobject -n default

# Verificar HPA generado por KEDA
kubectl get hpa -n default
```

**Estado esperado:**
- Application: `Synced` y `Healthy`
- Pods: Al menos 2 en estado `Running`
- PDB: Debe existir con `minAvailable: 1`
- ScaledObject: `Ready: True`
- HPA: Creado automáticamente por KEDA

### PASO 2: Preparar el Sync (Método Manual)

Si vas a hacer sync manual desde la UI de ArgoCD:

1. Ir a la aplicación en ArgoCD UI
2. Click en **"APP DIFF"** para ver los cambios
3. Click en **"SYNC"**
4. **IMPORTANTE:** Seleccionar estas opciones:
   - ✅ `PRUNE` - Eliminar recursos obsoletos
   - ✅ `APPLY ONLY OUT OF SYNC` - Solo aplicar lo que cambió
   - ⚠️ **NO seleccionar** `FORCE` - Esto causaría recreación de pods
5. Click en **"SYNCHRONIZE"**

### PASO 3: Monitorear el Sync en Tiempo Real

Abrir 3 terminales para monitoreo simultáneo:

**Terminal 1 - Ver pods:**
```bash
kubectl get pods -n #{namespace}# -l pod=#{service}#-pod -w
```

**Terminal 2 - Ver eventos:**
```bash
kubectl get events -n #{namespace}# --sort-by='.lastTimestamp' -w | grep #{service}#
```

**Terminal 3 - Ver estado de ArgoCD:**
```bash
watch -n 2 "argocd app get #{service}# | grep -E 'Health Status|Sync Status'"
```

### PASO 4: Verificar el Rolling Update

Durante el sync, deberías ver esta secuencia:

**Fase 1 - Estado inicial:**
```
NAME                                          READY   STATUS
demo-microservice-keda-abc123                 1/1     Running
demo-microservice-keda-def456                 1/1     Running
demo-microservice-keda-ghi789                 1/1     Running
```

**Fase 2 - Creando nuevo pod:**
```
demo-microservice-keda-abc123                 1/1     Running
demo-microservice-keda-def456                 1/1     Running
demo-microservice-keda-ghi789                 1/1     Running
demo-microservice-keda-xyz000                 0/1     ContainerCreating  ← NUEVO
```

**Fase 3 - Nuevo pod listo:**
```
demo-microservice-keda-abc123                 1/1     Running
demo-microservice-keda-def456                 1/1     Running
demo-microservice-keda-ghi789                 1/1     Running
demo-microservice-keda-xyz000                 1/1     Running  ← READY!
```

**Fase 4 - Terminando pod viejo:**
```
demo-microservice-keda-abc123                 1/1     Terminating  ← Esperando preStop (15s)
demo-microservice-keda-def456                 1/1     Running
demo-microservice-keda-ghi789                 1/1     Running
demo-microservice-keda-xyz000                 1/1     Running
```

**Fase 5 - Completado:**
```
demo-microservice-keda-def456                 1/1     Running
demo-microservice-keda-ghi789                 1/1     Running
demo-microservice-keda-xyz000                 1/1     Running
```

**✅ NUNCA verás 0 pods en estado Running**
**✅ KEDA respeta el PDB y no escala a 0 durante el sync**

### PASO 5: Health Check Post-Sync

Después del sync, verificar conectividad:

```bash
# Health check del servicio
kubectl exec -n default deploy/demo-microservice-keda -- curl -f http://localhost:8080/actuator/health

# Verificar logs del nuevo pod
kubectl logs -n default -l app=demo-microservice-keda --tail=50

# Verificar métricas
kubectl top pods -n default -l app=demo-microservice-keda

# Verificar que KEDA sigue funcionando
kubectl get scaledobject demo-microservice-keda-scaler -n default -o yaml

# Verificar HPA generado por KEDA
kubectl describe hpa demo-microservice-keda-hpa -n default
```

## 🧪 Pruebas Recomendadas

### Prueba 1: Sync Manual con Cambio Menor
1. Cambiar una variable de entorno en el deployment:
   ```yaml
   # En 01-deployment-with-hpa.yaml
   - name: APP_VERSION
     value: "stable-v1.0.1-keda"  # Cambiar versión
   ```
2. Hacer sync manual desde ArgoCD UI
3. Verificar que no haya downtime

### Prueba 2: Sync Automático (Self-Heal)
1. Hacer un cambio directamente en el cluster:
   ```bash
   kubectl scale deployment demo-microservice-keda -n default --replicas=5
   ```
2. ArgoCD debería detectar el drift y hacer self-heal
3. KEDA volverá a gestionar las réplicas según el horario
4. Verificar que no haya downtime durante el proceso

### Prueba 3: Sync con Cambio de Imagen
1. Actualizar la versión de la imagen en el deployment:
   ```yaml
   image: zadan04/demo-microservice:v2.0.0
   ```
2. Hacer sync desde ArgoCD
3. Monitorear el rolling update completo
4. Verificar que KEDA respeta el PDB

### Prueba 4: Prueba de Escalado de KEDA Durante Sync
1. Esperar a que KEDA cambie las réplicas (5:55 PM o 6:00 PM)
2. Hacer un sync de ArgoCD durante el escalado
3. Verificar que ambos procesos coexisten sin conflictos
4. Verificar que no haya downtime

### Prueba 5: Prueba de Carga Durante Sync
1. Iniciar prueba de carga:
   ```bash
   # Usando kubectl port-forward
   kubectl port-forward -n default svc/demo-microservice-keda 8080:8080
   
   # En otra terminal, generar carga
   while true; do curl http://localhost:8080/actuator/health; sleep 0.1; done
   ```
2. Hacer sync mientras la prueba corre
3. Verificar que no haya errores de conexión

## 🚨 Troubleshooting

### Problema: El sync se queda en "Progressing"

**Diagnóstico:**
```bash
# Ver estado del deployment
kubectl rollout status deployment/demo-microservice-keda -n default

# Ver por qué el pod no está ready
kubectl describe pod -n default -l app=demo-microservice-keda

# Ver logs del pod
kubectl logs -n default -l app=demo-microservice-keda --tail=100
```

**Solución:**
- Si el readiness probe falla, revisar el endpoint `/actuator/health`
- Si el pod no inicia, revisar recursos (CPU/Memory limits)
- Si hay error de imagen, verificar el registry

### Problema: ArgoCD muestra "OutOfSync" constantemente

**Diagnóstico:**
```bash
# Ver diferencias
argocd app diff argocd-keda
```

**Solución:**
- KEDA modifica las réplicas del deployment dinámicamente
- Ya está configurado en el Application con `ignoreDifferences`:

```yaml
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
  - group: keda.sh
    kind: ScaledObject
    jsonPointers:
    - /status
```

### Problema: KEDA y ArgoCD entran en conflicto

**Diagnóstico:**
```bash
# Ver eventos de KEDA
kubectl get events -n default | grep ScaledObject

# Ver logs de KEDA operator
kubectl logs -n keda -l app=keda-operator --tail=50

# Ver estado del ScaledObject
kubectl describe scaledobject demo-microservice-keda-scaler -n default
```

**Solución:**
- Verificar que `ignoreDifferences` incluya `/spec/replicas`
- Verificar annotation `scaledobject.keda.sh/transfer-hpa-ownership: "true"`
- No modificar réplicas manualmente, dejar que KEDA las gestione

### Problema: Pods se caen durante el sync

**Diagnóstico:**
```bash
# Verificar PDB
kubectl get pdb demo-microservice-keda-pdb -n default -o yaml

# Ver eventos de eviction
kubectl get events -n default | grep Evicted

# Ver si KEDA está escalando a 0
kubectl get hpa demo-microservice-keda-hpa -n default
```

**Solución:**
- Verificar que `maxUnavailable: 0` esté configurado en el deployment
- Verificar que el PDB tenga `minAvailable: 1`
- Verificar que `minReplicaCount: 2` en el ScaledObject (nunca 0)
- Revisar que no haya `FORCE` sync habilitado en ArgoCD

### Problema: Timeout durante el sync

**Diagnóstico:**
```bash
# Ver timeout de ArgoCD
argocd app get argocd-keda -o yaml | grep timeout

# Ver progreso del deployment
kubectl rollout status deployment/demo-microservice-keda -n default --timeout=10m
```

**Solución:**
- Aumentar `progressDeadlineSeconds: 600` en el deployment
- Aumentar timeout en ArgoCD Application
- Revisar si los probes son muy estrictos (initialDelaySeconds, timeoutSeconds)

## ✅ Checklist de Validación

Después de cada prueba, verificar:

- [ ] ArgoCD muestra `Synced` y `Healthy`
- [ ] Todos los pods en estado `Running`
- [ ] Health check responde 200 OK
- [ ] No hubo errores 503/504 durante el sync
- [ ] El tiempo de sync fue razonable (2-5 minutos)
- [ ] Los logs no muestran errores de conexión
- [ ] Las métricas de KEDA/HPA funcionan correctamente
- [ ] El PDB está activo y respetado

## 📊 Métricas Esperadas

- **Downtime durante sync:** 0 segundos
- **Tiempo de sync:** 2-5 minutos
- **Pods simultáneos durante sync:** 3 (2 viejos + 1 nuevo)
- **Errores HTTP:** 0
- **Tiempo de readiness del nuevo pod:** 20-30 segundos

## 🎯 Estrategia de Rollout Progresivo

### Fase 1: DEV (Pruebas iniciales)
1. ✅ Aplicar configuraciones de zero downtime
2. ✅ Realizar 3-5 syncs manuales
3. ✅ Habilitar auto-sync y probar self-heal
4. ✅ Realizar prueba de carga durante sync

### Fase 2: QA (Validación)
1. ✅ Replicar configuraciones de DEV
2. ✅ Realizar 2-3 syncs manuales
3. ✅ Validar con equipo de QA

### Fase 3: PROD (Implementación)
1. ✅ Aplicar en horario de bajo tráfico
2. ✅ Monitoreo intensivo durante primer sync
3. ✅ Habilitar auto-sync después de validación

## 🔧 Comandos Útiles de ArgoCD

```bash
# Ver aplicaciones
argocd app list

# Ver detalles de una app
argocd app get #{service}#

# Hacer sync manual
argocd app sync #{service}# --prune

# Ver diferencias
argocd app diff #{service}#

# Ver historial de syncs
argocd app history #{service}#

# Rollback a versión anterior
argocd app rollback #{service}# <revision-number>

# Ver logs de sync
argocd app logs #{service}# --follow

# Forzar refresh (sin sync)
argocd app get #{service}# --refresh
```

## 📝 Notas Importantes

1. **NUNCA usar `FORCE` sync** a menos que sea absolutamente necesario - esto recrea los pods
2. **Siempre tener PDB configurado** antes de habilitar auto-sync
3. **Monitorear el primer sync** de cada ambiente intensivamente
4. **Configurar alertas** en ArgoCD para sync failures
5. **Documentar cualquier issue** encontrado durante las pruebas

**¡Listo para probar en ArgoCD sin downtime!** 🚀
