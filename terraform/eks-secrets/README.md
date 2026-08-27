# 🔐 AWS Secrets Manager on EKS (Secrets Store CSI Driver)

Mounts secrets from **AWS Secrets Manager** into pods as files, and optionally
mirrors them into a native Kubernetes `Secret` so they can be consumed as
environment variables.

| Component | Version |
|-----------|---------|
| Secrets Store CSI Driver | Helm chart `secrets-store-csi-driver` **v1.6.0** |
| AWS provider | **v3.1.3** |
| Auth | EKS Pod Identity (IRSA documented as the legacy path) |

---

## 🧭 Why not just use a Kubernetes Secret?

A `Secret` is base64, not encryption, and it lives in etcd for the lifetime of
the object. With the CSI driver the value stays in Secrets Manager: rotation
happens there, access is an IAM decision, and every read is in CloudTrail.

---

## 🔢 One version, pinned everywhere

```bash
export CHART_VERSION=1.6.0
export PROVIDER_VERSION=3.1.3

helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update
```

---

## 📦 Step 1 — Install the CSI driver

> ⚠️ **`tokenRequests` is not optional.** The chart ships it empty. Without it
> the CSIDriver never receives a service account token and every mount fails
> with `CSI token error: serviceAccount.tokens not provided`. Set the audience
> for whichever auth method you use — both is fine.

```bash
helm -n kube-system upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --version "$CHART_VERSION" --set syncSecret.enabled=true --set enableSecretRotation=true --set 'tokenRequests[0].audience=sts.amazonaws.com' --set 'tokenRequests[1].audience=pods.eks.amazonaws.com' --wait
```

- `syncSecret.enabled=true` allows mirroring into a Kubernetes `Secret`
- `enableSecretRotation=true` re-reads the source on an interval so a rotated secret reaches the pod
- audience `sts.amazonaws.com` covers IRSA, `pods.eks.amazonaws.com` covers Pod Identity

Verify the spec actually carries the audiences:

```bash
kubectl get csidriver secrets-store.csi.k8s.io -o jsonpath='{.spec.tokenRequests}'
```

---

## 📦 Step 2 — Install the AWS provider

Pinned to a release tag, not `main`:

```bash
kubectl apply -f "https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/${PROVIDER_VERSION}/deployment/aws-provider-installer.yaml"
```

```bash
kubectl -n kube-system rollout status daemonset/csi-secrets-store-provider-aws
```

> 🧩 There is also a Helm chart (`aws-secrets-manager/secrets-store-csi-driver-provider-aws`),
> but its ServiceAccount collides with the driver chart's when both are released
> into `kube-system`. The installer manifest sidesteps that.

---

## 🔑 Step 3 — Grant AWS permissions

Create the secret:

```bash
aws secretsmanager create-secret --name eks-demo-secret --secret-string '{"username":"asim","password":"s4ndb0x-demo"}'
```

Create a role the pod can assume. Pod Identity trusts the EKS service principal
rather than an OIDC provider:

```bash
aws iam create-role --role-name eks-secrets-demo --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}'
```

Scope the policy to the one secret — never `Resource: "*"` here:

```bash
export SECRET_ARN=$(aws secretsmanager describe-secret --secret-id eks-demo-secret --query ARN --output text)
```

```bash
aws iam put-role-policy --role-name eks-secrets-demo --policy-name read-demo-secret --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:GetSecretValue\",\"secretsmanager:DescribeSecret\"],\"Resource\":\"$SECRET_ARN\"}]}"
```

Bind the role to the service account:

```bash
aws eks create-pod-identity-association --cluster-name cloudgeeks-eks-dev --namespace app --service-account cloudgeeks-secrets --role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/eks-secrets-demo
```

> 📜 **Legacy IRSA path.** Annotate the ServiceAccount with
> `eks.amazonaws.com/role-arn: <role>`, trust the cluster's OIDC provider in the
> role, and omit `usePodIdentity` below. Pod Identity is preferred: no OIDC
> trust policy to maintain, and the binding is a plain EKS API object.

---

## 🚀 Step 4 — Deploy the workload

