# ---------- Redis: окремий ECS-сервіс, спільний кеш для всіх екземплярів API ----------

# Приватна DNS-зона всередині VPC: API знаходить Redis за іменем redis.<project>.internal
resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "${var.project}.internal"
  vpc  = aws_vpc.main.id
}

resource "aws_service_discovery_service" "redis" {
  name          = "redis"
  force_destroy = true

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

# Мережева ізоляція: до Redis можна дістатися ТІЛЬКИ з контейнерів API
resource "aws_security_group" "redis" {
  name        = "${var.project}-redis-sg"
  description = "Redis: only from API security group"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_app" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# Вихід HTTPS потрібен лише щоб завантажити образ і писати логи
resource "aws_vpc_security_group_egress_rule" "redis_https" {
  security_group_id = aws_security_group.redis.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_to_redis" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.redis.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_cloudwatch_log_group" "redis" {
  name              = "/ecs/${var.project}-redis"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "redis" {
  family                   = "${var.project}-redis"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "redis"
    image     = var.redis_image
    essential = true

    # Тільки кеш у пам'яті: без запису на диск, при заповненні витісняються найстаріші ключі
    command = [
      "redis-server",
      "--save", "",
      "--appendonly", "no",
      "--maxmemory", "256mb",
      "--maxmemory-policy", "allkeys-lru",
    ]

    portMappings = [{ containerPort = 6379, protocol = "tcp" }]

    healthCheck = {
      command     = ["CMD-SHELL", "redis-cli ping | grep -q PONG"]
      interval    = 10
      timeout     = 5
      retries     = 3
      startPeriod = 5
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.redis.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "redis"
      }
    }
  }])
}

resource "aws_ecs_service" "redis" {
  name            = "${var.project}-redis"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.redis.arn
  desired_count   = 1 # один спільний Redis, не масштабується
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.redis.id]
    assign_public_ip = true # лише для завантаження образу; вхід закритий security group
  }

  service_registries {
    registry_arn = aws_service_discovery_service.redis.arn
  }
}
