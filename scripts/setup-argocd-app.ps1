# Script para configurar la aplicación en ArgoCD
# Crea la aplicación y configura el repositorio

param(
    [string]$AppName = "demo-microservice-app",
    [string]$Namespace = "demo-app", 
    [string]$RepoUrl = "https://github.com/your-org/demo-microservice-config.git",
    [string]$RepoPath = "k8s-manifests",
    [string]$TargetRevision = "HEAD",
    [string]$ArgocdNamespace = "argocd",
    [switch]$AutoSync = $true,
    [switch]$CreateNamespace = $true,
    [switch]$Verbose = $false
)

Write-Host "🚀 CONFIGURACIÓN DE APLICACIÓN EN ARGOCD" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""

Write-Host "📋 Configuración:" -ForegroundColor Cyan
Write-Host "  • Nombre de aplicación: $AppName" -ForegroundColor White
Write-Host "  • Namespace destino: $Namespace" -ForegroundColor White
Write-Host "  • Repositorio: $RepoUrl" -ForegroundColor White
Write-Host "  • Path en repo: $RepoPath" -ForegroundColor White
Write-Host "  • Revisión: $TargetRevision" -ForegroundColor White
Write-Host "  • Auto-sync: $AutoSync" -ForegroundColor White
Write-Host ""

# Verificar conexión a Kubernetes
try {
    Write-Host "🔍 Verificando conexión a Kubernetes..." -ForegroundColor Blue
    kubectl cluster-info | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "No hay conexión al cluster"
    }
    Write-Host "✅ Conexión a Kubernetes OK" -ForegroundColor Green
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Verificar que ArgoCD esté instalado
try {
    Write-Host "🔍 Verificando instalación de ArgoCD..." -ForegroundColor Blue
    kubectl get namespace $ArgocdNamespace | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Namespace de ArgoCD no encontrado: $ArgocdNamespace"
    }
    
    kubectl get deployment argocd-server -n $ArgocdNamespace | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ArgoCD no está instalado en el namespace $ArgocdNamespace"
    }
    
    Write-Host "✅ ArgoCD encontrado" -ForegroundColor Green
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Instala ArgoCD primero o verifica el namespace" -ForegroundColor Yellow
    exit 1
}

# Crear namespace destino si no existe
if ($CreateNamespace) {
    Write-Host "📁 Creando namespace destino..." -ForegroundColor Blue
    kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    Write-Host "✅ Namespace $Namespace listo" -ForegroundColor Green
}

# Crear manifiesto de aplicación ArgoCD
Write-Host "📝 Creando manifiesto de aplicación ArgoCD..." -ForegroundColor Blue

$appManifest = @"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $AppName
  namespace: $ArgocdNamespace
  labels:
    app: demo-microservice
    managed-by: argocd
    environment: production
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: '$RepoUrl'
    path: $RepoPath
    targetRevision: $TargetRevision
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: $Namespace
  syncPolicy:
$(if ($AutoSync) {
@"
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
"@
} else {
@"
    # Sync manual - cambiar a automated para auto-sync
"@
})
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    - RespectIgnoreDifferences=true
    - ApplyOutOfSyncOnly=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  revisionHistoryLimit: 10
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /metadata/annotations/deployment.kubernetes.io~1revision
    - /spec/replicas
  - group: ""
    kind: Service
    jsonPointers:
    - /spec/clusterIP
    - /spec/clusterIPs
    - /metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration
"@

# Guardar manifiesto temporal
$tempFile = [System.IO.Path]::GetTempFileName() + ".yaml"
$appManifest | Out-File -FilePath $tempFile -Encoding UTF8

Write-Host "✅ Manifiesto creado" -ForegroundColor Green

