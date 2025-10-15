# Infraestructura de Microservicio con Experimentos

## 📁 Estructura de Archivos

### Infraestructura Base (Siempre desplegada)
- `01-production-deployment.yaml` - Deployment de producción (3 pods)
- `02-services.yaml` - Servicios permanentes (stable + experiment)
- `03-proxy-intelligent.yaml` - Proxy inteligente con fallback automático

### Experimento (Desplegado manualmente)
- `experiment-deployment.yaml` - Deployment de experimento (1 pod)

## 🚀 Flujo de Uso

### 1. Desplegar Infraestructura Base
```bash
# Ejecutar una sola vez al inicio
./scripts/deploy-base-infrastructure.sh
```

**Resultado:**
- ✅ 3 pods de producción activos
- ✅ Servicios permanentes creados
- ✅ Proxy inteligente funcionando
- ✅ URL única: http://localhost:8080/api/v1/experiment/version

### 2. Configurar Argo Rollouts (Opcional - para promociones automáticas)
```bash
# Configurar Argo Rollouts
./scripts/setup-argo-rollouts.sh

# Iniciar dashboard web para ver los rollouts
./scripts/start-argo-dashboard.sh
```

**Resultado:**
- ✅ Argo Rollouts instalado y configurado
- ✅ BlueGreen deployment listo
- ✅ Servicios de rollout creados
- ✅ Dashboard web en http://localhost:3100

### 3. Activar Experimento (Cuando necesites probar)
```bash
# Desplegar experimento
kubectl apply -f k7s/experiment-deployment.yaml

# Verificar que esté funcionando
kubectl get pods -l tier=experiment
```

**Resultado:**
- ✅ 1 pod de experimento activo
- ✅ Proxy detecta automáticamente el experimento
- ✅ Tráfico con header va al experimento
- ✅ Tráfico normal sigue yendo a producción

### 4. Probar Ambas Versiones
```bash
# Tráfico normal → Producción (3 pods)
curl http://localhost:8080/api/v1/experiment/version

# Tráfico con header → Experimento (1 pod)
curl -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
     http://localhost:8080/api/v1/experiment/version
```

### 5A. Promover Experimento con Argo Rollouts (Recomendado)
```bash
# Si el experimento funciona bien, promover automáticamente
./scripts/promote-experiment-to-rollout.sh
```

**Resultado:**
- ✅ BlueGreen deployment automático
- ✅ Sin downtime
- ✅ Rollback automático si falla
- ✅ Nueva versión en producción

### 5B. O Desactivar Experimento (Si no quieres promover)
```bash
# Eliminar experimento
kubectl delete -f k7s/experiment-deployment.yaml

# Verificar que se eliminó
kubectl get pods -l tier=experiment
```

**Resultado:**
- ✅ Experimento eliminado
- ✅ Proxy hace fallback automático a producción
- ✅ Producción no se afecta

### 6. Rollback (Si es necesario)
```bash
# Hacer rollback a versión anterior
./scripts/rollback-rollout.sh
```

## 🔧 Personalización

### Cambiar Imagen del Experimento
Editar `experiment-deployment.yaml`:
```yaml
containers:
- name: demo-microservice
  image: demo-microservice:nueva-version  # Cambiar aquí
  env:
  - name: APP_VERSION
    value: "experiment-v2.0.0"  # Cambiar versión
```

### Cambiar Imagen de Producción
Editar `01-production-deployment.yaml`:
```yaml
containers:
- name: demo-microservice
  image: demo-microservice:nueva-stable  # Cambiar aquí
  env:
  - name: APP_VERSION
    value: "production-v2.0.0"  # Cambiar versión
```

## 🏭 Integración con Azure DevOps

### Pipeline Principal (Producción)
```yaml
- task: KubernetesManifest@0
  displayName: 'Update Production'
  inputs:
    action: 'patch'
    resourceToPatch: 'name'
    name: 'demo-microservice-production'
    patch: |
      spec:
        template:
          spec:
            containers:
            - name: demo-microservice
              image: $(containerRegistry)/$(imageName):$(Build.BuildId)
```

### Task Externo (Experimento)
```yaml
- task: KubernetesManifest@0
  displayName: 'Deploy Experiment'
  inputs:
    action: 'deploy'
    manifests: 'k7s/experiment-deployment.yaml'
    containers: |
      demo-microservice=$(containerRegistry)/$(imageName):$(Build.BuildId)-experiment
```

## 🔍 Comandos Útiles

```bash
# Ver estado completo
kubectl get pods -l app=demo-microservice --show-labels

# Ver logs del proxy
kubectl logs -l app=intelligent-proxy

# Ver estado del proxy
curl http://localhost:8080/proxy/status

# Ver rollouts
kubectl get rollouts
kubectl argo rollouts get rollout demo-microservice-rollout

# Dashboard de Argo Rollouts
./scripts/start-argo-dashboard.sh  # http://localhost:3100

# Port-forward manual (si se pierde)
kubectl port-forward svc/intelligent-proxy 8080:80

# Demo completa
./scripts/demo-complete-argo.sh

# Limpiar todo
kubectl delete -f k7s/
```

## ✅ Ventajas de esta Arquitectura

1. **🔒 Seguridad**: Experimento no afecta producción
2. **🚀 Performance**: Fallback automático si experimento falla
3. **💰 Costo**: Solo 1 pod adicional cuando se necesita
4. **🔧 Flexibilidad**: Activar/desactivar experimentos fácilmente
5. **📊 Testing**: Misma URL, diferentes versiones
6. **🏭 DevOps**: Integración simple con pipelines