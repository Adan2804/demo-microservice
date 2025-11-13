# ArgoCD KEDA - Escalado Inteligente con Zero Downtime

Esta carpeta contiene los manifiestos para una aplicación separada de ArgoCD que gestiona el escalado inteligente con KEDA, configurada para **ZERO DOWNTIME** durante los syncs.

## 🎯 Características Principales

✅ **Zero Downtime** - Nunca 0 pods durante syncs de ArgoCD
✅ **KEDA Integration** - Escalado automático por horario
✅ **PodDisruptionBudget** - Garantiza disponibilidad mínima
✅ **Graceful Shutdown** - Terminación ordenada de pods
✅ **ArgoCD Optimizado** - Configuración para evitar conflictos

## 📁 Arquitectura

```
argocd-production/          → Aplicación principal (sin HPA)
  ├── Deployment: demo-microservice-production-istio
  ├── Service: demo-microservice-istio
  └── VirtualServices, DestinationRules, etc.

argocd-keda/               → Aplicación de escalado (con KEDA + Zero Downtime)
  ├── 01-deployment-with-hpa.yaml      → Deployment con rolling update seguro
  ├── 02-service.yaml                  → Service
  ├── 03-scaled-object.yaml            → ScaledObject de KEDA
  ├── 04-pdb.yaml                      → PodDisruptionBudget (NUEVO)
  └── instructivo-argocd-zero-downtime.md → Guía completa

scripts/
  └── setup-argocd-keda.sh             → Script de instalación automática
```

## 📋 Componentes

### 01-deployment-with-hpa.yaml ✅ ACTUALIZADO
**Configuración Zero Downtime:**
- ✅ `maxUnavailable: 0` - Nunca 0 pods disponibles
- ✅ `maxSurge: 1` - Permite 1 pod extra durante actualización
- ✅ `minReadySeconds: 10` - Espera antes de considerar ready
- ✅ `progressDeadlineSeconds: 600` - Timeout de 10 minutos
- ✅ `readinessProbe.successThreshold: 2` - Debe pasar 2 veces
- ✅ `lifecycle.preStop` - Graceful shutdown (15s)
- ✅ `terminationGracePeriodSeconds: 30` - Tiempo para terminar

### 02-service.yaml
- Service para el deployment de KEDA
- Nombre: `demo-microservice-keda`
- Port: 8080

### 03-scaled-object.yaml ✅ ACTUALIZADO
**Configuración de KEDA:**
- ✅ `minReplicaCount: 2` - NUNCA menos de 2 pods
- ✅ `maxReplicaCount: 10` - Máximo 10 pods
- ✅ Horarios configurados:
  - 5:55 PM - 6:00 PM: 2 pods (downscale)
  - 6:00 PM - 5:55 PM: 3 pods (normal)
- ✅ Behavior optimizado para escalado gradual

### 04-pdb.yaml 🆕 NUEVO
**PodDisruptionBudget:**
- Garantiza `minAvailable: 1` pod siempre
- Protege contra:
  - Rolling updates
  - Syncs de ArgoCD
  - Escalado de KEDA
  - Mantenimiento del cluster

### 05-argocd-application.yaml 🆕 NUEVO
**Application de ArgoCD:**
- ✅ `ignoreDifferences` para réplicas (KEDA las gestiona)
- ✅ `syncOptions` optimizadas para zero downtime
- ✅ `automated.selfHeal` para auto-corrección
- ✅ `retry` con backoff exponencial

## 🚀 Instalación Rápida

### Opción 1: Usando el Script (RECOMENDADO)

```bash
# Ejecutar el script de configuración
./scripts/setup-argocd-keda.sh
```

**El script automáticamente:**
- ✅ Instala ArgoCD si no está instalado
- ✅ Verifica prerequisitos (Kubernetes, KEDA)
- ✅ Crea la Application de ArgoCD con configuración Zero Downtime
- ✅ Configura `ignoreDifferences` para réplicas
- ✅ Habilita auto-sync y self-heal
- ✅ Hace el sync inicial
- ✅ Configura port-forward para ArgoCD (puerto 8081)
- ✅ Configura port-forward para el microservicio (puerto 8082)
- ✅ Crea script de monitoreo
- ✅ Muestra credenciales y resumen completo

