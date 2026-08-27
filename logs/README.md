# 📊 Logging on EKS

Elasticsearch and Kibana for cluster and application logs.

> ⚠️ **Read [the status section](#-status-this-vendored-chart-is-stale) before running anything here.** The vendored chart in
> [`elasticsearch/`](elasticsearch/) is pinned to Bitnami Elasticsearch 8.6.2
> and references container images that **no longer exist** at the paths it uses.

---

## 🚨 Status: this vendored chart is stale

| | Vendored here | Current upstream |
|---|---|---|
| Chart | Bitnami `elasticsearch` (appVersion **8.6.2**) | `bitnami/elasticsearch` **22.1.6** (appVersion 9.1.2) |
| Image in `commands.txt` | `bitnami/elasticsearch:7.17.8` | ❌ **404 — tag removed from Docker Hub** |

In August 2025 Bitnami restructured its catalog: most images moved to the paid
**Bitnami Secure Images**, and the free tier was moved to the
`bitnamilegacy/*` namespace, which is frozen and receives **no security
patches**. Verified 2026-08-27:

```bash
curl -s -o /dev/null -w '%{http_code}\n' "https://hub.docker.com/v2/repositories/bitnami/elasticsearch/tags/7.17.8"
```

```
404
```

So `helm upgrade --install ... --set image.tag=7.17.8` from `commands.txt`
fails at image pull. This is not a bug in the chart — the images were withdrawn
underneath it.

Rendering the vendored chart shows **every** image it would pull, and all three
are gone (checked 2026-08-27):

```
docker.io/bitnami/elasticsearch:8.6.2-debian-11-r10   -> 404
docker.io/bitnami/kibana:7.17.8                       -> 404
docker.io/bitnami/bitnami-shell:11-debian-11-r97      -> 404
```

The chart itself is still structurally valid — `helm lint` passes and
`helm dependency build` resolves both subcharts. It is only the images that
have been removed, which is exactly the failure mode that looks fine in CI and
dies on first deploy.

**Elasticsearch 7.17 and 8.6 are also both end of life.** Running either is a
standing CVE exposure regardless of where the image comes from.

---

## 🧭 Pick a path forward

| Option | Chart | When it fits |
|---|---|---|
| 🥇 **ECK operator** (Elastic official) | `elastic/eck-operator` **3.5.0** | You want Elasticsearch, supported, with operator-managed upgrades and TLS |
| 🥈 **OpenSearch** | `opensearch/opensearch` **3.8.0** | Apache-2.0 fork, no Elastic licence questions, AWS-aligned |
| 🥉 **Amazon OpenSearch Service** | — managed | You would rather not run a stateful search cluster at all |
| ⚠️ Bitnami chart, current version | `bitnami/elasticsearch` 22.1.6 | Only with a Bitnami Secure Images subscription, or pinned to frozen `bitnamilegacy` images |

For a cluster that already runs Karpenter and the AWS Load Balancer Controller,
**ECK** is the natural fit: it is the vendor's own operator, it manages
StatefulSets, TLS and rolling upgrades itself, and it does not depend on a
third-party image catalogue.

```bash
helm repo add elastic https://helm.elastic.co
```

```bash
helm repo update
```

```bash
helm search repo elastic/eck-operator --versions | head -5
```

```bash
helm -n elastic-system upgrade --install eck-operator elastic/eck-operator --version 3.5.0 --create-namespace --wait
```

The operator is small — one pod — and it is the cluster resources you create
afterwards that carry the real footprint.

---

## 🧪 Sandbox reality check

This blueprint's cluster runs in a **Pluralsight AWS sandbox**
([limits](../docs/sandbox/)), which makes the settings in `commands.txt`
impossible:

| `commands.txt` asks for | Sandbox allows |
|---|---|
| `master.replicaCount=3` + `data.replicaCount=3` + ingest + Kibana | ~5 pods needing several GiB each; nodes are **t3.medium — 2 vCPU / 4 GiB** |
| `master.persistence.size=100Gi` **and** `data.persistence.size=100Gi` (×3 each = 600 GiB) | **100 GiB per volume**, and only nine EC2 instances account-wide |

A production-shaped Elasticsearch cluster does not fit, and forcing it would
trip the instance cap and get the sandbox reclaimed. **Nothing on this branch
has been deployed to the live cluster** — the verification below is static.

To experiment inside the sandbox, run a single node with small volumes:

```bash
helm -n logging upgrade --install elasticsearch oci://registry-1.docker.io/bitnamicharts/elasticsearch --set master.replicaCount=1 --set data.replicaCount=1 --set coordinating.replicaCount=0 --set ingest.enabled=false --set master.persistence.size=8Gi --set data.persistence.size=8Gi --set global.kibanaEnabled=false --create-namespace
```

Even then, expect Elasticsearch to be unhappy with less than 2 GiB of heap.

---

## ✅ Static verification

What can be checked without deploying — and what was actually run:

```bash
helm dependency build ./elasticsearch
```

```bash
helm lint ./elasticsearch --values ./elasticsearch/security-values.yaml
```

```bash
helm template elasticsearch ./elasticsearch --values ./elasticsearch/security-values.yaml | head -60
```

Confirm which images a render would actually pull — this is what exposes the
withdrawn tags before a deploy does:

```bash
helm template elasticsearch ./elasticsearch --values ./elasticsearch/security-values.yaml | grep -E '^\s+image:' | sort -u
```

Compare the vendored chart against current upstream:

```bash
helm search repo bitnami/elasticsearch --versions | head -5
```

```bash
helm show chart bitnami/elasticsearch | grep -E '^(version|appVersion)'
```

---

## 🔍 Runtime verification (whichever path you choose)

```bash
helm -n logging list
```

```bash
helm -n logging status elasticsearch
```

```bash
helm -n logging get values elasticsearch --all
```

```bash
kubectl -n logging get pods,svc,pvc
```

```bash
kubectl -n logging get statefulset
```

Cluster health from inside — `green` or `yellow`, never `red`:

```bash
kubectl -n logging exec -it sts/elasticsearch-master -- curl -s localhost:9200/_cluster/health?pretty
```

```bash
kubectl -n logging exec -it sts/elasticsearch-master -- curl -s localhost:9200/_cat/nodes?v
```

```bash
kubectl -n logging exec -it sts/elasticsearch-master -- curl -s localhost:9200/_cat/indices?v
```

Storage is where a stateful chart usually fails first:

```bash
kubectl -n logging get pvc
```

```bash
kubectl get storageclass
```

```bash
kubectl -n logging describe pod -l app=elasticsearch-master | tail -20
```

---

## 💡 Notes worth keeping

**`helm dependency build` before anything.** The chart pulls `kibana` and
`common` as subcharts; without it, `helm template` fails on missing
dependencies. The `.tgz` files under `charts/` are those dependencies vendored.

**Elasticsearch needs real memory.** Heap should be roughly half the container
limit, and the container needs more than the heap. This is why the sandbox's
t3.medium nodes cannot host a realistic cluster.

**Use `gp3`, not `gp2`.** The EBS CSI driver is installed by the
[`eks`](../modules/eks) module; set `global.storageClass` explicitly rather
than inheriting whatever the cluster default happens to be.

**Back the data up.** A search cluster holds state Terraform cannot recreate —
see [backup-dr](../docs/backup-dr/).

---

## 📚 References

| Topic | Link |
|---|---|
| Bitnami Elasticsearch chart | https://artifacthub.io/packages/helm/bitnami/elasticsearch |
| Bitnami catalog changes | https://github.com/bitnami/containers/issues/83267 |
| Elastic Cloud on Kubernetes (ECK) | https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html |
| ECK Helm chart | https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-install-helm.html |
| OpenSearch Helm chart | https://github.com/opensearch-project/helm-charts |
| Amazon OpenSearch Service | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/what-is.html |
| Elastic version support matrix | https://www.elastic.co/support/eol |
