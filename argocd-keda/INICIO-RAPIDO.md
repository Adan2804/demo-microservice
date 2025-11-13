# 🚀 Inicio Rápido - ArgoCD-KEDA Zero Downtime

## ⚡ Instalación en 1 Comando

```bash
./scripts/setup-argocd-keda.sh
```

## ✅ ¿Qué hace?

Configura ArgoCD + KEDA con **ZERO DOWNTIME**:
- ✅ Instala ArgoCD (si no está instalado)
- ✅ Nunca 0 pods durante syncs
- ✅ PodDisruptionBudget protege disponibilidad
- ✅ KEDA escala sin conflictos con ArgoCD
- ✅ Rolling updates seguros
- ✅ Port-forward automático para ArgoCD (puerto 8081)
- ✅ Port-forward automático para el microservicio (puerto 8082)

## 📊 Verificar

```bash
# Ver todo
kubectl get all,pdb,scaledobject,hpa -l app=demo-microservice-keda

# Monitorear
./scripts/monitor-keda-scaling.sh

# Acceder a ArgoCD
# URL: https://localhost:8081
# Usuario: admin
# Password: (mostrado al final del script)

# Probar el microservicio
curl http://localhost:8082/actuator/health
curl http://localhost:8082/actuator/info
```

## 🧪 Probar

1. Cambiar algo en `01-deployment-with-hpa.yaml`
2. Hacer commit y push
3. ArgoCD hace sync automático
4. Monitorear: `kubectl get pods -l app=demo-microservice-keda -w`
5. ✅ Nunca verás 0 pods

## 📚 Documentación Completa

- **Guía completa:** `instructivo-argocd-zero-downtime.md`
- **Detalles técnicos:** `CAMBIOS-ZERO-DOWNTIME.md`
- **Resumen:** `RESUMEN-ADAPTACION.md`

## 🎯 Configuración Clave

```yaml
# Deployment
maxUnavailable: 0        # Nunca 0 pods
maxSurge: 1              # 1 pod extra durante update

# PDB
minAvailable: 1          # Siempre al menos 1 pod

# KEDA
minReplicaCount: 2       # Nunca menos de 2 pods

# ArgoCD
ignoreDifferences:
  - /spec/replicas       # KEDA gestiona réplicas
```

## ⏰ Horarios de Escalado

- **5:55 PM - 6:00 PM:** 2 pods (mínimo)
- **6:00 PM - 5:55 PM:** 3 pods (normal)
- **Timezone:** America/Bogota

## 🆘 Ayuda

```bash
# Ver estado en ArgoCD
argocd app get demo-microservice-keda

# Ver logs de KEDA
kubectl logs -n keda -l app=keda-operator --tail=50

# Ver eventos
kubectl get events -n default --sort-by='.lastTimestamp'

# Detener port-forwards
pkill -f 'kubectl port-forward'

# Reiniciar port-forwards
kubectl port-forward svc/argocd-server -n argocd 8081:443 &
kubectl port-forward svc/demo-microservice-keda -n default 8082:8080 &
```

---

**¡Listo para usar!** 🎉
