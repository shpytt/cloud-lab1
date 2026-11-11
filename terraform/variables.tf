variable "region" {
  description = "AWS регіон (у акаунті фіксований)"
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Префікс для назв ресурсів"
  type        = string
  default     = "cloud-lab1"
}

variable "image_tag" {
  description = "Тег Docker-образу в ECR (короткий хеш коміту)"
  type        = string
  default     = "none"
}

variable "app_port" {
  description = "Порт, на якому слухає API в контейнері"
  type        = number
  default     = 8000
}

variable "desired_count" {
  description = "Скільки копій контейнера запускати"
  type        = number
  default     = 1
}

variable "db_instance_class" {
  description = "Розмір сервера бази"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  type    = string
  default = "iotdb"
}

variable "db_username" {
  type    = string
  default = "labadmin"
}

variable "github_repo" {
  description = "Репозиторій GitHub, якому дозволено деплоїти (власник/назва)"
  type        = string
  default     = "shpytt/cloud-lab1"
}
# ---------- Автомасштабування (лабораторна 2) ----------

variable "autoscaling_min" {
  description = "Мінімальна кількість задач"
  type        = number
  default     = 1
}

variable "autoscaling_max" {
  description = "Максимальна кількість задач (за умовою лаби не більше 4)"
  type        = number
  default     = 4
}

variable "autoscaling_cpu_target" {
  description = "Цільове середнє завантаження процесора, %"
  type        = number
  default     = 60
}

# ---------- Сповіщення (лабораторна 2) ----------

variable "alert_email" {
  description = "Адреса для сповіщень (задається в terraform.tfvars, не в репозиторії)"
  type        = string
}

variable "alarm_cpu_threshold" {
  description = "Поріг сповіщення за завантаженням процесора, %"
  type        = number
  default     = 70
}

# ---------- Кеш (лабораторна 2) ----------

variable "redis_image" {
  description = "Образ Redis (офіційний redis:7-alpine з публічного дзеркала ECR)"
  type        = string
  default     = "public.ecr.aws/docker/library/redis:7-alpine"
}

variable "cache_enabled" {
  description = "Чи використовує API кеш Redis (перемикач для порівняльного тесту)"
  type        = bool
  default     = false
}

variable "cache_ttl_seconds" {
  description = "Термін дії запису в кеші, с"
  type        = number
  default     = 30
}
