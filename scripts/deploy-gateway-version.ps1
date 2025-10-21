# Script para desplegar una nueva versión usando el enfoque Gateway + ArgoCD
# Simula el pipeline de CI/CD que reemplaza tokens y hace commit

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [string]$Namespace = "demo-app",
    [string]$ImageRegistry = "ecr-repo",
    [string]$BuildNumber = "",
    [string]$GitRepo = "",
    [string]$ManifestsPath = "k8s-gateway-manifests",
    [string]$OutputPath = "k8s-gateway-manifests-processed",
    [switch]$BuildImage = $false,
    [switch]$PushImage = $false,
    [switch]$ApplyToCluster = $false,
    [switch]$Verbose = $false
)

Write-Host "🚀 DESPLIEGUE DE NUEVA VERSIÓN CON GATEWAY" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""

# Validar parámetros
if (-not $Version) {
    Write-Host "❌ Error: Version es requerida (ej: v-1-1-0)" -ForegroundColor Red
    exit 1
}

# Establecer valores por defecto
if (-not $BuildNumber) {
    $BuildNumber = "build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
}

$ImageName = "$ImageRegistry/demo-microservice"
$ImageTag = $Version
$FullImage = "${ImageName}:${ImageTag}"
$TargetUri = "http://demo-microservice-gateway.$Namespace.svc.cluster.local"
$DtReleaseVersion = $Version
$DtBuildVersion = $BuildNumber

Write-Host "📋 Parámetros del despliegue:" -ForegroundColor Cyan
Write-Host "  • Versión: $Version" -ForegroundColor White
Write-Host "  • Imagen: $FullImage" -ForegroundColor White
Write-Host "  • Namespace: $Namespace" -ForegroundColor White
Write-Host "  • Build Number: $BuildNumber" -ForegroundColor White
Write-Host "  • Target URI: $TargetUri" -ForegroundColor White
Write-Host ""

