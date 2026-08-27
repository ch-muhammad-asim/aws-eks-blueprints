# 🦌 Elasticsearch + Kibana on EKS (ECK operator)

The **working** logging stack for this cluster: Elastic Cloud on Kubernetes
(ECK), the vendor's own operator, sized to run inside the Pluralsight AWS
sandbox.

This replaces the vendored Bitnami chart in [`../elasticsearch/`](../elasticsearch/),
whose container images have been withdrawn from Docker Hub — see [`../README.md`](../README.md).

| Component | Version |
|-----------|---------|
| ECK operator | Helm chart `elastic/eck-operator` **3.5.0** |
| Elasticsearch | **9.1.2** |
| Kibana | **9.1.2** |
| Storage | `gp3`, EBS CSI, encrypted |

---

## 🧭 Why an operator instead of a chart

A Helm chart renders StatefulSets and hands you the rest. ECK owns the
lifecycle: it generates the TLS certificates, creates the `elastic` superuser
secret, wires Kibana to Elasticsearch, and performs rolling upgrades in the
right order when you change `version`. The manifests here are ~40 lines because
everything else is the operator's job.

It also removes the third-party image catalogue from the path, which is exactly
what broke the previous approach.

---

## 📂 Files

| File | Creates |
|---|---|
| [`00-storageclass.yaml`](00-storageclass.yaml) | `gp3` StorageClass on the EBS CSI driver, set as cluster default |
| [`10-elasticsearch.yaml`](10-elasticsearch.yaml) | single-node `Elasticsearch` with an 8 GiB gp3 volume |
| [`20-kibana.yaml`](20-kibana.yaml) | `Kibana`, wired to Elasticsearch by `elasticsearchRef` |

---

## 💾 Why a new StorageClass

The cluster ships only the in-tree `gp2` class, served through CSI migration.
That matters twice:

- **gp3 is cheaper and faster** than gp2 at the same size.
- **AWS Backup does not support CSI-migrated or in-tree volumes** — only
  volumes provisioned by a genuine CSI StorageClass. Search data is exactly the
  state you cannot rebuild from Terraform, so it has to be backup-eligible.

`00-storageclass.yaml` makes `gp3` the default and demotes `gp2`.

---

## 🚀 Install

### Step 1 — the operator

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
helm -n elastic-system upgrade --install eck-operator elastic/eck-operator --version 3.5.0 --create-namespace --set resources.requests.memory=256Mi --set resources.limits.memory=512Mi --wait --timeout 5m
```

The operator installs its own CRDs, so there is no separate `helm show crds`
step here.

```bash
kubectl -n elastic-system get pods
```

### Step 2 — storage

```bash
kubectl apply -f 00-storageclass.yaml
```

```bash
kubectl patch storageclass gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

### Step 3 — Elasticsearch and Kibana

```bash
kubectl create namespace logging
```

```bash
kubectl apply -f 10-elasticsearch.yaml
```

```bash
kubectl -n logging get elasticsearch -w
```

Wait for `HEALTH: green` before adding Kibana — it will not associate with a
cluster that is not yet serving.

```bash
kubectl apply -f 20-kibana.yaml
```

```bash
kubectl -n logging get kibana -w
```

---

## 🔍 Verification

### Operator and custom resources

```bash
helm -n elastic-system list
```

```bash
helm -n elastic-system status eck-operator
```

```bash
helm -n elastic-system get values eck-operator --all
```

```bash
kubectl get crd | grep elastic
```

```bash
kubectl -n logging get elasticsearch,kibana
```

```bash
kubectl -n logging get pods,pvc,svc
```

### Elasticsearch itself

The operator stores the superuser password in a Secret named
`<cluster>-es-elastic-user`:

```bash
export PW=$(kubectl -n logging get secret logging-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
```

```bash
kubectl -n logging exec logging-es-default-0 -- curl -sk -u "elastic:$PW" "https://localhost:9200/_cluster/health?pretty"
```

```bash
kubectl -n logging exec logging-es-default-0 -- curl -sk -u "elastic:$PW" "https://localhost:9200/_cat/nodes?v"
```

```bash
kubectl -n logging exec logging-es-default-0 -- curl -sk -u "elastic:$PW" "https://localhost:9200/_cat/indices?v"
```

