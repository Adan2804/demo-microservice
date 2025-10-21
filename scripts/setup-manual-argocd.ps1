# Script para configurar ArgoCD con SYNC MANUAL
# Para pruebas controladas sin auto-sync

param(
    [string]$AppName = "demo-microservice-versioned-app",
    [string]$Namespace = "demo-app", 
    [string]$RepoUrl = "https://github.com/Adan2804/demo-microservice-config.git",
    [string]$RepoPath = "k8s-versioned-manifests-processed",
    [string]$TargetRevision = "HEAD",
    [string]$ArgocdNamespace = "argocd",
    [switch]$CreateNamespace = $true,
    [switch]$Verbose = $false
)

Write-Host "🚀 CONFIGURACIÓN DE ARGOCD - SYNC MANUAL" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""

Write-Host "📋 Configuración:" -ForegroundColor Cyan
Write-Host "  • Nombre de aplicación: $AppName" -ForegroundColor White
Write-Host "  • Namespace destino: $Namespace" -ForegroundColor White
Write-Host "  • Repositorio: $RepoUrl" -ForegroundColor White
Write-Host "  • Path en repo: $RepoPath" -ForegroundColor White
Write-Host "  • Sync Mode: MANUAL (sin auto-sync)" -ForegroundColor Yellow
Write-Host ""

# Verificar conexión a Kubernetes y ArgoCD
try {
    Write-Host "🔍 Verificando conexión a Kubernetes..." -ForegroundColor Blue
    kubectl cluster-info | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "No hay conexión al cluster"
    }
    
    Write-Host "🔍 Verificando ArgoCD..." -ForegroundColor Blue
    kubectl get deployment argocd-server -n $ArgocdNamespace | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ArgoCD no está instalado en el namespace $ArgocdNamespace"
    }
    
    Write-Host "✅ Verificaciones OK" -ForegroundColor Green
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Crear namespace destino si no existe
if ($CreateNamespace) {
    Write-Host "📁 Creando namespace destino..." -ForegroundColor Blue
    kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    Write-Host "✅ Namespace $Namespace listo" -ForegroundColor Green
}

# Eliminar aplicación anterior si existe
Write-Host "🧹 Limpiando aplicación anterior..." -ForegroundColor Blue
kubectl delete application $AppName -n $ArgocdNamespace --ignore-not-found=true
kubectl delete application demo-microservice-app -n $ArgocdNamespace --ignore-not-found=true
Start-Sleep -Seconds 5

# Crear manifiesto de aplicación ArgoCD con SYNC MANUAL
Write-Host "📝 Creando aplicación ArgoCD con sync manual..." -ForegroundColor Blue

$appManifest = @"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $AppName
  namespace: $ArgocdNamespace
  labels:
    app: demo-microservice-versioned
    managed-by: argocd
    sync-mode: manual
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
    # SYNC MANUAL - Comentado para evitar auto-sync
    # automated:
    #   prune: true
    #   selfHeal: true
    #   allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    - RespectIgnoreDifferences=true
    - ApplyOutOfSyncOnly=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 1m
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

# Guardar y aplicar manifiesto
$tempFile = [System.IO.Path]::GetTempFileName() + ".yaml"
$appManifest | Out-File -FilePath $tempFile -Encoding UTF8

try {
    kubectl apply -f $tempFile
    if ($LASTEXITCODE -ne 0) {
        throw "Error aplicando manifiesto de aplicación"
    }
    
    Write-Host "✅ Aplicación creada en ArgoCD (SYNC MANUAL)" -ForegroundColor Green
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
    
    if ($appStatus -eq "OutOfSync" -or $appStatus -eq "Unknown") {
        Write-Host "  ✅ Estado correcto para sync manual" -ForegroundColor Green
        Write-Host "  La aplicación esperará sync manual" -ForegroundColor Gray
    } else {
        Write-Host "  ℹ️  Estado: $appStatus" -ForegroundColor Blue
    }
    
} catch {
    Write-Host "⚠️  No se pudo obtener el estado (normal en primera ejecución)" -ForegroundColor Yellow
}

# Configurar acceso a ArgoCD UI
Write-Host ""
Write-Host "🌐 Configurando acceso a ArgoCD UI..." -ForegroundColor Blue

$existingPortForward = Get-Process | Where-Object { $_.ProcessName -eq "kubectl" -and $_.CommandLine -like "*port-forward*argocd-server*" } 2>$null

