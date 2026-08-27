# 🔄 EKS auto upgrade and version support policy

## ⚠️ The default is not what you want

Amazon EKS gives every cluster an **upgrade policy**, set through the
`upgradePolicy.supportType` property. It decides what happens when the
cluster's Kubernetes version reaches end of standard support:

| `supportType` | Behaviour at end of standard support | Cost |
|---|---|---|
| `STANDARD` | AWS **automatically upgrades** the cluster to the next version in standard support | no extended-support charge |
| `EXTENDED` | Cluster **enters extended support** and stays on its version | extended-support charge per cluster hour |

Per the AWS documentation: *"Extended support is enabled by default for new
clusters, and existing clusters."* So a cluster you create without specifying
anything gets `EXTENDED` — it will **not** auto-upgrade, and it will start
billing at a premium once its version ages out.

This blueprint sets `STANDARD` explicitly.

Timeline: a minor version gets **14 months** of standard support, then **12
months** of extended support. Clusters on extended support are auto-upgraded at
the end of *that* period.

## 🚧 Why this matters here

The Pluralsight sandbox permits standard-support versions only - extended
support is blocked on cost ([SANDBOX.md](SANDBOX.md)). A cluster left on the
AWS default would drift into a state the sandbox forbids without anyone
touching it.

Two constraints worth knowing before you rely on flipping this later:

- Once a cluster **has entered** extended support, you cannot disable it. The
  cluster must be running a standard-support version to change the policy.
- If an automatic upgrade has already been initiated, AWS does not guarantee a
  late switch to `EXTENDED` will take effect.

## 🛠️ How it is configured

`modules/eks/main.tf` passes the policy to the cluster:

```hcl
upgrade_policy = {
  support_type = var.cluster_support_type
}
```

`cluster_support_type` defaults to `STANDARD` and is validated to reject
anything other than `STANDARD` or `EXTENDED`. To deliberately opt a
non-sandbox cluster into extended support, set it in the Terragrunt unit:

```hcl
inputs = {
  cluster_support_type = "EXTENDED"
}
```

## ✅ Verification

Check the live policy - this is the exact command from the AWS docs:

```bash
aws eks describe-cluster --name cloudgeeks-eks-dev --query "cluster.upgradePolicy.supportType"
```

Verified on this cluster, 2026-08-27:

```
"STANDARD"
```

Confirm the running version is genuinely in standard support:

```bash
aws eks describe-cluster --name cloudgeeks-eks-dev --query "cluster.version"
```

```bash
aws eks describe-cluster-versions --query "clusterVersions[?status=='STANDARD_SUPPORT'].clusterVersion"
```

At the time of writing the cluster runs `1.36`, and standard support covers
`1.34`, `1.35` and `1.36` - so the cluster is compliant and will auto-upgrade
rather than roll into extended support.

Terraform will also show drift if someone changes the policy out of band:

```bash
terragrunt plan --working-dir terragrunt/env/dev/region/us-east-1/eks
```

## 📌 Not to be confused with EKS Auto Mode

**Auto Mode** is a separate feature where AWS manages the data plane -
provisioning nodes, and replacing the VPC CNI, CoreDNS, kube-proxy, the EBS CSI
driver, the Load Balancer Controller and *Karpenter itself* with managed
service functionality.

It is **off** by default and off here, because this blueprint runs its own
Karpenter installation. Check it with:

```bash
aws eks describe-cluster --name cloudgeeks-eks-dev --query "cluster.computeConfig"
```

```
{ "enabled": false, "nodePools": [] }
```

If you ever enable Auto Mode, the `karpenter` Terragrunt unit becomes redundant
and should be destroyed first.

## 📚 Official AWS documentation

| Topic | Link |
|---|---|
| Kubernetes versions and the support lifecycle | https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html |
| View current cluster upgrade policy | https://docs.aws.amazon.com/eks/latest/userguide/view-upgrade-policy.html |
| Edit cluster upgrade policy | https://docs.aws.amazon.com/eks/latest/userguide/edit-upgrade-policy.html |
| Versions on standard support (release notes) | https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html |
| Versions on extended support | https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-extended.html |
| Update a cluster to a new Kubernetes version | https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html |
| Cluster upgrade best practices | https://docs.aws.amazon.com/eks/latest/best-practices/cluster-upgrades.html |
| EKS Auto Mode | https://docs.aws.amazon.com/eks/latest/userguide/automode.html |
| Updating an Auto Mode cluster | https://docs.aws.amazon.com/eks/latest/userguide/auto-upgrade.html |
| `update-cluster-config` CLI reference | https://docs.aws.amazon.com/cli/latest/reference/eks/update-cluster-config.html |