A real write-and-read round trip proves more than a health check:

```bash
kubectl -n logging exec logging-es-default-0 -- curl -sk -u "elastic:$PW" -X POST "https://localhost:9200/blueprint-test/_doc?refresh=true" -H 'Content-Type: application/json' -d '{"service":"eks-blueprint","msg":"logging stack verified"}'
```

```bash
kubectl -n logging exec logging-es-default-0 -- curl -sk -u "elastic:$PW" "https://localhost:9200/blueprint-test/_search?pretty"
```

```bash
kubectl -n logging exec logging-es-default-0 -- curl -sk -u "elastic:$PW" -X DELETE "https://localhost:9200/blueprint-test"
```

### Kibana

```bash
kubectl -n logging exec deploy/logging-kb -- curl -sk -u "elastic:$PW" "https://localhost:5601/api/status"
```

Reach the UI locally — Kibana is deliberately not exposed publicly:

```bash
kubectl -n logging port-forward service/logging-kb-http 5601
```

Then open `https://localhost:5601` and log in as `elastic` with `$PW`. The
certificate is the operator's own CA, so the browser will warn.

---

## ✅ Recorded result

Verified 2026-08-27 on `cloudgeeks-eks-dev` (Kubernetes 1.36):

```
elasticsearch/logging   green   1 node   9.1.2   Ready     (2m35s to green)
kibana/logging          green   1        9.1.2   Established

_cluster/health   -> status green, 40 active shards, 0 unassigned
_cat/nodes        -> logging-es-default-0, roles dim, elected master
write + read      -> document indexed and returned by search
kibana /api/status-> "level": "available", "All services and plugins are available"

PVC  elasticsearch-data-logging-es-default-0   8Gi   gp3   Bound
Node ip-10-60-1-214  t3a.medium  provisioned by Karpenter for this workload
```

Karpenter provisioned the node on demand, which is the whole stack working
together: a pending pod with a 2 GiB request produced a t3a.medium, and the
account stayed at 4 EC2 instances against a sandbox cap of 9.

---

## 🧪 Sizing notes

**One node, 2 GiB, 1 GiB heap.** Heap is set to half the container limit via
`ES_JAVA_OPTS`; Elasticsearch needs the remainder for Lucene and off-heap
structures. Below roughly 1 GiB of heap it spends its time in GC.

**No CPU limit.** Throttling the JVM produces GC pauses that present as cluster
instability. Requests reserve capacity; limits on CPU cause the problem they
appear to prevent.

**`node.store.allow_mmap: false`** avoids needing `vm.max_map_count` raised on
the host, which you cannot do from inside a managed node group without a
privileged init container.

**Single node means no replicas.** `number_of_replicas` defaults to 1 and a
one-node cluster cannot allocate them, which would show as `yellow`. The
indices created here are green because ECK's system indices adapt; any index
you create for real should set `number_of_replicas: 0` on a single node.

### Growing beyond the sandbox

Split roles across dedicated nodeSets — masters, data, ingest — raise `count`
to at least 3 for masters, and give data nodes real memory:

```yaml
nodeSets:
  - name: master
    count: 3
    config:
      node.roles: ["master"]
  - name: data
    count: 3
    config:
      node.roles: ["data", "ingest"]
```

---

## 🧹 Uninstall

```bash
kubectl delete -f 20-kibana.yaml -f 10-elasticsearch.yaml
```

```bash
kubectl -n logging get pvc
```

> ⚠️ ECK does **not** delete the PersistentVolumeClaims when you delete the
> Elasticsearch resource — deliberately, so a mistaken `kubectl delete` does not
> destroy your data. Remove them explicitly once you are sure:

```bash
kubectl -n logging delete pvc -l elasticsearch.k8s.elastic.co/cluster-name=logging
```

```bash
helm -n elastic-system uninstall eck-operator
```

---

## 📚 References

| Topic | Link |
|---|---|
| ECK documentation | https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html |
| Install ECK with Helm | https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-install-helm.html |
| Elasticsearch resource reference | https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-elasticsearch-specification.html |
| Managing compute resources | https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-managing-compute-resources.html |
| Kibana resource reference | https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-kibana.html |
| EBS CSI driver StorageClass parameters | https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/parameters.md |
