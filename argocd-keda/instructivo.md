# 🚀 Instrucciones para Deploy en DEV con Zero Downtime

## ✅ Cambios Realizados

### 1. Archivo: `deployment-probes-channel-v2.yaml`
**Modificaciones:**
- ✅ `maxUnavailable: 0` - Nunca 0 pods disponibles
- ✅ `progressDeadlineSeconds: 600` - Timeout de 10 minutos
- ✅ `minReadySeconds: 10` - Esperar 10s antes de considerar ready
- ✅ `readinessProbe.successThreshold: 2` - Debe pasar 2 veces seguidas
- ✅ `readinessProbe.periodSeconds: 5` - Verificar cada 5 segundos
- ✅ `lifecycle.preStop` - Graceful shutdown (esperar 15s)
- ✅ `terminationGracePeriodSeconds: 30` - Tiempo para terminar correctamente

### 2. Archivo NUEVO: `pdb.yaml`
**Propósito:** Garantizar que siempre haya al menos 1 pod disponible

## 📋 Pasos en Azure DevOps Release

### PASO 1: Agregar PDB al Stage de Deploy DEV

En tu Release Pipeline, en el stage "Deploy DEV", **ANTES** del task "kubectl apply deployment":

1. Ir a: **Pipelines → Releases → Editar Release-19**

2. En el stage **"Deploy DEV"**, agregar un nuevo task:
   - **Tipo:** Kubectl
   - **Nombre:** "kubectl apply pdb"
   - **Posición:** ANTES de "kubectl apply deployment"
   - **Command:** apply
   - **Arguments:** `-f $(System.DefaultWorkingDirectory)/_NU0621001_super_app_p_CH_MR_ch_ms_transa/trunk/deployment/prueba/pdb.yaml`

3. El orden debe quedar así:
   ```
   1. Replace tokens in *.yaml
   2. kubernetes files replaced
   3. kubectl apply configmap
   4. kubectl apply pdb          ← NUEVO
   5. kubectl apply deployment
   6. kubectl apply service
   7. kubectl apply virtual service
   8. kubectl apply gateway
   9. kubectl apply hpa
   10. wait for deployment
   ```

### PASO 2: Modificar el Task "wait for deployment"

Cambiar el comando actual por:

**Command:** `rollout`
**Arguments:** `status deployment/#{service}#-deployment -n #{namespace}# --timeout=10m`

Esto esperará a que el rolling update complete correctamente.

### PASO 3: Agregar Health Check (Opcional pero recomendado)

Después de "wait for deployment", agregar un task de PowerShell:

**Display name:** Health Check
**Type:** Inline
**Script:**
```powershell
Write-Host "🏥 Ejecutando health check..."

$maxAttempts = 5
$attempt = 0
$success = $false

while ($attempt -lt $maxAttempts -and -not $success) {
    $attempt++
    Write-Host "Intento $attempt de $maxAttempts..."
    
    try {
        $response = Invoke-WebRequest -Uri "https://canalpersonas-int-dev.apps.ambientesbc.com/super-svp/api/v1/ch-ms-cross-catalogues/health/readiness" -UseBasicParsing
        
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ Health check exitoso!"
            $success = $true
        }
    }
    catch {
        Write-Host "⚠️ Health check falló, reintentando..."
        Start-Sleep -Seconds 10
    }
}

if (-not $success) {
    Write-Host "❌ Health checks fallaron"
    exit 1
}

Write-Host "✅ Despliegue completado exitosamente"
```

## 🧪 Cómo Probar en DEV

### 1. Ejecutar el Release
- Seleccionar el artefacto (como siempre)
- Hacer clic en "Deploy" para DEV
- Observar los logs

### 2. Monitorear en Tiempo Real (Opcional)

Abrir una terminal y ejecutar:

```bash
# Ver pods en tiempo real
kubectl get pods -n super-svp-dev -l pod=ch-ms-cross-catalogues-pod -w

# En otra terminal, ver eventos
kubectl get events -n super-svp-dev --sort-by='.lastTimestamp' -w
```

### 3. Qué Deberías Ver

**Antes del despliegue:**
```
NAME                                          READY   STATUS
ch-ms-cross-catalogues-deployment-old-abc     1/1     Running
ch-ms-cross-catalogues-deployment-old-def     1/1     Running
```

**Durante el despliegue (Paso 1):**
```
ch-ms-cross-catalogues-deployment-old-abc     1/1     Running
ch-ms-cross-catalogues-deployment-old-def     1/1     Running
ch-ms-cross-catalogues-deployment-new-xyz     0/1     ContainerCreating  ← NUEVO
```

**Durante el despliegue (Paso 2):**
```
ch-ms-cross-catalogues-deployment-old-abc     1/1     Running
ch-ms-cross-catalogues-deployment-old-def     1/1     Running
ch-ms-cross-catalogues-deployment-new-xyz     1/1     Running  ← READY!
```

**Durante el despliegue (Paso 3):**
```
ch-ms-cross-catalogues-deployment-old-def     1/1     Running
ch-ms-cross-catalogues-deployment-new-xyz     1/1     Running
ch-ms-cross-catalogues-deployment-new-www     0/1     ContainerCreating  ← NUEVO
```

**Después del despliegue:**
```
ch-ms-cross-catalogues-deployment-new-xyz     1/1     Running
ch-ms-cross-catalogues-deployment-new-www     1/1     Running
```

**✅ NUNCA verás 0 pods en estado Running**

## 🚨 Qué Hacer Si Falla

### Si el despliegue se queda "stuck":

1. **Ver logs del pod nuevo:**
   ```bash
   kubectl logs -n super-svp-dev <pod-name>
   ```

2. **Ver por qué no pasa readiness:**
   ```bash
   kubectl describe pod -n super-svp-dev <pod-name>
   ```

3. **Rollback manual:**
   ```bash
   kubectl rollout undo deployment/ch-ms-cross-catalogues-deployment -n super-svp-dev
   ```

### Si el health check falla:

- Verificar que el endpoint `/health/readiness` responda 200
- Verificar que el pod esté realmente ready
- Revisar logs de la aplicación

## ✅ Validación de Éxito

Después del despliegue, verificar:

- [ ] Todos los pods en estado `Running`
- [ ] Health check pasa
- [ ] No hubo errores 503/504 durante el despliegue
- [ ] El tiempo de despliegue fue ~2-5 minutos
- [ ] Los logs no muestran errores

## 📊 Métricas Esperadas

- **Downtime:** 0 segundos
- **Tiempo de despliegue:** 2-5 minutos
- **Pods simultáneos durante despliegue:** 3 (2 viejos + 1 nuevo)
- **Errores HTTP:** 0

## 🎯 Próximos Pasos

Una vez que funcione en DEV:

1. ✅ Probar 2-3 despliegues más en DEV
2. ✅ Aplicar los mismos cambios en QA
3. ✅ Probar en QA
4. ✅ Aplicar en PROD

**¡Listo para probar en DEV!** 🚀
