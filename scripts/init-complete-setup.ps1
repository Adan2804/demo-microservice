# Script de inicialización completa del entorno Gateway + ArgoCD
# Configura todo desde cero para el flujo end-to-end

param(
    [string]$Namespace = "demo-app",
    [string]$Registry = "your-registry.com",
    [string]$InitialVersion = "v-1-0-0",
    [string]$RepoUrl = "https://github.com/your-org/demo-microservice-config.git",
    [switch]$SkipBuild = $false,
    [switch]$AutoSync = $true,
    [switch]$Verbose = $false
)

Write-Host "🚀 INICIALIZACIÓN COMPLETA DEL ENTORNO" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""

Write-Host "📋 Configuración inicial:" -ForegroundColor Cyan
Write-Host "  • Namespace: $Namespace" -ForegroundColor White
Write-Host "  • Registry: $Registry" -ForegroundColor White
Write-Host "  • Versión inicial: $InitialVersion" -ForegroundColor White
Write-Host "  • Repositorio: $RepoUrl" -ForegroundColor White
Write-Host "  • Auto-sync: $AutoSync" -ForegroundColor White
Write-Host ""

# FASE 1: VERIFICACIONES INICIALES
Write-Host "🔍 FASE 1: VERIFICACIONES INICIALES" -ForegroundColor Yellow
Write-Host "===================================" -ForegroundColor Yellow

try {
    # Verificar Kubernetes
    Write-Host "📡 Verificando conexión a Kubernetes..." -ForegroundColor Blue
    kubectl cluster-info | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "No hay conexión al cluster de Kubernetes"
    }
    Write-Host "✅ Kubernetes OK" -ForegroundColor Green
    
    # Verificar ArgoCD
    Write-Host "🔍 Verificando ArgoCD..." -ForegroundColor Blue
    kubectl get namespace argocd | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ArgoCD no está instalado (namespace 'argocd' no encontrado)"
    }
    
    kubectl get deployment argocd-server -n argocd | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "ArgoCD server no está desplegado"
    }
    Write-Host "✅ ArgoCD OK" -ForegroundColor Green
    
    # Verificar herramientas de build
    if (-not $SkipBuild) {
        Write-Host "🔨 Verificando herramientas de build..." -ForegroundColor Blue
        
        if (Test-Path "pom.xml") {
            mvn --version | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Maven no está disponible"
            }
            Write-Host "✅ Maven OK" -ForegroundColor Green
        } elseif (Test-Path "build.gradle") {
            ./gradlew --version | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Gradle no está disponible"
            }
            Write-Host "✅ Gradle OK" -ForegroundColor Green
        } else {
            Write-Host "⚠️  No se encontró pom.xml ni build.gradle" -ForegroundColor Yellow
        }
        
        # Verificar Docker
        docker version | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Docker no está disponible"
        }
        Write-Host "✅ Docker OK" -ForegroundColor Green
    }
    
} catch {
    Write-Host "❌ Error en verificaciones: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "🔧 Requisitos:" -ForegroundColor Yellow
    Write-Host "  • Kubernetes cluster activo (minikube, kind, etc.)" -ForegroundColor Gray
    Write-Host "  • ArgoCD instalado en namespace 'argocd'" -ForegroundColor Gray
    Write-Host "  • Maven/Gradle para build" -ForegroundColor Gray
    Write-Host "  • Docker para imágenes" -ForegroundColor Gray
    exit 1
}

# FASE 2: CONFIGURAR ARGOCD APPLICATION
Write-Host ""
Write-Host "📝 FASE 2: CONFIGURAR ARGOCD APPLICATION" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

