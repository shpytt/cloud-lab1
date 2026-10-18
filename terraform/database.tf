# Пароль генерує Terraform: його немає ні в коді, ні в Git
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#%^*-_=+"
}

# Логін і пароль бази зберігаються в Secrets Manager
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}-db-credentials"
  recovery_window_in_days = 0 # щоб terraform destroy видаляв секрет одразу
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false # немає публічної адреси
  multi_az               = false # для лаби економимо

  backup_retention_period = 1 # автоматичні бекапи + point-in-time recovery

  skip_final_snapshot = true  # щоб destroy не залишав знімок
  deletion_protection = false # щоб destroy міг видалити базу
  apply_immediately   = true
}