```bash
kubectl apply -f app/0-namespace.yaml -f app/1-service-account.yaml
```

```bash
kubectl apply -f app/2-SecretProviderClass.yaml -f app/3-deployment.yaml
```

> ⚠️ **`usePodIdentity: "true"` is required** in the SecretProviderClass. The
> AWS provider defaults to IRSA and will otherwise look for a web-identity token
> that Pod Identity never issues.

| File | Purpose |
|---|---|
| [`app/0-namespace.yaml`](app/0-namespace.yaml) | namespace |
| [`app/1-service-account.yaml`](app/1-service-account.yaml) | service account the Pod Identity association binds to |
| [`app/2-SecretProviderClass.yaml`](app/2-SecretProviderClass.yaml) | what to fetch, and what to mirror into a Kubernetes Secret |
| [`app/3-deployment.yaml`](app/3-deployment.yaml) | mounts the CSI volume and consumes the synced Secret as env vars |

---

## 🔍 Verification

### Driver and provider

```bash
kubectl get csidrivers
```

```bash
kubectl get csinode
```

```bash
kubectl -n kube-system get daemonset | grep -Ei 'secrets|csi'
```

```bash
helm -n kube-system list
```

```bash
helm -n kube-system get values csi-secrets-store --all
```

```bash
helm -n kube-system history csi-secrets-store
```

### The secret itself

```bash
kubectl -n app get secretproviderclass
```

```bash
export POD=$(kubectl -n app get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
```

```bash
kubectl -n app exec $POD -- ls -l /mnt/secrets-store/
```

```bash
kubectl -n app exec $POD -- cat /mnt/secrets-store/username
```

```bash
kubectl -n app get secret eks-demo-secret
```

```bash
kubectl -n app exec $POD -- sh -c 'echo $SECRET_USERNAME'
```

> 🧩 The synced Kubernetes `Secret` only exists while a pod mounts the volume. A
> `SecretProviderClass` on its own creates nothing, and the Secret is removed
> when the last mounting pod goes away.

### When a mount fails

```bash
kubectl -n app describe pod $POD | tail -20
```

```bash
kubectl -n kube-system logs -l app=secrets-store-csi-driver --tail=50
```

```bash
kubectl -n kube-system logs -l app=csi-secrets-store-provider-aws --tail=50
```

---

## ✅ Recorded result

Verified 2026-08-27 on `cloudgeeks-eks-dev` (Kubernetes 1.36):

```
/mnt/secrets-store/
  eks-demo-secret      45 bytes   (the full JSON)
  username              4 bytes   -> asim
  password             12 bytes   -> s4ndb0x-demo

kubectl -n app get secret eks-demo-secret   -> Opaque, 2 keys
env in container                            -> SECRET_USERNAME=asim SECRET_PASSWORD=s4ndb0x-demo
```

Two failures were hit and fixed during this run, both of which produce a pod
stuck in `Pending` with a `MountVolume.SetUp failed` event:

1. `CSI token error: serviceAccount.tokens not provided` — the driver chart's
   `tokenRequests` was empty. Fixed in Step 1.
2. The provider defaulting to IRSA under a Pod Identity setup. Fixed with
   `usePodIdentity: "true"` in the SecretProviderClass.

---

## 💡 Notes worth keeping

**`jmesPath` splits a JSON secret into files.** Without it you get one file
containing the whole JSON blob and the application has to parse it.

**Rotation is pull-based.** `enableSecretRotation=true` polls on an interval
(default 2 minutes). The mounted file updates; an environment variable does
**not** — env vars are set once at container start. Read from the file if you
need rotation without a restart.

**Scope IAM to the secret ARN.** A wildcard here hands every pod on the node's
role the whole vault.

---

## 📚 References

| Topic | Link |
|---|---|
| Secrets Store CSI Driver | https://secrets-store-csi-driver.sigs.k8s.io/ |
| AWS provider | https://github.com/aws/secrets-store-csi-driver-provider-aws |
| Using Secrets Manager with EKS | https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html |
| EKS Pod Identity | https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html |
| SecretProviderClass reference | https://secrets-store-csi-driver.sigs.k8s.io/getting-started/usage.html |
