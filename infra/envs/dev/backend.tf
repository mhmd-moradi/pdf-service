# Fill in the bucket/table names with whatever you used in infra/bootstrap.
# Terraform doesn't allow variables in a backend block (it's read before
# any variables are resolved), so these values are hardcoded here.

terraform {
  backend "s3" {
    bucket         = "pdf-service-tfstate-demo-test-787878"
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "pdf-service-tfstate-demo-test-787878-locks"
    encrypt        = true
  }
}
