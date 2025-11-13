# ✅ Checklist de Implementación KEDA en el Banco

## 📋 Pre-requisitos

### En el Cluster
- [ ] KEDA está instalado en el cluster
  ```bash
  kubectl get crd scaledobjects.keda.sh
  ```
- [ ] El deployment objetivo existe
  ```bash
  kubectl get deployment <service>-deployment -n <namespace>
  ```
- [ ] Tienes permisos para crear ScaledObjects
  ```bash
  kubectl auth can-i create scaledobjects.keda.sh -n <namespace>
  ```

### En tu Librería
- [ ] Añadidas las 7 nuevas variables de KEDA
- [ ] Validación de formato de cron implementada
- [ ] Validación de rangos de réplicas implementada
- [ ] Documentación actualizada con las nuevas variables

## 🔧 Configuración

### 1. Variables de Ambiente
- [ ] Archivo `variables-keda-qa.properties` creado
- [ ] Variable `timezone` configurada correctamente
- [ ] Variable `replicas-downscale` < `replicas-upscale`
- [ ] Variable `replicas-downscale` >= 1
- [ ] Variable `replicas-upscale` <= `replicas-max`
- [ ] Variables de cron con formato válido
- [ ] Horarios de cron tienen sentido (no se solapan incorrectamente)

### 2. Template
- [ ] Archivo `scaled-object.yaml` tiene todas las variables
- [ ] Labels del banco están presentes
- [ ] Configuración de HPA behavior está incluida
- [ ] Annotation `scaledobject.keda.sh/transfer-hpa-ownership: "true"` presente

### 3. Script de Procesamiento
- [ ] Script `replace-tokens-keda.ps1` funciona correctamente
- [ ] Genera archivo en `keda-banco-processed/`
- [ ] No quedan tokens sin reemplazar
- [ ] Archivo generado es YAML válido

## 🧪 Pruebas en Local/DEV

### Validación del Template
- [ ] Procesar template con variables de DEV
  ```powershell
  .\scripts\replace-tokens-keda.ps1 -Environment dev -Verbose
  ```
- [ ] Verificar que no hay tokens sin reemplazar
- [ ] Validar YAML con `kubectl apply --dry-run=client`
  ```bash
  kubectl apply -f keda-banco-processed/scaled-object.yaml --dry-run=client
  ```

### Prueba Funcional
- [ ] Aplicar ScaledObject en DEV
  ```bash
  kubectl apply -f keda-banco-processed/scaled-object.yaml
  ```
- [ ] Verificar que se creó correctamente
  ```bash
  kubectl get scaledobject -n <namespace>
  kubectl describe scaledobject <service>-scaled-object -n <namespace>
  ```
- [ ] Verificar que KEDA creó el HPA
  ```bash
  kubectl get hpa -n <namespace>
  ```
- [ ] Monitorear logs de KEDA
  ```bash
  kubectl logs -n keda -l app=keda-operator --tail=50 -f
  ```
- [ ] Esperar al horario de downscale y verificar que reduce pods
- [ ] Esperar al horario de upscale y verificar que aumenta pods

## 🚀 Despliegue en QA

### Pre-despliegue
- [ ] Backup del HPA actual (si existe)
  ```bash
  kubectl get hpa <service>-hpa -n <namespace> -o yaml > hpa-backup.yaml
  ```
- [ ] Documentar configuración actual de réplicas
- [ ] Notificar al equipo sobre el cambio
- [ ] Definir ventana de mantenimiento (si es necesario)

### Despliegue
- [ ] Procesar template con variables de QA
  ```powershell
  .\scripts\replace-tokens-keda.ps1 -Environment qa -Verbose
  ```
- [ ] Revisar archivo generado
- [ ] Eliminar HPA tradicional (si existe)
  ```bash
  kubectl delete hpa <service>-hpa -n <namespace>
  ```
- [ ] Aplicar ScaledObject
  ```bash
  kubectl apply -f keda-banco-processed/scaled-object.yaml
  ```
- [ ] Verificar estado
  ```bash
  kubectl get scaledobject,hpa,pods -n <namespace>
  ```

