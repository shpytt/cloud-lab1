# ---------- Автоматичне горизонтальне масштабування ECS-сервісу ----------

# Що саме масштабуємо: кількість задач (DesiredCount) сервісу, у межах min..max
resource "aws_appautoscaling_target" "app" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min
  max_capacity       = var.autoscaling_max

  # Мінімум удень змінює розклад (schedule.tf); без цього apply повертав би його до 1
  lifecycle {
    ignore_changes = [min_capacity]
  }
}

# Як масштабуємо: target tracking — AWS сам додає/вилучає задачі,
# щоб середнє завантаження процесора по сервісу трималося біля цілі
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = var.autoscaling_cpu_target

    # Період стабілізації (cooldown), секунди:
    scale_out_cooldown = 60  # після додавання задач чекаємо 1 хв
    scale_in_cooldown  = 120 # після вилучення задач чекаємо 2 хв
  }
}

# ---------- Швидка реакція на різкий сплеск (step scaling) ----------
# Target tracking додає задачі лише після 3 хвилинних точок вище цілі.
# Ця політика спрацьовує вже після 1 точки і додає одразу 2 задачі.
# Вилученням задач займається тільки target tracking.

resource "aws_appautoscaling_policy" "cpu_spike" {
  name               = "${var.project}-cpu-spike-step"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity" # змінюємо кількість на фіксоване число
    cooldown                = 120                # 2 хв паузи, щоб нові задачі встигли взяти навантаження
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0 # будь-яке перевищення порогу
      scaling_adjustment          = 2 # +2 задачі
    }
  }
}

# Тривога, яка запускає швидку політику (листів не надсилає)
resource "aws_cloudwatch_metric_alarm" "cpu_spike" {
  alarm_name        = "${var.project}-cpu-spike-scale-out"
  alarm_description = "CPU понад ${var.alarm_cpu_threshold}% протягом 1 хвилини: швидке додавання задач"

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_appautoscaling_policy.cpu_spike.arn]
}
