# 🔄 Últimos Cambios - Port-Forwards Automáticos

## ✅ Cambios Realizados

Se agregó al script `setup-argocd-keda.sh` la funcionalidad de:

1. **Instalación automática de ArgoCD** (si no está instalado)
2. **Port-forward automático para ArgoCD** (puerto 8081)
3. **Port-forward automático para el microservicio** (puerto 8082)
4. **Mostrar credenciales de ArgoCD** al finalizar

## 🚀 Uso

```bash
# Ejecutar el script
./scripts/setup-argocd-keda.sh
```

**El script ahora:**
1. Verifica si ArgoCD está instalado
2. Si no está, pregunta si deseas instalarlo
3. Instala ArgoCD automáticamente si aceptas
4. Configura la aplicación de KEDA
5. Inicia port-forward para ArgoCD (puerto 8081)
6. Inicia port-forward para el microservicio (puerto 8082)
7. Muestra las credenciales de acceso

## 🌐 Acceso Después de la Instalación

### ArgoCD UI
```
URL: https://localhost:8081
Usuario: admin
Password: (mostrado al final del script)
```

### Microservicio
```
URL: http://localhost:8082
Health: http://localhost:8082/actuator/health
Info: http://localhost:8082/actuator/info
```

## 🧪 Probar el Microservicio

```bash
# Health check
curl http://localhost:8082/actuator/health

# Info
curl http://localhost:8082/actuator/info

# O abrir en el navegador
open http://localhost:8082/actuator/health  # macOS
start http://localhost:8082/actuator/health # Windows
xdg-open http://localhost:8082/actuator/health # Linux
```

## 🛑 Detener Port-Forwards

```bash
# Ver los PIDs (mostrados al final del script)
# Ejemplo: Port-forward activo (PID: 12345)

# Detener por PID
kill 12345

# O detener todos los port-forwards
pkill -f 'kubectl port-forward'
```

## 🔄 Reiniciar Port-Forwards

Si cierras la terminal o los port-forwards se detienen:

```bash
# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8081:443 &

# Microservicio
kubectl port-forward svc/demo-microservice-keda -n default 8082:8080 &
```

## 📝 Cambios en el Script

### Antes
```bash
# Solo verificaba si ArgoCD existía
if ! kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    echo "❌ ArgoCD no está instalado"
    exit 1
fi
```

### Después
```bash
# Ahora instala ArgoCD si no existe
if ! kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    echo "⚠️  ArgoCD no está instalado"
    read -p "¿Deseas instalar ArgoCD ahora? (y/N): " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Instala ArgoCD automáticamente
        kubectl create namespace argocd
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        # ... espera y configura
    fi
fi

# Configura port-forwards automáticamente
kubectl port-forward svc/argocd-server -n argocd 8081:443 &
kubectl port-forward svc/demo-microservice-keda -n default 8082:8080 &

# Muestra credenciales
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "Password: $ARGOCD_PASSWORD"
```

## 💡 Ventajas

1. **Todo en un comando**: No necesitas ejecutar múltiples scripts
2. **Instalación automática**: ArgoCD se instala si no existe
3. **Acceso inmediato**: Port-forwards configurados automáticamente
4. **Credenciales visibles**: No necesitas buscar el password
5. **Listo para probar**: Puedes acceder inmediatamente al microservicio

## 📚 Documentación Actualizada

Los siguientes archivos fueron actualizados:

- ✅ `scripts/setup-argocd-keda.sh` - Script principal
- ✅ `README.md` - Documentación principal
- ✅ `INICIO-RAPIDO.md` - Guía rápida
- ✅ `instructivo-argocd-zero-downtime.md` - Instructivo completo
- ✅ `ULTIMOS-CAMBIOS.md` - Este archivo

## 🎯 Flujo Completo

```
1. Ejecutar script
   └─> ./scripts/setup-argocd-keda.sh

2. Script verifica ArgoCD
   ├─> Si existe: Continúa
   └─> Si no existe: Pregunta si instalar
       └─> Si acepta: Instala ArgoCD

3. Script configura aplicación
   ├─> Crea Application de ArgoCD
   ├─> Configura ignoreDifferences
   └─> Hace sync inicial

4. Script configura port-forwards
   ├─> ArgoCD: puerto 8081
   └─> Microservicio: puerto 8082

5. Script muestra resumen
   ├─> URLs de acceso
   ├─> Credenciales
   ├─> PIDs de port-forwards
   └─> Comandos útiles

6. ¡Listo para usar!
   ├─> Abrir ArgoCD: https://localhost:8081
   └─> Probar micro: http://localhost:8082/actuator/health
```

## ✅ Checklist

- [x] Script instala ArgoCD si no existe
- [x] Port-forward para ArgoCD (8081)
- [x] Port-forward para microservicio (8082)
- [x] Muestra credenciales de ArgoCD
- [x] Muestra PIDs de port-forwards
- [x] Documentación actualizada
- [x] Guía de inicio rápido actualizada
- [x] Instructivo actualizado

---

**Fecha:** $(date)
**Versión:** 1.1.0
**Estado:** ✅ Completado
