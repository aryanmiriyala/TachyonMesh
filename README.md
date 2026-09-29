<p align="center">
  <img src="https://img.shields.io/badge/Go-1.22-00ADD8?style=flat-square&logo=go&logoColor=white" alt="Go 1.22" />
  <img src="https://img.shields.io/badge/Envoy-v1.30-6C3FC5?style=flat-square&logo=envoyproxy&logoColor=white" alt="Envoy v1.30" />
  <img src="https://img.shields.io/badge/Kubernetes-local-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="Kubernetes" />
  <img src="https://img.shields.io/badge/Prometheus-v2.53-E6522C?style=flat-square&logo=prometheus&logoColor=white" alt="Prometheus" />
  <img src="https://img.shields.io/badge/Grafana-11.1-F2CC0C?style=flat-square&logo=grafana&logoColor=black" alt="Grafana" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License" />
</p>

<h1 align="center">TachyonMesh</h1>

<p align="center">
  <strong>A production-grade microservice traffic engineering lab running entirely on your local Kubernetes cluster.</strong>
</p>

<p align="center">
  Envoy L7 proxy - Round-robin load balancing - Prometheus metrics pipeline - Auto-provisioned Grafana dashboards
</p>

---

TachyonMesh is a fully runnable reference architecture that demonstrates how modern infrastructure teams build observable, proxy-driven service topologies. Every component is deployed as declarative Kubernetes manifests with zero manual configuration -- `make all` and you have a live system with traffic flowing, metrics collecting, and dashboards rendering.

This is not a tutorial scaffold. It's a working system designed to be read, forked, extended, and used as proof of hands-on infrastructure engineering capability.

## Table of Contents

