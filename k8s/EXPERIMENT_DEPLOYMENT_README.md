# Argo Experiment - Documentación Completa

## Descripción General

El **Argo Experiment** es un recurso personalizado de Kubernetes que permite ejecutar **experimentos controlados** en producción para probar nuevas versiones de aplicaciones de forma segura y temporal.

## Arquitectura del Experiment

### Tipo de Recurso
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Experiment
```
- **API Group**: argoproj.io/v1alpha1
- **Tipo**: Custom Resource Definition (CRD)
- **Controlador**: Argo Rollouts Controller

## Configuración Principal

### Metadatos del Experiment
```yaml
metadata:
  name: demo-microservice-experiment
  namespace: default
  labels:
    app: demo-microservice
    tier: experiment
    managed-by: argo-experiments
```

**Explicación de Labels:**
- `app: demo-microservice` - Identifica la aplicación
- `tier: experiment` - Marca como componente experimental
- `managed-by: argo-experiments` - Indica gestión por Argo

### Especificaciones Temporales

#### Duración del Experiment
```yaml
spec:
  duration: 24h
  progressDeadlineSeconds: 86400
```

**Configuración Temporal:**
- **Duration**: 24 horas de duración máxima
- **Progress Deadline**: 86400 segundos (24h) para completar el despliegue
- **Auto-cleanup**: Se elimina automáticamente después de 24h

**Justificación:**
- **24 horas**: Tiempo suficiente para testing completo
- **Auto-cleanup**: Evita acumulación de experimentos olvidados
- **Safety net**: Previene experimentos eternos

## Template del Experiment

### Configuración de Replicas
```yaml
templates:
- name: experimental
  replicas: 1
```
- **Replicas**: Solo 1 pod para minimizar impacto
- **Nombre**: "experimental" para identificación clara

### Selector y Labels
```yaml
selector:
  matchLabels:
    app: demo-microservice
    tier: experiment
    traffic-type: experiment

template:
  metadata:
    labels:
      app: demo-microservice
      tier: experiment
      traffic-type: experiment
      version: experimental
```

**Sistema de Labels Explicado:**
- `app: demo-microservice` - Agrupa con la aplicación principal
- `tier: experiment` - Identifica como experimental
- `traffic-type: experiment` - Para enrutamiento del proxy
- `version: experimental` - Marca la versión específica

## Configuración del Container

### Imagen y Puerto
```yaml
containers:
- name: demo-microservice
  image: demo-microservice:experiment
  ports:
  - containerPort: 3000
```
- **Imagen**: `demo-microservice:experiment` (versión experimental)
- **Puerto**: 3000 (mismo que producción para compatibilidad)

### Variables de Entorno
```yaml
env:
- name: PORT
  value: "3000"
- name: APP_VERSION
  value: "experiment-candidate-v1.1.0"
- name: ENVIRONMENT
  value: "production-experiment"
- name: EXPERIMENT_ENABLED
  value: "true"
```

**Variables Explicadas:**
- `PORT`: Puerto de escucha de la aplicación
- `APP_VERSION`: Versión específica del experimento
- `ENVIRONMENT`: Identifica como entorno de experimento en producción
- `EXPERIMENT_ENABLED`: Flag booleano para lógica experimental

### Recursos Asignados
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"
```

**Justificación de Recursos:**
- **Requests bajos**: Experimento de 1 pod, no requiere muchos recursos
- **Memory**: 64Mi request, 128Mi limit (suficiente para microservicio)
- **CPU**: 50m request, 100m limit (0.05-0.1 cores)
- **Proporción 1:2**: Permite burst temporal sin desperdiciar recursos

### Health Checks

#### Readiness Probe
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 5
```

#### Liveness Probe
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 15
  periodSeconds: 10
```

**Configuración de Health Checks:**
- **Endpoint**: `/health` (mismo que producción)
- **Puerto**: 3000
- **Readiness**: 5s inicial, cada 5s (rápido para experimentos)
- **Liveness**: 15s inicial, cada 10s (más conservador)

**Diferencias con Producción:**
- **Más agresivo**: Checks más frecuentes para detección rápida
- **Inicio rápido**: 5s vs 10s para readiness
- **Monitoring intensivo**: Para experimentos temporales

## Ciclo de Vida del Experiment

### Fases del Experiment
1. **Pending**: Experiment creado, esperando recursos
2. **Running**: Pod experimental ejecutándose
3. **Successful**: Experiment completado exitosamente
4. **Failed**: Experiment falló durante ejecución
5. **Error**: Error en configuración del experiment

### Estados del Pod
```bash
# Ver estado del experiment
kubectl get experiment demo-microservice-experiment

# Ver pods del experiment
kubectl get pods -l tier=experiment

# Ver logs del experiment
kubectl logs -l tier=experiment -f
```

## Integración con Proxy Inteligente

### Enrutamiento de Tráfico
El experiment se integra con el proxy inteligente mediante:

