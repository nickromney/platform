# Tooling

## Why Terragrunt

This stack uses [Terragrunt](https://terragrunt.gruntwork.io/) as a thin orchestration layer over OpenTofu or Terraform.

In this repo, Terragrunt is mainly doing three things:

- generating the local backend configuration
- keeping shared inputs DRY
- standardizing how plans and applies are run

The backend generation is defined in [`root.hcl`](../../../terraform/root.hcl).

## Why OpenTofu

The default IaC engine here is [OpenTofu](https://opentofu.org/).

The intent is to stay as close as practical to mainstream Terraform-style workflows while using an open-source default. In repo terms, the switch is the `terraform_binary = "tofu"` setting in [`root.hcl`](../../../terraform/root.hcl).

If you want to use the Terraform binary instead, change that value to `terraform` and keep the same Terragrunt workflow.

## Without Make

`make` here is mostly a wrapper around Terragrunt/OpenTofu plus a few guardrails:

- prereq checks
- stage-order checks
- state-path wiring
- kind-specific bootstrap and kubeconfig retries

If you do not want to use `make`, the supported direct path is Terragrunt from `terraform/kubernetes`.

## Terragrunt Commands

From repo root:

```bash
cd terraform/kubernetes
export TG_STATE_PATH="$(pwd)/../.run/kubernetes/terraform.tfstate"

terragrunt init -reconfigure

terragrunt plan \
  -var-file=../../kubernetes/kind/stages/100-cluster.tfvars \
  -var-file=../../kubernetes/kind/targets/kind.tfvars

terragrunt apply \
  -var-file=../../kubernetes/kind/stages/100-cluster.tfvars \
  -var-file=../../kubernetes/kind/targets/kind.tfvars \
  -auto-approve
```

Swap `100-cluster.tfvars` for any later stage such as `200-cilium.tfvars` or `900-sso.tfvars`.

## OpenTofu Commands

If you want the lower-level path, use OpenTofu after Terragrunt has generated `backend.tf` and initialized the working directory:

```bash
cd terraform/kubernetes
export TG_STATE_PATH="$(pwd)/../.run/kubernetes/terraform.tfstate"

terragrunt init -reconfigure

tofu plan \
  -var-file=../../kubernetes/kind/stages/100-cluster.tfvars \
  -var-file=../../kubernetes/kind/targets/kind.tfvars

tofu apply \
  -var-file=../../kubernetes/kind/stages/100-cluster.tfvars \
  -var-file=../../kubernetes/kind/targets/kind.tfvars \
  -auto-approve
```

If you normally override kubeconfig or cluster name in the Make wrapper, pass those values explicitly:

```bash
terragrunt plan \
  -var-file=../../kubernetes/kind/stages/100-cluster.tfvars \
  -var-file=../../kubernetes/kind/targets/kind.tfvars \
  -var 'kubeconfig_path=~/.kube/config' \
  -var 'kubeconfig_context=kind-kind-local' \
  -var 'cluster_name=kind-local'
```

## What You Lose By Skipping `make`

- no prereq checks
- no automatic stage-monotonicity check
- no automatic kind bootstrap for later stages
- no automatic kubeconfig refresh retry on CA mismatch
