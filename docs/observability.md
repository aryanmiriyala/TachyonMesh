# Observability

## Dashboard Overview

The **TachyonMesh Traffic** dashboard is auto-provisioned via ConfigMap and appears immediately when Grafana starts. It contains three panels that cover the core observability signals: throughput, latency, and error rates.

Dashboard UID: `tachyonmesh-traffic`
Refresh interval: 5 seconds
Default time range: Last 15 minutes

---

## Panel 1: Total Request Rate (RPS)

**What it shows:** Aggregate requests per second flowing through Envoy to the backend cluster, with a separate series for successful (2xx) responses.

**Queries:**

```promql
# Total RPS across all response codes
sum(rate(envoy_cluster_upstream_rq_total{envoy_cluster_name="backend_cluster"}[1m]))

# 2xx RPS only
sum(rate(envoy_cluster_upstream_rq_xx{envoy_cluster_name="backend_cluster", envoy_response_code_class="2"}[1m]))
```

**How to read it:**
- Under the default load test (50 RPS), expect the total line to stabilize around 50 req/s
- The 2xx line should closely track the total line under healthy conditions
- A gap between total and 2xx indicates non-success responses (4xx/5xx)

**Underlying metric:** `envoy_cluster_upstream_rq_total` is a counter that increments with every completed upstream request. `rate()` computes the per-second increase over a 1-minute window.

---

## Panel 2: Upstream Latency (P95 / P99)

**What it shows:** Tail latency percentiles for requests from Envoy to the backend, computed from Envoy's upstream request time histogram.

**Queries:**

```promql
# 95th percentile latency
histogram_quantile(0.95,
  sum(rate(envoy_cluster_upstream_rq_time_bucket{envoy_cluster_name="backend_cluster"}[1m])) by (le)
)

# 99th percentile latency
histogram_quantile(0.99,
  sum(rate(envoy_cluster_upstream_rq_time_bucket{envoy_cluster_name="backend_cluster"}[1m])) by (le)
)
```

**How to read it:**
- The backend sleeps for a uniform random 20-150ms, so expect:
  - **P95** around ~130-140ms
  - **P99** around ~145-150ms
- Spikes above 150ms indicate queueing or resource contention
- A flat line at exactly one value suggests insufficient histogram bucket granularity

**Underlying metric:** `envoy_cluster_upstream_rq_time_bucket` is a histogram with `le` (less-than-or-equal) bucket boundaries. `histogram_quantile()` interpolates between buckets to estimate the requested percentile.

---

## Panel 3: HTTP Error Rates (4xx / 5xx)

**What it shows:** Rate of client errors (4xx) and server errors (5xx) from the backend, with color-coded severity.

**Queries:**

```promql
# 5xx error rate (server errors)
sum(rate(envoy_cluster_upstream_rq_xx{envoy_cluster_name="backend_cluster", envoy_response_code_class="5"}[1m]))

# 4xx error rate (client errors)
sum(rate(envoy_cluster_upstream_rq_xx{envoy_cluster_name="backend_cluster", envoy_response_code_class="4"}[1m]))
```

**How to read it:**
- Under normal load, both lines should be at zero
- 5xx errors (red) indicate backend failures -- pod crashes, OOM kills, application bugs
- 4xx errors (orange) indicate client-side issues -- bad routes, malformed requests
- A sudden spike in 5xx during a load test suggests the backend can't handle the concurrency

**Underlying metric:** `envoy_cluster_upstream_rq_xx` breaks down completed requests by response code class (1xx, 2xx, 3xx, 4xx, 5xx).

---

## Envoy Metrics Catalog

Key metrics exposed at `/stats/prometheus` on port 9901:

### Request Metrics

| Metric | Type | Description |
|:-------|:-----|:------------|
| `envoy_cluster_upstream_rq_total` | Counter | Total completed upstream requests |
| `envoy_cluster_upstream_rq_xx` | Counter | Requests by response code class (labels: `envoy_response_code_class`) |
| `envoy_cluster_upstream_rq_active` | Gauge | Currently in-flight upstream requests |
| `envoy_cluster_upstream_rq_pending_active` | Gauge | Requests waiting for a connection |
| `envoy_cluster_upstream_rq_timeout` | Counter | Requests that timed out |
| `envoy_cluster_upstream_rq_retry` | Counter | Upstream request retries |

### Latency Metrics

| Metric | Type | Description |
|:-------|:-----|:------------|
| `envoy_cluster_upstream_rq_time_bucket` | Histogram | Upstream request duration distribution |
| `envoy_cluster_upstream_rq_time_sum` | Counter | Total upstream request time (for computing averages) |
| `envoy_cluster_upstream_rq_time_count` | Counter | Total number of observations |

### Connection Metrics

| Metric | Type | Description |
|:-------|:-----|:------------|
| `envoy_cluster_upstream_cx_total` | Counter | Total upstream connections opened |
| `envoy_cluster_upstream_cx_active` | Gauge | Currently active upstream connections |
| `envoy_cluster_upstream_cx_connect_timeout` | Counter | Connection timeouts |
| `envoy_cluster_upstream_cx_destroy` | Counter | Connections destroyed |

### HTTP Connection Manager Metrics

| Metric | Type | Description |
|:-------|:-----|:------------|
| `envoy_http_downstream_rq_total` | Counter | Total requests received by Envoy |
| `envoy_http_downstream_rq_active` | Gauge | Currently active downstream requests |
| `envoy_http_downstream_cx_total` | Counter | Total downstream connections |

---

## Useful PromQL Queries

Beyond the dashboard panels, these queries are helpful for debugging:

```promql
# Average latency (simpler than percentiles, useful for quick checks)
rate(envoy_cluster_upstream_rq_time_sum{envoy_cluster_name="backend_cluster"}[1m])
/
rate(envoy_cluster_upstream_rq_time_count{envoy_cluster_name="backend_cluster"}[1m])

# Error percentage (5xx as a fraction of total)
sum(rate(envoy_cluster_upstream_rq_xx{envoy_response_code_class="5"}[1m]))
/
sum(rate(envoy_cluster_upstream_rq_total[1m])) * 100

# Active connections to backend (useful for detecting connection leaks)
envoy_cluster_upstream_cx_active{envoy_cluster_name="backend_cluster"}

# Requests waiting for a connection (indicates pool exhaustion)
envoy_cluster_upstream_rq_pending_active{envoy_cluster_name="backend_cluster"}
```
