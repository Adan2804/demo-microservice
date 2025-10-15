# Proxy Inteligente - Documentación Completa

## Descripción General

El **Proxy Inteligente** es un componente crítico que permite realizar **testing en producción** de forma segura mediante enrutamiento inteligente de tráfico basado en headers HTTP específicos.

## Arquitectura del Proxy

### Componentes Principales

1. **ConfigMap** - Configuración de Nginx
2. **Deployment** - Pod del proxy con Nginx Alpine
3. **Service** - Exposición del proxy como LoadBalancer

## Funcionalidades Clave

### 1. Enrutamiento Inteligente por Headers

**Header de Experimento:**
```
aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400
```

**Comportamiento:**
- **Sin header**: Tráfico va a producción estable
- **Con header**: Tráfico va al experimento (con fallback automático)

### 2. Backends Configurados

#### Backend de Producción (stable_backend)
```nginx
upstream stable_backend {
    server demo-microservice-stable:80;
}
```
- **Propósito**: Servir tráfico normal de usuarios
- **Disponibilidad**: Siempre disponible
- **Pods**: 3 pods de producción estable

#### Backend de Experimento (experiment_backend)
```nginx
upstream experiment_backend {
    server demo-microservice-experiment:80 max_fails=1 fail_timeout=1s;
    server demo-microservice-stable:80 backup;
}
```
- **Propósito**: Servir tráfico de testing
- **Fallback**: Automático a producción si falla
- **Pods**: 1 pod experimental + fallback a producción

### 3. Configuración de Logs

#### Log Format Detallado
```nginx
log_format detailed '$remote_addr - $remote_user [$time_local] "$request" '
                   '$status $body_bytes_sent "$http_referer" '
                   '"$http_user_agent" '
                   'experiment_header="$http_aws_cf_cd_super_svp_9f8b7a6d" '
                   'upstream_used="$upstream_addr"';
```

**Información Capturada:**
- IP del cliente
- Timestamp de la request
- Request completa
- Status code de respuesta
- User agent
- **Header de experimento** (si presente)
- **Upstream utilizado** (para debugging)

### 4. Endpoints de Monitoreo

#### Health Check Interno (Puerto 8080)
```
GET /health
Response: "intelligent-proxy-healthy"
```
- **Propósito**: Kubernetes readiness/liveness probes
- **Puerto**: 8080 (interno)
- **Sin logs**: `access_log off`

#### Health Check Público (Puerto 80)
```
GET /proxy/health
Response: "proxy-ok"
```
- **Propósito**: Monitoreo externo
- **Puerto**: 80 (público)

#### Status del Proxy (Puerto 80)
```
GET /proxy/status
Response: Información detallada del proxy
```
**Información Mostrada:**
- Configuración de backends
- Header requerido para experimentos
- Estado de fallbacks

### 5. Configuración de Proxy

#### Headers Forwarded
```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

#### Timeouts y Reintentos
```nginx
proxy_connect_timeout 5s;
proxy_send_timeout 30s;
proxy_read_timeout 30s;
proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
proxy_next_upstream_tries 2;
```

**Configuración Explicada:**
- **Connect timeout**: 5 segundos para conectar
- **Send timeout**: 30 segundos para enviar datos
- **Read timeout**: 30 segundos para leer respuesta
- **Next upstream**: Intenta siguiente servidor en caso de error
- **Max tries**: Máximo 2 intentos

### 6. Headers de Respuesta

#### Para Tráfico de Experimento
```nginx
add_header X-Routed-To "experiment-attempt" always;
add_header X-Fallback-Available "yes" always;
```

#### Para Tráfico Normal
```nginx
add_header X-Routed-To "production-stable" always;
```

**Propósito**: Debugging y trazabilidad del enrutamiento

## Especificaciones del Deployment

### Imagen Base
```yaml
image: nginx:alpine
```
- **Ventajas**: Ligera, segura, rápida
- **Tamaño**: ~5MB
- **Base**: Alpine Linux

### Recursos Asignados
```yaml
resources:
  requests:
    memory: "32Mi"
    cpu: "25m"
  limits:
    memory: "64Mi"
    cpu: "50m"
