# 🧭 Traefik IngressRoute

Routing resources for **Traefik v3** — `IngressRoute` and `Middleware` CRDs,
served through the single NLB that fronts Traefik.

> 📌 Requires Traefik. Install it first: [`../traefik/`](../traefik/)

| File | What it creates |
|---|---|
| [`demo-ingressroute.yaml`](demo-ingressroute.yaml) | path-based route — `whoami` on `PathPrefix(/whoami)` with a response-header middleware |
| [`app-ingressroute.yaml`](app-ingressroute.yaml) | host-based route — `app.saqlainmushtaq.com` with a security-headers middleware, and a commented TLS variant |

---

## 🧩 Why IngressRoute instead of Ingress?

Traefik reads plain `Ingress` objects too, but its routing model does not fit in
them. `IngressRoute` gives you what annotations cannot express:

| | `Ingress` | `IngressRoute` |
|---|---|---|
| Match expression | host + path only | `Host()`, `PathPrefix()`, `Headers()`, `Query()`, and boolean combinations |
| Middleware chain | annotation strings | typed `Middleware` objects, ordered per route |
| Route priority | implicit | explicit `priority` |
| Multiple services per route | ❌ | ✅ with weights, for canaries |
| TLS options per route | ❌ | ✅ `tls.options` |

---

## 🚀 Deploy

Path-based demo:

```bash
kubectl apply -f demo-ingressroute.yaml
```

Host-based application route:

```bash
kubectl apply -f app-ingressroute.yaml
```

---

## 🌐 DNS

Point the hostname at Traefik's NLB with a **CNAME** — never an A record, since
the NLB's addresses change:

```bash
kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

```
app.saqlainmushtaq.com.  CNAME  k8s-traefik-traefik-xxxxxxxxxx.elb.us-east-1.amazonaws.com.
```

For a Route 53 hosted zone, prefer an **alias A record** to the NLB — it
resolves at the zone apex and costs nothing per query.

---

## 🔍 Verification

Before DNS exists, test with `--resolve` so curl sends the right `Host` header
to the load balancer's actual address:

```bash
export NLB=$(kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

```bash
export NLB_IP=$(dig +short "$NLB" | head -1)
```

```bash
curl -si --resolve "app.saqlainmushtaq.com:80:$NLB_IP" "http://app.saqlainmushtaq.com/" | head -14
```

Path-based demo:

```bash
curl -si "http://$NLB/whoami" | head -12
```

What Traefik actually loaded:

```bash
kubectl get ingressroute,middleware -A
```

```bash
kubectl -n app-demo describe ingressroute app
```

```bash
kubectl -n traefik logs -l app.kubernetes.io/name=traefik --tail=100 | grep -iE 'router|ingressroute|error'
```

Load balancer health:

```bash
aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName,'traefik')].TargetGroupArn" --output text | head -1) --output table
```

---

## ✅ Recorded result

Verified 2026-08-27 on `cloudgeeks-eks-dev`, through NLB
`k8s-traefik-traefik-4aa5761898-029280f894ef86fb.elb.us-east-1.amazonaws.com`:

```
HTTP/1.1 200 OK
Referrer-Policy: strict-origin-when-cross-origin
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-Served-By: traefik-eks
X-Xss-Protection: 1; mode=block

Hostname: app-5d4784c9c7-gdvgp
```

Both NLB addresses returned 200 and traffic landed on both replicas, so the
route, the middleware chain and cross-AZ balancing all work.

---

## ⚠️ The trap that costs an hour

`../traefik/eks-values.yaml` sets `providers.kubernetesCRD.ingressClass:
traefik-external`. Traefik then **ignores every `IngressRoute` without a
matching class annotation**:

```yaml
metadata:
  annotations:
    kubernetes.io/ingress.class: traefik-external
```

Symptom: healthy NLB targets, Traefik running, and a flat **404** — because the
route was dropped before a router was ever built. Both files here carry the
annotation.

---

## 🔐 Adding TLS

`app-ingressroute.yaml` ships a commented `websecure` variant. Create the
certificate Secret, then uncomment it:

```bash
kubectl -n app-demo create secret tls app-tls --cert=fullchain.pem --key=privkey.pem
```

With cert-manager, issue a `Certificate` into the same namespace and reference
its `secretName` under `tls.secretName`. TLS terminates at **Traefik**, not at
the NLB — the NLB stays a layer-4 passthrough, which is the point of putting
Traefik behind an NLB rather than an ALB.

---

## 💡 Patterns worth knowing

**Canary by weight** — two services on one route:

```yaml
services:
  - name: app
    port: 80
    weight: 90
  - name: app-canary
    port: 80
    weight: 10
```

**Rate limiting** is a Middleware, not an annotation:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: ratelimit
spec:
  rateLimit:
    average: 100
    burst: 50
```

**Middlewares are namespaced.** Referencing one from another namespace needs
`namespace-name@kubernetescrd` syntax, and a route that references a missing
middleware fails closed — the whole route stops serving.

---

## 🧹 Clean up

```bash
kubectl delete -f app-ingressroute.yaml
```

```bash
kubectl delete -f demo-ingressroute.yaml
```

---

## 📚 References

| Topic | Link |
|---|---|
| IngressRoute reference | https://doc.traefik.io/traefik/routing/providers/kubernetes-crd/ |
| Routing rules and matchers | https://doc.traefik.io/traefik/routing/routers/ |
| Middlewares overview | https://doc.traefik.io/traefik/middlewares/overview/ |
| Kubernetes CRD provider | https://doc.traefik.io/traefik/providers/kubernetes-crd/ |
| cert-manager | https://cert-manager.io/docs/ |
