# Demo Microservice - Gateway Setup con ArgoCD

## 🎯 Objetivo

Implementar un flujo end-to-end donde ArgoCD detecta cambios en manifiestos, sincroniza automáticamente, y los pods se recrean tomando nueva imagen y variables de entorno. El Security Filters (Spring Cloud Gateway) mantiene una URI estable hacia el Service de Kubernetes.

## 🏗️ Arquitectura

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Git Repo      │    │    ArgoCD        │    │   Kubernetes    │
│   (Config)      │───▶│   (Sync)         │───▶│    Cluster      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  CI/CD Pipeline │    │ Security Filters │    │ Demo Microservice│
│ (Build & Push)  │    │ (Spring Gateway) │───▶│  (Spring Boot)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 📋 Componentes

### 1. Demo Microservice (Spring Boot)
- **Endpoint**: `GET /demo/monetary`
- **Headers**: `X-App-Version` (desde env var `APP_VERSION`)
- **Response**: JSON con versión y metadata

### 2. Security Filters (Spring Cloud Gateway)
- **Función**: Proxy inteligente con filtros de seguridad
- **URI Estable**: Siempre apunta al Service de Kubernetes
- **Configuración**: Via ConfigMap con checksum para forzar rollouts

### 3. ArgoCD Application
- **Sync**: Automático cuando detecta cambios en Git
- **Rollout**: Automático cuando cambia `spec.template` del Deployment

## 🚀 Pasos de Implementación

### Paso 1: Preparar el Entorno

```powershell
# 1. Verificar que ArgoCD esté funcionando
kubectl get pods -n argocd

# 2. Configurar la aplicación en ArgoCD
.\scripts\setup-argocd-app.ps1 -AppName "demo-microservice-app" -Namespace "demo-app"

# 3. Verificar que la aplicación se creó
kubectl get applications -n argocd
```

### Paso 2: Primer Deployment (v-1-0-0)

```powershell
# 1. Build y deploy de la versión inicial
.\scripts\build-and-deploy.ps1 -Version "v-1-0-0" -Registry "your-registry.com"

# 2. Verificar que ArgoCD sincronizó
# Abrir ArgoCD UI: https://localhost:8081
# Usuario: admin, Password: (obtener con el script)

# 3. Verificar pods
kubectl get pods -n demo-app -l app=demo-microservice

# 4. Probar endpoint
.\scripts\test-endpoint.ps1 -RequestCount 10 -Verbose
```

### Paso 3: Actualización a Nueva Versión (v-1-1-0)

```powershell
# 1. Deploy nueva versión
.\scripts\build-and-deploy.ps1 -Version "v-1-1-0" -Registry "your-registry.com"

# 2. Observar en ArgoCD UI:
#    - Estado cambia de Synced → OutOfSync → Syncing → Synced
#    - Pods antiguos se terminan, nuevos pods se crean

# 3. Verificar cambios
kubectl get deployment demo-microservice -n demo-app -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment demo-microservice -n demo-app -o jsonpath='{.spec.template.metadata.labels.version}'

# 4. Probar que el header cambió
.\scripts\test-endpoint.ps1 -RequestCount 20 -Verbose
# Debe mostrar X-App-Version: v-1-1-0
```

### Paso 4: Verificación Completa

```powershell
# 1. Verificar que todos los componentes funcionan
kubectl get all -n demo-app

# 2. Probar endpoint directo del microservicio
kubectl port-forward -n demo-app svc/demo-microservice 8082:80
# En otra terminal: curl http://localhost:8082/demo/monetary

# 3. Probar a través del Security Filters
kubectl port-forward -n demo-app svc/security-filters 8083:80
# En otra terminal: curl http://localhost:8083/demo/monetary

# 4. Ejecutar prueba de carga
.\scripts\test-endpoint.ps1 -RequestCount 100 -DelayMs 50
```

## 🔧 Tokens Utilizados

Los manifiestos usan estos tokens que son reemplazados automáticamente:

| Token | Descripción | Ejemplo |
|-------|-------------|---------|
| `#{namespace}#` | Namespace de Kubernetes | `demo-app` |
| `#{version}#` | Versión de la aplicación | `v-1-1-0` |
| `#{image}#` | Imagen Docker completa | `your-registry.com/demo-microservice:v-1-1-0` |
| `#{target_uri}#` | URI del microservicio | `http://demo-microservice.demo-app.svc.cluster.local` |
| `#{dt_release_version}#` | Versión de release | `v-1-1-0` |
| `#{dt_build_version}#` | Versión de build | `build-20241021-143022` |
| `#{config_checksum}#` | Hash del ConfigMap | `a1b2c3d4e5f6g7h8` |

