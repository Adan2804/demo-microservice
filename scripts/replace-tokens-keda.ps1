# Script para reemplazar tokens en manifiestos de KEDA
# Adaptado para el formato del banco con variables de escalado por horario

param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,  # qa, dev, prod
    
    [string]$ManifestsPath = "keda-banco",
    [string]$OutputPath = "keda-banco-processed",
    [string]$VariablesFile = "",
    [switch]$ApplyToCluster = $false,
    [switch]$Verbose = $false
)

Write-Host "🔄 REEMPLAZO DE TOKENS KEDA - AMBIENTE: $Environment" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""

# Determinar archivo de variables
if (-not $VariablesFile) {
    $VariablesFile = Join-Path $ManifestsPath "variables-keda-$Environment.properties"
}

# Validar que existe el archivo de variables
if (-not (Test-Path $VariablesFile)) {
    Write-Host "❌ Error: No se encontró el archivo de variables: $VariablesFile" -ForegroundColor Red
    Write-Host "💡 Crea el archivo con las variables necesarias para el ambiente $Environment" -ForegroundColor Yellow
    exit 1
}

Write-Host "📋 Cargando variables desde: $VariablesFile" -ForegroundColor Cyan

# Leer variables del archivo properties
$tokens = @{}
Get-Content $VariablesFile | ForEach-Object {
    $line = $_.Trim()
    # Ignorar líneas vacías y comentarios
    if ($line -and -not $line.StartsWith("#")) {
        $parts = $line -split "=", 2
        if ($parts.Count -eq 2) {
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            $tokenKey = "#{$key}#"
            $tokens[$tokenKey] = $value
            
            if ($Verbose) {
                Write-Host "  • $tokenKey = $value" -ForegroundColor Gray
            }
        }
    }
}

Write-Host "✅ Cargadas $($tokens.Count) variables" -ForegroundColor Green
Write-Host ""

# Crear directorio de salida
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "📁 Directorio de salida creado: $OutputPath" -ForegroundColor Green
}

Write-Host "🔄 Procesando manifiestos KEDA..." -ForegroundColor Yellow
Write-Host ""

# Obtener archivo de ScaledObject
$scaledObjectFile = Join-Path $ManifestsPath "scaled-object.yaml"

if (-not (Test-Path $scaledObjectFile)) {
    Write-Host "❌ Error: No se encontró scaled-object.yaml en $ManifestsPath" -ForegroundColor Red
    exit 1
}

Write-Host "📝 Procesando: scaled-object.yaml" -ForegroundColor Blue

# Leer contenido del archivo
$content = Get-Content $scaledObjectFile -Raw -Encoding UTF8

# Reemplazar tokens
$processedContent = $content
$replacedCount = 0

foreach ($token in $tokens.Keys) {
    $value = $tokens[$token]
    if ($content -match [regex]::Escape($token)) {
        $processedContent = $processedContent -replace [regex]::Escape($token), $value
        $replacedCount++
        
        if ($Verbose) {
            Write-Host "  • Reemplazado: $token → $value" -ForegroundColor Gray
        }
    }
}

# Escribir archivo procesado
$outputFile = Join-Path $OutputPath "scaled-object.yaml"
$processedContent | Out-File -FilePath $outputFile -Encoding UTF8 -NoNewline

Write-Host "  ✅ Guardado en: $outputFile" -ForegroundColor Green
Write-Host "  📊 Tokens reemplazados: $replacedCount" -ForegroundColor Cyan
Write-Host ""

# Verificar si quedaron tokens sin reemplazar
$unreplacedTokens = [regex]::Matches($processedContent, '#\{[^}]+\}#')
if ($unreplacedTokens.Count -gt 0) {
    Write-Host "⚠️  ADVERTENCIA: Tokens sin reemplazar encontrados:" -ForegroundColor Yellow
    $unreplacedTokens | ForEach-Object {
        Write-Host "  • $($_.Value)" -ForegroundColor Yellow
    }
    Write-Host ""
}

