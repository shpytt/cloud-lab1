# ---------- Сповіщення на пошту: правило (alarm) + канал доставки (SNS) ----------

# Канал доставки: тема SNS і підписка електронною поштою
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # після apply треба підтвердити підписку з листа
}

# Правило: CPU сервісу > 70% протягом 2 хвилин поспіль
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name        = "${var.project}-cpu-high"
  alarm_description = "Середнє завантаження процесора ECS-сервісу понад ${var.alarm_cpu_threshold}% протягом 2 хвилин"

  namespace   = "AWS/ECS"
  metric_name = "CPUUtilization"
  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  statistic           = "Average"
  period              = 60 # одна точка = 1 хвилина
  evaluation_periods  = 2  # дивимося на 2 останні точки
  datapoints_to_alarm = 2  # обидві мають перевищити поріг (захист від flapping)
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn] # лист 1: надмірне навантаження
  ok_actions    = [aws_sns_topic.alerts.arn] # лист 2: повернення до норми
}
