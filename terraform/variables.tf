variable "region" {
  description = "AWS регіон (у нашому акаунті фіксований)"
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