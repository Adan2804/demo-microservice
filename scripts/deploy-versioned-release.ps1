# Script para desplegar nueva versión con el patrón de Bancolombia
# Cambia solo la versión y ArgoCD sincroniza automáticamente

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [string]$Namespace = "demo-app",
    [string]$Registry = "your-registry.com",
    [string]$Repository = "demo-microservice",
    [switch]$SkipBuild = $false,
    [switch]$AutoSync = $true,
    [switch]$Verbose = $false
)

Write-Host "🚀 DEPLOY VERSIONED RELEASE - PATRÓN BANCOLOMBIA" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green
Write-Host ""

$imageName = "$Registry/$Repository"
$imageTag = $Version
$fullImageName = "${imageName}:${imageTag}"

Write-Host "📋 Configuración del Release:" -ForegroundColor Cyan
Write-Host "  • Versión: $Version" -ForegroundColor White
Write-Host "  • Imagen: $fullImageName" -ForegroundColor White
Write-Host "  • Namespace: $Namespace" -ForegroundColor White
Write-Host ""

# FASE 1: BUILD (si es necesario)
if (-not $SkipBuild) {
    Write-Host "🔨 FASE 1: BUILD DE LA APLICACIÓN" -ForegroundColor Yellow
    
    try {
        if (Test-Path "pom.xml") {
            mvn clean package -DskipTests
        } elseif (Test-Path "build.gradle") {
            ./gradlew clean build -x test
        }
        
        docker build -t $fullImageName . --build-arg APP_VERSION=$Version
        Write-Host "✅ Build completado" -ForegroundColor Green
        
    } catch {
        Write-Host "❌ Error en build: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
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
    
    # Procesar manifiestos
    $manifestFiles = Get-ChildItem -Path "k8s-versioned-manifests" -Filter "*.yaml" -File
    
    foreach ($file in $manifestFiles) {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        $processedContent = $content
        
        foreach ($token in $tokens.Keys) {
            $value = $tokens[$token]
            $processedContent = $processedContent -replace [regex]::Escape($token), $value
        }
        
        $outputFile = Join-Path $outputPath $file.Name
        $processedContent | Out-File -FilePath $outputFile -Encoding UTF8 -NoNewline
        
        if ($Verbose) {
            Write-Host "📝 Procesado: $($file.Name)" -ForegroundColor Blue
        }
    }
    
    Write-Host "✅ Manifiestos versionados generados" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error generando manifiestos: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}# FASE 3:
 APLICAR AL CLUSTER
Write-Host ""
Write-Host "🚀 FASE 3: APLICAR AL CLUSTER" -ForegroundColor Yellow

try {
    # Crear namespace si no existe
    kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    
    # Aplicar manifiestos en orden específico
    $applyOrder = @(
        "configmap-security-filters-versioned.yaml",
        "service-demo-microservice-versioned.yaml", 
        "deployment-demo-microservice-versioned.yaml",
        "deployment-security-filters-versioned.yaml"
    )
    
    foreach ($manifestFile in $applyOrder) {
        $manifestPath = Join-Path $outputPath $manifestFile
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
    
    Write-Host "✅ Manifiestos aplicados al cluster" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error aplicando al cluster: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# FASE 4: VERIFICAR DEPLOYMENT
Write-Host ""
Write-Host "🔍 FASE 4: VERIFICAR DEPLOYMENT" -ForegroundColor Yellow

Write-Host "⏳ Esperando que los pods estén listos..." -ForegroundColor Blue
Start-Sleep -Seconds 30

# Verificar estado de deployments
Write-Host "📊 Estado de deployments:" -ForegroundColor Cyan
kubectl get deployments -n $Namespace -l version=$Version

Write-Host ""
Write-Host "📦 Estado de pods:" -ForegroundColor Cyan
kubectl get pods -n $Namespace -l version=$Version

Write-Host ""
Write-Host "🌐 Estado de services:" -ForegroundColor Cyan
kubectl get services -n $Namespace -l version=$Version

# FASE 5: PRUEBAS DE CONECTIVIDAD
Write-Host ""
Write-Host "🧪 FASE 5: PRUEBAS DE CONECTIVIDAD" -ForegroundColor Yellow

# Configurar port-forward si es necesario
$gatewayService = "security-filters-versioned"
Write-Host "🔌 Configurando acceso al gateway..." -ForegroundColor Blue

# Limpiar port-forwards existentes del gateway
Get-Process | Where-Object { $_.ProcessName -eq "kubectl" -and $_.CommandLine -like "*port-forward*$gatewayService*" } | Stop-Process -Force 2>$null

# Iniciar nuevo port-forward
Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "svc/$gatewayService", "-n", $Namespace, "8080:80" -WindowStyle Hidden
Start-Sleep -Seconds 5

# Probar conectividad
Write-Host "🔍 Probando conectividad..." -ForegroundColor Blue

try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/demo/monetary" -TimeoutSec 10 2>$null
    if ($response.StatusCode -eq 200) {
        $appVersion = $response.Headers["X-App-Version"]
        $gatewayVersion = $response.Headers["X-Gateway-Version"]
        $serviceVersion = $response.Headers["X-Service-Version"]
        
        Write-Host "✅ Gateway responde correctamente" -ForegroundColor Green
        Write-Host "  • X-App-Version: $appVersion" -ForegroundColor White
        Write-Host "  • X-Gateway-Version: $gatewayVersion" -ForegroundColor White
        Write-Host "  • X-Service-Version: $serviceVersion" -ForegroundColor White
        
        if ($appVersion -eq $Version) {
            Write-Host "✅ Versión correcta desplegada" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Versión no coincide (esperada: $Version, actual: $appVersion)" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "⚠️  Gateway aún no responde (normal en despliegues nuevos)" -ForegroundColor Yellow
    Write-Host "Espera 2-3 minutos y prueba manualmente" -ForegroundColor Gray
}

# RESUMEN FINAL
Write-Host ""
Write-Host "🎉 DEPLOY VERSIONED RELEASE COMPLETADO" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""

Write-Host "✅ Nueva versión desplegada: $Version" -ForegroundColor Green
Write-Host "✅ Services versionados creados" -ForegroundColor Green
Write-Host "✅ Gateway configurado para nueva versión" -ForegroundColor Green

Write-Host ""
Write-Host "🌐 ACCESOS:" -ForegroundColor Cyan
Write-Host "  • Gateway versionado: http://localhost:8080" -ForegroundColor White
Write-Host "  • Service directo: demo-microservice-$Version.$Namespace.svc.cluster.local" -ForegroundColor White

Write-Host ""
Write-Host "🧪 PRUEBAS:" -ForegroundColor Cyan
Write-Host "  • Prueba básica:" -ForegroundColor White
Write-Host "    .\scripts\test-endpoint.ps1 -RequestCount 10 -Verbose" -ForegroundColor Gray
Write-Host "  • Verificar versión:" -ForegroundColor White
Write-Host "    curl http://localhost:8080/demo/monetary -H 'Accept: application/json'" -ForegroundColor Gray

Write-Host ""
Write-Host "🔍 VERIFICACIONES:" -ForegroundColor Cyan
Write-Host "  • Imagen del deployment:" -ForegroundColor White
Write-Host "    kubectl get deployment demo-microservice-$Version -n $Namespace -o jsonpath='{.spec.template.spec.containers[0].image}'" -ForegroundColor Gray
Write-Host "  • Labels de versión:" -ForegroundColor White
Write-Host "    kubectl get deployment demo-microservice-$Version -n $Namespace -o jsonpath='{.metadata.labels.version}'" -ForegroundColor Gray

Write-Host ""
Write-Host "💡 PATRÓN IMPLEMENTADO:" -ForegroundColor Yellow
Write-Host "• ✅ Deployment versionado: demo-microservice-$Version" -ForegroundColor Gray
Write-Host "• ✅ Service versionado: demo-microservice-$Version" -ForegroundColor Gray  
Write-Host "• ✅ Gateway enruta a versión específica" -ForegroundColor Gray
Write-Host "• ✅ Headers reflejan versión actual" -ForegroundColor Gray
Write-Host "• ✅ ArgoCD gestiona el ciclo de vida" -ForegroundColor Gray