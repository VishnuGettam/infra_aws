## to run locally 

cd D:\Projects\Aws\infra_aws\terraform\infrastructure\dev
$env:AWS_PROFILE = "gh-user"

aws sts get-caller-identity      # check you're in account 512093097289

terraform init -backend-config="bucket=infra-aws-state-512093097289-ap-south-2-an"
terraform plan -out=tfplan
terraform apply tfplan