# 1. CONSTRUIR IMAGEN (si se solicita)
if ($BuildImage) {
    Write-Host "🔨 CONSTRUYENDO IMAGEN DOCKER..." -ForegroundColor Yellow
    
    try {
        # Verificar que existe Dockerfile
        if (-not (Test-Path "Dockerfile")) {
            Write-Host "❌ Error: Dockerfile no encontrado" -ForegroundColor Red
            exit 1
        }
        
        # Construir con Gradle
        Write-Host "📦 Construyendo JAR con Gradle..." -ForegroundColor Blue
        ./gradlew clean bootJar
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error al construir JAR" -ForegroundColor Red
            exit 1
        }
        
        # Construir imagen Docker
        Write-Host "🐳 Construyendo imagen Docker: $FullImage" -ForegroundColor Blue
        docker build -t $FullImage .
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error al construir imagen Docker" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "✅ Imagen construida exitosamente: $FullImage" -ForegroundColor Green
        
        # Push imagen (si se solicita)
        if ($PushImage) {
            Write-Host "📤 Pushing imagen a registry..." -ForegroundColor Blue
            docker push $FullImage
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Imagen pushed exitosamente" -ForegroundColor Green
            } else {
                Write-Host "❌ Error al hacer push de la imagen" -ForegroundColor Red
                exit 1
            }
        }
        
    } catch {
        Write-Host "❌ Error durante la construcción: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# 2. CALCULAR CHECKSUM DEL CONFIGMAP
Write-Host "🔍 CALCULANDO CHECKSUM DE CONFIGURACIÓN..." -ForegroundColor Yellow

$configMapPath = Join-Path $ManifestsPath "configmap-security-filters.yaml"
$configChecksum = ""

if (Test-Path $configMapPath) {
    $configContent = Get-Content $configMapPath -Raw
    # Reemplazar tokens temporalmente para calcular checksum correcto
    $tempContent = $configContent -replace "#{namespace}#", $Namespace
    $tempContent = $tempContent -replace "#{version}#", $Version
    
    $configBytes = [System.Text.Encoding]::UTF8.GetBytes($tempContent)
    $configHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($configBytes)
    $configChecksum = [System.BitConverter]::ToString($configHash).Replace("-", "").ToLower().Substring(0, 16)
    
    Write-Host "✅ Config checksum calculado: $configChecksum" -ForegroundColor Green
} else {
    Write-Host "⚠️  ConfigMap no encontrado, usando checksum por defecto" -ForegroundColor Yellow
    $configChecksum = "default-checksum"
}

# 3. REEMPLAZAR TOKENS
Write-Host ""
Write-Host "🔄 REEMPLAZANDO TOKENS EN MANIFIESTOS..." -ForegroundColor Yellow

# Crear directorio de salida
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Definir tokens y sus valores
$tokens = @{
    "#{namespace}#" = $Namespace
    "#{version}#" = $Version
    "#{image}#" = $FullImage
    "#{target_uri}#" = $TargetUri
    "#{dt_release_version}#" = $DtReleaseVersion
    "#{dt_build_version}#" = $DtBuildVersion
    "#{config_checksum}#" = $configChecksum
    "#{timestamp}#" = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    "#{request_id}#" = [System.Guid]::NewGuid().ToString()
}

# Procesar archivos YAML
$yamlFiles = Get-ChildItem -Path $ManifestsPath -Filter "*.yaml" -File

foreach ($file in $yamlFiles) {
    Write-Host "📝 Procesando: $($file.Name)" -ForegroundColor Blue
    
    $content = Get-Content $file.FullName -Raw -Encoding UTF8
    $processedContent = $content
    
    foreach ($token in $tokens.Keys) {
        $value = $tokens[$token]
        $processedContent = $processedContent -replace [regex]::Escape($token), $value
        
        if ($Verbose -and $content -match [regex]::Escape($token)) {
            Write-Host "  • $token → $value" -ForegroundColor Gray
        }
    }
    
    $outputFile = Join-Path $OutputPath $file.Name
    $processedContent | Out-File -FilePath $outputFile -Encoding UTF8 -NoNewline
    
    Write-Host "  ✅ Guardado: $outputFile" -ForegroundColor Green
}

# 4. APLICAR AL CLUSTER (si se solicita)
if ($ApplyToCluster) {
    Write-Host ""
    Write-Host "🚀 APLICANDO MANIFIESTOS AL CLUSTER..." -ForegroundColor Yellow
    
    try {
        # Verificar conexión a kubectl
        kubectl cluster-info | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Error: No hay conexión al cluster" -ForegroundColor Red
            exit 1
        }
        
        # Crear namespace
        kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
        
        # Aplicar en orden específico
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
        
        # Esperar rollout
        Write-Host ""
        Write-Host "⏳ Esperando rollout del microservicio..." -ForegroundColor Blue
        kubectl rollout status deployment/demo-microservice-gateway -n $Namespace --timeout=300s
        
        Write-Host "⏳ Esperando rollout del gateway..." -ForegroundColor Blue
        kubectl rollout status deployment/security-filters-gateway -n $Namespace --timeout=300s
        
        Write-Host ""
        Write-Host "🔍 Verificando estado final..." -ForegroundColor Blue
        kubectl get pods -n $Namespace -l app=demo-microservice-gateway
        kubectl get pods -n $Namespace -l app=security-filters-gateway
        
    } catch {
        Write-Host "❌ Error al aplicar manifiestos: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 5. VERIFICACIONES
Write-Host ""
Write-Host "🔍 COMANDOS DE VERIFICACIÓN:" -ForegroundColor Cyan
Write-Host ""

Write-Host "📊 Verificar imagen del deployment:" -ForegroundColor Gray
Write-Host "kubectl -n $Namespace get deploy demo-microservice-gateway -o jsonpath='{.spec.template.spec.containers[0].image}'" -ForegroundColor White

Write-Host ""
Write-Host "🏷️  Verificar versión en labels:" -ForegroundColor Gray
Write-Host "kubectl -n $Namespace get deploy demo-microservice-gateway -o jsonpath='{.spec.template.metadata.labels.version}'" -ForegroundColor White

Write-Host ""
Write-Host "🌐 Verificar checksum del gateway:" -ForegroundColor Gray
Write-Host "kubectl -n $Namespace get deploy security-filters-gateway -o jsonpath='{.spec.template.metadata.annotations.checksum/config}'" -ForegroundColor White

Write-Host ""
Write-Host "🧪 Probar endpoint:" -ForegroundColor Gray
Write-Host ".\test-endpoint.ps1 -RequestCount 10 -UseGateway -Verbose" -ForegroundColor White

# 6. RESUMEN FINAL
Write-Host ""
Write-Host "🎉 DESPLIEGUE COMPLETADO" -ForegroundColor Green
Write-Host "========================" -ForegroundColor Green
Write-Host ""
Write-Host "✅ Versión desplegada: $Version" -ForegroundColor Green
Write-Host "✅ Imagen: $FullImage" -ForegroundColor Green
Write-Host "✅ Config checksum: $configChecksum" -ForegroundColor Green
Write-Host "✅ Manifiestos procesados en: $OutputPath" -ForegroundColor Green

if ($ApplyToCluster) {
    Write-Host "✅ Aplicado al cluster en namespace: $Namespace" -ForegroundColor Green
}

Write-Host ""
Write-Host "🚀 PRÓXIMOS PASOS:" -ForegroundColor Cyan
Write-Host "1. Verificar que ArgoCD detecte los cambios" -ForegroundColor White
Write-Host "2. Monitorear el rollout en ArgoCD Dashboard" -ForegroundColor White
Write-Host "3. Probar el endpoint con el script de pruebas" -ForegroundColor White
Write-Host "4. Validar que X-App-Version refleje la nueva versión" -ForegroundColor White