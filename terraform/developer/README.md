# 👥 Developer access (assume-role + RBAC)

Read-only cluster access for developers: an IAM role they assume, mapped to a
Kubernetes group, bound to a deliberately narrow `ClusterRole`.

| File | Purpose |
|---|---|
| [`reader.yaml`](reader.yaml) | `ClusterRole` + `ClusterRoleBinding` for the `reader` group |
| [`commands.txt`](commands.txt) | the raw CLI sequence, kept as-is |

---

## 🧭 How the two halves connect

```
IAM user  ──assume──▶  IAM role (eks-developer-*)  ──access entry──▶  Kubernetes group "reader"
                                                                              │
                                                                     ClusterRoleBinding
                                                                              ▼
                                                                     ClusterRole "reader"
```

AWS decides **who you are**; Kubernetes RBAC decides **what you may do**. Both
halves must exist — an access entry with no RBAC grants nothing, and RBAC with
no access entry is never reached.

> 📌 The cluster in this blueprint uses **access entries**, not the `aws-auth`
> ConfigMap. The `eks` module creates the developer role and its entry; see
> [`modules/eks/iam-access.tf`](../../modules/eks/iam-access.tf).

---

## 🔧 Configure a profile that assumes the role

```bash
export PROFILE_NAME=asim
```

```bash
aws configure --profile $PROFILE_NAME
```

```bash
aws sts get-caller-identity --profile $PROFILE_NAME
```

Add the assume-role profile to `~/.aws/config`:

```ini
[profile developer]
role_arn = arn:aws:iam::<account-id>:role/eks-developer-cloudgeeks-eks-dev
source_profile = asim
```

```bash
aws sts get-caller-identity --profile developer
```

The `Arn` in that output should be an `assumed-role/eks-developer-...`, not the
source user.

---

## 🔑 Get a kubeconfig as the developer

```bash
export AWS_PROFILE=developer
```

```bash
aws eks update-kubeconfig --region us-east-1 --name cloudgeeks-eks-dev
```

---

## 🚀 Apply the RBAC

Applied once by a cluster admin, not by the developer:

```bash
kubectl apply -f reader.yaml
```

```bash
kubectl get clusterrole reader
```

```bash
kubectl get clusterrolebinding reader
```

---

## 🔍 Verification

`kubectl auth can-i` answers from the API server's own authoriser, so it is the
only check that matters:

```bash
kubectl auth can-i "*" "*"
```

```bash
kubectl auth can-i get pods
```

```bash
kubectl auth can-i delete pods
```

```bash
kubectl auth can-i create deployments
```

Expected for a developer: **no**, **yes**, **no**, **no**.

> ⚠️ **Subresources need `--subresource`, not a slash.** `kubectl auth can-i
> create pods/exec` returns **`no`** even when the role grants it — the slash
> form is not parsed as a subresource. Use:
>
> ```bash
> kubectl auth can-i create pods --subresource=exec
> ```
>
> Verified on this cluster: the slash form says `no`, `--subresource=exec` says
> `yes`, for the same identity against the same role. Auditing exec access with
> the slash form will tell you the cluster is safe when it is not.

List everything the current identity may do:

```bash
kubectl auth can-i --list
```

Check on someone else's behalf, as an admin:

```bash
kubectl auth can-i get pods --as-group=reader --as=eks-developer-cloudgeeks-eks-dev
```

Confirm the AWS side of the mapping:

```bash
aws eks list-access-entries --cluster-name cloudgeeks-eks-dev
```

```bash
aws eks describe-access-entry --cluster-name cloudgeeks-eks-dev --principal-arn arn:aws:iam::<account-id>:role/eks-developer-cloudgeeks-eks-dev
```

---

## ✅ Verified permission matrix

Checked against the live cluster by impersonating the group
(`--as=dev-test --as-group=reader`), 2026-08-27:

| Check | Result |
|---|---|
| `get pods` | ✅ yes |
| `list deployments` | ✅ yes |
| `get pods --subresource=log` | ✅ yes |
| `create pods --subresource=exec` | ⚠️ **yes** |
| `create pods --subresource=portforward` | ⚠️ **yes** |
| `delete pods` | ❌ no |
| `create deployments` | ❌ no |
| `get secrets` | ❌ no |

The two ⚠️ rows are the point of the next section.

---

## ⚠️ What this role can actually do

`reader.yaml` is not purely read-only, and that is worth being explicit about:

| Permission | Risk |
|---|---|
| `pods/log` `get` | logs frequently contain tokens, connection strings and PII |
| `pods/exec` `create` | ⚠️ **a shell in any pod** — effectively the pod's service account and everything it can reach |
| `pods/portforward` `create` | ⚠️ tunnels to any in-cluster service, bypassing network policy |
| `configmaps` `get`/`list` | configuration, and whatever secrets people wrongly put in ConfigMaps |

`exec` and `port-forward` are not read-only operations. They are convenient for
debugging and are how a "read-only" role becomes a lateral-movement path. For a
genuinely read-only role, drop both:

```yaml
# remove these two rules
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["pods/portforward"]
  verbs: ["create"]
```

Note also that `secrets` is **not** granted — keep it that way.

---

## 💡 Alternative: skip the ClusterRole entirely

EKS ships managed access policies that cover the common cases, with no RBAC
objects to maintain:

| Policy | Grants |
|---|---|
| `AmazonEKSViewPolicy` | read-only, no secrets, no exec |
| `AmazonEKSEditPolicy` | edit most resources |
| `AmazonEKSAdminPolicy` | admin, namespace-scopable |
| `AmazonEKSClusterAdminPolicy` | full cluster admin |

The `eks` module already attaches `AmazonEKSViewPolicy` to the developer role.
Use `reader.yaml` only when you need permissions those policies do not express —
`pods/exec` being the usual reason.

---

## 📚 References

| Topic | Link |
|---|---|
| EKS access entries | https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html |
| EKS access policies | https://docs.aws.amazon.com/eks/latest/userguide/access-policies.html |
| Kubernetes RBAC | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| `kubectl auth can-i` | https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/ |
| Assuming an IAM role with the CLI | https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html |