## 📊 Validaciones de Funcionamiento

### ✅ Criterios de Aceptación

1. **ArgoCD Sync**: 
   - Estado cambia de `OutOfSync` → `Synced` tras commit
   - No errores en la sincronización

2. **Pod Rollout**:
   - Pods antiguos se reemplazan por nuevos
   - Nueva imagen se refleja en el deployment
   - Labels de versión se actualizan

3. **Header X-App-Version**:
   - Refleja la nueva versión en todas las respuestas
   - Consistente en el 100% de las requests

4. **Gateway Rollout**:
   - Cambio en ConfigMap provoca rollout del gateway
   - Nueva configuración se aplica correctamente

### 🧪 Scripts de Prueba

```powershell
# Prueba básica (10 requests)
.\scripts\test-endpoint.ps1 -RequestCount 10 -Verbose

# Prueba de carga (100 requests)
.\scripts\test-endpoint.ps1 -RequestCount 100 -DelayMs 100

# Prueba a través del gateway
.\scripts\test-endpoint.ps1 -UseGateway -RequestCount 50
```

## 🔄 Flujo de Rollout

### Secuencia Completa

1. **Developer** hace cambios en código
2. **CI/CD Pipeline** ejecuta:
   ```powershell
   .\scripts\build-and-deploy.ps1 -Version "v-1-2-0"
   ```
3. **Script** actualiza manifiestos con nuevos tokens
4. **Git Commit** actualiza repo de configuración
5. **ArgoCD** detecta cambios automáticamente
6. **Kubernetes** aplica nuevos manifiestos:
   - Deployment cambia → Pods se recrean
   - ConfigMap cambia → Gateway se reinicia (por checksum)
7. **Verificación** automática con scripts de prueba

### Triggers de Rollout

Los pods se reinician cuando cambia:
- ✅ `spec.template.spec.containers[0].image`
- ✅ `spec.template.spec.containers[0].env`
- ✅ `spec.template.metadata.labels.version`
- ✅ `spec.template.metadata.annotations.checksum/config`

## 🛠️ Troubleshooting

### Problemas Comunes

1. **ArgoCD no sincroniza**:
   ```powershell
   # Forzar sync manual
   kubectl patch application demo-microservice-app -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
   ```

2. **Pods no se recrean**:
   ```powershell
   # Verificar que cambió spec.template
   kubectl get deployment demo-microservice -n demo-app -o yaml | grep -A 10 "template:"
   ```

3. **Header X-App-Version incorrecto**:
   ```powershell
   # Verificar env var en pod
   kubectl get pod -n demo-app -l app=demo-microservice -o jsonpath='{.items[0].spec.containers[0].env}'
   ```

4. **Gateway no actualiza configuración**:
   ```powershell
   # Verificar checksum en deployment
   kubectl get deployment security-filters -n demo-app -o jsonpath='{.spec.template.metadata.annotations.checksum/config}'
   ```

## 📁 Estructura de Archivos

```
demo-microservice/
├── src/main/java/com/demo/           # Código fuente Spring Boot
├── k8s-manifests/                    # Manifiestos con tokens
│   ├── deployment-demo-microservice.yaml
│   ├── service-demo-microservice.yaml
│   ├── configmap-security-filters.yaml
│   ├── deployment-security-filters.yaml
│   └── argocd-application.yaml
├── k8s-manifests-processed/          # Manifiestos procesados (generados)
└── scripts/                          # Scripts de automatización
    ├── setup-argocd-app.ps1         # Configurar ArgoCD
    ├── build-and-deploy.ps1          # Pipeline completo
    ├── replace-tokens.ps1            # Reemplazo de tokens
    └── test-endpoint.ps1             # Pruebas de endpoint
```

## 🎯 Próximos Pasos

1. **Configurar ArgoCD**: `.\scripts\setup-argocd-app.ps1`
2. **Primer Deploy**: `.\scripts\build-and-deploy.ps1 -Version "v-1-0-0"`
3. **Actualizar Versión**: `.\scripts\build-and-deploy.ps1 -Version "v-1-1-0"`
4. **Verificar Funcionamiento**: `.\scripts\test-endpoint.ps1 -RequestCount 50 -Verbose`