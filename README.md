# Лабораторна робота 1 — Розгортання застосунку в AWS

**IoT Devices API** — REST API для обліку IoT-пристроїв та їхніх показань (температура, вологість).
Застосунок запакований у Docker, інфраструктура описана в Terraform і розгорнута в AWS
(ECS Fargate + RDS PostgreSQL + Application Load Balancer).

## Публічна адреса

- API: http://cloud-lab1-alb-497232148.eu-north-1.elb.amazonaws.com
- Swagger UI: http://cloud-lab1-alb-497232148.eu-north-1.elb.amazonaws.com/docs

> Адреса змінюється після кожного `terraform destroy` / `terraform apply`.
> Актуальну можна отримати командою `terraform -chdir=terraform output alb_url`.

## Технології

| Шар | Технологія |
|---|---|
| Застосунок | Python 3.12, FastAPI, SQLAlchemy 2, psycopg 3 |
| База даних | PostgreSQL 16 (локально — контейнер, у хмарі — Amazon RDS) |
| Контейнеризація | Docker, Docker Compose |
| Хмара | AWS, регіон `eu-north-1` (Стокгольм) |
| Інфраструктура як код | Terraform, провайдер `hashicorp/aws` 6.x |

## Ендпоінти API

| Метод | Шлях | Опис |
|---|---|---|
| GET | `/` | Назва та версія сервісу |
| GET | `/health` | Перевірка стану (health check для ALB) |
| GET | `/devices` | Список пристроїв |
| POST | `/devices` | Створити пристрій |
| GET | `/devices/{id}` | Отримати пристрій |
| PATCH | `/devices/{id}` | Змінити пристрій |
| DELETE | `/devices/{id}` | Видалити пристрій (разом з показаннями) |
| POST | `/devices/{id}/readings` | Додати показання |
| GET | `/devices/{id}/readings` | Останні показання пристрою |

## Архітектура в AWS

```
Інтернет
   │  HTTP :80
   ▼
Application Load Balancer          (публічні підмережі, 2 зони доступності)
   │  :8000 — тільки від security group ALB
   ▼
ECS Fargate — контейнер з API      (образ з ECR, пароль бази з Secrets Manager)
   │  :5432 — тільки від security group застосунку
   ▼
RDS PostgreSQL                     (приватні підмережі, без публічної адреси)
```

- **Мережа:** VPC `10.0.0.0/16`, 2 публічні підмережі (ALB, контейнер) і 2 приватні (база)
  у зонах `eu-north-1a` та `eu-north-1b`. Приватні підмережі не мають маршруту в інтернет.
- **Security groups:** ALB приймає 80 з інтернету; контейнер приймає 8000 лише від ALB;
  база приймає 5432 лише від security group контейнера (не від IP-діапазонів).
- **Секрети:** пароль бази генерує Terraform (`random_password`) і зберігає в AWS Secrets Manager.
  ECS передає його в контейнер як змінні середовища `DB_USER` / `DB_PASSWORD`.
  У коді, образі та репозиторії паролів немає.
- **Health check:** ALB перевіряє `GET /health` кожні 15 секунд.
- **Логи:** CloudWatch Logs, група `/ecs/cloud-lab1`.

## Структура проєкту

```
cloud-lab1/
├── app/
│   ├── __init__.py
│   ├── database.py      # підключення до БД через змінні середовища
│   ├── models.py        # таблиці devices і readings
│   ├── schemas.py       # Pydantic-схеми запитів/відповідей
│   └── main.py          # ендпоінти FastAPI
├── terraform/
│   ├── providers.tf     # версії Terraform і провайдерів, регіон
│   ├── variables.tf     # змінні (регіон, тег образу, розміри)
│   ├── network.tf       # VPC, підмережі, маршрути, security groups
│   ├── database.tf      # RDS PostgreSQL, пароль у Secrets Manager
│   ├── app.tf           # ECR, CloudWatch Logs, IAM, ALB, ECS Fargate
│   └── outputs.tf       # публічна адреса та інші результати
├── Dockerfile
├── compose.yaml
├── requirements.txt
├── .env.example         # приклад змінних для локального запуску
├── .dockerignore
└── .gitignore           # .env, *.tfstate, .terraform/ не комітяться
```

## Локальний запуск

```bash
cp .env.example .env          # заповнити свої значення
docker compose up -d --build
curl http://localhost:8000/health
```

Swagger: http://localhost:8000/docs.
Дані бази зберігаються у volume `pgdata` і переживають `docker compose down`.

## Розгортання в AWS

Потрібні: Terraform ≥ 1.10, AWS CLI з налаштованим IAM-користувачем, Docker.

```bash
# 1. Створити реєстр образів
cd terraform
terraform init
terraform apply -target=aws_ecr_repository.app
cd ..

# 2. Зібрати і завантажити образ (тег = короткий хеш коміту)
REPO=$(terraform -chdir=terraform output -raw ecr_repository_url)
TAG=$(git rev-parse --short HEAD)
aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin ${REPO%%/*}
docker build -t $REPO:$TAG .
docker push $REPO:$TAG

# 3. Створити решту інфраструктури
terraform -chdir=terraform apply -var="image_tag=$TAG"
```

## Видалення ресурсів

```bash
terraform -chdir=terraform destroy
```

Видаляє всі ресурси, включно з образами в ECR, базою та секретом.

## CI/CD (завдання 5) — реалізовано, але не застосовано

Код готовий:
- `terraform/github_oidc.tf.disabled` — OIDC-провайдер GitHub, IAM-роль з trust policy
  (тільки репозиторій `shpytt/cloud-lab1`, гілка `main`) і політика з мінімальними правами
  (push лише в наш ECR, оновлення лише нашого ECS-сервісу, PassRole лише ролі виконання).
- `.github/workflows/deploy.yml` — збірка образу, тег = хеш коміту, push в ECR,
  нова task definition, оновлення ECS-сервісу. Автентифікація через OIDC, без ключів.

**Чому не застосовано.** Акаунт створено за новою схемою AWS («Sign up for AWS (new)»):
він є проєктом в AWS Organizations, якою керує AWS, з незмінними service control policies.
Для Free і Paid планів SCP містить `Deny` на `iam:*Provider*`, тому `terraform apply` повертає:

    AccessDenied: ... not authorized to perform: iam:CreateOpenIDConnectProvider ...
    with an explicit deny in a service control policy

Зняти обмеження можна лише через «Activate advanced features», що вимагає переходу на Paid plan.
Варіант з довгоживучими access keys у GitHub Secrets заборонений умовою лаби, тому не використовувався.
Джерело: https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html