#### Service Automático
Argo crea automáticamente un service:
```yaml
# Service generado automáticamente
apiVersion: v1
kind: Service
metadata:
  name: demo-microservice-experiment
spec:
  selector:
    app: demo-microservice
    tier: experiment
  ports:
  - port: 80
    targetPort: 3000
```

#### Header de Enrutamiento
```bash
# Tráfico normal (va a producción)
curl http://localhost:8080/api/v1/experiment/version

# Tráfico experimental (va al experiment)
curl -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
     http://localhost:8080/api/v1/experiment/version
```

## Monitoreo y Observabilidad

### Comandos de Monitoreo
```bash
# Estado general del experiment
kubectl get experiment demo-microservice-experiment -o wide

# Detalles completos
kubectl describe experiment demo-microservice-experiment

# Logs en tiempo real
kubectl logs -l tier=experiment -f --tail=100

# Métricas del pod
kubectl top pod -l tier=experiment
```

### Métricas Importantes
- **Pod Status**: Running/Pending/Failed
- **Restart Count**: Número de reinicios
- **CPU/Memory Usage**: Consumo de recursos
- **Request Rate**: Requests por segundo al experiment
- **Error Rate**: Porcentaje de errores
- **Response Time**: Latencia del experiment

### Debugging
```bash
# Entrar al pod experimental
kubectl exec -it $(kubectl get pods -l tier=experiment -o jsonpath='{.items[0].metadata.name}') -- sh

# Ver variables de entorno
kubectl exec $(kubectl get pods -l tier=experiment -o jsonpath='{.items[0].metadata.name}') -- env

# Test directo al pod
kubectl port-forward $(kubectl get pods -l tier=experiment -o jsonpath='{.items[0].metadata.name}') 3001:3000
curl http://localhost:3001/health
```

## Casos de Uso

### 1. Feature Testing
```yaml
env:
- name: FEATURE_NEW_API
  value: "true"
- name: FEATURE_ENHANCED_UI
  value: "enabled"
```

### 2. Performance Testing
```yaml
resources:
  requests:
    memory: "128Mi"  # Más memoria para testing
    cpu: "100m"      # Más CPU para carga
```

### 3. Integration Testing
```yaml
env:
- name: EXTERNAL_API_ENDPOINT
  value: "https://staging-api.example.com"
- name: DATABASE_CONNECTION
  value: "experiment-db-connection"
```

## Ventajas del Argo Experiment

### 1. Gestión Automática
- **Auto-cleanup**: Se elimina automáticamente
- **Resource management**: Gestión automática de recursos
- **Service creation**: Crea services automáticamente

### 2. Integración Nativa
- **Argo Rollouts**: Integración con rollouts
- **Kubernetes**: Recurso nativo de K8s
- **Observability**: Métricas y logs integrados

### 3. Seguridad
- **Aislamiento**: Pod separado del tráfico principal
- **Temporal**: Duración limitada automáticamente
- **Controlled**: Solo tráfico específico va al experiment

## Limitaciones y Consideraciones

### Limitaciones
1. **Single Pod**: Solo 1 replica para minimizar impacto
2. **Temporal**: Duración máxima de 24 horas
3. **Resource Constrained**: Recursos limitados intencionalmente

### Consideraciones
1. **Network Policies**: Puede requerir políticas de red específicas
2. **Service Mesh**: Integración con Istio/Linkerd si está presente
3. **Monitoring**: Requiere monitoreo específico para experimentos

## Evolución del Experiment

### Promoción a Rollout
Cuando el experiment es exitoso:
```bash
# El script 05-promote-experiment.sh:
# 1. Toma la imagen del experiment exitoso
# 2. Crea un Argo Rollout con esa imagen
# 3. Promueve gradualmente usando Blue-Green
# 4. Limpia el experiment
```

### Rollback
Si el experiment falla:
```bash
# Eliminación inmediata
kubectl delete experiment demo-microservice-experiment

# El tráfico automáticamente vuelve a producción
# (gracias al fallback del proxy)
```

## Mejores Prácticas

### 1. Configuración
- **Recursos conservadores**: No sobrecargar el cluster
- **Health checks agresivos**: Detección rápida de problemas
- **Labels consistentes**: Para integración con proxy

### 2. Monitoreo
- **Logs centralizados**: Agregación de logs del experiment
- **Métricas específicas**: Dashboards para experimentos
- **Alertas**: Notificaciones si el experiment falla

### 3. Seguridad
- **Headers únicos**: Para evitar tráfico accidental
- **Duración limitada**: No más de 24-48 horas
- **Resource limits**: Prevenir consumo excesivo

## Conclusión

El Argo Experiment proporciona:
- **Testing seguro** en producción
- **Gestión automática** del ciclo de vida
- **Integración nativa** con Kubernetes
- **Observabilidad completa** del proceso
- **Promoción controlada** a producción

Su diseño temporal y controlado lo hace ideal para validar nuevas versiones antes de promociones completas a producción.