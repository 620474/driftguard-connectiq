# Calibration Edge 1050 — этап 1

30 октября 2026. Локальная реализация на базе `7d6b5c1123e208ef64e4911a662392cfdf0a9810` репозитория 620474/driftguard-connectiq. Push, PR и commit не выполнялись. Исходная рабочая копия и её незавершённые изменения не затронуты; существующий validation-lab перенесён в эту копию без `.env`, архива поездок и окружения.

Прочитаны AGENTS.md, CLAUDE.md, CURRENT_TASK, PROJECT_BRIEF, ARCHITECTURE, DECISIONS, STATUS, исходники приложения, validation-lab, FINDINGS_RU.md, IMPROVEMENT_PLAN_RU.md, research.json и verification.json. Текущий запрос владельца расширяет старый Milestone 4 диагностическим этапом. Новые фильтры, UI объяснений и подбор порогов в этот этап не входят.

## FIT контракт v1

Проверена официальная документация:
- https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html#createField-instance_function
- https://developer.garmin.com/connect-iq/api-docs/Toybox/FitContributor.html
- https://developer.garmin.com/fit/articles/fit-protocol/fit_protocol.html

Для Data Field максимум 32 байта на тип сообщения. Это не число полей. RECORD может зависеть от Smart Recording и не гарантирует одну запись на каждый callback. Фактическая доступность и нагрузка на физическом устройстве ещё не измерены.

Старые поля сохраняют ID 0–9. ProductionRecorder — перенесённый прежний DriftRecorder; изменены только имя класса и доступность writeMinute для наследника. Основная сборка использует простой наследник. Calibration добавляет диагностику. Математика и пороги неизменны; hook в commitMinute снимает суммы до resetMinute. В production hook пустой, диагностические данные исключены аннотацией.

| ID | RECORD поле | Тип | Байт |
|---|---|---|---|
| 0–4 | прежние EF/steady/drift/state/cadence | прежние | 11 |
| 10 | dg_minute_seq | uint16 | 2 |
| 11 | dg_sample_seq | uint32 | 4 |
| 12 | dg_valid_seconds | uint8 | 1 |
| 13 | dg_reject_reason | uint8 | 1 |
| 14 | dg_min_power_sum | uint32 | 4 |
| 15 | dg_min_hr_sum | uint16 | 2 |
| 16 | dg_compat_seconds | uint8 | 1 |
| 17 | dg_compat_power_sum | uint32 | 4 |
| 18 | dg_compat_hr_sum | uint16 | 2 |
| | Итого RECORD | | **32** |

SESSION: прежние 14 байт + dg_algo_version (ID19 uint16, значение 1), dg_config_crc (ID20 uint32), dg_bucket_width и dg_compat_width (ID21/22 uint16) = **24 байта**. CRC32 IEEE стандартной UTF-8 строки из driftlab/calibration_config.py, значение **1575803903**. Алгоритм/config v1 фиксированы: warmup15, valid48, band20, recovery3, mismatch5, ride40/70, last60/48, histogram10/150, buckets240. Тест проверяет соответствие исходным константам. При изменениях контракта нужна новая версия.

minute_seq=0 означает отсутствие завершённой минуты. Начиная с 1, каждый снимок описывает ровно 60 running callbacks, включая invalid samples. sample_seq — **конец завершённой минуты**, равен minute_seq*60; не счётчик текущей незавершённой минуты. Пауза ничего не добавляет; частичная минута продолжается после resume. Последний неполный хвост в FIT-полях не отражён. seq>=65535 отключает диагностику и обнуляет снимок, без wrap. uint16 65535 зарезервировано FIT; штатные HR-суммы должны быть <=65534. Неправдоподобные sensor values и переполнение Number не калиброваны на железе.

Причины взаимоисключающие, в порядке решения production: 0 warm-up; 1 меньше 48 valid seconds; 2 power band; 3 recovery; 4 accepted. Суммы valid относятся к секундам с положительными power и HR, независимо от принятия минуты. Compat включает все running секунды с положительным HR, missing/zero/negative power даёт нулевой вклад мощности. Median и recovery_left в RECORD не поместились и не записываются. Session bucket widths показывают ширину на последнем commit.

