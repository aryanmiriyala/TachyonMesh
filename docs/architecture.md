# Architecture

## Overview

TachyonMesh follows a proxy-first architecture where no request reaches the application directly. All inbound traffic flows through an Envoy L7 proxy that provides routing, load balancing, and metrics collection without any instrumentation in the application code.

This is the same pattern used by service meshes like Istio and AWS App Mesh -- observability is a property of the infrastructure, not the application.

## Components

### Go Backend

A minimal HTTP server built with Go's standard library (`net/http`). Two endpoints:

- **`/health`** -- Returns instantly with uptime. Used by Kubernetes readiness and liveness probes to determine pod health and traffic eligibility.
- **`/api/process`** -- Sleeps for a random 20-150ms before returning JSON. The variable latency produces realistic histogram distributions in Prometheus rather than flat lines.

**Why Go with stdlib:**
- Compiles to a single static binary with no runtime dependencies
- The `scratch` container (empty filesystem + binary) produces images under 10MB with zero attack surface
- No framework overhead signals understanding of HTTP fundamentals

**Graceful shutdown:** The server listens for SIGTERM and drains in-flight requests over a 15-second window. When Kubernetes initiates a rolling update, it sends SIGTERM first. The pod continues serving active requests rather than dropping them, then exits cleanly.

### Envoy Proxy

Envoy sits between the client and backend pods as an L7 (HTTP-aware) reverse proxy.

**Why Envoy over Nginx, HAProxy, or Traefik:**
- Built by Lyft specifically for microservice traffic at scale
- Native Prometheus metrics endpoint with zero configuration -- every request is automatically tracked for latency, response codes, and connection state
- Foundation of Istio, AWS App Mesh, and every major service mesh
- xDS API enables dynamic configuration in production (not used here, but signals awareness)

**Listener (front door):** Accepts traffic on `:8080`. The HTTP connection manager inspects each request path and routes `/api/*` and `/health` to the backend cluster. This is Layer 7 routing -- Envoy understands HTTP semantics, not just TCP ports.

**Cluster (backend pool):** Uses `STRICT_DNS` resolution against the Kubernetes Service name `backend-service`. CoreDNS returns the pod IPs, and Envoy round-robins across them. DNS re-resolution picks up new pods automatically during scaling events.

**Admin interface:** Listens on `:9901` and exposes `/stats/prometheus` with all internal metrics in Prometheus exposition format. This is the bridge between the proxy layer and the observability stack.

### Prometheus

A pull-based time-series database that scrapes Envoy's admin endpoint every 5 seconds. Each scrape downloads ~2000+ metric lines (counters, gauges, histograms), timestamps them, and stores them in the local TSDB.

**Why pull-based works here:** Prometheus reaches out to targets; targets don't need to know Prometheus exists. If a pod dies, Prometheus just stops getting data -- no backpressure, no lost connections. This model is purpose-built for dynamic Kubernetes environments.

**Retention:** Set to 1 hour (`--storage.tsdb.retention.time=1h`) to keep the local storage footprint small. In production, you'd set this to 15-30 days or use remote write to Thanos/Cortex for long-term storage.

### Grafana

Dashboarding layer that queries Prometheus via PromQL and renders time-series graphs. All configuration is injected via Kubernetes ConfigMaps mounted to Grafana's provisioning directories -- no manual UI clicks required.

Three ConfigMaps handle auto-provisioning:

| ConfigMap | Mount Path | Purpose |
|:----------|:-----------|:--------|
| `grafana-datasources` | `/etc/grafana/provisioning/datasources/` | Registers Prometheus as the default datasource |
| `grafana-dashboard-providers` | `/etc/grafana/provisioning/dashboards/` | Points to the JSON dashboard directory |
| `grafana-dashboards` | `/var/lib/grafana/dashboards/` | Contains the raw dashboard JSON |

## Request Lifecycle

```
1. Client sends GET http://localhost:8080/api/process
2. kubectl port-forward tunnels to envoy-service:8080
3. Envoy listener receives the request
4. HTTP connection manager matches prefix "/api" --> backend_cluster
5. STRICT_DNS resolved backend-service to pod IPs [10.1.0.5, 10.1.0.6]
6. Round-robin selects the next pod
7. Envoy forwards the request to that pod on :8081
8. Backend pod sleeps 20-150ms, returns JSON response
9. Envoy proxies the response back to the client
10. Envoy records internally: request count, response code, latency bucket
```

## Metrics Lifecycle

```
1. Every 5s, Prometheus GETs envoy-service:9901/stats/prometheus
2. Envoy returns all metrics (counters, histograms, gauges)
3. Prometheus parses, timestamps, and stores each data point
4. Grafana queries Prometheus every 5s via PromQL
5. Dashboard panels re-render with latest data
```

## Kubernetes Networking

All inter-service communication uses Kubernetes DNS (CoreDNS). Every Service gets a stable DNS name inside the cluster:

| DNS Name | Used By | Purpose |
|:---------|:--------|:--------|
| `backend-service` | Envoy | Discover backend pod IPs for load balancing |
| `envoy-service` | Prometheus | Scrape target for metrics collection |
| `prometheus-service` | Grafana | Datasource for PromQL queries |

**Service types:**
- **ClusterIP** (backend, prometheus, grafana) -- Internal only. Not exposed outside the cluster.
- **NodePort** (envoy) -- Accessible from the host on ports 30080/30901. In production, this would be a LoadBalancer with a cloud provider's LB in front.

**`imagePullPolicy: Never`** on the backend tells Kubernetes to use the locally built Docker image rather than pulling from a registry. Standard pattern for local development with Docker Desktop's built-in Kubernetes.