# Aplicar aplicación a ArgoCD
try {
    Write-Host "🚀 Aplicando aplicación a ArgoCD..." -ForegroundColor Blue
    
    kubectl apply -f $tempFile
    if ($LASTEXITCODE -ne 0) {
        throw "Error aplicando manifiesto de aplicación"
    }
    
    Write-Host "✅ Aplicación creada en ArgoCD" -ForegroundColor Green
    
    # Limpiar archivo temporal
    Remove-Item $tempFile -Force
    
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# Verificar estado de la aplicación
Write-Host ""
Write-Host "🔍 Verificando estado de la aplicación..." -ForegroundColor Blue

Start-Sleep -Seconds 5

try {
    $appStatus = kubectl get application $AppName -n $ArgocdNamespace -o jsonpath='{.status.sync.status}' 2>$null
    $healthStatus = kubectl get application $AppName -n $ArgocdNamespace -o jsonpath='{.status.health.status}' 2>$null
    
    Write-Host "📊 Estado de la aplicación:" -ForegroundColor Cyan
    Write-Host "  • Sync Status: $appStatus" -ForegroundColor White
    Write-Host "  • Health Status: $healthStatus" -ForegroundColor White
    
    if ($appStatus -eq "Synced") {
        Write-Host "  ✅ Aplicación sincronizada" -ForegroundColor Green
    } elseif ($appStatus -eq "OutOfSync") {
        Write-Host "  ⚠️  Aplicación fuera de sincronización" -ForegroundColor Yellow
        Write-Host "  Esto es normal si el repositorio aún no tiene manifiestos" -ForegroundColor Gray
    } else {
        Write-Host "  ℹ️  Estado: $appStatus" -ForegroundColor Blue
    }
    
} catch {
    Write-Host "⚠️  No se pudo obtener el estado (normal en primera ejecución)" -ForegroundColor Yellow
}

# Mostrar información de la aplicación
Write-Host ""
Write-Host "📋 Información de la aplicación:" -ForegroundColor Cyan
kubectl get application $AppName -n $ArgocdNamespace -o wide

# Configurar acceso a ArgoCD UI (si no está configurado)
Write-Host ""
Write-Host "🌐 Configurando acceso a ArgoCD UI..." -ForegroundColor Blue

# Verificar si ya hay un port-forward activo
$existingPortForward = Get-Process | Where-Object { $_.ProcessName -eq "kubectl" -and $_.CommandLine -like "*port-forward*argocd-server*" } 2>$null

if (-not $existingPortForward) {
    Write-Host "🔌 Iniciando port-forward para ArgoCD UI..." -ForegroundColor Blue
    Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "svc/argocd-server", "-n", $ArgocdNamespace, "8081:443" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    Write-Host "✅ Port-forward iniciado en puerto 8081" -ForegroundColor Green
} else {
    Write-Host "✅ Port-forward ya está activo" -ForegroundColor Green
}

# Obtener credenciales de ArgoCD
Write-Host ""
Write-Host "🔑 Obteniendo credenciales de ArgoCD..." -ForegroundColor Blue

try {
    $argocdPassword = kubectl get secret argocd-initial-admin-secret -n $ArgocdNamespace -o jsonpath='{.data.password}' | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
    
    Write-Host "✅ Credenciales obtenidas" -ForegroundColor Green
    
} catch {
    Write-Host "⚠️  No se pudieron obtener las credenciales automáticamente" -ForegroundColor Yellow
    $argocdPassword = "Ver documentación de ArgoCD"
}

# Resumen final
Write-Host ""
Write-Host "🎉 CONFIGURACIÓN COMPLETADA" -ForegroundColor Green
Write-Host "===========================" -ForegroundColor Green
Write-Host ""

Write-Host "✅ Aplicación '$AppName' creada en ArgoCD" -ForegroundColor Green
Write-Host "✅ Namespace '$Namespace' configurado" -ForegroundColor Green
Write-Host "✅ Auto-sync: $(if ($AutoSync) { 'Habilitado' } else { 'Deshabilitado' })" -ForegroundColor Green

Write-Host ""
Write-Host "🌐 Acceso a ArgoCD UI:" -ForegroundColor Cyan
Write-Host "  • URL: https://localhost:8081" -ForegroundColor White
Write-Host "  • Usuario: admin" -ForegroundColor White
Write-Host "  • Password: $argocdPassword" -ForegroundColor White
Write-Host "  • Aplicación: $AppName" -ForegroundColor White

Write-Host ""
Write-Host "🚀 Próximos pasos:" -ForegroundColor Cyan
Write-Host "  1. Abrir ArgoCD UI: https://localhost:8081" -ForegroundColor White
Write-Host "  2. Buscar la aplicación: $AppName" -ForegroundColor White
Write-Host "  3. Configurar el repositorio con manifiestos procesados" -ForegroundColor White
Write-Host "  4. Ejecutar primer deployment:" -ForegroundColor White
Write-Host "     .\scripts\build-and-deploy.ps1 -Version 'v-1-0-0'" -ForegroundColor Gray

Write-Host ""
Write-Host "🔧 Comandos útiles:" -ForegroundColor Cyan
Write-Host "  • Ver aplicaciones: kubectl get applications -n $ArgocdNamespace" -ForegroundColor Gray
Write-Host "  • Sync manual: kubectl patch application $AppName -n $ArgocdNamespace --type merge -p '{\"operation\":{\"sync\":{\"revision\":\"HEAD\"}}}'" -ForegroundColor Gray
Write-Host "  • Ver logs de ArgoCD: kubectl logs -n $ArgocdNamespace -l app.kubernetes.io/name=argocd-server -f" -ForegroundColor Gray

if ($Verbose) {
    Write-Host ""
    Write-Host "📄 Manifiesto aplicado:" -ForegroundColor Gray
    Write-Host $appManifest -ForegroundColor DarkGray
}