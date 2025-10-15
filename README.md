# Demo Microservice - Argo CD + Rollouts + Experiments

Stack completo de GitOps con Argo CD, Blue-Green deployments con Argo Rollouts, y A/B testing con Argo Experiments.

## 🚀 Inicio Rápido

### Opción 1: Solo Experimento (Funcionando ✅)
```bash
cd scripts
./deploy-basic-working.sh
```

### Opción 2: Stack Completo de Argo
```bash
cd scripts
chmod +x setup-complete-argo.sh
./setup-complete-argo.sh
```

## 📋 Estado Actual

✅ **Funcionando perfectamente:**
- **Argo Experiments**: Header routing con aislamiento de tráfico
- **NGINX Proxy**: Routing correcto basado en headers
- **4 pods**: 3 stable + 1 experimental
- **URL**: `http://localhost:8080/api/v1/experiment/version`
- **Header**: `aws-cf-cd-super-svp-9f8b7a6d = 123e4567-e89b-12d3-a456-42661417400`

## 🏗️ Arquitectura

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Argo CD       │    │  Argo Rollouts  │    │ Argo Experiments│
│   (GitOps)      │───▶│  (Deployments)  │───▶│  (A/B Testing)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Git Repo      │    │  Blue-Green     │    │ Header Routing  │
│   (Source)      │    │  Canary         │    │ Traffic Split   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📁 Scripts Principales

### Instalación
- `setup-complete-argo.sh` - **Script maestro** para todo el stack
- `install-argocd.sh` - Solo Argo CD
- `install-rollouts.sh` - Solo Argo Rollouts
- `deploy-basic-working.sh` - Solo experimento (funciona ✅)

### Operación
- `create-rollout.sh` - Crear Rollout basado en experimento
- `fix-nginx-dns.sh` - Arreglar routing (si es necesario)
- `check-status.sh` - Verificar estado

## 🎯 Flujo de Trabajo

### 1. Desarrollo y Testing
```bash
# Crear experimento para A/B testing
./deploy-basic-working.sh

# Probar con header en Postman
# URL: http://localhost:8080/api/v1/experiment/version
# Header: aws-cf-cd-super-svp-9f8b7a6d = 123e4567-e89b-12d3-a456-42661417400
```

### 2. Promoción a Rollout
```bash
# Si experimento es exitoso, crear rollout
./create-rollout.sh

# Actualizar imagen
kubectl argo rollouts set image demo-microservice-rollout \
  demo-microservice=demo-microservice:experiment

# Promover
kubectl argo rollouts promote demo-microservice-rollout
```

### 3. GitOps con Argo CD
```bash
# Actualizar manifiestos en Git
git add k8s/
git commit -m "Update to new version"
git push

# Argo CD sincroniza automáticamente
```

## 🔧 Configuración

### Experimento
- **Duración**: 4 horas
- **Pods**: 3 stable + 1 experimental
- **Routing**: Header HTTP
- **Aislamiento**: Tráfico completamente separado

### Rollout
- **Estrategia**: Blue-Green
- **Análisis**: Automático con métricas
- **Promoción**: Manual con validación

### Argo CD
- **URL**: https://localhost:8081
- **Usuario**: admin
- **Sync**: Automático desde Git

## 📚 Documentación

- **`COMPLETE_ARGO_GUIDE.md`** - Guía completa paso a paso
- **`HEADER_ROUTING_GUIDE.md`** - Detalles del routing por headers

## 🛠️ Comandos Útiles

### Argo CD
```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443 &
# https://localhost:8081
```

### Argo Rollouts
```bash
kubectl argo rollouts dashboard &
# http://localhost:3100
```

### Experimentos
```bash
kubectl get experiments
kubectl describe experiment demo-microservice-experiment
```

## ✅ Verificación

```bash
# Verificar experimento
curl http://localhost:8080/api/v1/experiment/version

# Con header experimental
curl -H "aws-cf-cd-super-svp-9f8b7a6d: 123e4567-e89b-12d3-a456-42661417400" \
     http://localhost:8080/api/v1/experiment/version

# Verificar rollouts
kubectl get rollouts

# Verificar Argo CD
kubectl get applications -n argocd
```

## 🎉 ¡Listo para Producción!

El stack está completamente funcional y listo para:
- **A/B Testing** con experimentos
- **Blue-Green Deployments** con rollouts  
- **GitOps** con Argo CD
- **Observabilidad** con métricas y análisis