```

**Justificación:**
- **Requests bajos**: Proxy ligero, no requiere muchos recursos
- **Limits conservadores**: Evita consumo excesivo de recursos

### Puertos Expuestos
```yaml
ports:
- containerPort: 80    # Tráfico principal
  name: http
- containerPort: 8080  # Health checks
  name: health
```

### Health Checks
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
```

## Especificaciones del Service

### Tipo de Servicio
```yaml
type: LoadBalancer
```
- **Propósito**: Acceso externo al proxy
- **Comportamiento**: Minikube crea túnel automático

### Puertos Expuestos
```yaml
ports:
- port: 80        # Tráfico principal
  targetPort: 80
  name: http
- port: 8080      # Health checks
  targetPort: 8080
  name: health
```

## Flujo de Tráfico

### Tráfico Normal (Sin Header)
```
Usuario → Proxy (puerto 80) → stable_backend → Producción (3 pods)
```

### Tráfico de Experimento (Con Header)
```
Testing → Proxy (puerto 80) → experiment_backend → Experimento (1 pod)
                                     ↓ (si falla)
                                stable_backend → Producción (3 pods)
```

## Casos de Uso

### 1. Testing A/B
- Enviar porcentaje de tráfico al experimento
- Comparar métricas entre versiones
- Rollback automático si hay problemas

### 2. Feature Flags
- Activar funcionalidades para usuarios específicos
- Testing gradual de nuevas features
- Control granular del rollout

### 3. Canary Deployments
- Probar nueva versión con tráfico limitado
- Monitoreo de métricas en tiempo real
- Promoción gradual basada en resultados

## Monitoreo y Debugging

### Logs de Acceso
```bash
# Ver logs del proxy
kubectl logs -l app=intelligent-proxy -f

# Filtrar por experimentos
kubectl logs -l app=intelligent-proxy | grep "experiment_header"
```

### Métricas Importantes
- **Request rate**: Requests por segundo
- **Error rate**: Porcentaje de errores
- **Latency**: Tiempo de respuesta
- **Upstream distribution**: Distribución de tráfico

### Comandos de Debugging
```bash
# Estado del proxy
curl http://localhost:8080/proxy/status

# Health check
curl http://localhost:8080/proxy/health

# Test con header
curl -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
     http://localhost:8080/api/v1/experiment/version

# Test sin header
curl http://localhost:8080/api/v1/experiment/version
```

## Seguridad

### Headers de Experimento
- **No públicos**: Solo para testing interno
- **Específicos**: UUID único para evitar colisiones
- **Rotables**: Pueden cambiarse fácilmente

### Aislamiento
- **Fallback automático**: Si experimento falla, va a producción
- **Sin impacto**: Usuarios normales nunca ven experimentos
- **Logs separados**: Trazabilidad completa

## Limitaciones y Consideraciones

### Limitaciones
1. **Single Point of Failure**: Si el proxy falla, todo el tráfico se ve afectado
2. **Latencia adicional**: Proxy añade ~1-2ms de latencia
3. **Recursos**: Consume CPU y memoria adicionales

### Mitigaciones
1. **Health checks agresivos**: Detección rápida de fallos
2. **Recursos limitados**: Evita consumo excesivo
3. **Fallback automático**: Recuperación automática ante fallos

## Evolución y Mejoras Futuras

### Posibles Mejoras
1. **Múltiples headers**: Soporte para diferentes tipos de experimentos
2. **Weighted routing**: Distribución porcentual de tráfico
3. **Métricas integradas**: Prometheus/Grafana integration
4. **Rate limiting**: Protección contra abuso
5. **SSL termination**: HTTPS nativo

### Escalabilidad
- **Horizontal**: Múltiples replicas del proxy
- **Vertical**: Más recursos por replica
- **Caching**: Redis para configuración dinámica

## Conclusión

El Proxy Inteligente es un componente esencial que permite:
- **Testing seguro en producción**
- **Fallback automático** ante fallos
- **Trazabilidad completa** del tráfico
- **Operación transparente** para usuarios

Su diseño robusto y configuración flexible lo hacen ideal para implementar estrategias de deployment avanzadas como Blue-Green, Canary, y A/B testing en entornos de producción.