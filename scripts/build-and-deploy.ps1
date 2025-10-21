# Script completo para build, push y deploy de nueva versión
# Simula un pipeline completo de CI/CD

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [string]$Namespace = "demo-app",
    [string]$Registry = "your-registry.com",
    [string]$Repository = "demo-microservice",
    [string]$ConfigRepo = "https://github.com/your-org/demo-microservice-config.git",
    [string]$ConfigBranch = "main",
    [switch]$SkipBuild = $false,
    [switch]$SkipPush = $false,
    [switch]$AutoSync = $false,
    [switch]$Verbose = $false
)

Write-Host "🚀 BUILD AND DEPLOY PIPELINE" -ForegroundColor Green
Write-Host "=============================" -ForegroundColor Green
Write-Host ""

# Validaciones iniciales
if (-not $Version) {
    Write-Host "❌ Error: Version es requerida" -ForegroundColor Red
    exit 1
}

$imageName = "$Registry/$Repository"
$imageTag = $Version
$fullImageName = "${imageName}:${imageTag}"

Write-Host "📋 Configuración del Pipeline:" -ForegroundColor Cyan
Write-Host "  • Versión: $Version" -ForegroundColor White
Write-Host "  • Imagen: $fullImageName" -ForegroundColor White
Write-Host "  • Namespace: $Namespace" -ForegroundColor White
Write-Host "  • Config Repo: $ConfigRepo" -ForegroundColor White
Write-Host "  • Config Branch: $ConfigBranch" -ForegroundColor White
Write-Host ""

