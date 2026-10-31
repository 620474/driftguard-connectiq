# Live AUTO на Edge 1050 — 2026-10-31

По новому запросу владельца автоматический режим включён в приложение по умолчанию.
Без workout/manual источника он работает при каждом compute, независимо от экрана.
Переключение на INTERVALS — обычным тапом. Первые 60 известных running samples
собирают baseline; затем возможна автоматическая детекция. HR для неё не требуется.
Параметры balanced v1 перенесены из Python как инженерный стартовый контракт,
без заявления, что это оптимальный или физиологически валидированный вариант.

Одиночный всплеск не становится усилием: 3 samples подтверждают начало,
до 10 s экран показывает CONFIRMING. Пять низких samples закрывают усилие;
короткий провал внутри включается в среднее. После окончания видны LAST W / s.
Pause/missing power закрывают достаточно длинное усилие с LAST INCOMPLETE,
baseline собирается заново. Текущая активность без HR поддерживается.

Manual LAP переводит в ручные сегменты до workout/reset; неполное AUTO при
переключении источника сбрасывается. Workout start/step имеют приоритет.
Определение окончания workout по-прежнему не реализовано: WORKOUT остаётся до
reset/new activity. Сохранённый экран не влияет на выбор источника анализа.
DRIFT и FIT-схемы не меняются. Разделы ниже описывают также историю этапов.

---

# INTERVALS: первый этап

База: d54af7a5f38dd96ac1958a490a0313c0757312a3. Дата: 2026-10-31.

Тап переключает DRIFT / INTERVALS. DRIFT сохраняет оба результата и прежний
fallback большого показателя. На компактном DRIFT обе строки видимы одновременно.
Ключ screen (0/1) сохраняет только экран. Старый metric игнорируется: первый запуск
после обновления открывает DRIFT. Между активностями анализ не сохраняется.

INTERVALS показывает SEG, среднюю мощность, running duration, число валидных
power samples / всех running samples и источник. Это сегмент, а не автоматически
распознанное усилие. Пропуск мощности не равен нулю. Диапазон допустимой мощности
0..10000 W — техническая защита от повреждённых значений, не физиологический порог.
Сумма Float и постоянное число scalar полей; секундные ряды не сохраняются.

## Границы

- До первого события samples не накапливаются. Первый manual lap начинает SEG 1;
  время до него не становится завершённым интервалом.
- onWorkoutStarted сбрасывает интервальную последовательность и начинает SEG 1.
- onWorkoutStepComplete закрывает текущий непустой сегмент и начинает следующий.
  Если приложение загружено посреди workout, первая замеченная граница начинает
  SEG 1; предшествующий неполный шаг не восстанавливается.
- Последовательные события границы без running sample между ними игнорируются.
- В режиме WORKOUT manual lap игнорируется; Auto Lap всегда игнорируется.
  onTimerLap2 возвращает true для исключения повторного legacy onTimerLap.
- После workout source остаётся WORKOUT до нового старта/сброса активности:
  автоматическое определение окончания workout на этом этапе не реализовано.
- Пауза не добавляет samples. Если уже есть данные, сегмент отмечается INTERRUPTED;
  после продолжения остаётся тот же сегмент, время паузы исключено.
- onTimerReset удаляет текущий незавершённый и предыдущий сегмент.
- При перезапуске поля накопление начинается заново; частичный сегмент не склеивается.
- Границы callbacks привязаны к порядку их доставки: последний полученный sample
  до события принадлежит завершаемому сегменту. На физическом Edge порядок нужно проверить.

Для onTimerLap2 оба manifest требуют API >=5.2.2. Edge 1050 поддерживается.
Activity.getCurrentWorkoutStep не используется: он запрещён для Data Field.
Документация: https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html

## Что проверять на FIT за шесть месяцев

Независимая offline-модель: validation-lab/driftlab/intervals.py, класс Intervals.
Ей передают running samples и явно размеченные события границ. Для обеих реализаций
проверяется одинаковый stream в intervalBoundariesAndMissingPower / test_shared_monkey_stream.

Сначала составить инвентаризацию исходных FIT, датчиков, timer events и lap metadata.
Не считать каждый lap ручным: если trigger неизвестен, источник границы неизвестен.
Не угадывать workout step callbacks по каждой lap-записи. Сопоставить доступные
реальные границы с разметкой и отдельно проверить арифметику по известным сегментам.
Smart Recording не равен 1 Hz compute: число записей не выдавать за running seconds.
Для идентичного replay нужна явная политика реконструкции; интерполяцию обозначать.
Старые FIT не содержат новых interval-полей: проверить реальный callback parity по
ним нельзя. Новые FIT-поля в этот этап не добавлены, calibration RECORD остаётся 32 B.

Далее: определить rep grouping и базу сравнения ΔP отдельно от допуска мощности
для ΔHR; только затем исследовать HR-tail/HRR на отложенной выборке. Эти метрики
и автоматическая классификация работы/отдыха в первую версию не входят.


## Следующий offline-этап

Добавлен экспериментальный детектор по мощности: [AUTO_EFFORTS_RU.md](AUTO_EFFORTS_RU.md).
Он пока не включён в приложение на Edge. В live-версии остаются явные границы.
Правила времени offline-импорта: [TIMER_POLICY_RU.md](TIMER_POLICY_RU.md).


## Experimental AUTO EXP (owner enabled, 2026-10-31)

AUTO sessions enable the experimental local-step variant on Edge. Explicit manual
and workout segments retain priority. The heading identifies AUTO EXP. A rolling
60-s median includes active-effort samples. Entry requires >=180 W and >=115% of
the median and >=median+30 W for 3 samples. The confirmed start is backdated two
samples. Exit requires five samples below 115% or median-at-start+20 W; those exit
samples are excluded. A brief dip is included when power returns. Save >=20-s
efforts; pause/dropout marks incomplete and clears baseline. After >=120 s of an
active effort, another confirmed local step closes the parent and starts a new
segment without counting the confirming samples twice. Such a split cancels HRR;
it is not recovery. Exit baseline stays frozen for each segment. These are
engineering choices, not validated physiological intensity zones. The absolute
180 W floor is not individualized and may miss low-power athletes' intervals.
Legacy balanced-v1 remains available internally for parity tests; actual AUTO
sessions explicitly enable the experiment. DRIFT and FIT field schema unchanged.
