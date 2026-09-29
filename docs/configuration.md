# Configuration Reference

## Envoy Proxy

The Envoy configuration is deployed as the `envoy-config` ConfigMap in [`k8s/envoy.yaml`](../k8s/envoy.yaml). A standalone reference copy lives at [`envoy/envoy.yaml`](../envoy/envoy.yaml).

### Listener

| Setting | Value | Rationale |
|:--------|:------|:----------|
| Address | `0.0.0.0:8080` | Accept traffic from any source on the standard HTTP port |
| Stat prefix | `ingress_http` | Namespace for all connection manager metrics in Prometheus |
| Codec type | `AUTO` | Auto-detect HTTP/1.1 vs HTTP/2 |
| Generate request ID | `true` | Envoy assigns a unique `x-request-id` to each request for tracing |

### Route Configuration

| Match | Action | Notes |
|:------|:-------|:------|
| `prefix: "/api"` | Route to `backend_cluster` | All API traffic |
| `prefix: "/health"` | Route to `backend_cluster` | Health checks through the proxy |

### Backend Cluster

| Setting | Value | Rationale |
|:--------|:------|:----------|
| Discovery type | `STRICT_DNS` | Resolves `backend-service` via CoreDNS to get pod IPs |
| LB policy | `ROUND_ROBIN` | Even distribution across replicas |
| Connect timeout | `5s` | Fail fast if a backend pod is unreachable |
| Address | `backend-service:8081` | Kubernetes Service DNS name |

### Admin Interface

| Setting | Value |
|:--------|:------|
| Address | `0.0.0.0:9901` |
| Metrics endpoint | `/stats/prometheus` (built-in) |
| Readiness endpoint | `/ready` (built-in) |

---

## Prometheus

The scrape configuration lives in the `prometheus-config` ConfigMap in [`k8s/prometheus.yaml`](../k8s/prometheus.yaml).

### Global Settings

| Setting | Value | Rationale |
|:--------|:------|:----------|
| `scrape_interval` | `5s` | Near-real-time metrics visibility |
| `evaluation_interval` | `5s` | Matches scrape interval for consistent alerting |

### Scrape Targets

| Job | Target | Metrics Path | What It Collects |
|:----|:-------|:-------------|:-----------------|
| `envoy` | `envoy-service:9901` | `/stats/prometheus` | All Envoy internal metrics: request counts, latency histograms, connection pools, circuit breaker state |

### Storage

| Setting | Value | Rationale |
|:--------|:------|:----------|
| TSDB path | `/prometheus` | Mounted as emptyDir |
| Retention | `1h` | Keeps local footprint small for a demo environment |

---

## Grafana

### Credentials

| Field | Value |
|:------|:------|
| Username | `admin` |
| Password | `tachyonmesh` |

### Provisioning System

Grafana auto-configures on boot using three ConfigMaps defined in [`k8s/grafana-dashboards.yaml`](../k8s/grafana-dashboards.yaml):

**Datasource (`grafana-datasources`):**
```yaml
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus-service:9090
    isDefault: true
```

**Dashboard provider (`grafana-dashboard-providers`):**
```yaml
providers:
  - name: "TachyonMesh"
    type: file
    options:
      path: /var/lib/grafana/dashboards
```

**Dashboard JSON (`grafana-dashboards`):** The raw JSON definition is mounted at `/var/lib/grafana/dashboards/tachyonmesh-traffic.json`. Grafana picks it up on startup without any API calls.

### Volume Mount Layout

```
/etc/grafana/provisioning/
  datasources/
    datasources.yaml        <-- from grafana-datasources ConfigMap
  dashboards/
    dashboards.yaml          <-- from grafana-dashboard-providers ConfigMap

/var/lib/grafana/dashboards/
  tachyonmesh-traffic.json   <-- from grafana-dashboards ConfigMap

/data/grafana/               <-- writable data dir (emptyDir, via GF_PATHS_DATA)
```

`GF_PATHS_DATA` is set to `/data/grafana` to avoid a volume mount conflict where the emptyDir would shadow the ConfigMap at `/var/lib/grafana/dashboards`.

---

## Kubernetes Resources

### Backend

| Resource | Name | Key Settings |
|:---------|:-----|:-------------|
| Deployment | `backend` | 2 replicas, `imagePullPolicy: Never` |
| Service | `backend-service` | ClusterIP, port 8081 |
| Readiness probe | `GET /health :8081` | 2s initial delay, 5s period |
| Liveness probe | `GET /health :8081` | 5s initial delay, 10s period |
| Resources | | 50m-200m CPU, 32Mi-64Mi memory |

### Envoy

| Resource | Name | Key Settings |
|:---------|:-----|:-------------|
| ConfigMap | `envoy-config` | Inline Envoy YAML |
| Deployment | `envoy` | 1 replica, config mounted at `/etc/envoy` |
| Service | `envoy-service` | NodePort, 8080:30080 (traffic), 9901:30901 (admin) |
| Resources | | 100m-500m CPU, 64Mi-256Mi memory |

### Prometheus

| Resource | Name | Key Settings |
|:---------|:-----|:-------------|
| ConfigMap | `prometheus-config` | Inline `prometheus.yml` |
| Deployment | `prometheus` | 1 replica, emptyDir for TSDB |
| Service | `prometheus-service` | ClusterIP, port 9090 |
| Resources | | 100m-500m CPU, 128Mi-512Mi memory |

### Grafana

| Resource | Name | Key Settings |
|:---------|:-----|:-------------|
| Deployment | `grafana` | 1 replica, 3 provisioning ConfigMap mounts |
| Service | `grafana-service` | ClusterIP, port 3000 |
| Resources | | 100m-500m CPU, 128Mi-256Mi memory |
