# DriftGuard Validation Lab

Локальный исследовательский инструмент Python 3.12+. Production Monkey C не изменён.

Обычный запуск: откройте `.env` в этом каталоге и вставьте Personal API key после `GARMIN_PERSONAL_API_KEY=`. Не вставляйте 24-часовой Bearer token вместо ключа. `.env` исключён из Git. Затем из этого каталога в PowerShell:

```powershell
.\lab.ps1 run -Suite
```

Альтернатива с зашифрованным Windows DPAPI хранением:

```powershell
.\lab.ps1 auth
.\lab.ps1 run -Suite
```

`auth` запрашивает **Personal API key**, а не 24-часовой access token. Ввод скрыт; ключ сохраняется в `.data/garmin-key.xml` через Windows DPAPI для текущего пользователя Windows. Не передавайте ключ в чат. Виртуальное окружение и зависимости создаются автоматически при первом запуске. Интернет нужен для установки и sync, HTML работает полностью offline.

Команды:

```powershell
.\lab.ps1 sync
.\lab.ps1 analyze -Suite
.\lab.ps1 compare
.\lab.ps1 report
.\lab.ps1 test
.\lab.ps1 run -Offline -Suite
.\lab.ps1 run -ImportDir 'D:\Garmin FIT' -Suite
```

Результат: `.data/report/index.html`, summary.csv, results.json, CSV минут каждого варианта. Исходные FIT и JSON содержат персональные данные: каталог `.data` игнорируется Git. Не переносите его в публичные артефакты. Для другого пути используйте `python -m driftlab.cli run --data PATH --offline`.

Sync получает cycling вместе с подтипами за шесть календарных месяцев от локальной даты запуска. Оригиналы имеют Garmin activity ID, импортированные файлы — SHA256. Manifest проверяет содержимое перед пропуском; загрузки и JSON сохраняются атомарно. Ошибки отдельных файлов не удаляют завершённую выгрузку, но дают ошибку запуска; повторите sync. Изменённые оригиналы сохраняются отдельными версиями. Анализ кешируется по SHA256 входа, исходников Python и набору экспериментов. Анализ ограничен шестью месяцами; исходный архив не удаляется.

Набор Suite меняет по одному параметру относительно current: warm-up 0/10/15/20/30, recovery 0/1/2/3, median current/prior/rolling60/fixed, band 10/15/20/25, valid seconds 42/48/54, mismatch 2/3/5/7.5/10. `compare` включает Suite. Fixed baseline означает первую подходящую минуту; prior при отсутствии истории использует текущую минуту. Это явные экспериментальные определения, не production.

## Подтверждённый официальный доступ

Проверено 30 октября 2026:

- https://developer.garmin.com/gc-developer-program/overview/ — Personal: pull, JSON и FIT.
- https://developer.garmin.com/gc-developer-program/personal/personal-faq/ — ключ обменивается на access token, срок до 24 часов, refresh token отсутствует.
- https://developer.garmin.com/gc-developer-program/personal/swagger-docs/ — activity search с датами и parent type cycling; original download возвращает ZIP.

Адаптер использует только `personal.connectapi.garmin.com`: POST `/personalapitoken-service/personal-api/personal-api-key/token` с `Authorization: ApiKey …`, GET search и GET download с Bearer token. Access token держится только в памяти; при 401 один повторный обмен. 429/5xx и сетевые ошибки имеют ограниченные повторы; длинный Retry-After требует повторного запуска позднее. 403 не обходится. Для перевыпуска ключа повторите auth. CAPTCHA, SSO и пароль не используются. Реальный доступ ещё не проверен вашим ключом. Китайский регион пока не поддержан.

Intervals.icu и blocks.zone не нужны для получения FIT. Их подключение можно добавить для внешнего сравнения при доступном контракте API/MCP; такая интеграция здесь ещё не реализована и не является физиологическим эталоном.

См. METHODOLOGY.md и ALGORITHM.md для ограничений. Тесты используют только синтетические данные. Реальных результатов тренировок в проекте нет.

Период по умолчанию — 6 календарных месяцев. Другой период: `.\lab.ps1 run -Suite -Months 6` или `python -m driftlab.cli run --suite --months 6`.

## Исследовательский разбор

После `run -Suite` выполните `.\lab.ps1 research`: проверка причин исключения, вариантов на общей поддержке, заданных 30-минутных блоков нагрузки, dg_* и read-only Intervals, затем отчёт с 14 кейсами и планом улучшений.

Для Intervals в локальном `.env` доступны `INTERVALS_API_KEY` и `INTERVALS_ATHLETE_ID` (0 означает владельца ключа). Используется Personal API key с HTTP Basic API_KEY, не OAuth Bearer token. При отсутствующем ключе анализ Garmin продолжается. Исходные файлы не отправляются в Intervals; получаются только метаданные активностей. Точный Garmin external_id используется для сопоставления; сходство времени не считается идентичностью. Документация: https://intervals.icu/api/v1/docs .

Результаты: `.data/research/index.html`, `FINDINGS_RU.md`, `IMPROVEMENT_PLAN_RU.md`, JSON/CSV и device_alignment.json. Отчёт — исследовательский вывод, не разрешение автоматически изменять production. Он содержит чувствительные данные и остаётся локальным. Последняя проверка: 25 Python-теста, Edge 1050 test build прошёл; новый simulator run не завершился. Визуальная проверка локального file URL инструментом браузера недоступна, структурные проверки HTML выполняются отдельно.

## Calibration Edge 1050

Диагностическая сборка и сравнение новых FIT-полей: [процедура](../docs/CALIBRATION_RU.md). Команда: python -m driftlab.calibration activity.fit.


## Experimental automatic power efforts (offline only)

See [AUTO_EFFORTS_RU.md](../docs/AUTO_EFFORTS_RU.md). Run:

```powershell
python -m driftlab.auto_efforts 'C:\path\archive' --output 'C:\path\new-private-report'
```

This does not change the Edge application. The output includes private activity
identifiers and must remain local. Three prespecified candidates are compared;
counts do not establish accuracy without independent effort labels.
