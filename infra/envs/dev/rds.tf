# Replaces the in-cluster Postgres StatefulSet with a managed RDS instance.
# Same username/database/password as before (see shared-storage's
# postgres-credentials Secret) -- only the HOST changes, so api/worker
# code needs zero changes, just a different POSTGRES_HOST value.

resource "aws_db_subnet_group" "postgres" {
  name       = "${local.cluster_name}-postgres"
  subnet_ids = module.vpc.private_subnet_ids
}

resource "aws_security_group" "rds" {
  name        = "${local.cluster_name}-rds-sg"
  description = "Allows Postgres access from inside the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Postgres from anywhere inside this VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # Scoped to the VPC's own CIDR rather than the specific EKS node
    # security group -- simpler for a learning project. A production setup
    # would scope this to just the EKS cluster's security group instead.
    cidr_blocks = [module.vpc.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "${local.cluster_name}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type       = "gp3"

  db_name  = "pdfservice"
  username = "pdfapp"
  # Matches the password already baked into shared-storage's Secret and
  # the (now-decommissioned) in-cluster Postgres chart -- kept identical
  # so nothing else needs to change. In a real project this would be a
  # generated secret, not a plaintext value committed to Git.
  password = "pdfapp_dev_pw"

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Keeps this cheap and easy to tear down for a learning project --
  # a real production database would want backups and a final snapshot.
  backup_retention_period = 0
  skip_final_snapshot     = true

  # Prevents accidental deletion via `terraform destroy` without an
  # explicit confirmation step -- remove this if you actually want
  # `terraform destroy` to be able to remove it.
  deletion_protection = false
}
