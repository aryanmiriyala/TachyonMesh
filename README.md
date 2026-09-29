<p align="center">
  <img src="https://img.shields.io/badge/Go-1.22-00ADD8?style=flat-square&logo=go&logoColor=white" alt="Go 1.22" />
  <img src="https://img.shields.io/badge/Envoy-v1.30-6C3FC5?style=flat-square&logo=envoyproxy&logoColor=white" alt="Envoy v1.30" />
  <img src="https://img.shields.io/badge/Kubernetes-local-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="Kubernetes" />
  <img src="https://img.shields.io/badge/Prometheus-v2.53-E6522C?style=flat-square&logo=prometheus&logoColor=white" alt="Prometheus" />
  <img src="https://img.shields.io/badge/Grafana-11.1-F2CC0C?style=flat-square&logo=grafana&logoColor=black" alt="Grafana" />
</p>

<h1 align="center">TachyonMesh</h1>

<p align="center">
  A production-grade microservice traffic engineering lab running on a local Kubernetes cluster.
</p>

<p align="center">
  Envoy L7 proxy -- Round-robin load balancing -- Prometheus metrics pipeline -- Auto-provisioned Grafana dashboards
</p>

---

## Architecture

```
                         +------------------+
                         |   Load Tester    |
                         |  (hey / k6)      |
                         +--------+---------+
                                  |
                                  | HTTP :8080
                                  v
                    +----------------------------+
                    |       Envoy Proxy          |
                    |  L7 routing + round-robin   |
                    |  :8080 ingress              |
                    |  :9901 admin / metrics      |
                    +------+----------+----------+
                           |          |
                  round-robin LB      | /stats/prometheus
                           |          |
              +------------+--+    +--+--------------+
              |               |    |                 |
        +-----v-----+  +-----v-----+  +-------------v--+
        |  Backend   |  |  Backend   |  |  Prometheus    |
        |  Pod 1     |  |  Pod 2     |  |  :9090         |
        |  :8081     |  |  :8081     |  +--------+-------+
        +------------+  +------------+           |
                                                 | PromQL
                                                 v
                                        +--------+-------+
                                        |    Grafana     |
                                        |    :3000       |
                                        +----------------+
```

## Tech Stack

| Component | Image | Role |
|:----------|:------|:-----|
| **Go Backend** | `tachyonmesh-backend:latest` (scratch, ~7MB) | Stateless API with simulated 20-150ms latency and graceful shutdown |
| **Envoy Proxy** | `envoyproxy/envoy:v1.30-latest` | L7 ingress, STRICT_DNS discovery, round-robin LB, native Prometheus metrics |
| **Prometheus** | `prom/prometheus:v2.53.0` | Pull-based metrics collection from Envoy admin, 5s scrape interval |
| **Grafana** | `grafana/grafana:11.1.0` | Auto-provisioned dashboards via ConfigMap injection |

## Project Structure

```
TachyonMesh/
  backend/
    main.go            # Go HTTP server (stdlib only)
    go.mod
    Dockerfile         # Multi-stage: golang:1.22-alpine -> scratch
  envoy/
    envoy.yaml         # Envoy proxy config (standalone reference)
  k8s/
    backend.yaml       # Deployment (2 replicas) + ClusterIP Service
    envoy.yaml         # ConfigMap + Deployment + NodePort Service
    prometheus.yaml    # ConfigMap + Deployment + ClusterIP Service
    grafana.yaml       # Deployment + ClusterIP Service
    grafana-dashboards.yaml  # Datasource, provider & dashboard ConfigMaps
  docs/
    architecture.md    # Design decisions and system deep-dive
    configuration.md   # Envoy, Prometheus, and Grafana config reference
    observability.md   # Dashboard panels, PromQL queries, metrics catalog
    troubleshooting.md # Common issues and fixes
  Makefile
```

## Prerequisites

- Docker Desktop with Kubernetes enabled (or Minikube)
- `kubectl` configured against your local cluster
- [`hey`](https://github.com/rakyll/hey) load testing tool -- `brew install hey`

## Quick Start

```bash
# Build the backend image and deploy the full stack
make all

# Open three terminal tabs for port forwarding
make port-forward-envoy       # Envoy at localhost:8080 + localhost:9901
make port-forward-grafana     # Grafana at localhost:3000
make port-forward-prometheus  # Prometheus at localhost:9090 (optional)

# Smoke test
curl http://localhost:8080/health
curl http://localhost:8080/api/process

# Generate load: 50 RPS for 2 minutes
make load-test
```

## Viewing the Dashboard

1. Open **http://localhost:3000**
2. Log in with `admin` / `tachyonmesh`
3. The **TachyonMesh Traffic** dashboard is auto-provisioned with three panels:
   - Total Request Rate (RPS)
   - P95 / P99 Upstream Latency
   - HTTP 4xx / 5xx Error Rates

## Makefile Targets

| Target | Description |
|:-------|:------------|
| `make build` | Build the Go backend Docker image |
| `make deploy` | Apply all K8s manifests, wait for rollouts |
| `make all` | Build + deploy |
| `make status` | Show pod and service status |
| `make port-forward-envoy` | Forward Envoy traffic (:8080) and admin (:9901) |
| `make port-forward-grafana` | Forward Grafana (:3000) |
| `make port-forward-prometheus` | Forward Prometheus (:9090) |
| `make load-test` | Run `hey` at 50 RPS for 2 minutes |
| `make destroy` | Delete all K8s resources |
| `make clean` | Destroy + remove Docker image |

## Teardown

```bash
# Remove all Kubernetes resources
make destroy

# Remove resources and the local Docker image
make clean
```

## Documentation

| Document | Contents |
|:---------|:---------|
| [Architecture](docs/architecture.md) | Design decisions, component roles, request lifecycle, Kubernetes networking model |
| [Configuration](docs/configuration.md) | Envoy routing, Prometheus scrape config, Grafana provisioning reference |
| [Observability](docs/observability.md) | Dashboard panels, PromQL query breakdown, metrics catalog |
| [Troubleshooting](docs/troubleshooting.md) | Common issues: ImagePullBackOff, 503s, missing data, port conflicts |
