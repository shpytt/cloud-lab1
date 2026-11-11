# ---------- Автоматичне горизонтальне масштабування ECS-сервісу ----------

# Що саме масштабуємо: кількість задач (DesiredCount) сервісу, у межах min..max
resource "aws_appautoscaling_target" "app" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscaling_min
  max_capacity       = var.autoscaling_max
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