- [Architecture](#architecture)
- [What's Inside](#whats-inside)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [Build](#1-build-the-backend-image)
  - [Deploy](#2-deploy-the-stack)
  - [Verify](#3-verify-the-deployment)
  - [Observe](#4-access-the-dashboards)
  - [Load Test](#5-generate-traffic)
- [Configuration Reference](#configuration-reference)
  - [Envoy Proxy](#envoy-proxy)
  - [Prometheus Scrape Config](#prometheus-scrape-config)
  - [Grafana Provisioning](#grafana-provisioning)
- [Dashboard Panels](#dashboard-panels)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Extending TachyonMesh](#extending-tachyonmesh)
- [Teardown](#teardown)
- [License](#license)

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
                    |  L7 Routing + Load Balancer |
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
                                        |  (auto-provisioned)
                                        +----------------+
```

**Traffic flow:** Client --> Envoy (L7 route matching, round-robin) --> Backend pods

**Metrics flow:** Prometheus scrapes Envoy's `/stats/prometheus` every 5s --> Grafana queries Prometheus via PromQL

## What's Inside

| Component | Image | Purpose |
|:----------|:------|:--------|
| **Go Backend** | `tachyonmesh-backend:latest` (scratch, ~7MB) | Stateless API with simulated 20-150ms latency. Graceful shutdown on SIGTERM. |
| **Envoy Proxy** | `envoyproxy/envoy:v1.30-latest` | L7 ingress gateway. STRICT_DNS service discovery. Round-robin load balancing. Native Prometheus metrics. |
| **Prometheus** | `prom/prometheus:v2.53.0` | Pull-based metrics collection from Envoy's admin endpoint. 5-second scrape interval. 1-hour local retention. |
| **Grafana** | `grafana/grafana:11.1.0` | Auto-provisioned dashboarding. Prometheus datasource and a 3-panel traffic dashboard are injected via ConfigMaps on boot. |

### Design Highlights

- **Zero-instrumentation observability** -- The Go backend has no metrics library. All telemetry is captured at the Envoy proxy layer, exactly how service meshes (Istio, Linkerd) operate in production.
- **Scratch container** -- The Go binary is statically compiled and runs in an empty container: no shell, no OS packages, no attack surface.
- **GitOps-ready** -- Every configuration, dashboard, and routing rule is declarative YAML. `make all` reproduces the entire system from a clean cluster.
- **Production health patterns** -- Liveness and readiness probes on every workload. Kubernetes will auto-restart unhealthy pods and hold traffic until backends are ready.

## Project Structure

```
TachyonMesh/
 |
 |-- backend/
 |   |-- main.go              # Go HTTP server (stdlib only)
 |   |-- go.mod               # Module definition
 |   +-- Dockerfile           # Multi-stage: golang:1.22-alpine -> scratch
 |
 |-- envoy/
 |   +-- envoy.yaml           # Envoy config (standalone reference copy)
 |
 |-- k8s/
 |   |-- backend.yaml         # Deployment (2 replicas) + ClusterIP Service
 |   |-- envoy.yaml           # ConfigMap + Deployment + NodePort Service
 |   |-- prometheus.yaml      # ConfigMap + Deployment + ClusterIP Service
 |   |-- grafana.yaml         # Deployment + ClusterIP Service
 |   +-- grafana-dashboards.yaml  # Datasource, provider & dashboard ConfigMaps
 |
 |-- Makefile                 # Build, deploy, test, port-forward, teardown
 +-- README.md
```

## Prerequisites

| Tool | Version | Install |
|:-----|:--------|:--------|
| Docker Desktop | 4.x+ (with Kubernetes enabled) | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) |
| kubectl | 1.28+ | Ships with Docker Desktop, or `brew install kubectl` |
| hey | any | `brew install hey` |

> **Using Minikube instead?** Run `eval $(minikube docker-env)` before `make build` so the image is accessible to the Minikube VM.

**Verify your environment:**

```bash
docker version          # Docker daemon running?
kubectl cluster-info    # Kubernetes reachable?
hey --help              # Load tester installed?
```

## Getting Started

### 1. Build the Backend Image

```bash
make build
```

Compiles the Go binary in a builder stage and packages it into a `scratch` container. Final image is typically under 10MB.

```
==> Building tachyonmesh-backend:latest...
```

### 2. Deploy the Stack

```bash
make deploy
```

Applies all Kubernetes manifests in dependency order and blocks until every deployment reports ready:

```
==> Applying Kubernetes manifests...
==> Waiting for rollouts...
deployment "backend" successfully rolled out
deployment "envoy" successfully rolled out
deployment "prometheus" successfully rolled out
deployment "grafana" successfully rolled out
==> All deployments ready.
```

> **Shortcut:** `make all` runs both `build` and `deploy` in sequence.

### 3. Verify the Deployment

```bash
make status
```

```
==> Pod status:
NAME                          READY   STATUS    RESTARTS   AGE
backend-7d4f8b6c5-k2x9m      1/1     Running   0          45s
backend-7d4f8b6c5-p8n3w      1/1     Running   0          45s
envoy-5c9f7d8b4-r6t2q        1/1     Running   0          45s
grafana-6b8c9d7e3-v4w1x      1/1     Running   0          44s
prometheus-4a7e6f5d2-m3j8k   1/1     Running   0          44s

==> Services:
NAME                 TYPE        CLUSTER-IP      PORT(S)
backend-service      ClusterIP   10.96.x.x       8081/TCP
envoy-service        NodePort    10.96.x.x       8080:30080/TCP,9901:30901/TCP
grafana-service      ClusterIP   10.96.x.x       3000/TCP
prometheus-service   ClusterIP   10.96.x.x       9090/TCP
```

### 4. Access the Dashboards

Open separate terminal windows for each port-forward:

```bash
# Terminal 1 -- Envoy (traffic ingress + admin)
make port-forward-envoy
# ==> Envoy proxy at http://localhost:8080
# ==> Envoy admin at http://localhost:9901

# Terminal 2 -- Grafana
make port-forward-grafana
# ==> Grafana at http://localhost:3000

# Terminal 3 (optional) -- Prometheus
make port-forward-prometheus
# ==> Prometheus at http://localhost:9090
```

**Smoke test the endpoints:**

```bash
# Health check (routed through Envoy to backend)
$ curl -s http://localhost:8080/health | jq
{
  "status": "ok",
  "uptime": "2m15.003s"
}

# Simulated workload (20-150ms response time)
$ curl -s http://localhost:8080/api/process | jq
{
  "status": "success",
  "processed": true
}

# Envoy metrics (raw Prometheus format)
$ curl -s http://localhost:9901/stats/prometheus | head -5
envoy_cluster_upstream_rq_total{...} 12
envoy_cluster_upstream_rq_time_bucket{...le="50"} 8
```

### 5. Generate Traffic

With the Envoy port-forward active, open a **new terminal** and run:

```bash
make load-test
```

This executes:

```bash
hey -z 2m -q 50 -c 50 -m GET http://localhost:8080/api/process
```

| Flag | Meaning |
|:-----|:--------|
| `-z 2m` | Run for 2 minutes |
| `-q 50` | 50 requests per second per worker |
| `-c 50` | 50 concurrent workers |

> **Alternative (k6):** If you prefer k6, an equivalent script would be:
> ```bash
> k6 run --vus 50 --duration 2m -e TARGET=http://localhost:8080/api/process - <<'EOF'
> import http from 'k6/http';
> export default function () { http.get(__ENV.TARGET); }
> EOF
> ```

### 6. View Live Dashboard

1. Open **http://localhost:3000**
2. Log in: `admin` / `tachyonmesh`
3. The **TachyonMesh Traffic** dashboard loads automatically as the home dashboard

The three panels will populate with live data as the load test runs. Give it ~30 seconds after starting the load test for the graphs to become meaningful.

## Configuration Reference

### Envoy Proxy

The Envoy configuration lives in the `envoy-config` ConfigMap ([`k8s/envoy.yaml`](k8s/envoy.yaml)):

| Setting | Value | Why |
|:--------|:------|:----|
| Listener address | `0.0.0.0:8080` | Accept traffic from any source on the standard HTTP port |
| Route match | `prefix: "/api"`, `prefix: "/health"` | Forward application routes to the backend cluster |
| Cluster discovery | `STRICT_DNS` | Resolve `backend-service` via Kubernetes CoreDNS to discover pod IPs |
| LB policy | `ROUND_ROBIN` | Even distribution across the 2 backend replicas |
| Admin address | `0.0.0.0:9901` | Exposes `/stats/prometheus` for Prometheus scraping and `/ready` for health probes |
| Connect timeout | `5s` | Fail fast if a backend pod is unreachable |
| Stat prefix | `ingress_http` | Namespace for all connection manager metrics |

### Prometheus Scrape Config

Defined in the `prometheus-config` ConfigMap ([`k8s/prometheus.yaml`](k8s/prometheus.yaml)):

```yaml
scrape_configs:
  - job_name: "envoy"
    metrics_path: "/stats/prometheus"
    static_configs:
      - targets: ["envoy-service:9901"]
```

- **5-second scrape interval** provides near-real-time visibility
- **`envoy-service:9901`** uses Kubernetes DNS -- no IP management required
- **1-hour TSDB retention** keeps the storage footprint small for local development

### Grafana Provisioning

Three ConfigMaps in [`k8s/grafana-dashboards.yaml`](k8s/grafana-dashboards.yaml) handle automatic setup:

| ConfigMap | Mounts To | Purpose |
|:----------|:----------|:--------|
| `grafana-datasources` | `/etc/grafana/provisioning/datasources/` | Registers Prometheus at `http://prometheus-service:9090` as the default datasource |
| `grafana-dashboard-providers` | `/etc/grafana/provisioning/dashboards/` | Tells Grafana to load dashboard JSON from `/var/lib/grafana/dashboards/` |
| `grafana-dashboards` | `/var/lib/grafana/dashboards/` | Contains the raw JSON definition for the TachyonMesh Traffic dashboard |

Grafana reads these directories on startup. No manual clicks, no API calls -- the dashboard exists the moment the pod is ready.

## Dashboard Panels

The auto-provisioned **TachyonMesh Traffic** dashboard contains three panels:

### Panel 1 -- Total Request Rate (RPS)

```promql
sum(rate(envoy_cluster_upstream_rq_total{envoy_cluster_name="backend_cluster"}[1m]))
```

Shows aggregate throughput (requests per second) flowing through Envoy to the backend, with a separate series for 2xx successes. Use this to confirm traffic is actually reaching your services and to spot throughput drops.

### Panel 2 -- Upstream Latency (P95 / P99)

```promql
histogram_quantile(0.95, sum(rate(envoy_cluster_upstream_rq_time_bucket{envoy_cluster_name="backend_cluster"}[1m])) by (le))
histogram_quantile(0.99, sum(rate(envoy_cluster_upstream_rq_time_bucket{envoy_cluster_name="backend_cluster"}[1m])) by (le))
```

Computes tail latencies from Envoy's upstream request time histogram. Expect P95 around ~135ms and P99 around ~148ms given the 20-150ms uniform random sleep in the backend. These are the metrics SRE teams use to define and monitor SLOs.

### Panel 3 -- HTTP Error Rates (4xx / 5xx)

```promql
sum(rate(envoy_cluster_upstream_rq_xx{envoy_cluster_name="backend_cluster", envoy_response_code_class="5"}[1m]))
sum(rate(envoy_cluster_upstream_rq_xx{envoy_cluster_name="backend_cluster", envoy_response_code_class="4"}[1m]))
```

Tracks client errors (4xx) and server errors (5xx) separately with color-coded severity (orange / red). Under normal load these should be zero -- a non-zero 5xx rate means something is broken.

## How It Works

### The Request Lifecycle

```
1. hey sends GET http://localhost:8080/api/process
2. kubectl port-forward tunnels the request to envoy-service:8080
3. Envoy's listener receives the request
4. HTTP Connection Manager matches prefix "/api"
5. Route action selects "backend_cluster"
6. STRICT_DNS has resolved backend-service to [10.1.0.5, 10.1.0.6]
7. Round-robin picks the next pod IP
8. Envoy opens an upstream connection to that pod on :8081
9. Backend pod sleeps 20-150ms, returns {"status":"success","processed":true}
10. Envoy proxies the response back to the client
11. Envoy internally records: request count, response code, latency histogram bucket
```

### The Metrics Lifecycle

```
1. Every 5 seconds, Prometheus GETs envoy-service:9901/stats/prometheus
2. Envoy returns ~2000+ metric lines (counters, gauges, histograms)
3. Prometheus parses and stores each metric with a timestamp
4. Grafana runs PromQL queries against Prometheus every 5 seconds
5. Dashboard panels re-render with the latest data points
```

### Kubernetes Networking

All inter-service communication uses **Kubernetes DNS** (CoreDNS):

| DNS Name | Resolves To | Used By |
|:---------|:------------|:--------|
| `backend-service` | Pod IPs of backend replicas | Envoy (STRICT_DNS cluster) |
| `envoy-service` | Pod IP of the Envoy proxy | Prometheus (scrape target) |
| `prometheus-service` | Pod IP of Prometheus | Grafana (datasource URL) |

No hardcoded IPs. No external service discovery. Kubernetes Services provide stable DNS names that survive pod restarts, scaling events, and rolling updates.

## Troubleshooting

<details>
<summary><strong>Pods stuck in ImagePullBackOff</strong></summary>

The backend image must be built locally and `imagePullPolicy` must be `Never`:

```bash
make build
kubectl get pods -l app=backend -o jsonpath='{.items[*].spec.containers[*].imagePullPolicy}'
# Should print: Never Never
```

For Minikube, ensure you built inside the Minikube Docker context:
```bash
eval $(minikube docker-env)
make build
```

</details>

<details>
<summary><strong>Envoy returns 503 (no healthy upstream)</strong></summary>

The backend pods aren't ready yet, or the readiness probe is failing:

```bash
kubectl get pods -l app=backend
kubectl describe pod -l app=backend | grep -A5 "Conditions"
kubectl logs -l app=backend
```

</details>

<details>
<summary><strong>Grafana dashboard shows "No data"</strong></summary>

1. Confirm Prometheus is scraping successfully:
   ```bash
   make port-forward-prometheus
   # Open http://localhost:9090/targets -- the envoy target should show "UP"
   ```
2. Confirm Envoy is producing metrics:
   ```bash
   curl -s http://localhost:9901/stats/prometheus | grep envoy_cluster_upstream_rq_total
   ```
3. Verify at least one request has been made through Envoy:
   ```bash
   curl http://localhost:8080/api/process
   ```

</details>

<details>
<summary><strong>Port 30080 or 30901 already in use</strong></summary>

Another service is using the NodePort. Either free the port or change the `nodePort` values in [`k8s/envoy.yaml`](k8s/envoy.yaml):

```yaml
ports:
  - port: 8080
    nodePort: 31080  # Change to an available port
```

</details>

<details>
<summary><strong>Load test shows connection refused</strong></summary>

Ensure the Envoy port-forward is running in another terminal:

```bash
make port-forward-envoy
```

Then re-run:

```bash
make load-test
```

</details>

## Extending TachyonMesh

TachyonMesh is designed as a foundation. Here are production-grade extensions you can layer on:

| Extension | What to Add | Complexity |
|:----------|:------------|:-----------|
| **Rate Limiting** | Add `envoy.filters.http.local_ratelimit` to the HTTP filter chain | Low |
| **Circuit Breaking** | Add `circuit_breakers` config to the backend cluster definition | Low |
| **Distributed Tracing** | Deploy Jaeger, enable `envoy.tracers.zipkin`, propagate trace headers | Medium |
| **mTLS** | Add TLS context with SDS (Secret Discovery Service) between Envoy and backend | Medium |
| **Canary Deployments** | Add weighted route splitting in Envoy (90/10 between v1/v2 backends) | Medium |
| **Helm Charts** | Parameterize all manifests with values.yaml for multi-environment deployment | Medium |
| **Alerting** | Add Alertmanager with rules for P99 > 200ms or 5xx rate > 1% | Medium |
| **xDS Control Plane** | Replace static config with a Go-based xDS server for dynamic Envoy configuration | High |

## Teardown

Remove all Kubernetes resources:

```bash
make destroy
```

Remove resources and the local Docker image:

```bash
make clean
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