# FASE 1: BUILD DE LA APLICACIÓN
if (-not $SkipBuild) {
    Write-Host "🔨 FASE 1: BUILD DE LA APLICACIÓN" -ForegroundColor Yellow
    Write-Host "=================================" -ForegroundColor Yellow
    
    try {
        # Verificar que estamos en el directorio correcto
        if (-not (Test-Path "pom.xml") -and -not (Test-Path "build.gradle")) {
            Write-Host "❌ Error: No se encontró pom.xml o build.gradle" -ForegroundColor Red
            Write-Host "Ejecuta desde el directorio raíz del proyecto" -ForegroundColor Red
            exit 1
        }
        
        # Build con Maven o Gradle
        if (Test-Path "pom.xml") {
            Write-Host "📦 Compilando con Maven..." -ForegroundColor Blue
            mvn clean package -DskipTests
            if ($LASTEXITCODE -ne 0) {
                throw "Error en Maven build"
            }
        } elseif (Test-Path "build.gradle") {
            Write-Host "📦 Compilando con Gradle..." -ForegroundColor Blue
            ./gradlew clean build -x test
            if ($LASTEXITCODE -ne 0) {
                throw "Error en Gradle build"
            }
        }
        
        Write-Host "✅ Build completado exitosamente" -ForegroundColor Green
        
    } catch {
        Write-Host "❌ Error en build: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "⏭️  FASE 1: SALTANDO BUILD (--SkipBuild especificado)" -ForegroundColor Gray
}

# FASE 2: BUILD Y PUSH DE IMAGEN DOCKER
if (-not $SkipPush) {
    Write-Host ""
    Write-Host "🐳 FASE 2: BUILD Y PUSH DE IMAGEN DOCKER" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    
    try {
        # Verificar Docker
        docker version | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Docker no está disponible"
        }
        
        # Build de imagen Docker
        Write-Host "🔨 Construyendo imagen Docker..." -ForegroundColor Blue
        docker build -t $fullImageName . --build-arg APP_VERSION=$Version
        if ($LASTEXITCODE -ne 0) {
            throw "Error en Docker build"
        }
        
        # Tag adicional como latest
        docker tag $fullImageName "${imageName}:latest"
        
        Write-Host "✅ Imagen construida: $fullImageName" -ForegroundColor Green
        
        # Push a registry (simulado - en producción sería real)
        Write-Host "📤 Simulando push a registry..." -ForegroundColor Blue
        Write-Host "  docker push $fullImageName" -ForegroundColor Gray
        Write-Host "  docker push ${imageName}:latest" -ForegroundColor Gray
        
        # En un entorno real, descomenta estas líneas:
        # docker push $fullImageName
        # docker push "${imageName}:latest"
        
        Write-Host "✅ Push completado (simulado)" -ForegroundColor Green
        
    } catch {
        Write-Host "❌ Error en Docker: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host ""
    Write-Host "⏭️  FASE 2: SALTANDO DOCKER PUSH (--SkipPush especificado)" -ForegroundColor Gray
}

# FASE 3: ACTUALIZACIÓN DE MANIFIESTOS
Write-Host ""
Write-Host "📝 FASE 3: ACTUALIZACIÓN DE MANIFIESTOS" -ForegroundColor Yellow
Write-Host "=======================================" -ForegroundColor Yellow

try {
    # Generar valores para tokens
    $dtReleaseVersion = $Version
    $dtBuildVersion = "build-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $targetUri = "http://demo-microservice.$Namespace.svc.cluster.local"
    
    # Ejecutar script de reemplazo de tokens
    Write-Host "🔄 Ejecutando reemplazo de tokens..." -ForegroundColor Blue
    
    $tokenParams = @{
        Version = $Version
        Image = $fullImageName
        Namespace = $Namespace
        TargetUri = $targetUri
        DtReleaseVersion = $dtReleaseVersion
        DtBuildVersion = $dtBuildVersion
        ManifestsPath = "k8s-manifests"
        OutputPath = "k8s-manifests-processed"
        Verbose = $Verbose
    }
    
    & ".\scripts\replace-tokens.ps1" @tokenParams
    
    Write-Host "✅ Manifiestos actualizados" -ForegroundColor Green
    
} catch {
    Write-Host "❌ Error actualizando manifiestos: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# FASE 4: COMMIT Y PUSH A REPO DE CONFIGURACIÓN
Write-Host ""
Write-Host "📤 FASE 4: ACTUALIZACIÓN DEL REPO DE CONFIGURACIÓN" -ForegroundColor Yellow
Write-Host "=================================================" -ForegroundColor Yellow

try {
    # En un entorno real, aquí harías:
    # 1. Clone del repo de configuración
    # 2. Copia de manifiestos procesados
    # 3. Commit y push
    
    Write-Host "📋 Simulando actualización del repo de configuración:" -ForegroundColor Blue
    Write-Host "  git clone $ConfigRepo config-repo" -ForegroundColor Gray
    Write-Host "  cp k8s-manifests-processed/* config-repo/k8s-manifests/" -ForegroundColor Gray
    Write-Host "  cd config-repo" -ForegroundColor Gray
    Write-Host "  git add ." -ForegroundColor Gray
    Write-Host "  git commit -m 'Deploy version $Version'" -ForegroundColor Gray
    Write-Host "  git push origin $ConfigBranch" -ForegroundColor Gray
    
    Write-Host "✅ Repo de configuración actualizado (simulado)" -ForegroundColor Green
    
    # Mostrar diff de cambios principales
    Write-Host ""
    Write-Host "📊 Cambios principales en esta versión:" -ForegroundColor Cyan
    Write-Host "  • Imagen: $fullImageName" -ForegroundColor White
    Write-Host "  • APP_VERSION: $Version" -ForegroundColor White
    Write-Host "  • DT_RELEASE_VERSION: $dtReleaseVersion" -ForegroundColor White
    Write-Host "  • DT_BUILD_VERSION: $dtBuildVersion" -ForegroundColor White
    
} catch {
    Write-Host "❌ Error actualizando repo: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# FASE 5: SINCRONIZACIÓN CON ARGOCD
Write-Host ""
Write-Host "🔄 FASE 5: SINCRONIZACIÓN CON ARGOCD" -ForegroundColor Yellow
Write-Host "====================================" -ForegroundColor Yellow

try {
    # Verificar conexión a ArgoCD
    Write-Host "🔍 Verificando conexión a ArgoCD..." -ForegroundColor Blue
    
    # En un entorno real, usarías argocd CLI:
    # argocd app sync demo-microservice-app
    
    if ($AutoSync) {
        Write-Host "🚀 Forzando sincronización automática..." -ForegroundColor Blue
        Write-Host "  argocd app sync demo-microservice-app --force" -ForegroundColor Gray
        Write-Host "✅ Sincronización iniciada" -ForegroundColor Green
    } else {
        Write-Host "⏸️  Sincronización manual requerida" -ForegroundColor Yellow
        Write-Host "Ejecuta: argocd app sync demo-microservice-app" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "❌ Error con ArgoCD: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Sincroniza manualmente desde la UI de ArgoCD" -ForegroundColor Yellow
}

# FASE 6: VERIFICACIÓN DEL DEPLOYMENT
Write-Host ""
Write-Host "🔍 FASE 6: VERIFICACIÓN DEL DEPLOYMENT" -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Yellow

try {
    Write-Host "⏳ Esperando que ArgoCD aplique los cambios..." -ForegroundColor Blue
    Write-Host "Esto puede tomar 1-3 minutos dependiendo de la configuración de sync" -ForegroundColor Gray
    
    # Esperar un poco para que ArgoCD procese
    Start-Sleep -Seconds 30
    
    Write-Host ""
    Write-Host "📊 Estado actual del cluster:" -ForegroundColor Cyan
    
    # Verificar deployments
    Write-Host "🚀 Deployments:" -ForegroundColor Blue
    kubectl get deployments -n $Namespace -l app=demo-microservice
    
    Write-Host ""
    Write-Host "📦 Pods:" -ForegroundColor Blue
    kubectl get pods -n $Namespace -l app=demo-microservice
    
    Write-Host ""
    Write-Host "🔍 Imagen actual del deployment:" -ForegroundColor Blue
    $currentImage = kubectl get deployment demo-microservice -n $Namespace -o jsonpath='{.spec.template.spec.containers[0].image}' 2>$null
    if ($currentImage) {
        Write-Host "  Imagen: $currentImage" -ForegroundColor White
        if ($currentImage -eq $fullImageName) {
            Write-Host "  ✅ Imagen actualizada correctamente" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Imagen aún no actualizada (ArgoCD sync pendiente)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  ⚠️  Deployment no encontrado o ArgoCD aún no ha sincronizado" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "🏷️  Versión actual en labels:" -ForegroundColor Blue
    $currentVersion = kubectl get deployment demo-microservice -n $Namespace -o jsonpath='{.spec.template.metadata.labels.version}' 2>$null
    if ($currentVersion) {
        Write-Host "  Versión: $currentVersion" -ForegroundColor White
        if ($currentVersion -eq $Version) {
            Write-Host "  ✅ Versión actualizada correctamente" -ForegroundColor Green
        } else {
            Write-Host "  ⚠️  Versión aún no actualizada" -ForegroundColor Yellow
        }
    }
    
} catch {
    Write-Host "❌ Error verificando deployment: $($_.Exception.Message)" -ForegroundColor Red
}

# RESUMEN FINAL
Write-Host ""
Write-Host "🎉 PIPELINE COMPLETADO" -ForegroundColor Green
Write-Host "======================" -ForegroundColor Green
Write-Host ""

Write-Host "📋 Resumen de la ejecución:" -ForegroundColor Cyan
Write-Host "  • Versión desplegada: $Version" -ForegroundColor White
Write-Host "  • Imagen: $fullImageName" -ForegroundColor White
Write-Host "  • Namespace: $Namespace" -ForegroundColor White
Write-Host "  • Build: $(if ($SkipBuild) { 'Saltado' } else { 'Completado' })" -ForegroundColor White
Write-Host "  • Docker Push: $(if ($SkipPush) { 'Saltado' } else { 'Completado (simulado)' })" -ForegroundColor White
Write-Host "  • Manifiestos: Actualizados" -ForegroundColor White
Write-Host "  • ArgoCD Sync: $(if ($AutoSync) { 'Automático' } else { 'Manual requerido' })" -ForegroundColor White

Write-Host ""
Write-Host "🚀 Próximos pasos:" -ForegroundColor Cyan
Write-Host "  1. Verificar sincronización en ArgoCD UI" -ForegroundColor White
Write-Host "  2. Esperar que los pods se reinicien (1-3 minutos)" -ForegroundColor White
Write-Host "  3. Probar el endpoint con el script de pruebas:" -ForegroundColor White
Write-Host "     .\scripts\test-endpoint.ps1 -RequestCount 20 -Verbose" -ForegroundColor Gray
Write-Host "  4. Verificar que X-App-Version sea: $Version" -ForegroundColor White

Write-Host ""
Write-Host "🔗 Enlaces útiles:" -ForegroundColor Cyan
Write-Host "  • ArgoCD UI: http://localhost:8081 (si tienes port-forward activo)" -ForegroundColor Gray
Write-Host "  • Logs del deployment: kubectl logs -n $Namespace -l app=demo-microservice -f" -ForegroundColor Gray
Write-Host "  • Estado de ArgoCD: kubectl get applications -n argocd" -ForegroundColor Gray