# IoT Devices API

REST API для IoT-пристроїв і їхніх показників (температура, вологість).
Написано на Python (FastAPI), працює в AWS: балансувальник ALB, контейнери ECS Fargate, база PostgreSQL в RDS.
Уся інфраструктура описана в Terraform.

## Лабораторна 1: розгортання в AWS

- застосунок у Docker, локально запускається через Docker Compose;
- інфраструктура в Terraform: мережа, база, контейнери, балансувальник;
- база в приватній мережі, доступ до неї лише з контейнерів;
- пароль бази зберігається в Secrets Manager, у коді його немає.

## Лабораторна 2: масштабування, моніторинг, кешування

1. Автомасштабування від 1 до 4 контейнерів за процесором — `terraform/autoscaling.tf`
2. Навантажувальний тест на k6 — `loadtest/`
3. Дашборд CloudWatch — `terraform/monitoring.tf`
4. Сповіщення на пошту — `terraform/alerts.tf`
5. Кеш у Redis — `app/cache.py`, `terraform/redis.tf`
6. Черга SQS з обробником (бонус) — `app/jobs.py`, `app/worker.py`, `terraform/queue.tf`
7. Ідемпотентність запису (бонус) — `app/idempotency.py`, `tests/`
8. Масштабування за розкладом (бонус) — `terraform/schedule.tf`

Звіти й знімки — у папці `docs/`.

## Локальний запуск

```bash
cp .env.example .env
docker compose up -d --build
```

Після запуску API доступне на http://localhost:8000, Swagger — на http://localhost:8000/docs.

## Розгортання в AWS

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply -target=aws_ecr_repository.app
./deploy.sh
```

Адреса сервісу: `terraform -chdir=terraform output alb_url`.

Навантажувальний тест: `./loadtest/run.sh`.

Видалити все: `terraform -chdir=terraform destroy`.

## Чому немає CI/CD

Акаунт AWS створений за новою схемою, і його політика забороняє створювати OIDC-провайдер для GitHub.
Тому розгортання робиться вручну скриптом `deploy.sh`.
