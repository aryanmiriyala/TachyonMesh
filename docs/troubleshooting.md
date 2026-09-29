# Troubleshooting

## Pods stuck in ImagePullBackOff

The backend image must be built locally. Kubernetes is trying to pull it from a registry.

```bash
# Build the image in your local Docker daemon
make build

# Verify the image exists
docker images | grep tachyonmesh-backend

# Verify imagePullPolicy is set to Never
kubectl get pods -l app=backend -o jsonpath='{.items[*].spec.containers[*].imagePullPolicy}'
# Expected: Never Never
```

**Minikube users:** Build inside the Minikube Docker context:

```bash
eval $(minikube docker-env)
make build
```

---

## Envoy returns 503 (no healthy upstream)

Envoy can't reach any healthy backend pod. Check backend health:

```bash
# Are backend pods running?
kubectl get pods -l app=backend

# Check pod conditions and probe status
kubectl describe pod -l app=backend | grep -A5 "Conditions"

# Check backend logs for startup errors
kubectl logs -l app=backend
```

Common causes:
- Backend pods haven't passed readiness probes yet (wait a few seconds)
- Backend image wasn't built (`make build`)
- Port mismatch between the Service (8081) and the container

---

## Grafana dashboard shows "No data"

Work through this checklist in order:

**1. Is Prometheus scraping successfully?**

```bash
make port-forward-prometheus
# Open http://localhost:9090/targets
# The "envoy" target should show State: UP
```

**2. Is Envoy producing metrics?**

```bash
curl -s http://localhost:9901/stats/prometheus | grep envoy_cluster_upstream_rq_total
```

If this returns nothing, no requests have flowed through Envoy yet.

**3. Has any traffic been generated?**

```bash
curl http://localhost:8080/api/process
```

At least one request must pass through Envoy before metrics appear.

**4. Is the datasource configured correctly?**

In Grafana, go to **Connections > Data sources > Prometheus** and click **Test**. It should say "Data source is working."

---

## Port 30080 or 30901 already in use

Another service is occupying the NodePort. Either free the port or change the `nodePort` values in `k8s/envoy.yaml`:

```yaml
ports:
  - port: 8080
    nodePort: 31080  # Change from 30080
```

Then re-apply:

```bash
kubectl apply -f k8s/envoy.yaml
```

---

## Load test shows connection refused

The Envoy port-forward must be running in a separate terminal:

```bash
# Terminal 1
make port-forward-envoy

# Terminal 2
make load-test
```

If port-forwarding drops during the load test, the `kubectl port-forward` process may have crashed. Restart it and re-run the test.

---

## Pods in CrashLoopBackOff

Check the logs for the crashing pod:

```bash
kubectl logs <pod-name> --previous
```

Common causes:
- Envoy: Invalid YAML in the ConfigMap (check indentation)
- Prometheus: Config syntax error in `prometheus.yml`
- Grafana: Volume mount conflict (verify `GF_PATHS_DATA` is set)

---

## Metrics exist in Prometheus but Grafana panels are empty

The dashboard queries filter by `envoy_cluster_name="backend_cluster"`. Verify the label exists:

```bash
curl -s http://localhost:9901/stats/prometheus | grep 'envoy_cluster_name="backend_cluster"'
```

If the label is different (e.g., capitalization), update the queries in `k8s/grafana-dashboards.yaml` to match.

---

## kubectl port-forward drops or hangs

Port-forward connections can be unstable under high load. Options:

- Restart the port-forward command
- Use NodePort access directly: `http://localhost:30080` (bypasses port-forward entirely, works with Docker Desktop Kubernetes)
- Reduce load test concurrency: `hey -z 2m -q 20 -c 20 http://localhost:8080/api/process`
