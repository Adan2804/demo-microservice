# Script de prueba para validar el endpoint y headers X-App-Version
# Realiza múltiples requests y reporta las versiones detectadas

param(
    [int]$RequestCount = 100,
    [string]$Endpoint = "http://localhost/demo/monetary",
    [string]$GatewayEndpoint = "http://localhost:8080/demo/monetary",
    [int]$DelayMs = 100,
    [switch]$UseGateway = $false,
    [switch]$Verbose = $false
)

Write-Host "🧪 SCRIPT DE PRUEBA DE ENDPOINT" -ForegroundColor Green
Write-Host "===============================" -ForegroundColor Green
Write-Host ""

# Determinar endpoint a usar
$targetEndpoint = if ($UseGateway) { $GatewayEndpoint } else { $Endpoint }
Write-Host "🎯 Endpoint objetivo: $targetEndpoint" -ForegroundColor Cyan
Write-Host "📊 Número de requests: $RequestCount" -ForegroundColor Cyan
Write-Host "⏱️  Delay entre requests: ${DelayMs}ms" -ForegroundColor Cyan
Write-Host ""

# Contadores
$successCount = 0
$errorCount = 0
$versionCounts = @{}
$responseTimes = @()
$errors = @()

Write-Host "🚀 Iniciando pruebas..." -ForegroundColor Yellow
Write-Host ""

for ($i = 1; $i -le $RequestCount; $i++) {
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Realizar request
        $response = Invoke-WebRequest -Uri $targetEndpoint -Method GET -TimeoutSec 10
        
        $stopwatch.Stop()
        $responseTime = $stopwatch.ElapsedMilliseconds
        $responseTimes += $responseTime
        
        # Extraer headers
        $appVersion = $response.Headers["X-App-Version"]
        $gatewayVersion = $response.Headers["X-Gateway-Version"]
        $routedBy = $response.Headers["X-Routed-By"]
        
        # Parsear JSON response
        $jsonResponse = $response.Content | ConvertFrom-Json
        $bodyVersion = $jsonResponse.version
        
        # Contar versiones
        if ($appVersion) {
            if ($versionCounts.ContainsKey($appVersion)) {
                $versionCounts[$appVersion]++
            } else {
                $versionCounts[$appVersion] = 1
            }
        }
        
        $successCount++
        
        if ($Verbose) {
            Write-Host "✅ Request $i - Status: $($response.StatusCode) - X-App-Version: $appVersion - Time: ${responseTime}ms" -ForegroundColor Green
            if ($gatewayVersion) {
                Write-Host "   Gateway-Version: $gatewayVersion - Routed-By: $routedBy" -ForegroundColor Gray
            }
            Write-Host "   Body-Version: $bodyVersion" -ForegroundColor Gray
        } else {
            # Mostrar progreso cada 10 requests
            if ($i % 10 -eq 0) {
                $percentage = [math]::Round(($i / $RequestCount) * 100, 1)
                Write-Host "📈 Progreso: $percentage% ($i/$RequestCount) - Última versión: $appVersion" -ForegroundColor Blue
            }
        }
        
    } catch {
        $errorCount++
        $errorMessage = $_.Exception.Message
        $errors += "Request $i : $errorMessage"
        
        if ($Verbose) {
            Write-Host "❌ Request $i - Error: $errorMessage" -ForegroundColor Red
        }
    }
    
    # Delay entre requests
    if ($DelayMs -gt 0 -and $i -lt $RequestCount) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

Write-Host ""
Write-Host "📊 RESULTADOS DE LA PRUEBA" -ForegroundColor Green
Write-Host "===========================" -ForegroundColor Green
Write-Host ""

# Estadísticas generales
Write-Host "📈 Estadísticas Generales:" -ForegroundColor Cyan
Write-Host "  • Total de requests: $RequestCount" -ForegroundColor White
Write-Host "  • Requests exitosos: $successCount" -ForegroundColor Green
Write-Host "  • Requests fallidos: $errorCount" -ForegroundColor Red
Write-Host "  • Tasa de éxito: $([math]::Round(($successCount / $RequestCount) * 100, 2))%" -ForegroundColor Yellow
Write-Host ""

# Distribución de versiones
if ($versionCounts.Count -gt 0) {
    Write-Host "🏷️  Distribución de Versiones (X-App-Version):" -ForegroundColor Cyan
    foreach ($version in $versionCounts.Keys | Sort-Object) {
        $count = $versionCounts[$version]
        $percentage = [math]::Round(($count / $successCount) * 100, 2)
        Write-Host "  • $version : $count requests ($percentage%)" -ForegroundColor White
    }
    Write-Host ""
}

# Estadísticas de tiempo de respuesta
if ($responseTimes.Count -gt 0) {
    $avgResponseTime = [math]::Round(($responseTimes | Measure-Object -Average).Average, 2)
    $minResponseTime = ($responseTimes | Measure-Object -Minimum).Minimum
    $maxResponseTime = ($responseTimes | Measure-Object -Maximum).Maximum
    
    Write-Host "⏱️  Tiempos de Respuesta:" -ForegroundColor Cyan
    Write-Host "  • Promedio: ${avgResponseTime}ms" -ForegroundColor White
    Write-Host "  • Mínimo: ${minResponseTime}ms" -ForegroundColor Green
    Write-Host "  • Máximo: ${maxResponseTime}ms" -ForegroundColor Red
    Write-Host ""
}

# Mostrar errores si los hay
if ($errors.Count -gt 0) {
    Write-Host "❌ Errores Detectados:" -ForegroundColor Red
    foreach ($error in $errors | Select-Object -First 5) {
        Write-Host "  • $error" -ForegroundColor Yellow
    }
    if ($errors.Count -gt 5) {
        Write-Host "  • ... y $($errors.Count - 5) errores más" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Validaciones
Write-Host "✅ Validaciones:" -ForegroundColor Cyan
if ($versionCounts.Count -eq 1) {
    $singleVersion = $versionCounts.Keys | Select-Object -First 1
    Write-Host "  • ✅ Consistencia de versión: Todas las respuestas tienen la misma versión ($singleVersion)" -ForegroundColor Green
} elseif ($versionCounts.Count -gt 1) {
    Write-Host "  • ⚠️  Múltiples versiones detectadas - Posible rollout en progreso" -ForegroundColor Yellow
} else {
    Write-Host "  • ❌ No se detectaron versiones en los headers" -ForegroundColor Red
}

if ($successCount -eq $RequestCount) {
    Write-Host "  • ✅ Disponibilidad: 100% de requests exitosos" -ForegroundColor Green
} elseif ($successCount -gt ($RequestCount * 0.95)) {
    Write-Host "  • ⚠️  Disponibilidad: Alta pero con algunos errores" -ForegroundColor Yellow
} else {
    Write-Host "  • ❌ Disponibilidad: Baja - Revisar configuración" -ForegroundColor Red
}

Write-Host ""
Write-Host "🎉 Prueba completada exitosamente" -ForegroundColor Green

# Ejemplo de uso
Write-Host ""
Write-Host "💡 Ejemplos de uso:" -ForegroundColor Cyan
Write-Host "  .\test-endpoint.ps1 -RequestCount 50 -Verbose" -ForegroundColor Gray
Write-Host "  .\test-endpoint.ps1 -UseGateway -RequestCount 200 -DelayMs 50" -ForegroundColor Gray
Write-Host "  .\test-endpoint.ps1 -Endpoint 'http://security-filters/demo/monetary'" -ForegroundColor Gray