Поля обновляются последовательно внутри одного callback после commit, sequence записывается последним; это логическая группа, не обещание транзакционной атомарности Garmin. При частичном отказе createField запись диагностики не считается полной; parser сообщает incomplete/unsupported при отсутствии данных. Общий FIT-бюджет и конфликт с другими полями нужно проверять на Edge. Начальные значения прежних полей и stale drift сохраняют прежнюю семантику: drift читать только при matching state VALID.

## Сборка и установка

В `garmin-app`, PowerShell:

```powershell
./build.ps1 -Calibration -Key 'C:\path\developer_key.der' -Java 'C:\path\java.exe'
./build.ps1 -Calibration -Test -Key 'C:\path\developer_key.der' -Java 'C:\path\java.exe'
./build.ps1 -Key 'C:\path\developer_key.der' -Java 'C:\path\java.exe'
```

SDK берётся из Garmin current-sdk.cfg. Фактически использовались SDK 9.2.0, Edge1050 и строгий уровень 3. Ключ использован из прежней локальной копии и сюда не скопирован.

1. Подключить Edge 1050 по USB. Скопировать `garmin-app/bin/DriftGuard-calibration.prg` в `GARMIN/APPS/DriftGuard-calibration.prg`. Безопасно отключить устройство.
2. В отдельном тестовом cycling-профиле добавить Connect IQ data field **DriftGuard Calibration**. Отдельный UUID `db66c379db704260b7199dfc467e407a` позволяет сосуществовать с production. В тестовой активности выбрать только calibration: одновременный запуск двух dg_* производителей делает сравнение по именам неоднозначным.
3. Включить Every Second recording. Использовать HR и power. Запустить запись после готовности датчиков; сохранить оригинальный FIT из GARMIN/ACTIVITY. Отрисовка developer-полей в Garmin Connect не является критерием успеха sideload.
4. Контрольный сценарий: 59/60/61 running seconds; пауза внутри минуты и на границе; resume; нулевая мощность и пропуск HR; ровные минуты после warm-up; нестабильная минута и три recovery; сохранение с неполным хвостом; новая активность после reset. Для RIDE VALID нужно не менее 40 steady минут после 15 warm-up.
5. Проверить sequence, суммы, причины, состояние и границы без подбора offset. Повторить Auto Pause и ручную паузу; это отдельные проверки на устройстве.

