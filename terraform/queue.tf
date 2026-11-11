# ---------- Черга SQS та обробник (бонус: асинхронний запис) ----------

# Черга "мертвих листів": сюди потрапляє повідомлення після 5 невдалих спроб обробки
resource "aws_sqs_queue" "readings_dlq" {
  name                      = "${var.project}-readings-dlq"
  message_retention_seconds = 1209600 # 14 днів
}

resource "aws_sqs_queue" "readings" {
  name                       = "${var.project}-readings"
  visibility_timeout_seconds = 60    # скільки повідомлення приховане, поки його обробляють
  receive_wait_time_seconds  = 20    # long polling
  message_retention_seconds  = 86400 # 1 доба

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.readings_dlq.arn
    maxReceiveCount     = 5
  })
}

# ---------- Ролі задач (task role): права самого коду, а не ECS-агента ----------

# API може лише класти повідомлення в чергу
resource "aws_iam_role" "api_task" {
  name               = "${var.project}-api-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "api_task_sqs" {
  name = "send-to-readings-queue"
  role = aws_iam_role.api_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.readings.arn
    }]
  })
}

# Обробник може лише читати й видаляти повідомлення
resource "aws_iam_role" "worker_task" {
  name               = "${var.project}-worker-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "worker_task_sqs" {
  name = "consume-readings-queue"
  role = aws_iam_role.worker_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = aws_sqs_queue.readings.arn
    }]
  })
}

# ---------- Обробник: той самий образ, інша команда запуску ----------

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.project}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.worker_task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "worker"
    image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential = true
    command   = ["python", "-m", "app.worker"]

    environment = [
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_PORT", value = tostring(aws_db_instance.main.port) },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_SSLMODE", value = "require" },
      { name = "REDIS_URL", value = "redis://redis.${aws_service_discovery_private_dns_namespace.main.name}:6379/0" },
      { name = "AWS_REGION", value = var.region },
      { name = "SQS_QUEUE_URL", value = aws_sqs_queue.readings.url },
      { name = "WORKER_DELAY_MS", value = tostring(var.worker_delay_ms) },
    ]

    secrets = [
      { name = "DB_USER", valueFrom = "${aws_secretsmanager_secret.db.arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.db.arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "worker"
      }
    }
  }])
}

resource "aws_ecs_service" "worker" {
  name            = "${var.project}-worker"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id] # ті самі правила: база, Redis, HTTPS
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [desired_count] # кількістю керує автомасштабування
  }

  depends_on = [aws_iam_role_policy.worker_task_sqs]
}

# ---------- Масштабування обробника від довжини черги ----------

resource "aws_appautoscaling_target" "worker" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = var.worker_max
}

resource "aws_appautoscaling_policy" "worker_queue" {
  name               = "${var.project}-worker-queue-length"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.worker.service_namespace
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension

  target_tracking_scaling_policy_configuration {
    # Метрика не вбудована, тому описуємо її вручну: кількість повідомлень у черзі
    customized_metric_specification {
      namespace   = "AWS/SQS"
      metric_name = "ApproximateNumberOfMessagesVisible"
      statistic   = "Average"

      dimensions {
        name  = "QueueName"
        value = aws_sqs_queue.readings.name
      }
    }

    target_value       = var.worker_queue_target # тримаємо в черзі не більше ~100 повідомлень
    scale_out_cooldown = 60
    scale_in_cooldown  = 120
  }
}