if (-not $existingPortForward) {
    Write-Host "🔌 Iniciando port-forward para ArgoCD..." -ForegroundColor Blue
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

# Crear scripts de gestión manual
Write-Host ""
Write-Host "📝 Creando scripts de gestión manual..." -ForegroundColor Blue

# Script para sync manual
$syncScript = @"
# Script para hacer sync manual de ArgoCD
Write-Host "🔄 SYNC MANUAL DE ARGOCD" -ForegroundColor Green
Write-Host "========================" -ForegroundColor Green

Write-Host "📊 Estado actual:" -ForegroundColor Cyan
kubectl get application $AppName -n $ArgocdNamespace

Write-Host ""
Write-Host "🚀 Ejecutando sync manual..." -ForegroundColor Blue
kubectl patch application $AppName -n $ArgocdNamespace --type merge -p '{\"operation\":{\"sync\":{\"revision\":\"HEAD\"}}}'

Write-Host ""
Write-Host "⏳ Esperando sincronización..." -ForegroundColor Blue
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "📊 Estado después del sync:" -ForegroundColor Cyan
kubectl get application $AppName -n $ArgocdNamespace

Write-Host ""
Write-Host "✅ Sync manual completado" -ForegroundColor Green
"@

$syncScript | Out-File -FilePath ".\scripts\manual-sync.ps1" -Encoding UTF8

# Script para ver estado
$statusScript = @"
# Script para ver estado de ArgoCD
Write-Host "📊 ESTADO DE ARGOCD" -ForegroundColor Green
Write-Host "===================" -ForegroundColor Green

Write-Host ""
Write-Host "🔍 Aplicación:" -ForegroundColor Cyan
kubectl get application $AppName -n $ArgocdNamespace -o wide

Write-Host ""
Write-Host "📦 Recursos en el cluster:" -ForegroundColor Cyan
kubectl get all -n $Namespace -l app=demo-microservice

Write-Host ""
Write-Host "🌐 Services versionados:" -ForegroundColor Cyan
kubectl get svc -n $Namespace -l app=demo-microservice

Write-Host ""
Write-Host "💡 Para hacer sync manual:" -ForegroundColor Yellow
Write-Host ".\scripts\manual-sync.ps1" -ForegroundColor Gray
"@

$statusScript | Out-File -FilePath ".\scripts\check-status.ps1" -Encoding UTF8

Write-Host "✅ Scripts de gestión creados" -ForegroundColor Green

# Resumen final
Write-Host ""
Write-Host "🎉 CONFIGURACIÓN MANUAL COMPLETADA" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Green
Write-Host ""

Write-Host "✅ Aplicación '$AppName' creada en ArgoCD" -ForegroundColor Green
Write-Host "✅ Sync configurado como MANUAL" -ForegroundColor Green
Write-Host "✅ Scripts de gestión creados" -ForegroundColor Green

Write-Host ""
Write-Host "🌐 Acceso a ArgoCD UI:" -ForegroundColor Cyan
Write-Host "  • URL: https://localhost:8081" -ForegroundColor White
Write-Host "  • Usuario: admin" -ForegroundColor White
Write-Host "  • Password: $argocdPassword" -ForegroundColor White
Write-Host "  • Aplicación: $AppName" -ForegroundColor White

Write-Host ""
Write-Host "🔧 FLUJO DE TRABAJO MANUAL:" -ForegroundColor Cyan
Write-Host "  1. Generar manifiestos:" -ForegroundColor White
Write-Host "     .\scripts\deploy-versioned-release.ps1 -Version 'v-1-0-0'" -ForegroundColor Gray
Write-Host "  2. Ver estado (debe mostrar OutOfSync):" -ForegroundColor White
Write-Host "     .\scripts\check-status.ps1" -ForegroundColor Gray
Write-Host "  3. Hacer sync manual:" -ForegroundColor White
Write-Host "     .\scripts\manual-sync.ps1" -ForegroundColor Gray
Write-Host "  4. Verificar deployment:" -ForegroundColor White
Write-Host "     .\scripts\test-version-routing.ps1 -TestVersion 'v-1-0-0'" -ForegroundColor Gray

Write-Host ""
Write-Host "📁 ARCHIVOS CREADOS:" -ForegroundColor Cyan
Write-Host "  • scripts/manual-sync.ps1 - Sync manual" -ForegroundColor Gray
Write-Host "  • scripts/check-status.ps1 - Ver estado" -ForegroundColor Gray

Write-Host ""
Write-Host "💡 VENTAJAS DEL SYNC MANUAL:" -ForegroundColor Yellow
Write-Host "  • Control total sobre cuándo se aplican cambios" -ForegroundColor Gray
Write-Host "  • Puedes revisar diffs antes de aplicar" -ForegroundColor Gray
Write-Host "  • Ideal para pruebas y demos" -ForegroundColor Gray
Write-Host "  • Evita cambios inesperados durante presentaciones" -ForegroundColor Gray