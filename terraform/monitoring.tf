# ---------- Панель моніторингу CloudWatch (5 графіків) ----------

locals {
  cluster_name = aws_ecs_cluster.main.name
  service_name = aws_ecs_service.app.name
  alb_suffix   = aws_lb.main.arn_suffix # вимір LoadBalancer для метрик ALB
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "1. Кількість екземплярів: бажана і фактична"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "Бажана (desired)" }],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "Фактична (running)" }],
          ]
          yAxis = { left = { min = 0, max = 5 } }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "2. Завантаження процесора, % (середнє по сервісу)"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", local.cluster_name, "ServiceName", local.service_name, { label = "CPU avg" }],
          ]
          yAxis = { left = { min = 0, max = 100 } }
          annotations = {
            horizontal = [
              { label = "Ціль масштабування", value = var.autoscaling_cpu_target },
              { label = "Поріг сповіщення", value = var.alarm_cpu_threshold },
            ]
          }
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 8, height = 6
        properties = {
          title   = "3. Кількість запитів за хвилину"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_suffix, { label = "Запитів/хв" }],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 6, width = 8, height = 6
        properties = {
          title   = "4. Латентність p95, секунди"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "p95"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb_suffix, { label = "p95" }],
          ]
          annotations = {
            horizontal = [{ label = "500 мс", value = 0.5 }]
          }
        }
      },
      {
        type = "metric", x = 16, y = 6, width = 8, height = 6
        properties = {
          title   = "5. Кількість відповідей 5xx за хвилину"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb_suffix, { label = "5xx від застосунку" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.alb_suffix, { label = "5xx від балансувальника" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title   = "Довжина черги SQS (повідомлень очікує обробки)"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.readings.name, { label = "У черзі" }],
          ]
          annotations = {
            horizontal = [{ label = "Ціль масштабування обробників", value = var.worker_queue_target }]
          }
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6
        properties = {
          title   = "Кількість обробників черги: бажана і фактична"
          region  = var.region
          view    = "timeSeries"
          stacked = false
          period  = 60
          stat    = "Average"
          metrics = [
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", local.cluster_name, "ServiceName", aws_ecs_service.worker.name, { label = "Бажана (desired)" }],
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", local.cluster_name, "ServiceName", aws_ecs_service.worker.name, { label = "Фактична (running)" }],
          ]
          yAxis = { left = { min = 0, max = 4 } }
        }
      },
    ]
  })
}

output "dashboard_url" {
  description = "Панель моніторингу в консолі CloudWatch"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
