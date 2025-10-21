# Script para generar manifiestos versionados SIN aplicar al cluster
# Para uso con ArgoCD MANUAL sync

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [string]$Namespace = "demo-app",
    [string]$Registry = "your-registry.com",
    [string]$Repository = "demo-microservice",
    [switch]$SkipBuild = $false,
    [switch]$Verbose = $false
)

Write-Host "📝 GENERAR MANIFIESTOS PARA ARGOCD MANUAL" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

$imageName = "$Registry/$Repository"
$imageTag = $Version
$fullImageName = "${imageName}:${imageTag}"

Write-Host "📋 Configuración:" -ForegroundColor Cyan
Write-Host "  • Versión: $Version" -ForegroundColor White
Write-Host "  • Imagen: $fullImageName" -ForegroundColor White
Write-Host "  • Namespace: $Namespace" -ForegroundColor White
Write-Host "  • Modo: SOLO GENERAR (no aplicar)" -ForegroundColor Yellow
Write-Host ""

# FASE 1: BUILD (si es necesario)
if (-not $SkipBuild) {
    Write-Host "🔨 FASE 1: BUILD DE LA APLICACIÓN" -ForegroundColor Yellow
    
    try {
        if (Test-Path "pom.xml") {
            Write-Host "📦 Compilando con Maven..." -ForegroundColor Blue
            mvn clean package -DskipTests
        } elseif (Test-Path "build.gradle") {
            Write-Host "📦 Compilando con Gradle..." -ForegroundColor Blue
            ./gradlew clean build -x test
        }
        
        Write-Host "🐳 Construyendo imagen Docker..." -ForegroundColor Blue
        docker build -t $fullImageName . --build-arg APP_VERSION=$Version
        
        Write-Host "✅ Build completado" -ForegroundColor Green
        
    } catch {
        Write-Host "❌ Error en build: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "⏭️  SALTANDO BUILD (--SkipBuild especificado)" -ForegroundColor Gray
}

# FASE 2: GENERAR MANIFIESTOS VERSIONADOS
Write-Host ""
Write-Host "📝 FASE 2: GENERAR MANIFIESTOS VERSIONADOS" -ForegroundColor Yellow

try {
    $dtReleaseVersion = $Version
    $dtBuildVersion = "build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $targetUri = "http://demo-microservice-$Version.$Namespace.svc.cluster.local"
    
    # Calcular checksum del ConfigMap
    $configContent = Get-Content "k8s-versioned-manifests/configmap-security-filters-versioned.yaml" -Raw
    $configBytes = [System.Text.Encoding]::UTF8.GetBytes($configContent)
    $configHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($configBytes)
    $configChecksum = [System.BitConverter]::ToString($configHash).Replace("-", "").ToLower().Substring(0, 16)
    
    # Tokens para reemplazo
    $tokens = @{
        "#{namespace}#" = $Namespace
        "#{version}#" = $Version
        "#{image}#" = $fullImageName
        "#{target_uri}#" = $targetUri
        "#{dt_release_version}#" = $dtReleaseVersion
        "#{dt_build_version}#" = $dtBuildVersion
        "#{config_checksum}#" = $configChecksum
        "#{timestamp}#" = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    }
    
    # Crear directorio de salida
    $outputPath = "k8s-versioned-manifests-processed"
    if (-not (Test-Path $outputPath)) {
        New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
    }
    
    # Limpiar archivos anteriores
    Get-ChildItem -Path $outputPath -Filter "*.yaml" | Remove-Item -Force
    
    # Procesar manifiestos
    $manifestFiles = Get-ChildItem -Path "k8s-versioned-manifests" -Filter "*.yaml" -File
    
    Write-Host "🔄 Procesando manifiestos..." -ForegroundColor Blue
    foreach ($file in $manifestFiles) {
        if ($file.Name -eq "argocd-application-manual.yaml") {
            # Procesar el manifiesto de ArgoCD por separado
            continue
        }
        
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        $processedContent = $content
        
        foreach ($token in $tokens.Keys) {
            $value = $tokens[$token]
            $processedContent = $processedContent -replace [regex]::Escape($token), $value
        }
        
        $outputFile = Join-Path $outputPath $file.Name
        $processedContent | Out-File -FilePath $outputFile -Encoding UTF8 -NoNewline
        
        Write-Host "  ✅ $($file.Name)" -ForegroundColor Green
        
        if ($Verbose) {
            Write-Host "    Tokens reemplazados:" -ForegroundColor Gray
            foreach ($token in $tokens.Keys) {
                if ($content -match [regex]::Escape($token)) {
                    Write-Host "      $token → $($tokens[$token])" -ForegroundColor DarkGray
                }
            }
        }
    }
    
    Write-Host "✅ Manifiestos versionados generados" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error generando manifiestos: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# FASE 3: MOSTRAR RESUMEN (NO APLICAR)
Write-Host ""
Write-Host "📋 FASE 3: RESUMEN DE MANIFIESTOS GENERADOS" -ForegroundColor Yellow

Write-Host "📁 Archivos generados en '$outputPath':" -ForegroundColor Cyan
$generatedFiles = Get-ChildItem -Path $outputPath -Filter "*.yaml" -File
foreach ($file in $generatedFiles) {
    $size = [math]::Round($file.Length / 1KB, 1)
    Write-Host "  • $($file.Name) (${size}KB)" -ForegroundColor White
}

Write-Host ""
Write-Host "🔍 Verificación de tokens:" -ForegroundColor Cyan
Write-Host "  • Versión: $Version" -ForegroundColor White
Write-Host "  • Imagen: $fullImageName" -ForegroundColor White
Write-Host "  • Namespace: $Namespace" -ForegroundColor White
Write-Host "  • Config Checksum: $configChecksum" -ForegroundColor White

# Verificar que no queden tokens sin reemplazar
Write-Host ""
Write-Host "🔍 Verificando tokens no reemplazados..." -ForegroundColor Blue
$unreplacedTokens = @()
foreach ($file in $generatedFiles) {
    $content = Get-Content $file.FullName -Raw
    if ($content -match '#\{[^}]+\}#') {
        $matches = [regex]::Matches($content, '#\{[^}]+\}#')
        foreach ($match in $matches) {
            if ($unreplacedTokens -notcontains $match.Value) {
                $unreplacedTokens += $match.Value
            }
        }
    }
}

if ($unreplacedTokens.Count -gt 0) {
    Write-Host "⚠️  Tokens no reemplazados encontrados:" -ForegroundColor Yellow
    foreach ($token in $unreplacedTokens) {
        Write-Host "  • $token" -ForegroundColor Red
    }
} else {
    Write-Host "✅ Todos los tokens fueron reemplazados correctamente" -ForegroundColor Green
}

# RESUMEN FINAL
Write-Host ""
Write-Host "🎉 MANIFIESTOS GENERADOS EXITOSAMENTE" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

Write-Host "✅ Manifiestos versionados listos para ArgoCD" -ForegroundColor Green
Write-Host "✅ Tokens reemplazados correctamente" -ForegroundColor Green
Write-Host "✅ Archivos guardados en: $outputPath" -ForegroundColor Green

Write-Host ""
Write-Host "🚀 PRÓXIMOS PASOS:" -ForegroundColor Cyan
Write-Host "  1. Verificar estado de ArgoCD (debe mostrar OutOfSync):" -ForegroundColor White
Write-Host "     .\scripts\check-status.ps1" -ForegroundColor Gray
Write-Host "  2. Hacer sync manual en ArgoCD:" -ForegroundColor White
Write-Host "     .\scripts\manual-sync.ps1" -ForegroundColor Gray
Write-Host "  3. O usar ArgoCD UI: https://localhost:8081" -ForegroundColor White
Write-Host "  4. Verificar deployment:" -ForegroundColor White
Write-Host "     .\scripts\test-version-routing.ps1 -TestVersion '$Version'" -ForegroundColor Gray

Write-Host ""
Write-Host "📊 ARCHIVOS PARA ARGOCD:" -ForegroundColor Cyan
foreach ($file in $generatedFiles) {
    Write-Host "  • $($file.Name)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "💡 NOTA IMPORTANTE:" -ForegroundColor Yellow
Write-Host "Los manifiestos están listos pero NO se aplicaron al cluster." -ForegroundColor Gray
Write-Host "ArgoCD debe hacer el sync manual para desplegar la nueva versión." -ForegroundColor Gray

Write-Host ""
Write-Host "🔄 FLUJO COMPLETO:" -ForegroundColor Cyan
Write-Host "  Manifiestos generados → ArgoCD detecta OutOfSync → Sync manual → Pods recreados" -ForegroundColor Gray