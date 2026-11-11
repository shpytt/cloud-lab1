# ---------- Масштабування за розкладом: різний мінімум удень і вночі ----------
# Розклад змінює лише межі; у цих межах далі працює масштабування за процесором.

resource "aws_appautoscaling_scheduled_action" "day" {
  name               = "${var.project}-day"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension

  schedule = "cron(0 8 * * ? *)" # щодня о 08:00
  timezone = "Europe/Kiev"

  scalable_target_action {
    min_capacity = var.schedule_day_min
    max_capacity = var.autoscaling_max
  }
}

resource "aws_appautoscaling_scheduled_action" "night" {
  name               = "${var.project}-night"
  service_namespace  = aws_appautoscaling_target.app.service_namespace
  resource_id        = aws_appautoscaling_target.app.resource_id
  scalable_dimension = aws_appautoscaling_target.app.scalable_dimension

  schedule = "cron(0 22 * * ? *)" # щодня о 22:00
  timezone = "Europe/Kiev"

  scalable_target_action {
    min_capacity = var.schedule_night_min
    max_capacity = var.autoscaling_max
  }
}
