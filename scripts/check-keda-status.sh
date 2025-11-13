#!/bin/bash

# Script para verificar el estado de KEDA y el microservicio
echo "🔍 VERIFICANDO ESTADO DE KEDA"
echo "=============================="

# 1. Verificar pods
echo ""
echo "📦 PODS:"
kubectl get pods -n default -l app=demo-microservice-keda

# 2. Verificar service
echo ""
echo "🌐 SERVICE:"
kubectl get svc demo-microservice-keda -n default

# 3. Verificar ScaledObject
echo ""
echo "📊 SCALEDOBJECT:"
kubectl get scaledobject demo-microservice-keda-scaler -n default

# 4. Verificar HPA
echo ""
echo "📈 HPA (creado por KEDA):"
kubectl get hpa demo-microservice-keda-hpa -n default 2>/dev/null || echo "HPA aún no creado"

# 5. Verificar PDB
echo ""
echo "🛡️  PDB:"
kubectl get pdb demo-microservice-keda-pdb -n default

# 6. Verificar port-forwards activos
echo ""
echo "🔌 PORT-FORWARDS ACTIVOS:"
ps aux | grep "kubectl port-forward" | grep -v grep || echo "No hay port-forwards activos"

# 7. Verificar endpoints del service
echo ""
echo "🎯 ENDPOINTS DEL SERVICE:"
kubectl get endpoints demo-microservice-keda -n default

# 8. Probar conectividad interna
echo ""
echo "🧪 PROBANDO CONECTIVIDAD INTERNA:"
POD_NAME=$(kubectl get pods -n default -l app=demo-microservice-keda -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD_NAME" ]; then
    echo "Pod encontrado: $POD_NAME"
    echo ""
    echo "Health check interno:"
    kubectl exec -n default $POD_NAME -- curl -s http://localhost:8080/actuator/health 2>/dev/null || echo "❌ No se pudo conectar"
    echo ""
    echo "Info interno:"
    kubectl exec -n default $POD_NAME -- curl -s http://localhost:8080/actuator/info 2>/dev/null || echo "❌ No se pudo conectar"
else
    echo "❌ No se encontró ningún pod"
fi

# 9. Sugerencias
echo ""
echo "💡 SUGERENCIAS:"
echo ""
echo "Si el microservicio está corriendo pero no puedes acceder desde localhost:"
echo ""
echo "1. Iniciar port-forward:"
echo "   kubectl port-forward svc/demo-microservice-keda -n default 8082:8080"
echo ""
echo "2. Probar endpoints correctos:"
echo "   curl http://localhost:8082/actuator/health"
echo "   curl http://localhost:8082/actuator/info"
echo ""
echo "3. Si usas Postman, los endpoints son:"
echo "   GET http://localhost:8082/actuator/health"
echo "   GET http://localhost:8082/actuator/info"
echo ""
echo "❌ ENDPOINTS INCORRECTOS (no existen):"
echo "   http://localhost:8082/demo/info  ← INCORRECTO"
echo "   http://localhost:8082/info       ← INCORRECTO"
echo ""
echo "✅ ENDPOINTS CORRECTOS:"
echo "   http://localhost:8082/actuator/health  ← CORRECTO"
echo "   http://localhost:8082/actuator/info    ← CORRECTO"