**Acceso después de la instalación:**
- ArgoCD UI: https://localhost:8081
- Microservicio: http://localhost:8082/actuator/health

### Opción 2: Aplicación Manual (sin ArgoCD)

```bash
# Aplicar todos los manifiestos en orden
kubectl apply -f argocd-keda/01-deployment-with-hpa.yaml
kubectl apply -f argocd-keda/02-service.yaml
kubectl apply -f argocd-keda/04-pdb.yaml
kubectl apply -f argocd-keda/03-scaled-object.yaml

# Verificar
kubectl get all,pdb,scaledobject -n default -l app=demo-microservice-keda
```

### Opción 3: Crear Application manualmente en ArgoCD UI

1. **Ir a ArgoCD UI** → Applications → New App
2. **Configurar:**
   - Application Name: `demo-microservice-keda`
   - Project: `default`
   - Sync Policy: `Automatic`
   - Repository URL: `https://github.com/Adan2804/demo-microservice.git`
   - Path: `argocd-keda`
   - Cluster: `https://kubernetes.default.svc`
   - Namespace: `default`
3. **Sync Options:**
   - ✅ Auto-Create Namespace
   - ✅ Prune Resources
   - ✅ Self Heal
4. **Ignore Differences:**
   - Group: `apps`, Kind: `Deployment`, JSONPath: `/spec/replicas`
   - Group: `keda.sh`, Kind: `ScaledObject`, JSONPath: `/status`
5. **Click "CREATE"**

## ✅ Ventajas de esta Arquitectura

### Zero Downtime Garantizado
- ✅ `maxUnavailable: 0` en el deployment
- ✅ `minAvailable: 1` en el PDB
- ✅ `minReplicaCount: 2` en KEDA
- ✅ Graceful shutdown con preStop hook
- ✅ Readiness probe con successThreshold: 2

### Separación de Responsabilidades
- ✅ `argocd-production`: Gestiona la aplicación principal
- ✅ `argocd-keda`: Gestiona solo el escalado
- ✅ No interfiere con producción
- ✅ Fácil de activar/desactivar

### Integración ArgoCD + KEDA
- ✅ `ignoreDifferences` para evitar OutOfSync
- ✅ KEDA gestiona réplicas dinámicamente
- ✅ ArgoCD respeta los cambios de KEDA
- ✅ Self-heal sin conflictos

## 📊 Monitoreo

```bash
# Ver todo el estado
kubectl get all,pdb,scaledobject,hpa -n default -l app=demo-microservice-keda

# Monitorear pods en tiempo real
kubectl get pods -n default -l app=demo-microservice-keda -w

# Ver estado de KEDA
kubectl describe scaledobject demo-microservice-keda-scaler -n default

# Ver HPA generado por KEDA
kubectl get hpa demo-microservice-keda-hpa -n default

# Ver logs de KEDA operator
kubectl logs -n keda -l app=keda-operator --tail=50 -f

# Ver estado en ArgoCD
argocd app get argocd-keda
```

## 🧪 Pruebas Recomendadas

Ver el archivo `instructivo-argocd-zero-downtime.md` para:
- ✅ Pruebas de sync manual
- ✅ Pruebas de self-heal
- ✅ Pruebas de cambio de imagen
- ✅ Pruebas de escalado de KEDA
- ✅ Pruebas de carga durante sync

## 🔄 Migración a Producción

Cuando estés listo para usar KEDA en producción:

1. **Validar en DEV/QA primero:**
   ```bash
   # Realizar 5-10 syncs exitosos
   # Verificar que no haya downtime
   # Validar que KEDA escala correctamente
   ```

2. **Aplicar en producción:**
   - Opción A: Mantener deployment separado
   - Opción B: Integrar en `argocd-production/`

3. **Si integras en argocd-production:**
   ```bash
   # Copiar archivos necesarios
   cp 04-pdb.yaml ../argocd-production/
   cp 03-scaled-object.yaml ../argocd-production/
   
   # Actualizar scaleTargetRef en scaled-object.yaml
   # Cambiar: demo-microservice-keda
   # Por: demo-microservice-production-istio
   
   # Actualizar Application de ArgoCD principal
   # Agregar ignoreDifferences para /spec/replicas
   ```
