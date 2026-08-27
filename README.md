# 🔐 AWS EKS Blueprints — `eks-secrets`

Feature branch covering **secrets delivery** and **developer access** on Amazon
EKS: mounting AWS Secrets Manager entries into pods, and giving developers a
scoped, assumable role instead of a shared kubeconfig.

> 🌿 Branch of [`master`](https://github.com/ch-muhammad-asim/aws-eks-blueprints).
> The cluster itself — VPC, EKS, Karpenter, ingress — lives there and is
> deployed with Terragrunt. This branch adds what runs *on top* of it.

---

## 📂 What is here

| Directory | Guide | Covers |
|---|---|---|
| 🔐 [`terraform/eks-secrets/`](terraform/eks-secrets/) | [README](terraform/eks-secrets/README.md) | Secrets Store CSI Driver + AWS provider, mounting Secrets Manager values as files and env vars |
| 👥 [`terraform/developer/`](terraform/developer/) | [README](terraform/developer/README.md) | Assume-role access for developers, and the RBAC that bounds it |

---

## 📌 Versions

| Component | Version |
|---|---|
| Secrets Store CSI Driver | Helm chart **1.6.0** |
| AWS provider | **3.1.3** |
| Auth | EKS Pod Identity (IRSA documented as legacy) |
| Kubernetes | 1.36 |

---

## 🚀 Quick start

```bash
export CHART_VERSION=1.6.0
export PROVIDER_VERSION=3.1.3
```

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
```

```bash
helm -n kube-system upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --version "$CHART_VERSION" --set syncSecret.enabled=true --set enableSecretRotation=true --set 'tokenRequests[0].audience=sts.amazonaws.com' --set 'tokenRequests[1].audience=pods.eks.amazonaws.com' --wait
```

```bash
kubectl apply -f "https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/${PROVIDER_VERSION}/deployment/aws-provider-installer.yaml"
```

Full walkthrough, including IAM and the demo workload:
[`terraform/eks-secrets/README.md`](terraform/eks-secrets/README.md)

---

## ⚠️ Two traps that cost the most time

**`tokenRequests` is empty by default.** The driver chart ships
`tokenRequests: []`, so kubelet never mints a service account token and every
mount fails with `CSI token error: serviceAccount.tokens not provided`. The pod
sits in `Pending` with a `MountVolume.SetUp failed` event.

**The AWS provider defaults to IRSA.** Under EKS Pod Identity you must set
`usePodIdentity: "true"` in the `SecretProviderClass`, or the provider looks for
a web-identity token that Pod Identity never issues.

Both are handled in the manifests here, and explained in the guide.

---

## ✅ Verified

Both guides were run end to end against a live EKS 1.36 cluster on 2026-08-27.
Secrets mounted as files, synced into a Kubernetes `Secret`, and exposed as
environment variables; the developer role's permissions were confirmed by
impersonation. Recorded results are in each guide.

---

## 📚 References

| Topic | Link |
|---|---|
| Secrets Store CSI Driver | https://secrets-store-csi-driver.sigs.k8s.io/ |
| AWS provider | https://github.com/aws/secrets-store-csi-driver-provider-aws |
| Secrets Manager with EKS | https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html |
| EKS Pod Identity | https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html |
| EKS access entries | https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html |