try {
    Write-Host "🚀 Configurando aplicación en ArgoCD..." -ForegroundColor Blue
    
    $setupParams = @{
        AppName = "demo-microservice-app"
        Namespace = $Namespace
        RepoUrl = $RepoUrl
        AutoSync = $AutoSync
        Verbose = $Verbose
    }
    
    & ".\scripts\setup-argocd-app.ps1" @setupParams
    
    Write-Host "✅ Aplicación ArgoCD configurada" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error configurando ArgoCD: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# FASE 3: PRIMER DEPLOYMENT
Write-Host ""
Write-Host "🚀 FASE 3: PRIMER DEPLOYMENT" -ForegroundColor Yellow
Write-Host "============================" -ForegroundColor Yellow

try {
    Write-Host "📦 Ejecutando primer deployment..." -ForegroundColor Blue
    
    $deployParams = @{
        Version = $InitialVersion
        Registry = $Registry
        Namespace = $Namespace
        SkipBuild = $SkipBuild
        SkipPush = $true  # Simulamos push por ahora
        AutoSync = $AutoSync
        Verbose = $Verbose
    }
    
    & ".\scripts\build-and-deploy.ps1" @deployParams
    
    Write-Host "✅ Primer deployment completado" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error en deployment: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# FASE 4: VERIFICAR DEPLOYMENT
Write-Host ""
Write-Host "🔍 FASE 4: VERIFICAR DEPLOYMENT" -ForegroundColor Yellow
Write-Host "===============================" -ForegroundColor Yellow

Write-Host "⏳ Esperando que ArgoCD sincronice y los pods estén listos..." -ForegroundColor Blue
Write-Host "Esto puede tomar 2-5 minutos..." -ForegroundColor Gray

# Esperar sincronización de ArgoCD
$maxWaitTime = 300  # 5 minutos
$waitTime = 0
$syncCompleted = $false

while ($waitTime -lt $maxWaitTime -and -not $syncCompleted) {
    Start-Sleep -Seconds 10
    $waitTime += 10
    
    try {
        $appStatus = kubectl get application demo-microservice-app -n argocd -o jsonpath='{.status.sync.status}' 2>$null
        $healthStatus = kubectl get application demo-microservice-app -n argocd -o jsonpath='{.status.health.status}' 2>$null
        
        Write-Host "📊 Estado ArgoCD: Sync=$appStatus, Health=$healthStatus (${waitTime}s)" -ForegroundColor Blue
        
        if ($appStatus -eq "Synced" -and $healthStatus -eq "Healthy") {
            $syncCompleted = $true
            Write-Host "✅ ArgoCD sincronizado y saludable" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "⏳ Esperando sincronización..." -ForegroundColor Gray
    }
}

if (-not $syncCompleted) {
    Write-Host "⚠️  Timeout esperando sincronización completa" -ForegroundColor Yellow
    Write-Host "Continúa con verificación manual..." -ForegroundColor Gray
}

# Verificar estado de pods
Write-Host ""
Write-Host "📊 Estado actual del cluster:" -ForegroundColor Cyan

Write-Host "🚀 Deployments:" -ForegroundColor Blue
kubectl get deployments -n $Namespace

Write-Host ""
Write-Host "📦 Pods:" -ForegroundColor Blue
kubectl get pods -n $Namespace

Write-Host ""
Write-Host "🌐 Services:" -ForegroundColor Blue
kubectl get services -n $Namespace

# FASE 5: CONFIGURAR ACCESOS
Write-Host ""
Write-Host "🔌 FASE 5: CONFIGURAR ACCESOS" -ForegroundColor Yellow
Write-Host "=============================" -ForegroundColor Yellow

Write-Host "🌐 Configurando port-forwards para acceso local..." -ForegroundColor Blue

# Limpiar port-forwards existentes
Get-Process | Where-Object { $_.ProcessName -eq "kubectl" -and $_.CommandLine -like "*port-forward*" } | Stop-Process -Force 2>$null

# Port-forward para ArgoCD (si no está activo)
$argocdPortForward = Get-Process | Where-Object { $_.ProcessName -eq "kubectl" -and $_.CommandLine -like "*port-forward*argocd-server*" } 2>$null
if (-not $argocdPortForward) {
    Write-Host "🔌 Iniciando port-forward para ArgoCD..." -ForegroundColor Blue
    Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "svc/argocd-server", "-n", "argocd", "8081:443" -WindowStyle Hidden
    Start-Sleep -Seconds 3
}

# Port-forward para Security Filters
Write-Host "🔌 Iniciando port-forward para Security Filters..." -ForegroundColor Blue
Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "svc/security-filters", "-n", $Namespace, "8080:80" -WindowStyle Hidden
Start-Sleep -Seconds 3

# Port-forward para Demo Microservice (directo)
Write-Host "🔌 Iniciando port-forward para Demo Microservice..." -ForegroundColor Blue
Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "svc/demo-microservice", "-n", $Namespace, "8082:80" -WindowStyle Hidden
Start-Sleep -Seconds 3

Write-Host "✅ Port-forwards configurados" -ForegroundColor Green

# FASE 6: PRUEBAS INICIALES
Write-Host ""
Write-Host "🧪 FASE 6: PRUEBAS INICIALES" -ForegroundColor Yellow
Write-Host "============================" -ForegroundColor Yellow

Write-Host "⏳ Esperando que los servicios estén listos..." -ForegroundColor Blue
Start-Sleep -Seconds 15

Write-Host "🔍 Ejecutando pruebas básicas..." -ForegroundColor Blue

try {
    # Prueba directa al microservicio
    Write-Host ""
    Write-Host "📡 Probando acceso directo al microservicio:" -ForegroundColor Cyan
    $response = Invoke-WebRequest -Uri "http://localhost:8082/demo/monetary" -TimeoutSec 10 2>$null
    if ($response.StatusCode -eq 200) {
        $appVersion = $response.Headers["X-App-Version"]
        Write-Host "✅ Microservicio responde - X-App-Version: $appVersion" -ForegroundColor Green
    }
    
} catch {
    Write-Host "⚠️  Microservicio aún no responde (normal en primera ejecución)" -ForegroundColor Yellow
}

try {
    # Prueba a través del gateway
    Write-Host ""
    Write-Host "📡 Probando acceso a través del Security Filters:" -ForegroundColor Cyan
    $response = Invoke-WebRequest -Uri "http://localhost:8080/demo/monetary" -TimeoutSec 10 2>$null
    if ($response.StatusCode -eq 200) {
        $appVersion = $response.Headers["X-App-Version"]
        $gatewayVersion = $response.Headers["X-Gateway-Version"]
        Write-Host "✅ Gateway responde - X-App-Version: $appVersion, X-Gateway-Version: $gatewayVersion" -ForegroundColor Green
    }
    
} catch {
    Write-Host "⚠️  Gateway aún no responde (normal en primera ejecución)" -ForegroundColor Yellow
}

# Obtener credenciales de ArgoCD
Write-Host ""
Write-Host "🔑 Obteniendo credenciales de ArgoCD..." -ForegroundColor Blue
try {
    $argocdPassword = kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
} catch {
    $argocdPassword = "Ver documentación de ArgoCD"
}

# RESUMEN FINAL
Write-Host ""
Write-Host "🎉 INICIALIZACIÓN COMPLETADA" -ForegroundColor Green
Write-Host "============================" -ForegroundColor Green
Write-Host ""

Write-Host "✅ Entorno configurado exitosamente" -ForegroundColor Green
Write-Host "✅ ArgoCD Application creada" -ForegroundColor Green
Write-Host "✅ Primer deployment ejecutado" -ForegroundColor Green
Write-Host "✅ Port-forwards configurados" -ForegroundColor Green

Write-Host ""
Write-Host "🌐 ACCESOS DISPONIBLES:" -ForegroundColor Cyan
Write-Host "  • ArgoCD UI: https://localhost:8081" -ForegroundColor White
Write-Host "    Usuario: admin" -ForegroundColor Gray
Write-Host "    Password: $argocdPassword" -ForegroundColor Gray
Write-Host "  • Security Filters: http://localhost:8080" -ForegroundColor White
Write-Host "  • Demo Microservice: http://localhost:8082" -ForegroundColor White

Write-Host ""
Write-Host "🧪 PRUEBAS DISPONIBLES:" -ForegroundColor Cyan
Write-Host "  • Prueba básica:" -ForegroundColor White
Write-Host "    .\scripts\test-endpoint.ps1 -RequestCount 10 -Verbose" -ForegroundColor Gray
Write-Host "  • Prueba de carga:" -ForegroundColor White
Write-Host "    .\scripts\test-endpoint.ps1 -RequestCount 100 -DelayMs 50" -ForegroundColor Gray

Write-Host ""
Write-Host "🚀 PRÓXIMOS PASOS:" -ForegroundColor Cyan
Write-Host "  1. Abrir ArgoCD UI y verificar la aplicación" -ForegroundColor White
Write-Host "  2. Ejecutar pruebas para validar funcionamiento" -ForegroundColor White
Write-Host "  3. Probar actualización de versión:" -ForegroundColor White
Write-Host "     .\scripts\build-and-deploy.ps1 -Version 'v-1-1-0'" -ForegroundColor Gray
Write-Host "  4. Observar rollout automático en ArgoCD" -ForegroundColor White

Write-Host ""
Write-Host "📚 DOCUMENTACIÓN:" -ForegroundColor Cyan
Write-Host "  • README completo: README-GATEWAY-SETUP.md" -ForegroundColor Gray
Write-Host "  • Troubleshooting: Ver sección en README" -ForegroundColor Gray

Write-Host ""
Write-Host "💡 NOTA IMPORTANTE:" -ForegroundColor Yellow
Write-Host "Si los servicios no responden inmediatamente, espera 2-3 minutos" -ForegroundColor Gray
Write-Host "para que todos los pods estén completamente listos." -ForegroundColor Gray