Write-Host "✅ Procesamiento completado" -ForegroundColor Green
Write-Host ""

# Mostrar resumen
Write-Host "📊 Resumen de configuración KEDA:" -ForegroundColor Cyan
Write-Host "  • Ambiente: $Environment" -ForegroundColor White
Write-Host "  • Namespace: $($tokens['#{namespace}#'])" -ForegroundColor White
Write-Host "  • Servicio: $($tokens['#{service}#'])" -ForegroundColor White
Write-Host "  • Réplicas mín: $($tokens['#{replicas}#'])" -ForegroundColor White
Write-Host "  • Réplicas máx: $($tokens['#{replicas-max}#'])" -ForegroundColor White
Write-Host "  • Polling Interval: $($tokens['#{polling-interval}#']) segundos" -ForegroundColor White
Write-Host "  • Cooldown Period: $($tokens['#{cooldown-period}#']) segundos" -ForegroundColor White
Write-Host "  • Downscale: $($tokens['#{replicas-downscale}#']) pods ($($tokens['#{cron-downscale-start}#']) - $($tokens['#{cron-downscale-end}#']))" -ForegroundColor White
Write-Host "  • Upscale: $($tokens['#{replicas-upscale}#']) pods ($($tokens['#{cron-upscale-start}#']) - $($tokens['#{cron-upscale-end}#']))" -ForegroundColor White
Write-Host "  • Timezone: $($tokens['#{timezone}#'])" -ForegroundColor White
Write-Host ""

# Aplicar al cluster si se solicita
if ($ApplyToCluster) {
    Write-Host "🚀 Aplicando ScaledObject al cluster..." -ForegroundColor Yellow
    
    try {
        # Verificar conexión a kubectl
        $kubectlTest = kubectl cluster-info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: No hay conexión al cluster de Kubernetes" -ForegroundColor Red
            exit 1
        }
        
        # Verificar que KEDA esté instalado
        $kedaCheck = kubectl get crd scaledobjects.keda.sh 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: KEDA no está instalado en el cluster" -ForegroundColor Red
            Write-Host "💡 Instala KEDA primero: kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml" -ForegroundColor Yellow
            exit 1
        }
        
        # Crear namespace si no existe
        $namespace = $tokens['#{namespace}#']
        kubectl create namespace $namespace --dry-run=client -o yaml | kubectl apply -f - 2>&1 | Out-Null
        
        # Aplicar ScaledObject
        Write-Host "📦 Aplicando: scaled-object.yaml" -ForegroundColor Blue
        kubectl apply -f $outputFile
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✅ ScaledObject aplicado exitosamente" -ForegroundColor Green
        } else {
            Write-Host "  ❌ Error al aplicar ScaledObject" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "🔍 Verificando estado de KEDA..." -ForegroundColor Blue
        kubectl get scaledobject -n $namespace
        kubectl get hpa -n $namespace
        
    } catch {
        Write-Host "❌ Error al aplicar manifiestos: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "🎉 Script completado exitosamente" -ForegroundColor Green
Write-Host ""

# Mostrar comandos útiles
Write-Host "💡 Comandos útiles:" -ForegroundColor Cyan
Write-Host "  # Ver ScaledObject:" -ForegroundColor Gray
Write-Host "  kubectl get scaledobject -n $($tokens['#{namespace}#'])" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Ver HPA generado por KEDA:" -ForegroundColor Gray
Write-Host "  kubectl get hpa -n $($tokens['#{namespace}#'])" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Ver logs de KEDA:" -ForegroundColor Gray
Write-Host "  kubectl logs -n keda -l app=keda-operator --tail=50" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Monitorear escalado:" -ForegroundColor Gray
Write-Host "  kubectl get pods -n $($tokens['#{namespace}#']) -w" -ForegroundColor Gray
