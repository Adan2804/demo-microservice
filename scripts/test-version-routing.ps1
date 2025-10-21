# Script para probar el enrutamiento por versiones
# Simula el comportamiento de Bancolombia con headers de versión

param(
    [string]$GatewayUrl = "http://localhost:8080",
    [string]$TestVersion = "v-1-1-0",
    [int]$RequestCount = 50,
    [int]$DelayMs = 100,
    [switch]$TestHeaders = $true,
    [switch]$Verbose = $false
)

Write-Host "🧪 TEST DE ENRUTAMIENTO POR VERSIONES" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""

Write-Host "📋 Configuración de pruebas:" -ForegroundColor Cyan
Write-Host "  • Gateway URL: $GatewayUrl" -ForegroundColor White
Write-Host "  • Versión de prueba: $TestVersion" -ForegroundColor White
Write-Host "  • Número de requests: $RequestCount" -ForegroundColor White
Write-Host "  • Delay entre requests: ${DelayMs}ms" -ForegroundColor White
Write-Host ""

# Contadores
$successCount = 0
$errorCount = 0
$versionCounts = @{}
$gatewayVersionCounts = @{}
$serviceVersionCounts = @{}
$responseTimes = @()

Write-Host "🚀 INICIANDO PRUEBAS DE ENRUTAMIENTO..." -ForegroundColor Yellow
Write-Host ""

# PRUEBA 1: Tráfico normal (sin headers especiales)
Write-Host "📡 PRUEBA 1: Tráfico Normal" -ForegroundColor Blue
Write-Host "============================" -ForegroundColor Blue

