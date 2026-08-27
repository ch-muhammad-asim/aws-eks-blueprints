# 📊 AWS EKS Blueprints — `logging`

Feature branch for the **logging stack** on Amazon EKS: Elasticsearch and
Kibana for cluster and application logs.

> 🌿 Branch of [`master`](https://github.com/ch-muhammad-asim/aws-eks-blueprints).
> The cluster itself — VPC, EKS, Karpenter, ingress — lives there and is
> deployed with Terragrunt. This branch adds what runs *on top* of it.

---

## ✅ What works today

[`logs/eck/`](logs/eck/) — **Elasticsearch 9.1.2 + Kibana 9.1.2** on the ECK
operator, deployed and verified on this cluster:

```
elasticsearch/logging   green   1 node   9.1.2   (2m35s to green)
kibana/logging          green   1        9.1.2   association Established
write + read round trip -> document indexed and returned
storage                 -> 8 GiB gp3, EBS CSI, encrypted
node                    -> t3a.medium, provisioned on demand by Karpenter
```

```bash
helm -n elastic-system upgrade --install eck-operator elastic/eck-operator --version 3.5.0 --create-namespace --wait
```

```bash
kubectl apply -f logs/eck/00-storageclass.yaml -f logs/eck/10-elasticsearch.yaml
```

```bash
kubectl apply -f logs/eck/20-kibana.yaml
```

Full guide, sizing rationale and verification commands:
[`logs/eck/README.md`](logs/eck/README.md)

---

## 🚨 Why the old chart was replaced

The chart vendored under [`logs/elasticsearch/`](logs/elasticsearch/) is
**deprecated and will not deploy**. Every container image it references has
been withdrawn from Docker Hub (verified 2026-08-27):

```
docker.io/bitnami/elasticsearch:8.6.2-debian-11-r10   -> 404
docker.io/bitnami/kibana:7.17.8                       -> 404
docker.io/bitnami/bitnami-shell:11-debian-11-r97      -> 404
```

Bitnami restructured its catalogue in August 2025: most images moved to the paid
**Bitnami Secure Images**, and the free tier moved to a frozen `bitnamilegacy/*`
namespace that receives no security patches.

The chart still passes `helm lint` and `helm dependency build` — which is the
awkward part. It looks healthy in CI and fails on first deploy.

**Elasticsearch 7.17 and 8.6 are both end of life**, so the pinned versions are
a standing CVE exposure regardless of where the images come from.

---

## 📂 What is here

| Path | Contents |
|---|---|
| 📊 [`logs/`](logs/) | [The logging guide](logs/README.md) — options, comparison, verification |
| 🦌 [`logs/eck/`](logs/eck/) | ✅ **The working stack** — ECK operator, Elasticsearch, Kibana, gp3 storage |
| 📦 [`logs/elasticsearch/`](logs/elasticsearch/) | ⚠️ Deprecated Bitnami chart, kept for reference |
| 🏗️ [`terraform/`](terraform/) | Older cluster definitions, superseded by `master` |

---

## 🧭 Pick a path forward

| Option | Chart | When it fits |
|---|---|---|
| 🥇 **ECK operator** (Elastic official) | `elastic/eck-operator` **3.5.0** | Elasticsearch, supported, operator-managed upgrades and TLS |
| 🥈 **OpenSearch** | `opensearch/opensearch` **3.8.0** | Apache-2.0 fork, no licence questions, AWS-aligned |
| 🥉 **Amazon OpenSearch Service** | — managed | You would rather not operate a stateful search cluster |
| ⚠️ Bitnami, current version | `bitnami/elasticsearch` **22.1.6** | Only with a Bitnami Secure Images subscription |

ECK is the natural fit for this cluster — the vendor's own operator, managing
StatefulSets, TLS and rolling upgrades, with no third-party image catalogue in
the path:

```bash
helm repo add elastic https://helm.elastic.co
```

```bash
helm repo update
```

```bash
helm -n elastic-system upgrade --install eck-operator elastic/eck-operator --version 3.5.0 --create-namespace --wait
```

---

## 🧪 Sandbox reality check

The blueprint's cluster runs in a **Pluralsight AWS sandbox**, where a
production-shaped Elasticsearch cluster does not fit:

| `logs/elasticsearch/commands.txt` asks for | Sandbox allows |
|---|---|
| 3 master + 3 data + ingest + Kibana | nodes are **t3.medium — 2 vCPU / 4 GiB** |
| `persistence.size=100Gi` × 6 = 600 GiB | **100 GiB per volume**, nine EC2 instances account-wide |

The `eck/` stack is sized for exactly this: **one** Elasticsearch node at 2 GiB
with an 8 GiB volume, which fits a t3a.medium and keeps the account at four EC2
instances. That is what is deployed and verified.

The vendored Bitnami chart was never deployed — its verification was static
(`helm lint`, `helm dependency build`, and rendering the chart to inspect the
images it would pull), and that static pass is what surfaced the withdrawn
images above.

---

## ✅ Static verification

```bash
helm dependency build ./logs/elasticsearch
```

```bash
helm lint ./logs/elasticsearch --values ./logs/elasticsearch/security-values.yaml
```

```bash
helm template elasticsearch ./logs/elasticsearch --values ./logs/elasticsearch/security-values.yaml | grep -E '^\s+image:' | sort -u
```

That last command is the one worth keeping — it lists every image a deploy
would pull, which is how withdrawn tags get caught before an install hangs on
`ImagePullBackOff`.

Full detail, including runtime verification for whichever stack you choose:
[`logs/README.md`](logs/README.md)

---

## 📚 References

| Topic | Link |
|---|---|
| Bitnami Elasticsearch chart | https://artifacthub.io/packages/helm/bitnami/elasticsearch |
| Elastic Cloud on Kubernetes (ECK) | https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html |
| OpenSearch Helm charts | https://github.com/opensearch-project/helm-charts |
| Amazon OpenSearch Service | https://docs.aws.amazon.com/opensearch-service/latest/developerguide/what-is.html |
| Elastic end-of-life matrix | https://www.elastic.co/support/eol |
