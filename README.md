# infra_aws

Terraform for AWS (`ap-south-2`), deployed from GitHub Actions using OIDC. No long-lived AWS keys are stored in GitHub.

## How it works

```
GitHub Actions run
   │  1. requests a short-lived OIDC token from GitHub
   ▼
AWS STS  ── 2. checks the token against the OIDC provider + role trust policy
   │
   ▼
github_actions_role  ── 3. temporary credentials (~1 hour)
   │
   ▼
terraform plan/apply in terraform/infrastructure
   └─ state stored in S3: infra-aws-state-512093097289-ap-south-2-an
```

The project is split in two:

| Folder | Purpose | Who runs it | State |
|---|---|---|---|
| `terraform/bootstrap` | One-time setup: OIDC provider, IAM role, state bucket | You, locally, with the `gh-user` profile | Local `terraform.tfstate` (see [Bootstrap state](#bootstrap-state)) |
| `terraform/infrastructure` | The actual infrastructure | GitHub Actions via OIDC | S3 bucket created by bootstrap |

Bootstrap exists because of a chicken-and-egg problem: GitHub cannot log in to AWS until the OIDC provider and role exist, and the infrastructure state cannot live in S3 until the bucket exists. So these are created once from a local machine.

## What bootstrap manages

| Resource | File | How it got there |
|---|---|---|
| OIDC provider `token.actions.githubusercontent.com` | `oidc.tf` | Created manually in the console, **imported** |
| IAM role `github_actions_role` | `iam.tf` | Created manually in the console, **imported** |
| Policy `github_actions_role-terraform-state` (+ attachment to the role) | `iam.tf` | Created by Terraform |
| S3 bucket `infra-aws-state-512093097289-ap-south-2-an` | `s3.tf` | Created by Terraform |
| Bucket versioning, AES256 encryption, public access block, owner-enforced ownership | `s3.tf` | Created by Terraform |

Outputs (`terraform output` in `terraform/bootstrap`):

```
github_actions_role_arn = arn:aws:iam::512093097289:role/github_actions_role
oidc_provider_arn       = arn:aws:iam::512093097289:oidc-provider/token.actions.githubusercontent.com
state_bucket_name       = infra-aws-state-512093097289-ap-south-2-an
```

### Role trust policy

Only this repository can assume the role:

- `aud` must be `sts.amazonaws.com`
- `sub` must match `repo:VishnuGettam@60579222/infra_aws@1423998307:*`

The `sub` claim includes the **numeric owner ID and repo ID** (`@60579222`, `@1423998307`), not just the names. This is how GitHub issues tokens for this repo, and it means a different repo that later takes the same name cannot assume the role. The IDs are in `terraform.tfvars` as `github_org_id` and `github_repo_id`.

> If the trust policy is ever written as `repo:VishnuGettam/infra_aws:...` (names only), it will not match and every workflow run will fail with `AccessDenied` on `AssumeRoleWithWebIdentity`.

### State bucket

- The name ends in `-an` because it is created in the S3 **account regional namespace** (`bucket_namespace = "account-regional"`). The name is reserved for this account and region.
- `prevent_destroy` is set, so `terraform destroy` refuses to delete it.
- Versioning is on, so earlier state versions can be recovered.
- Locking uses S3 native lock files (`use_lockfile = true`). No DynamoDB table is needed.

## What we did, step by step

1. **Created resources manually in the AWS console**
   - OIDC provider for `token.actions.githubusercontent.com`, audience `sts.amazonaws.com`
   - Role `github_actions_role` trusting that provider, with `AdministratorAccess`
   - Temporary IAM user `github-actions-user` with `AdministratorAccess` and an access key, saved locally as AWS CLI profile `gh-user`

2. **Wrote the bootstrap configuration** (`terraform/bootstrap`)
   - `versions.tf`: Terraform `>= 1.16.0`, AWS provider `~> 6.69`
   - `provider.tf`: uses profile `gh-user`, region from `var.aws_region`, default tags `Project` and `ManagedBy`
   - `variables.tf` + `terraform.tfvars`: region, GitHub org/repo names and IDs, role name
   - `oidc.tf`, `iam.tf`, `s3.tf`, `outputs.tf`

3. **Brought the manual resources under Terraform with `import` blocks**, so Terraform manages them instead of trying to create duplicates. An account can have only one OIDC provider per URL, so creating it again would fail.

4. **Fixed the permissions boundary blocker.** The first `terraform plan` failed with:
   ```
   not authorized to perform: iam:GetOpenIDConnectProvider ...
   because no permissions boundary allows the iam:GetOpenIDConnectProvider action
   ```
   `github-actions-user` had `AdministratorAccess`, but also a **permissions boundary**. Effective permissions are the *intersection* of attached policies and the boundary, so the boundary blocked all IAM actions. We removed the boundary.

5. **Caught a trust policy mismatch before apply.** The first draft used the names-only `sub` format, which would have locked GitHub out. We read the role's real trust policy from AWS, matched its ID-based format, and confirmed in the saved plan that the new policy has the same contents as the existing one.

6. **Applied.** `2 imported, 7 added, 2 changed (tags only), 0 destroyed`.

## Running bootstrap again

Only needed if the role, OIDC provider or bucket must change.

```sh
cd terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

`terraform.tfvars` is git-ignored. Recreate it if missing:

```hcl
aws_region     = "ap-south-2"
github_org     = "VishnuGettam"
github_repo    = "infra_aws"
github_org_id  = "60579222"
github_repo_id = "1423998307"
```

The `import` blocks can stay in the code. Once a resource is in state, Terraform ignores them.

### Bootstrap state

Bootstrap state is currently **only** in `terraform/bootstrap/terraform.tfstate` on your machine (git-ignored). If it is lost, Terraform forgets it manages these resources. Either back it up, or move it into the state bucket under its own key (see [Next steps](#next-steps)).

## Cleanup: temporary user and admin role

### Temporary user `github-actions-user`

This user has `AdministratorAccess`, **no permissions boundary**, and an active long-lived access key on your laptop. It is the riskiest thing in the account right now. Bootstrap is done, so:

1. **Now:** make sure the GitHub workflow can authenticate through the role (`aws sts get-caller-identity` step succeeds).
2. **Then deactivate the access key**: IAM → Users → `github-actions-user` → Security credentials → Access keys → **Deactivate**. This can be undone if something was missed.
3. **After a week or so without needing it, delete the key and the user**, and remove the `[gh-user]` entries from `~/.aws/credentials` and `~/.aws/config`.
4. **For future bootstrap changes**, don't recreate a long-lived admin user. Use IAM Identity Center (SSO) or a short-lived admin session, and change `profile` in `terraform/bootstrap/provider.tf` to that profile.

### Role `github_actions_role` with AdministratorAccess

**Keep the role.** It is what GitHub uses, and it is now managed by Terraform. The problem is the `AdministratorAccess` policy still attached from the console. It is not managed by Terraform (only the state policy is), and with the trust policy matching `:*`, any workflow run on any branch of this repo gets full admin.

Plan to reduce it in two steps:

1. **Once `terraform/infrastructure` has real resources**, add a least-privilege policy for them in `terraform/bootstrap/iam.tf` (same pattern as the `terraform_state` policy), apply, and confirm CI still works. Then detach `AdministratorAccess`: IAM → Roles → `github_actions_role` → Permissions → Remove.
2. **Narrow the trust policy** from `:*` to only what the workflow needs, for example:
   ```
   repo:VishnuGettam@60579222/infra_aws@1423998307:ref:refs/heads/main
   repo:VishnuGettam@60579222/infra_aws@1423998307:pull_request
   ```
   Check the exact `sub` value first (it appears in the CloudTrail `AssumeRoleWithWebIdentity` event for a workflow run) before tightening, so you don't lock GitHub out.

   Better still, use two roles: a read-only **plan** role for pull requests and a write **apply** role that only `main` can assume.

## Next steps

1. **Add the role ARN to GitHub**: repo → Settings → Secrets and variables → Actions → **Variables** → New variable
   - Name: `AWS_ROLE_ARN`
   - Value: `arn:aws:iam::512093097289:role/github_actions_role`
2. **Fill in `terraform/infrastructure`**
   - `backend.tf`: S3 backend → bucket `infra-aws-state-512093097289-ap-south-2-an`, key such as `infrastructure/terraform.tfstate`, `region = "ap-south-2"`, `use_lockfile = true`, `encrypt = true`
   - `provider.tf`: AWS provider with **no `profile`** (CI gets credentials from OIDC), same default tags
   - `versions.tf`: same constraints as bootstrap
   - `s3.tf`: a first small resource to prove the pipeline works
3. **Write `.github/workflows/infra.yaml`**
   - `permissions: id-token: write, contents: read`
   - `aws-actions/configure-aws-credentials` with `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`
   - `working-directory: terraform/infrastructure`
   - `fmt -check`, `validate`, `plan` on pull requests; `apply` only on push to `main`
   - `paths:` filter on `terraform/infrastructure/**` so bootstrap edits don't trigger it
4. **Verify CI**, then do the [cleanup](#cleanup-temporary-user-and-admin-role) above.
5. **Optional: move bootstrap state into the bucket.** Add a `backend "s3"` block to bootstrap with key `bootstrap/terraform.tfstate` and run `terraform init -migrate-state`.
