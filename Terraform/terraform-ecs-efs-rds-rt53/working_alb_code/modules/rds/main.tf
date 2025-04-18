resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "aws_rds_cluster" "wordpress" {
  cluster_identifier      = "wordpress-cluster"
  engine                  = "aurora-mysql"
  engine_version          = "8.0.mysql_aurora.3.05.2" # Updated version
  database_name           = "wordpress"
  master_username         = "admin"
  master_password         = random_password.db_password.result
  backup_retention_period = 7
  preferred_backup_window = "07:00-09:00"
  db_subnet_group_name    = var.db_subnet_group_name
  vpc_security_group_ids  = [var.sg_rds_id]
  skip_final_snapshot     = true
}

resource "aws_rds_cluster_instance" "cluster_instances" {
  count              = 1
  identifier         = "wordpress-cluster-${count.index}"
  cluster_identifier = aws_rds_cluster.wordpress.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.wordpress.engine
  engine_version     = aws_rds_cluster.wordpress.engine_version
}

resource "aws_secretsmanager_secret" "rds_secret" {
  name = "wordpress-rds-secret"
}

resource "aws_secretsmanager_secret_version" "rds_secret_version" {
  secret_id = aws_secretsmanager_secret.rds_secret.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.db_password.result
  })
}

output "rds_cluster_endpoint" {
  value = aws_rds_cluster.wordpress.endpoint
}

output "secret_arn" {
  value = aws_secretsmanager_secret.rds_secret.arn
}
