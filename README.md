# Terraform Aws Eks Blue Print

- Eks Cluster Deployment in custom vpc

- Terraform Backend S3 by using aws cli and enabling versioning

```bash
aws s3api create-bucket --bucket cloudgeeks-ca-terraform --region us-east-1
aws s3api put-bucket-versioning --bucket cloudgeeks-ca-terraform --versioning-configuration Status=Enabled
```

```bash
terraform init 
terraform validate
terraform plan
terraform apply -auto-approve
```

- aws-auth configmap
```bash
kubectl get configmap aws-auth -n kube-system -o yaml
```
```yaml
apiVersion: v1
data:
  mapAccounts: |
    []
  mapRoles: |
    - "groups":
      - "system:bootstrappers"
      - "system:nodes"
      "rolearn": "arn:aws:iam::381492080129:role/on-demand-eks-node-group-20240828112902751700000003"
      "username": "system:node:{{EC2PrivateDNSName}}"
    - "groups":
      - "system:bootstrappers"
      - "system:nodes"
      "rolearn": "arn:aws:iam::381492080129:role/spot-eks-node-group-20240828112902751900000004"
      "username": "system:node:{{EC2PrivateDNSName}}"
    - "groups":
      - "system:masters"
      "rolearn": "arn:aws:iam::381492080129:role/eks-admin-cloudgeeks-eks-dev"
      "username": "eks-admin-cloudgeeks-eks-dev"
    - "groups":
      - "reader"
      "rolearn": "arn:aws:iam::381492080129:role/eks-developers-cloudgeeks-eks-dev"
      "username": "eks-developers-cloudgeeks-eks-dev"
  mapUsers: |
    []
kind: ConfigMap
metadata:
  creationTimestamp: "2024-08-28T11:38:21Z"
  name: aws-auth
  namespace: kube-system
  resourceVersion: "1545"
  uid: c6022467-1259-433b-82f4-bd503e1f3041
```
