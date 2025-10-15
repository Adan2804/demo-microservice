# 1. Primero aplicar los servicios del rollout
kubectl apply -f k7s/04-rollout-services.yaml

# 2. Luego aplicar el rollout
kubectl apply -f k7s/05-argo-rollout.yaml

# 3. Verificar que se creó el rollout
kubectl get rollouts

# 4. Ver el estado detallado
kubectl argo rollouts get rollout demo-microservice-rollout

# 5. Verificar que los pods se están creando
kubectl get pods -l app=demo-microservice-rollout

# 6. Ver los servicios del rollout
kubectl get svc -l app=demo-microservice-rollout

