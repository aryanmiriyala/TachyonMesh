.PHONY: build deploy destroy port-forward-grafana port-forward-envoy load-test status clean all

# ---------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------
IMAGE_NAME := tachyonmesh-backend
IMAGE_TAG  := latest
K8S_DIR    := k8s
NAMESPACE  := default

# ---------------------------------------------------------------
# Build
# ---------------------------------------------------------------
build:
	@echo "==> Building $(IMAGE_NAME):$(IMAGE_TAG)..."
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) ./backend

# ---------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------
deploy:
	@echo "==> Applying Kubernetes manifests..."
	kubectl apply -f $(K8S_DIR)/backend.yaml
	kubectl apply -f $(K8S_DIR)/envoy.yaml
	kubectl apply -f $(K8S_DIR)/prometheus.yaml
	kubectl apply -f $(K8S_DIR)/grafana-dashboards.yaml
	kubectl apply -f $(K8S_DIR)/grafana.yaml
	@echo "==> Waiting for rollouts..."
	kubectl rollout status deployment/backend --timeout=120s
	kubectl rollout status deployment/envoy --timeout=120s
	kubectl rollout status deployment/prometheus --timeout=120s
	kubectl rollout status deployment/grafana --timeout=120s
	@echo "==> All deployments ready."

all: build deploy

# ---------------------------------------------------------------
# Destroy
# ---------------------------------------------------------------
destroy:
	@echo "==> Tearing down TachyonMesh..."
	kubectl delete -f $(K8S_DIR)/ --ignore-not-found

clean: destroy
	@echo "==> Removing Docker image..."
	docker rmi $(IMAGE_NAME):$(IMAGE_TAG) || true

# ---------------------------------------------------------------
# Port Forwarding
# ---------------------------------------------------------------
port-forward-grafana:
	@echo "==> Grafana available at http://localhost:3000 (admin / tachyonmesh)"
	kubectl port-forward svc/grafana-service 3000:3000

port-forward-envoy:
	@echo "==> Envoy proxy available at http://localhost:8080"
	@echo "==> Envoy admin available at http://localhost:9901"
	kubectl port-forward svc/envoy-service 8080:8080 9901:9901

port-forward-prometheus:
	@echo "==> Prometheus available at http://localhost:9090"
	kubectl port-forward svc/prometheus-service 9090:9090

# ---------------------------------------------------------------
# Load Testing (requires 'hey': brew install hey)
# ---------------------------------------------------------------
load-test:
	@echo "==> Running load test: 50 RPS for 2 minutes against Envoy..."
	hey -z 2m -q 50 -c 50 -m GET http://localhost:8080/api/process

# ---------------------------------------------------------------
# Status
# ---------------------------------------------------------------
status:
	@echo "==> Pod status:"
	@kubectl get pods -l project=tachyonmesh -o wide
	@echo ""
	@echo "==> Services:"
	@kubectl get svc -l project=tachyonmesh

# ---------------------------------------------------------------
# Chaos Engineering (Fault Injection)
# ---------------------------------------------------------------
chaos-abort:
	@echo "==> Running chaos test: Injecting 50% HTTP 503 Aborts..."
	hey -z 30s -q 20 -c 20 -H "x-envoy-fault-abort-request: 503" -H "x-envoy-fault-abort-request-percentage: 50" http://localhost:8080/api/process

chaos-delay:
	@echo "==> Running chaos test: Injecting 3s Latency Delay..."
	hey -z 30s -q 20 -c 20 -H "x-envoy-fault-delay-request: 3000" -H "x-envoy-fault-delay-request-percentage: 100" http://localhost:8080/api/process