### Post-despliegue
- [ ] Verificar que los pods están corriendo
- [ ] Verificar que el HPA fue creado por KEDA
- [ ] Monitorear logs de KEDA por 10 minutos
- [ ] Verificar métricas en Dynatrace/Prometheus
- [ ] Documentar hora de despliegue

## 📊 Monitoreo (Primeras 24 horas)

### Horario de Downscale
- [ ] Verificar que reduce pods a la hora configurada
- [ ] Verificar que el número de pods es el esperado
- [ ] Verificar que no hay errores en logs de KEDA
- [ ] Verificar que la aplicación sigue funcionando

### Horario de Upscale
- [ ] Verificar que aumenta pods a la hora configurada
- [ ] Verificar que el número de pods es el esperado
- [ ] Verificar que no hay errores en logs de KEDA
- [ ] Verificar que la aplicación sigue funcionando

### Métricas
- [ ] CPU usage durante downscale
- [ ] Memory usage durante downscale
- [ ] Response time durante cambios de escala
- [ ] Error rate durante cambios de escala
- [ ] Latencia durante cambios de escala

## 🔍 Troubleshooting

### Si el ScaledObject no se crea
```bash
# Ver eventos del namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Ver logs de KEDA
kubectl logs -n keda -l app=keda-operator --tail=100

# Verificar CRD
kubectl get crd scaledobjects.keda.sh
```

### Si no escala en el horario esperado
```bash
# Ver detalles del ScaledObject
kubectl describe scaledobject <service>-scaled-object -n <namespace>

# Ver HPA generado
kubectl describe hpa <service>-hpa -n <namespace>

# Verificar timezone
kubectl get scaledobject <service>-scaled-object -n <namespace> -o yaml | grep timezone
```

### Si hay conflictos con HPA existente
```bash
# Listar todos los HPAs
kubectl get hpa -n <namespace>

# Eliminar HPA conflictivo
kubectl delete hpa <hpa-name> -n <namespace>

# Reiniciar KEDA operator (último recurso)
kubectl rollout restart deployment keda-operator -n keda
```

## 📝 Documentación

### Documentar en Confluence/Wiki
- [ ] Configuración de variables usadas
- [ ] Horarios de escalado elegidos
- [ ] Justificación de los horarios
- [ ] Resultados de las pruebas
- [ ] Métricas de ahorro de recursos
- [ ] Contactos del equipo responsable

### Actualizar Runbooks
- [ ] Procedimiento de despliegue
- [ ] Procedimiento de rollback
- [ ] Troubleshooting común
- [ ] Comandos de verificación

## 🔄 Rollback (Si es necesario)

### Plan de Rollback
- [ ] Eliminar ScaledObject
  ```bash
  kubectl delete scaledobject <service>-scaled-object -n <namespace>
  ```
- [ ] Restaurar HPA tradicional
  ```bash
  kubectl apply -f hpa-backup.yaml
  ```
- [ ] Verificar que vuelve a funcionar
  ```bash
  kubectl get hpa,pods -n <namespace>
  ```
- [ ] Documentar razón del rollback
- [ ] Analizar causa raíz

## ✅ Criterios de Éxito

- [ ] ScaledObject se crea sin errores
- [ ] KEDA genera HPA automáticamente
- [ ] Pods escalan según horario configurado
- [ ] No hay errores en logs de KEDA
- [ ] Aplicación funciona correctamente durante escalado
- [ ] Métricas de performance se mantienen estables
- [ ] Equipo está satisfecho con el comportamiento

## 📞 Contactos de Soporte

- **Equipo KEDA**: [email/slack]
- **Equipo Kubernetes**: [email/slack]
- **Equipo de tu aplicación**: [email/slack]
- **Soporte 24/7**: [teléfono/slack]

## 📚 Referencias Rápidas

```bash
# Ver todo relacionado con KEDA
kubectl get scaledobject,hpa,pods -n <namespace>

# Logs de KEDA en tiempo real
kubectl logs -n keda -l app=keda-operator -f

# Monitorear pods en tiempo real
kubectl get pods -n <namespace> -w

# Ver eventos recientes
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Describir ScaledObject
kubectl describe scaledobject <service>-scaled-object -n <namespace>
```

---

**Fecha de última actualización**: [Fecha]
**Versión**: 1.0
**Responsable**: [Tu nombre/equipo]
