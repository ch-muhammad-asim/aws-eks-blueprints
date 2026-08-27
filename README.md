# 🚀 AWS EKS Blueprint - Terragrunt, Karpenter and EKS Auto-scaling

Opinionated, layered EKS blueprint driven entirely by **Terragrunt**. One set of
Terraform modules, one Terragrunt unit per layer, and Karpenter instead of
Cluster Autoscaler for node provisioning.

Tuned to run inside a **Pluralsight AWS cloud sandbox** without tripping any of
its guardrails - see [docs/SANDBOX.md](docs/SANDBOX.md).

---

## 🏗️ Architecture

```
                      ┌──────────────────────────────────────────┐
                      │  Terragrunt units (env/dev/us-east-1)    │
                      │                                          │
                      │   vpc  ──▶  eks  ──▶  karpenter          │
                      │        dependency    dependency          │
                      └──────────────────────────────────────────┘
                                        │  source
                                        ▼
                      ┌──────────────────────────────────────────┐
                      │  modules/{vpc,eks,karpenter,oidc}        │
                      └──────────────────────────────────────────┘

  VPC            10.60.0.0/16, 3 AZs, private + public tiers, single NAT
                 private subnets tagged karpenter.sh/discovery

  EKS            control plane (standard-support version, auto-upgrade on)
                 access entries (API auth mode) - no aws-auth ConfigMap
                 add-ons: vpc-cni, kube-proxy, coredns, pod-identity-agent,
                          metrics-server, ebs-csi (EKS Pod Identity)
                 system managed node group: on-demand t3.medium x2

  Karpenter      controller (Pod Identity), SQS interruption queue,
                 EC2NodeClass + NodePool (v1 APIs), consolidation on
```

Each layer is a separate state file. The `eks` unit consumes the `vpc` unit's
outputs through a Terragrunt `dependency` block, and `karpenter` consumes `eks`.

---

## 📂 Layout

```
modules/                    Terraform modules - no backend, no aws provider
├── vpc/                    network + subnet discovery tags
├── eks/                    control plane, add-ons, system node group, access
├── karpenter/              controller, IAM, queue, EC2NodeClass, NodePool
│   └── manifests/          inflate workload used to exercise scaling
└── oidc/github/            GitHub Actions OIDC federation

terragrunt/
├── root.hcl                remote state, provider generation, retries
├── account.hcl             account id, state bucket, state KMS key
└── env/dev/
    ├── env.hcl             environment name, cluster name, k8s version
    └── region/us-east-1/
        ├── region.hcl
        ├── vpc/terragrunt.hcl
        ├── eks/terragrunt.hcl
        ├── karpenter/terragrunt.hcl
        └── oidc/github/terragrunt.hcl

terraform/                  standalone Kubernetes manifests and helper configs
                            (ALB ingress, ArgoCD, Vault, EBS, legacy Karpenter)
docs/                       sandbox limits, bootstrap, Karpenter, testing
```

The modules are **not** root modules: they carry no `backend.tf` and no `aws`
provider block. Terragrunt generates both. That is what keeps a single copy of
each module usable across every environment and region.

---

## 📌 Versions

| Component | Version |
|---|---|
| Terraform | >= 1.10 |
| Terragrunt | >= 1.1 |
| AWS provider | ~> 6.0 |
| Helm provider | ~> 3.0 |
| `terraform-aws-modules/eks/aws` | ~> 21.25 |
| `terraform-aws-modules/vpc/aws` | ~> 6.7 |
| Kubernetes / EKS | 1.36 (standard support; `supportType = STANDARD`) |
| Karpenter | 1.14.1 (v1 APIs) |
| Node AMI | AL2023 |

---

## ✅ Prerequisites

- AWS credentials for the target account (`aws sts get-caller-identity`)
- Terraform, Terragrunt, kubectl and helm on `$PATH`
- A state bucket and KMS key - see [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md)

Point `terragrunt/account.hcl` at your account id, bucket and key alias.

---

## 🚢 Deploy

All deployment goes through Terragrunt. Run from
`terragrunt/env/dev/region/us-east-1`.

Plan everything, respecting dependency order:

```bash
terragrunt run --all plan
```

Apply everything:

```bash
terragrunt run --all apply
```

Or one layer at a time, which is what you want the first time through:

```bash
terragrunt apply --working-dir vpc
```

```bash
terragrunt apply --working-dir eks
```

```bash
terragrunt apply --working-dir karpenter
```

Then point kubectl at the cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name cloudgeeks-eks-dev
```

---

## 🔍 Verify

```bash
kubectl get nodes -L node.kubernetes.io/instance-type -L karpenter.sh/nodepool
```

```bash
kubectl get nodepool,ec2nodeclass
```

Exercise the autoscaler with the bundled probe:

```bash
kubectl apply -f modules/karpenter/manifests/inflate.yaml
```

```bash
kubectl scale deployment inflate --replicas 6
```

Karpenter should launch nodes within roughly a minute. Scaling back to zero
returns them after `consolidateAfter`.

For a realistic end-to-end test - CPU load driving the HPA, the HPA driving
Karpenter - use the load-testing suite, which has its own guardrails and
recorded timings: [load-testing/](load-testing/). Blueprint-wide validation
results are in [docs/TESTING.md](docs/TESTING.md).

---

## 🧹 Teardown

Reverse dependency order matters: Karpenter's nodes must go before the cluster,
or the node group delete blocks on orphaned instances.

```bash
terragrunt destroy --working-dir karpenter
```

```bash
terragrunt destroy --working-dir eks
```

```bash
terragrunt destroy --working-dir vpc
```

---

## 📚 Documentation

| Document | Contents |
|---|---|
| 🧪 [docs/SANDBOX.md](docs/SANDBOX.md) | Pluralsight sandbox limits and how the code encodes them |
| 🪣 [docs/BOOTSTRAP.md](docs/BOOTSTRAP.md) | State bucket and KMS key bootstrap |
| ⚡ [docs/KARPENTER.md](docs/KARPENTER.md) | NodePool/EC2NodeClass settings and production tuning |
| ✅ [docs/TESTING.md](docs/TESTING.md) | Validation procedure and recorded results |
| 🔄 [docs/MIGRATION.md](docs/MIGRATION.md) | What changed from the previous revision and why |
| ⬆️ [docs/AUTO-UPGRADE.md](docs/AUTO-UPGRADE.md) | What EKS auto-upgrades (and what it does not, versus GKE) |
| 🔥 [load-testing/](load-testing/) | HPA + Karpenter load test, commands and recorded results |
