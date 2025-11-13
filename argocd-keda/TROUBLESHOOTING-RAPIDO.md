# 🔧 Troubleshooting Rápido - ArgoCD KEDA

## ✅ ArgoCD está Synced pero no puedo acceder al microservicio

### Problema: `http://localhost:8082/demo/info` no funciona

**Causa:** El path es incorrecto. El microservicio usa Spring Boot Actuator.

**Solución:**

```bash
# ❌ INCORRECTO
http://localhost:8082/demo/info
http://localhost:8082/info

# ✅ CORRECTO
http://localhost:8082/actuator/health
http://localhost:8082/actuator/info
```

### Problema: "Connection refused" en localhost:8082

**Causa:** El port-forward no está activo.

**Solución:**

```bash
# 1. Verificar si hay port-forward activo
ps aux | grep "kubectl port-forward" | grep demo-microservice-keda

# 2. Si no hay, iniciarlo
kubectl port-forward svc/demo-microservice-keda -n default 8082:8080 &

# 3. Esperar 2-3 segundos y probar
curl http://localhost:8082/actuator/health
```

### Problema: Port-forward se detiene constantemente

**Causa:** El port-forward se ejecuta en primer plano o la terminal se cierra.

**Solución:**

```bash
# Ejecutar en background con nohup
nohup kubectl port-forward svc/demo-microservice-keda -n default 8082:8080 > /tmp/pf-keda.log 2>&1 &

# Ver el PID
echo $!

# Ver logs si hay problemas
tail -f /tmp/pf-keda.log
```

## 🔍 Verificación Rápida

### 1. Verificar que todo está corriendo

```bash
# Ejecutar script de verificación
./scripts/check-keda-status.sh
```

### 2. Verificar pods

```bash
# Ver pods
kubectl get pods -n default -l app=demo-microservice-keda

# Debe mostrar algo como:
# NAME                                    READY   STATUS    RESTARTS   AGE
# demo-microservice-keda-xxx              1/1     Running   0          5m
# demo-microservice-keda-yyy              1/1     Running   0          5m
```

### 3. Verificar service

```bash
# Ver service
kubectl get svc demo-microservice-keda -n default

# Debe mostrar:
# NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
# demo-microservice-keda   ClusterIP   10.x.x.x        <none>        8080/TCP   5m
```

### 4. Probar conectividad interna

```bash
# Obtener nombre del pod
POD_NAME=$(kubectl get pods -n default -l app=demo-microservice-keda -o jsonpath='{.items[0].metadata.name}')

# Probar desde dentro del pod
kubectl exec -n default $POD_NAME -- curl -s http://localhost:8080/actuator/health

# Debe responder: {"status":"UP"}
```

## 📝 Endpoints Disponibles

### Spring Boot Actuator Endpoints

```bash
# Health check
GET http://localhost:8082/actuator/health

# Información de la aplicación
GET http://localhost:8082/actuator/info

# Métricas (si está habilitado)
GET http://localhost:8082/actuator/metrics

# Prometheus (si está habilitado)
GET http://localhost:8082/actuator/prometheus
```

### Ejemplo de respuesta exitosa

**Health:**
```json
{
  "status": "UP"
}
```

**Info:**
```json
{
  "app": {
    "name": "demo-microservice",
    "version": "stable-v1.0.0-keda",
    "environment": "production-keda"
  }
}
```

## 🧪 Probar con cURL

```bash
# Health check
curl http://localhost:8082/actuator/health

# Info
curl http://localhost:8082/actuator/info

# Con formato bonito (requiere jq)
curl -s http://localhost:8082/actuator/health | jq .
curl -s http://localhost:8082/actuator/info | jq .
```

## 🧪 Probar con Postman

### Configuración en Postman

1. **Método:** GET
2. **URL:** `http://localhost:8082/actuator/health`
3. **Headers:** (ninguno necesario)
4. **Body:** (ninguno)

### Colección de Postman

```json
{
  "info": {
    "name": "Demo Microservice KEDA",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Health Check",
      "request": {
        "method": "GET",
        "header": [],
        "url": {
          "raw": "http://localhost:8082/actuator/health",
          "protocol": "http",
          "host": ["localhost"],
          "port": "8082",
          "path": ["actuator", "health"]
        }
      }
    },
    {
      "name": "Info",
      "request": {
        "method": "GET",
        "header": [],
        "url": {
          "raw": "http://localhost:8082/actuator/info",
          "protocol": "http",
          "host": ["localhost"],
          "port": "8082",
          "path": ["actuator", "info"]
        }
      }
    }
  ]
}
```

## 🔄 Reiniciar Todo

Si nada funciona, reinicia todo:

```bash
# 1. Detener port-forwards
pkill -f "kubectl port-forward"

# 2. Eliminar recursos
kubectl delete -f argocd-keda/

# 3. Esperar 10 segundos
sleep 10

# 4. Volver a desplegar
./scripts/deploy-keda-direct.sh

# 5. Iniciar port-forward
kubectl port-forward svc/demo-microservice-keda -n default 8082:8080 &

# 6. Probar
curl http://localhost:8082/actuator/health
```

## 🆘 Comandos de Emergencia

```bash
# Ver logs del pod
kubectl logs -n default -l app=demo-microservice-keda --tail=50

# Ver eventos
kubectl get events -n default --sort-by='.lastTimestamp' | grep demo-microservice-keda

# Describir pod
kubectl describe pod -n default -l app=demo-microservice-keda

# Ver si el puerto está en uso
netstat -an | grep 8082  # Linux/Mac
netstat -ano | findstr 8082  # Windows

# Matar proceso en puerto 8082 (si está ocupado)
# Linux/Mac:
lsof -ti:8082 | xargs kill -9
# Windows:
# Buscar PID: netstat -ano | findstr 8082
# Matar: taskkill /PID <PID> /F
```

## 📊 Verificar KEDA

```bash
# Ver ScaledObject
kubectl get scaledobject demo-microservice-keda-scaler -n default

# Describir ScaledObject
kubectl describe scaledobject demo-microservice-keda-scaler -n default

# Ver HPA generado por KEDA
kubectl get hpa demo-microservice-keda-hpa -n default

# Ver logs de KEDA operator
kubectl logs -n keda -l app=keda-operator --tail=50
```

## ✅ Checklist de Verificación

- [ ] Pods están en estado `Running`
- [ ] Service existe y tiene endpoints
- [ ] Port-forward está activo en puerto 8082
- [ ] Puedo hacer curl a `http://localhost:8082/actuator/health`
- [ ] ScaledObject está en estado `Ready`
- [ ] HPA fue creado por KEDA
- [ ] PDB existe con `minAvailable: 1`

## 💡 Tips

1. **Siempre usa `/actuator/` en el path** - Es el prefijo de Spring Boot Actuator
2. **Verifica el port-forward primero** - Es la causa más común de problemas
3. **Usa el script de verificación** - `./scripts/check-keda-status.sh`
4. **Revisa los logs** - `kubectl logs` es tu amigo
5. **Paciencia** - Los pods pueden tardar 30-60 segundos en estar listos

---

**¿Aún tienes problemas?** Ejecuta:
```bash
./scripts/check-keda-status.sh
```
