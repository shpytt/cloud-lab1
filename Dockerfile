# Фіксована версія базового образу (не latest)
FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Окремий непривілейований користувач
RUN useradd --create-home --uid 10001 appuser

# 1) Спочатку тільки залежності: цей шар кешується,
#    поки requirements.txt не змінюється
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2) Потім код: зміна коду не змушує перевстановлювати бібліотеки
COPY app ./app

# Процес працює не від root
USER appuser

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]