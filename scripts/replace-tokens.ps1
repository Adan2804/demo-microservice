# Script para reemplazar tokens en manifiestos de Kubernetes
# Simula el comportamiento de Azure DevOps "Replace Tokens"

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [Parameter(Mandatory=$true)]
    [string]$Image,
    
    [string]$Namespace = "demo-app",
    [string]$TargetUri = "",
    [string]$DtReleaseVersion = "",
    [string]$DtBuildVersion = "",
    [string]$ManifestsPath = "k8s-manifests",
    [string]$OutputPath = "k8s-manifests-processed",
    [switch]$ApplyToCluster = $false,
    [switch]$Verbose = $false
)

Write-Host "🔄 REEMPLAZO DE TOKENS EN MANIFIESTOS" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

# Validar parámetros
if (-not $Version) {
    Write-Host "❌ Error: Version es requerida" -ForegroundColor Red
    exit 1
}

if (-not $Image) {
    Write-Host "❌ Error: Image es requerida" -ForegroundColor Red
    exit 1
}

# Establecer valores por defecto
if (-not $TargetUri) {
    $TargetUri = "http://demo-microservice.$Namespace.svc.cluster.local"
}

if (-not $DtReleaseVersion) {
    $DtReleaseVersion = $Version
}

if (-not $DtBuildVersion) {
    $DtBuildVersion = "build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}

# Calcular checksum del ConfigMap
$configMapPath = Join-Path $ManifestsPath "configmap-security-filters.yaml"
$configChecksum = ""
if (Test-Path $configMapPath) {
    $configContent = Get-Content $configMapPath -Raw
    $configBytes = [System.Text.Encoding]::UTF8.GetBytes($configContent)
    $configHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($configBytes)
    $configChecksum = [System.BitConverter]::ToString($configHash).Replace("-", "").ToLower().Substring(0, 16)
}

Write-Host "📋 Parámetros de reemplazo:" -ForegroundColor Cyan
Write-Host "  • Version: $Version" -ForegroundColor White
Write-Host "  • Image: $Image" -ForegroundColor White
Write-Host "  • Namespace: $Namespace" -ForegroundColor White
Write-Host "  • Target URI: $TargetUri" -ForegroundColor White
Write-Host "  • DT Release Version: $DtReleaseVersion" -ForegroundColor White
Write-Host "  • DT Build Version: $DtBuildVersion" -ForegroundColor White
Write-Host "  • Config Checksum: $configChecksum" -ForegroundColor White
Write-Host "  • Manifests Path: $ManifestsPath" -ForegroundColor White
Write-Host "  • Output Path: $OutputPath" -ForegroundColor White
Write-Host ""

# Crear directorio de salida
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "📁 Directorio de salida creado: $OutputPath" -ForegroundColor Green
}

# Definir tokens y sus valores
$tokens = @{
    "#{namespace}#" = $Namespace
    "#{version}#" = $Version
    "#{image}#" = $Image
    "#{target_uri}#" = $TargetUri
    "#{dt_release_version}#" = $DtReleaseVersion
    "#{dt_build_version}#" = $DtBuildVersion
    "#{config_checksum}#" = $configChecksum
    "#{timestamp}#" = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    "#{request_id}#" = [System.Guid]::NewGuid().ToString()
}

Write-Host "🔄 Procesando manifiestos..." -ForegroundColor Yellow
Write-Host ""

# Obtener todos los archivos YAML
$yamlFiles = Get-ChildItem -Path $ManifestsPath -Filter "*.yaml" -File

foreach ($file in $yamlFiles) {
    Write-Host "📝 Procesando: $($file.Name)" -ForegroundColor Blue
    
    # Leer contenido del archivo
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    
    # Reemplazar tokens
    $processedContent = $content
    foreach ($token in $tokens.Keys) {
        $value = $tokens[$token]
        $processedContent = $processedContent -replace [regex]::Escape($token), $value
        
        if ($Verbose -and $content -match [regex]::Escape($token)) {
            Write-Host "  • Reemplazado: $token → $value" -ForegroundColor Gray
        }
    }
    
    # Escribir archivo procesado
    $outputFile = Join-Path $OutputPath $file.Name
    $processedContent | Out-File -FilePath $outputFile -Encoding UTF8 -NoNewline
    
    Write-Host "  ✅ Guardado en: $outputFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "✅ Procesamiento completado" -ForegroundColor Green
Write-Host ""

# Mostrar resumen de cambios
Write-Host "📊 Resumen de tokens reemplazados:" -ForegroundColor Cyan
foreach ($token in $tokens.Keys) {
    Write-Host "  • $token → $($tokens[$token])" -ForegroundColor White
}

# Aplicar al cluster si se solicita
if ($ApplyToCluster) {
    Write-Host ""
    Write-Host "🚀 Aplicando manifiestos al cluster..." -ForegroundColor Yellow
    
    try {
        # Verificar conexión a kubectl
        $kubectlTest = kubectl cluster-info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: No hay conexión al cluster de Kubernetes" -ForegroundColor Red
            exit 1
        }
        
        # Crear namespace si no existe
        kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - 2>&1 | Out-Null
        
        # Aplicar manifiestos en orden
        $applyOrder = @(
            "service-demo-microservice.yaml",
            "configmap-security-filters.yaml", 
            "deployment-demo-microservice.yaml",
            "deployment-security-filters.yaml"
        )
        
        foreach ($manifestFile in $applyOrder) {
            $manifestPath = Join-Path $OutputPath $manifestFile
            if (Test-Path $manifestPath) {
                Write-Host "📦 Aplicando: $manifestFile" -ForegroundColor Blue
                kubectl apply -f $manifestPath
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  ✅ Aplicado exitosamente" -ForegroundColor Green
                } else {
                    Write-Host "  ❌ Error al aplicar" -ForegroundColor Red
                }
            }
        }
        
        Write-Host ""
        Write-Host "🔍 Verificando estado del deployment..." -ForegroundColor Blue
        kubectl get pods -n $Namespace -l app=demo-microservice
        kubectl get pods -n $Namespace -l app=security-filters
        
    } catch {
        Write-Host "❌ Error al aplicar manifiestos: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "🎉 Script completado exitosamente" -ForegroundColor Green
Write-Host ""

# Mostrar comandos útiles
Write-Host "💡 Comandos útiles:" -ForegroundColor Cyan
Write-Host "  # Verificar imagen del deployment:" -ForegroundColor Gray
Write-Host "  kubectl -n $Namespace get deploy demo-microservice -o jsonpath='{.spec.template.spec.containers[0].image}'" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Verificar versión en labels:" -ForegroundColor Gray
Write-Host "  kubectl -n $Namespace get deploy demo-microservice -o jsonpath='{.spec.template.metadata.labels.version}'" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Probar endpoint:" -ForegroundColor Gray
Write-Host "  .\test-endpoint.ps1 -RequestCount 10 -Verbose" -ForegroundColor Gray