В `validation-lab`, Python >=3.12:

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -e .
./.venv/Scripts/python.exe -m driftlab.calibration 'C:\path\activity.fit' > calibration-result.json
./.venv/Scripts/python.exe -m unittest discover -s tests -v
```

Код выхода 0 только у matched_candidate. Остальные статусы: unsupported (версия/config/session), incomplete (нет снимков/sequence, пропуски, противоречивые повторы), mismatch (суммы/состояния/границы/float расходятся). Одинаковые соседние минуты различаются по sequence, неизменные повторные RECORD схлопываются. Пропуски и сдвиг первого наблюдения не компенсируются. Сравниваются integer/state строго, drift/compat/power change с заранее заданным абсолютным допуском 0.001 процентного пункта. Финальный stale drift при не-VALID не сравнивается как актуальный. Обязательные определения и присутствие полей RECORD/SESSION проверяются целиком до сравнения. Nullable float может быть unset, пока соответствующий результат не определён; отсутствующее обязательное определение этим не оправдывается.

matched_candidate означает совпадение декодированных FIT входов с наблюдаемыми снимками, а не доказанную идентичность входов compute. FIT реконструкция сохраняет quality issues, не интерполирует сенсоры. Smart Recording, отсутствующие timer events и первая запись после старта могут менять границы. Версия/config отсутствуют в старых FIT: их нельзя объявлять точным replay. Parser сохраняет provenance; calibration-validator отклоняет смешанных производителей dg_* и не выбирает поля только по именам. Не подбирать offset для получения совпадения.

## Проверки первого этапа (bb98020) и ограничения

- Python **35/35**: прежние 25 + 10 новых, в том числе настоящий синтетический FIT с developer descriptions, CRC и полями session/record; 59/60/61; пауза внутри минуты; равные соседние снимки; missing/conflicting sequence; invalid config; integer mismatch; zero power; CRC/config; power/compression boundaries.
- Monkey C calibration **24/24** в симуляторе: прежние 21 + 3 новых. Логи рядом: calibration-python-tests.txt и calibration-simulator-tests.txt.
- Production, production test, calibration и calibration test **собраны успешно**. Дополнительно production test прогнан в симуляторе: **21/21**, лог production-simulator-tests.txt; runner также вернул 1 при PASSED.
- Runner симулятора завершился с exit code 1, несмотря на `PASSED (passed=24, failed=0, errors=0)`; статус подтверждён по полному выводу, не по коду процесса. Python выдаёт ResourceWarning из старых HTTP mock-тестов, без падения.
- Найдено и сохранено различие точно на gate 5%: 20 минут 200 W + 20 минут 210 W при HR100 дают Python double `5.000000000000004%` / POWER_CHANGED; Monkey C Float — VALID. 211 W отвергается обоими. Oracle не bitwise эмулятор Float. Состояния в отчёте не маскируются float-допуском.
- Проверены compression boundaries 240/241/481/961 на одинаковых синтетических данных в обоих языках. Суммы сохраняются, но половинный split после compression остаётся приближённым для неоднородной нагрузки (прежний тест это фиксирует).
- Не выполнены: запись и выгрузка нового FIT физическим Edge, нагрузочное измерение CPU/памяти/FIT allocation и гарантии callback/record порядка на железе. Симуляторные unit tests не создают FIT fields в activity и не доказывают успех их выделения на устройстве.
- Новые FIT поля не присутствуют в исследованном архиве 122 поездок; этот архив не может подтвердить новую схему. Compatibility — собственная whole-activity reference, совпадение с Intervals не обещается.

Следующая проверка — контрольная запись на Edge по процедуре выше, затем разбор несовпадений до любых изменений production порогов.

## Уточнение validator: происхождение и полная схема

Этот этап меняет только validation-lab. Monkey C, UI, математический oracle, пороги, UUID и FIT payload не изменены.

Основание: [Garmin Developer Data](https://developer.garmin.com/fit/articles/cookbook/developer_data.html) и [FIT Protocol](https://developer.garmin.com/fit/articles/fit-protocol/fit_protocol.html). Источник задаётся application_id из developer_data_id; ссылку на поле задают developer_data_index + field_definition_number. Это идентификация в FIT, не криптографическое доказательство подлинности приложения.

Проверено API установленного fitdecode 0.11.0: FitDefinitionMessage.dev_field_defs и FieldData.field_def содержат is_dev, dev_data_index, def_num, base_type.identifier и size. application_id читается из raw developer_data_id; private API библиотеки не используется.

Decoder сохраняет все developer_fields отдельным списком с raw application_id (16 байт в hex), developer_data_index, field_definition_number, name, base_type, size и value. Определения сообщения сохраняются как developer_schema. Поля разных разработчиков с одинаковыми именами не теряются: неоднозначные имена не включаются в прежний плоский fields. Для не-calibration потребителей однозначные имена сохранены.

Validator использует только developer metadata ожидаемого calibration UUID. Поддерживаются точные GUID bytes и .NET GUID little-endian layout, без угадывания по имени. Любой dg_* другого/неизвестного UUID, отсутствующий provenance, несколько developer indices для calibration, дубли полей или переназначенный developer_data_index дают unsupported. В частности, совместная запись production+calibration не может стать matched_candidate. Старые decoded JSON без metadata нужно заново получить из оригинального FIT.

### Обязательная схема v1

Единственный программный manifest: validation-lab/driftlab/calibration_schema.py (SCHEMA). Для каждого поля обязательны правильные message type, field ID, FIT base type и scalar size. Ниже полный список, включая прежние production-поля.

| Message | Поле | ID | FIT base type | Байты |
|---|---|---|---|---|
| record | dg_ef | 0 | 0x88 | 4 |
| record | dg_steady | 1 | 0x02 | 1 |
| record | dg_ride_drift | 2 | 0x88 | 4 |
| record | dg_ride_state | 3 | 0x02 | 1 |
| record | dg_cadence | 4 | 0x02 | 1 |
| session | dg_ride_drift_final | 5 | 0x88 | 4 |
| session | dg_ride_state_final | 6 | 0x02 | 1 |
| session | dg_steady_percent | 7 | 0x02 | 1 |
| session | dg_power_change | 8 | 0x88 | 4 |
| session | dg_compat_drift | 9 | 0x88 | 4 |
| record | dg_minute_seq | 10 | 0x84 | 2 |
| record | dg_sample_seq | 11 | 0x86 | 4 |
| record | dg_valid_seconds | 12 | 0x02 | 1 |
| record | dg_reject_reason | 13 | 0x02 | 1 |
| record | dg_min_power_sum | 14 | 0x86 | 4 |
| record | dg_min_hr_sum | 15 | 0x84 | 2 |
| record | dg_compat_seconds | 16 | 0x02 | 1 |
| record | dg_compat_power_sum | 17 | 0x86 | 4 |
| record | dg_compat_hr_sum | 18 | 0x84 | 2 |
| session | dg_algo_version | 19 | 0x84 | 2 |
| session | dg_config_crc | 20 | 0x86 | 4 |
| session | dg_bucket_width | 21 | 0x84 | 2 |
| session | dg_compat_width | 22 | 0x84 | 2 |

Проверяется и полный набор определений, и присутствие полей в каждом RECORD/SESSION. Обязательные scalar integers должны иметь значение в session и завершённых minute snapshots. До первой завершённой минуты nullable initial values разрешены. dg_ef должен иметь значение после commit; dg_ride_drift при VALID также обязателен. Неактуальные drift/power-change floats могут оставаться unset при наличии их определений; когда oracle ожидает session float результат, отсутствие значения даёт incomplete. Float-допуск 0.001 применяется только к сравнению значений, а не состояний. Неизменные соседние RECORD не подменяют проверку полноты.

### Статусы и порядок проверки

- unsupported: нет однозначного calibration producer, неверные definition type/size/ID/message, смешанные dg_* источники, неизвестные version/config или неподдерживаемое число sessions.
- incomplete: источник распознан, но обязательное определение/поле/необходимое значение отсутствует, sequence имеет gaps/conflicts или нет завершённых snapshots.
- mismatch: сопоставимые полные данные есть, но значения, состояния или границы расходятся.
- matched_candidate: источник, полная схема, sequence и сравнение прошли. При наличии проблем полноты они имеют приоритет над найденными численными расхождениями; differences остаются в отчёте, если были рассчитаны.

matched_candidate по-прежнему не доказывает идентичность reconstructed FIT stream и DataField.compute callbacks. Offset fitting не добавлен. Физические Every Second / Auto Pause / reset записи Edge 1050 обязательны для проверки канала наблюдения. Этот этап выполняет проверки на синтетических FIT и не заменяет физический эксперимент.


Проверки этого этапа: **53/53 Python tests**, 0 failures/errors, команда `python -m unittest discover -s tests -v` из validation-lab; полный вывод — calibration-provenance-tests.txt. Включены отрицательные случаи для каждого из 23 обязательных определений, разных UUID, двух producers, дублированных имён, неверных message/type/size/ID, отсутствующих значений и sequence conflicts. Существующие математические тесты, включая точную границу 5%, сохранены. Production и calibration повторно собраны SDK 9.2.0 / edge1050 / strict level 3. Команды и результаты — calibration-provenance-verification.json. Гармин-исходники и oracle имеют zero diff. Симулятор на этом offline-этапе повторно не запускался; физический Edge не проверен. В старых HTTP mock-тестах сохраняются ResourceWarning без ошибок тестов.
