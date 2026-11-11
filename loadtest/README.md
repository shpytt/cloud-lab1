# Навантажувальний тест

Запуск (60 користувачів, 10 хвилин):

    ./loadtest/run.sh

Інша кількість користувачів:

    ./loadtest/run.sh -e VUS=120

Потрібен встановлений k6 (https://k6.io). Адреса сервісу береться з `terraform output alb_url`
або зі змінної `BASE_URL`. Опис сценарію, параметри й результати: [docs/LOADTEST.md](../docs/LOADTEST.md).