for ($i = 1; $i -le ($RequestCount / 2); $i++) {
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        $response = Invoke-WebRequest -Uri "$GatewayUrl/demo/monetary" -Method GET -TimeoutSec 10
        
        $stopwatch.Stop()
        $responseTime = $stopwatch.ElapsedMilliseconds
        $responseTimes += $responseTime
        
        # Extraer headers de versión
        $appVersion = $response.Headers["X-App-Version"]
        $gatewayVersion = $response.Headers["X-Gateway-Version"] 
        $serviceVersion = $response.Headers["X-Service-Version"]
        $routedBy = $response.Headers["X-Routed-By"]
        
        # Contar versiones
        if ($appVersion) {
            if ($versionCounts.ContainsKey($appVersion)) {
                $versionCounts[$appVersion]++
            } else {
                $versionCounts[$appVersion] = 1
            }
        }
        
        if ($gatewayVersion) {
            if ($gatewayVersionCounts.ContainsKey($gatewayVersion)) {
                $gatewayVersionCounts[$gatewayVersion]++
            } else {
                $gatewayVersionCounts[$gatewayVersion] = 1
            }
        }
        
        $successCount++
        
        if ($Verbose) {
            Write-Host "✅ Request $i - App: $appVersion, Gateway: $gatewayVersion, Service: $serviceVersion - ${responseTime}ms" -ForegroundColor Green
        } else {
            if ($i % 10 -eq 0) {
                Write-Host "📈 Progreso normal: $i/$(($RequestCount / 2)) - Última versión: $appVersion" -ForegroundColor Blue
            }
        }
        
    } catch {
        $errorCount++
        if ($Verbose) {
            Write-Host "❌ Request $i - Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

# PRUEBA 2: Tráfico con headers de versión (si está habilitado)
if ($TestHeaders) {
    Write-Host ""
    Write-Host "📡 PRUEBA 2: Tráfico con Headers de Versión" -ForegroundColor Blue
    Write-Host "===========================================" -ForegroundColor Blue
    
    $headerTests = @(
        @{ Name = "app-version"; Value = "1.0.0"; Expected = "v-1-0-0" },
        @{ Name = "app-version"; Value = "1.1.0"; Expected = "v-1-1-0" },
        @{ Name = "staging"; Value = "true"; Expected = $TestVersion }
    )
    
    foreach ($headerTest in $headerTests) {
        Write-Host "🔍 Probando header: $($headerTest.Name) = $($headerTest.Value)" -ForegroundColor Cyan
        
        for ($i = 1; $i -le 10; $i++) {
            try {
                $headers = @{ $headerTest.Name = $headerTest.Value }
                
                $response = Invoke-WebRequest -Uri "$GatewayUrl/demo/monetary" -Method GET -Headers $headers -TimeoutSec 10
                
                $appVersion = $response.Headers["X-App-Version"]
                $gatewayVersion = $response.Headers["X-Gateway-Version"]
                $targetService = $response.Headers["X-Target-Service"]
                
                if ($Verbose) {
                    Write-Host "  ✅ Header test $i - App: $appVersion, Target: $targetService" -ForegroundColor Green
                }
                
                # Verificar si el enrutamiento funcionó como esperado
                if ($appVersion -eq $headerTest.Expected) {
                    Write-Host "  ✅ Enrutamiento correcto para $($headerTest.Name)" -ForegroundColor Green
                } else {
                    Write-Host "  ⚠️  Enrutamiento inesperado: esperado $($headerTest.Expected), actual $appVersion" -ForegroundColor Yellow
                }
                
                $successCount++
                
            } catch {
                $errorCount++
                if ($Verbose) {
                    Write-Host "  ❌ Header test $i - Error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}

# PRUEBA 3: Tráfico al endpoint bancario (simulado)
Write-Host ""
Write-Host "📡 PRUEBA 3: Endpoint Bancario Simulado" -ForegroundColor Blue
Write-Host "=======================================" -ForegroundColor Blue

for ($i = 1; $i -le 10; $i++) {
    try {
        $headers = @{ 
            "channel" = "APP"
            "Content-Type" = "application/json"
        }
        
        $bankingUrl = "$GatewayUrl/api/v1/security-filters/ch-ms-transactional-credit-card-monetary/credit-cards/cash-advance/fee"
        
        $response = Invoke-WebRequest -Uri $bankingUrl -Method GET -Headers $headers -TimeoutSec 10 2>$null
        
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 404) {
            $appVersion = $response.Headers["X-App-Version"]
            $gatewayVersion = $response.Headers["X-Gateway-Version"]
            
            if ($Verbose) {
                Write-Host "✅ Banking endpoint $i - Status: $($response.StatusCode) - Gateway: $gatewayVersion" -ForegroundColor Green
            }
            
            $successCount++
        }
        
    } catch {
        # Es normal que falle porque el microservicio bancario no existe
        if ($Verbose) {
            Write-Host "⚠️  Banking endpoint $i - Expected failure (service not deployed)" -ForegroundColor Yellow
        }
    }
}

# ANÁLISIS DE RESULTADOS
Write-Host ""
Write-Host "📊 ANÁLISIS DE RESULTADOS" -ForegroundColor Green
Write-Host "=========================" -ForegroundColor Green
Write-Host ""

# Estadísticas generales
Write-Host "📈 Estadísticas Generales:" -ForegroundColor Cyan
Write-Host "  • Total de requests: $(($RequestCount / 2) + 40)" -ForegroundColor White
Write-Host "  • Requests exitosos: $successCount" -ForegroundColor Green
Write-Host "  • Requests fallidos: $errorCount" -ForegroundColor Red
$successRate = [math]::Round(($successCount / (($RequestCount / 2) + 40)) * 100, 2)
Write-Host "  • Tasa de éxito: $successRate%" -ForegroundColor Yellow

# Distribución de versiones de aplicación
if ($versionCounts.Count -gt 0) {
    Write-Host ""
    Write-Host "🏷️  Distribución de Versiones de Aplicación:" -ForegroundColor Cyan
    foreach ($version in $versionCounts.Keys | Sort-Object) {
        $count = $versionCounts[$version]
        $percentage = [math]::Round(($count / $successCount) * 100, 2)
        Write-Host "  • $version : $count requests ($percentage%)" -ForegroundColor White
    }
}

# Distribución de versiones de gateway
if ($gatewayVersionCounts.Count -gt 0) {
    Write-Host ""
    Write-Host "🌐 Distribución de Versiones de Gateway:" -ForegroundColor Cyan
    foreach ($version in $gatewayVersionCounts.Keys | Sort-Object) {
        $count = $gatewayVersionCounts[$version]
        $percentage = [math]::Round(($count / $successCount) * 100, 2)
        Write-Host "  • $version : $count requests ($percentage%)" -ForegroundColor White
    }
}

# Estadísticas de tiempo de respuesta
if ($responseTimes.Count -gt 0) {
    $avgResponseTime = [math]::Round(($responseTimes | Measure-Object -Average).Average, 2)
    $minResponseTime = ($responseTimes | Measure-Object -Minimum).Minimum
    $maxResponseTime = ($responseTimes | Measure-Object -Maximum).Maximum
    
    Write-Host ""
    Write-Host "⏱️  Tiempos de Respuesta:" -ForegroundColor Cyan
    Write-Host "  • Promedio: ${avgResponseTime}ms" -ForegroundColor White
    Write-Host "  • Mínimo: ${minResponseTime}ms" -ForegroundColor Green
    Write-Host "  • Máximo: ${maxResponseTime}ms" -ForegroundColor Red
}

# Validaciones del patrón Bancolombia
Write-Host ""
Write-Host "✅ VALIDACIONES DEL PATRÓN BANCOLOMBIA:" -ForegroundColor Cyan

if ($versionCounts.Count -eq 1) {
    $singleVersion = $versionCounts.Keys | Select-Object -First 1
    Write-Host "  • ✅ Consistencia de versión: Todas las respuestas tienen la misma versión ($singleVersion)" -ForegroundColor Green
} elseif ($versionCounts.Count -gt 1) {
    Write-Host "  • ⚠️  Múltiples versiones detectadas - Posible transición de versión" -ForegroundColor Yellow
    Write-Host "    Esto es normal durante deployments con ArgoCD" -ForegroundColor Gray
} else {
    Write-Host "  • ❌ No se detectaron versiones en los headers" -ForegroundColor Red
}

if ($successRate -ge 95) {
    Write-Host "  • ✅ Alta disponibilidad: $successRate% de requests exitosos" -ForegroundColor Green
} elseif ($successRate -ge 80) {
    Write-Host "  • ⚠️  Disponibilidad aceptable: $successRate%" -ForegroundColor Yellow
} else {
    Write-Host "  • ❌ Baja disponibilidad: $successRate% - Revisar configuración" -ForegroundColor Red
}

# Verificar que el gateway está enrutando correctamente
$gatewayWorking = $gatewayVersionCounts.Count -gt 0
if ($gatewayWorking) {
    Write-Host "  • ✅ Gateway funcionando: Headers de versión presentes" -ForegroundColor Green
} else {
    Write-Host "  • ❌ Gateway no funcionando: No se detectaron headers de gateway" -ForegroundColor Red
}

Write-Host ""
Write-Host "🎉 Pruebas de enrutamiento completadas" -ForegroundColor Green

Write-Host ""
Write-Host "💡 Comandos útiles para debugging:" -ForegroundColor Cyan
Write-Host "  # Ver pods por versión:" -ForegroundColor Gray
Write-Host "  kubectl get pods -n demo-app -l version=$TestVersion" -ForegroundColor Gray
Write-Host "  # Ver services versionados:" -ForegroundColor Gray
Write-Host "  kubectl get svc -n demo-app -l version=$TestVersion" -ForegroundColor Gray
Write-Host "  # Ver logs del gateway:" -ForegroundColor Gray
Write-Host "  kubectl logs -n demo-app -l app=security-filters -f" -ForegroundColor Gray