# Instrucciones Simples - Testing de Nueva Versión

## Concepto
Durante un rolling update, puedes probar la nueva versión con un header HTTP antes de que todos los usuarios la vean.

## Pasos

### 1. Aplicar Istio configs (solo una vez)
```bash
kubectl apply -f argocd-keda/05-destination-rule.yaml
kubectl apply -f argocd-keda/06-virtualservice-canary.yaml
```

### 2. Cuando quieras probar una nueva versión

Edita `argocd-keda/01-deployment-with-hpa.yaml` y cambia:
- `version: stable` → `version: canary`
- `image: zadan04/demo-microservice:stable` → `image: zadan04/demo-microservice:experiment`

### 3. Aplicar el cambio
```bash
kubectl apply -f argocd-keda/01-deployment-with-hpa.yaml
```

### 4. Probar

**Tráfico normal (va a pods stable):**
```bash
curl http://192.168.49.2:32647/actuator/info
```

**Tráfico de prueba (va a pods canary):**
```bash
curl -H "x-test-new: true" http://192.168.49.2:32647/actuator/info
```

### 5. Cuando todo esté OK

Cambia todos los pods a la nueva versión:
- Edita el deployment
- Cambia `version: canary` → `version: stable`
- Cambia la imagen a la versión final
- Aplica

## Resumen

- **version: stable** = Pods que reciben tráfico normal
- **version: canary** = Pods que solo reciben tráfico con header `x-test-new: true`
- Sin Jobs complejos, sin automatización que falla
- Control manual simple y directo
