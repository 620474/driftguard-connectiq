"""Render the research conclusions and selected cases without a server."""
from pathlib import Path
from collections import Counter
import json,html,statistics

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'.data/research'
r=json.loads((OUT/'research.json').read_text('utf8'));s=r['summary'];cohort=r['cohort'];lookup={c['id']:c for c in cohort}
def fmt(v):return '—' if v is None else f'{v:.2f}' if isinstance(v,float) else str(v)
def table(headers,rows):
    return '<div class="scroll"><table><thead><tr>'+''.join('<th>'+html.escape(str(v))+'</th>' for v in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(fmt(v))+'</td>' for v in row)+'</tr>' for row in rows)+'</tbody></table></div>'
insuff=Counter();origins=Counter()
for c in cohort:insuff.update(c['insufficient_minute_causes']);origins.update(c['recovery_origins'])
absolute=[abs(v['delta_compat_pp']) for v in r['intervals_matches'] if v['delta_compat_pp'] is not None]
accepted=sum(c['accepted_second_power_cv']['n'] for c in cohort);highcv=sum(c['accepted_cv_over_30'] for c in cohort)
findings=f'''# DriftGuard: результаты валидации и следующий этап разработки

Дата: 30 октября 2026. Период: 30 апреля — 30 октября 2026. Исследовано 122 Garmin FIT и 20 вариантов; оригиналы и production-код сохранены. Intervals подключён только на чтение.

## Решение

Не менять пороги production по этому архиву. Следующий релиз стоит посвятить диагностике входных данных и объяснимости отказов, затем провести ограниченное испытание recovery и внутриминутной вариативности. Сейчас главная проблема разработки — недостаточная наблюдаемость, а не доказанная ошибка формулы Pw:HR.

## Подтверждённые результаты

- 108 файлов — кандидаты для сравнения, 13 — приближённое воспроизведение, 1 — недостаточно данных. Candidate не означает идентичность live compute и FIT.
- RIDE: VALID 8; POWER_CHANGED 3; NOT_STEADY 86; COLLECTING 11; WARMUP 14. Часть архива слишком коротка для результата по текущему контракту; 8/122 нельзя интерпретировать как долю ошибочно обработанных подходящих тренировок.
- Принято {accepted} минут. Исключено из-за valid seconds 3135, power band 3037, recovery 2482; warm-up 1726 учитывается отдельно.
- В {insuff['coasting_dominant']} из 3135 минут с недостатком valid seconds преобладает нулевая мощность при наличии HR, а не пропуски. Это {insuff['coasting_dominant']/3135*100:.1f}%. Нулевая мощность часто соответствует свободному качению, но сама по себе не доказывает его физиологическую причину.
- Из 2482 recovery-минут {origins['insufficient valid seconds']} следуют за недостатком valid seconds, {origins['power out of band']} — за power band. Трёхминутный штраф усиливает оба типа исключения.
- {highcv}/{accepted} принятых минут ({highcv/accepted*100:.1f}%) имеют CV положительной секундной мощности выше 30%. Steady по средней минутной мощности не означает ровную мощность внутри минуты. Это диагностический экран, не доказательство физиологической непригодности каждой такой минуты.

## Что показали эксперименты

Recovery 3→2→1→0 минут даёт соответственно 8→10→12→19 VALID поездок. Без recovery добавляются ровно 2482 минуты; медианное изменение покрытия +19.30 процентного пункта. Среди 8 поездок, VALID в обоих вариантах, сдвиг drift от −0.98 до +0.75 п.п., медиана +0.09. Это выбранная подгруппа, не оценка всех 122 тренировок.

Band ±25% даёт 10 VALID против 8, ±15% — 5, ±10% — 0. Ослабление band не решает общую проблему доступности. Prior-only и rolling60 median дают те же 8 VALID, но меняют отбор в 46 и 25 поездках соответственно. Равное число итоговых состояний не означает одинаковые фильтры. Fixed baseline первой подходящей минуты даёт 7 VALID и чувствителен к первой минуте; оснований делать его основным нет.

Valid threshold 42 секунды оставляет 8 VALID, 54 секунды — 7. Понижать 48 ради доступности на этих данных не обосновано. Power mismatch 3% оставляет 7 VALID, 2% — 5; 10% даёт 11. Этот gate меняет разрешение показать число, а не отбор минут. Ослаблять его ради совпадения с Intervals не следует.

Warm-up 10/20/30 минут даёт по 10 VALID; это не делает ни один вариант оптимальным. Сдвиги warm-up меняют и выборку, и reference median; оценивать их нужно на контролируемой нагрузке.

## Систематическое смещение: что установлено

Заранее заданный, независимый от HR экран искал неперекрывающиеся 30-минутные блоки после 15 минут: >=54 valid seconds в каждой минуте, минутный CV мощности <=10%, каждая минутная мощность в ±15% медианы блока, mismatch половин <=3%. Найдено только 4 блока в 3 поездках. Это операционное определение ровной нагрузки, не физиологический ground truth.

В 3 блоках steady-фильтр оставил всё; в одном исключил 2 recovery-минуты. Разница между отфильтрованным и полным drift составила от −0.263 до 0 п.п. Данных недостаточно, чтобы подтвердить либо опровергнуть систематическое смещение, и недостаточно для частоты false rejection.

Для каждой пары фильтров также рассчитан drift на пересечении одинаковых минут: формула на одинаковых суммах одинакова по построению. Этот контроль отделяет изменение состава выборки от изменения формулы; он не является независимым доказательством правильности oracle.

## Сопоставление с устройством

В 17 активностях есть dg_*; финальное состояние совпало 17/17, но 16 из этих состояний не VALID, поэтому это слабое подтверждение. Только одна поездка позволяет сравнить финальный VALID drift: запись устройства 1.7432%, Python 1.7960%, разница 0.0528 п.п. Это близость, не точное совпадение.

Compatibility drift расходится от −71.80 до +5.38 п.п. Доля steady-минут тоже местами расходится. Наибольшее расхождение — короткая поездка в WARMUP; не переносить его на оценку валидного RIDE. Между изменениями dg_ef встречаются 59/61/62 и более running seconds, а не только 60. Возможные причины: границы callbacks/record, старт/пауза, отличия live sensor values, версия приложения. Эти причины пока не разделены экспериментом. Подбор ближайшего snapshot в device_alignment.json — диагностический поиск, а не подтверждение совпадения.

Необходимы minute_seq, sample counter, версия/config и исходные минутные суммы. Без них обещать точный replay по обычным FIT недостоверно.

## Сопоставление с Intervals

Получено 143 активности; 112 сопоставлены по точному Garmin external_id, для 111 есть decoupling. Десять Garmin-активностей не сопоставлены; близость времени сама по себе не использовалась как идентичность. Совпадение ID не доказывает одинаковые потоки данных и настройки обработки.

Для oracle compatibility против Intervals: медиана signed delta −0.045 п.п., но медиана абсолютной разницы {statistics.median(absolute):.2f} п.п.; только {sum(v<=1 for v in absolute)}/111 значений отличаются не более чем на 1 п.п., {sum(v>5 for v in absolute)}/111 — более чем на 5 п.п. Нулевая медиана signed difference скрывает разнонаправленные большие расхождения. Для classic clock median absolute difference 4.71 п.п.

Следовательно, dg_compat_drift нельзя описывать как точный клон Intervals. Различаются возможные правила warm-up/cool-down, временного разделения, HR gaps и обработки потоков. API decoupling не объявляется эталоном; текущие пользовательские настройки и внутренние исправления потоков Intervals здесь не восстановлены.

Источники контракта: https://intervals.icu/api/v1/docs ; объяснение расчёта для выделенных интервалов разработчиком: https://forum.intervals.icu/t/aerobic-decoupling-calculation-question/1823 . Не следует автоматически отождествлять формулу выделенного интервала с любым агрегатом всей активности.

## Сжатие buckets

Суммы сохраняются точно, разбиение на половины — приблизительно. Детерминированный пример с capacity=4 и пятью минутами даёт 44.4444% без сжатия и 35.2941% после сжатия при сохранённых суммах. Это специально стрессовый пример, не оценка типичной ошибки при capacity=240. В 8 реальных VALID результатах измеренная разница 0; это не доказательство нулевой ошибки на всех длинных поездках. Добавлен регрессионный тест, сохраняющий фактическое поведение production.

## Проверки и границы

25 Python-теста проходят. Edge 1050 test build с strict compiler level 3 собран успешно. MonkeyDoDeux не завершил запуск тестов и не выдал результат; ожидание остановлено. Поэтому новый прогон simulator tests не объявляется успешным. Python float64 не является битовым воспроизведением Monkey C Float; версия приложения, записавшего каждый FIT, не подтверждена. Production Monkey C, его пороги и алгоритм не изменены, push и PR не выполнялись.

Подробности: research.json, cohort.csv, models.csv, comparisons.csv, segments.csv, device_comparisons.csv, device_alignment.json, intervals_matches.csv. 14 показательных поездок с графиками находятся в index.html. Все отчёты локальные и содержат персональные данные.
'''
plan='''# DriftGuard: план улучшений и критерии приёмки

## P0 — сделать воспроизведение проверяемым

Первый кандидат на следующий релиз — диагностическая запись, без изменения алгоритма. Не включать все поля сразу: проверить бюджет FIT, память и время записи на целевом Edge; начать с отдельного calibration build.

| Поле | Где / тип-кандидат | Что позволяет проверить |
|---|---|---|
| dg_algo_version | session / uint16 | Версию математического контракта |
| dg_config_crc | session / uint32 | Точное соответствие warm-up, recovery, band, gates |
| dg_minute_seq | record / uint16 | Границы engine-minute вместо угадывания по изменению EF |
| dg_sample_seq | record / uint32 | Число consumed running callbacks, включая invalid seconds |
| dg_valid_seconds | record / uint8 | Почему минута не прошла 48-second gate |
| dg_reject_reason | record / uint8 | warm-up / insufficient / band / recovery / accepted |
| dg_recovery_left | record / uint8 | Состояние recovery после решения |
| dg_ref_power | record / uint16 | Использованную reference median |
| dg_min_power_sum | calibration / uint32 | Точные суммы мощности для current drift |
| dg_min_hr_sum | calibration / uint16 | Точные суммы HR для current drift |
| dg_compat_seconds и суммы | calibration / тип по диапазону | Особую семантику compatibility, включая missing power |
| dg_bucket_width | session / uint16 | Фактическую точность половин после compression |

Типы — проектные предложения, не гарантия доступности бюджета на устройстве. Счётчики должны быть явно привязаны к одному minute_seq; поля обновляются атомарной логической группой после commit. Коды reject reason версионируются; записать определение, относится ли recovery_left к состоянию до или после commit.

Приёмка: одна и та же последовательность поступает в Monkey C и Python; совпадают valid seconds, причины, медиана, суммы и состояния. Float сравнивается с заранее установленным допуском, отдельно от integer/state checks. Добавить испытания pause/resume, sensor gaps, zero power, 48-second boundary, 5% power-change boundary, 240/241 и несколько циклов compression. Для реального FIT сравнивать только подтверждённый minute_seq и версию.

## P1 — объяснять отказ пользователю

Сохранять существующие состояния. Для NOT_STEADY показывать краткую причину: мало времени с мощностью, нестабильная мощность или recovery, плюс accepted/required duration. Различать потерю сигнала и нулевую мощность; не называть любое zero-power sensor dropout. LAST60 и RIDE должны иметь собственные причины/coverage.

Доступные дополнительные поля интерфейса: «Steady 24/40 min», «Recovery 2 min», «PWR Δ −6%» при power-change gate, «Data gaps 1%» в диагностическом экране. Проверить существующие элементы UI, чтобы не дублировать уже показанные steady/progress/power change. Новые данные добавлять только если они объясняют решение; не перегружать основной экран датчиковыми счётчиками. Полное объяснение — в отчёте, короткая причина — на Edge.

Приёмка: на синтетических сценариях причина экрана соответствует reject reason; текст читаем на Edge 1050 в полном и компактном layout, далее отдельно проверить устройства без touch. Последний числовой drift не должен выглядеть актуальным, если matching state уже не VALID. Существующий контракт stale developer values нужно документировать и проверять у потребителей, а не объявлять любую сохранённую цифру ошибкой формулы.

## P1 — эксперимент по recovery, без немедленной калибровки

Сначала проверить 3/2/1 минуты на одних и тех же заранее выбранных нагрузках. Дополнительная offline-гипотеза: различать причины выхода из steady и не назначать одинаковый штраф одиночному краткому coasting, длительной остановке и мощному подъёму. Это новая модель, её нельзя подменять в oracle. Пульс после coasting тоже запаздывает, поэтому простое удаление recovery не обосновано.

Измерять: доступность RIDE/LAST60, поддержку по времени в обеих половинах, сколько steady сегмента исключено, распределение изменений drift при одинаковом workload, а также сохранение защиты после тяжёлой нагрузки. Заморозить кандидата на части поездок, проверить на отложенной части; не выбирать победителя на всех данных сразу. Повторные поездки одного пользователя не считать независимой выборкой из популяции.

## P1 — отделить ровную минутную среднюю от ровной нагрузки

455 принятых минут имеют секундный CV мощности >30%. Добавить offline-признаки: CV секундной мощности, 10-second power range и доля нулей. Сначала показать их рядом с классификацией, затем испытать новые правила на устойчивых и интервальных сценариях. Не назначать production-порог CV=30% из этого описательного анализа. Каденс использовать как диагностический признак, не как автоматический физиологический критерий.

## P2 — математические и методические уточнения

- Сохранить текущую формулу Pw:HR и power-change gate до контролируемого сравнения. Более частый VALID не равен более точной оценке.
- Называть compatibility собственной документированной whole-activity reference, а не обещать численное совпадение с Intervals.
- Документировать approximation после bucket compression; хранить bucket width и сравнивать с uncompressed offline reference. Не увеличивать production memory без измерения бюджета; точное сохранение сумм само по себе не гарантирует точный split.
- Current median включает текущую минуту. Prior-only и rolling60 заслуживают дальнейшего исследования по causal selection, но на этих данных не дали выигрыша по числу VALID. Current running median не использует будущие данные.
- Fixed baseline первой eligible minute не выбирать основным: возможна плохая стартовая нагрузка и длительный lockout.
- Warm-up оставлять 15 минут до дополнительных контролируемых тренировок. Поддержка нескольких warm-up настроек — отдельное продуктовое решение, не вывод о физиологическом оптимуме.

## P2 — оптимизация реализации

На устройстве не установлен CPU/memory bottleneck. Текущие фиксированные histogram/buckets/ring buffer соответствуют ограничениям Edge; переписывать их ради предположенной скорости сейчас не нужно. Сначала профилировать compute, commit, render и FitContributor на устройстве, включая navigation/pause и несколько data fields. Новую подробную запись включать по флагу calibration, чтобы не тратить FIT budget постоянно.

В lab в первую очередь оптимизировать хранение и отчёты: сохранять полный decoded FIT отдельно, для исследования читать только необходимые message types, сохранять компактные sufficient statistics, разделить ключи кеша importer/oracle/experiments/report, чтобы изменение HTML или сетевого адаптера не заставляло пересчитывать oracle. Записывать версию parser и source revision в manifest. Сохранить атомарные записи и immutable originals; оптимизация не должна удалять архив.

## Критерий готовности к изменению production

1. Проверен replay одинаковых входов, известны версия/config и границы минут.
2. Есть заранее заданные контролируемые steady-сегменты и нестабильные контрольные сценарии.
3. Кандидат улучшает объяснимость/доступность без утраты защиты после изменения нагрузки; не оценивается только по меньшему drift.
4. Отложенные поездки подтверждают результат; опубликованы ограничения, build и tests проходят.
5. Изменение production оформляется отдельно после завершения валидации и решения владельца. Этот отчёт не вносит production patch.
'''
(OUT/'FINDINGS_RU.md').write_text(findings,encoding='utf8');(OUT/'IMPROVEMENT_PLAN_RU.md').write_text(plan,encoding='utf8')
# Simple Markdown display: preserve readable source, tables are rendered independently below.
def prose(text):
    parts=[]
    for paragraph in text.split('\n\n'):
        if paragraph.startswith('# '):parts.append('<h1>'+html.escape(paragraph[2:])+'</h1>')
        elif paragraph.startswith('## '):parts.append('<h2>'+html.escape(paragraph[3:])+'</h2>')
        elif paragraph.startswith('|'):
            rows=[[v.strip() for v in line.strip().strip('|').split('|')] for line in paragraph.splitlines()]
            parts.append(table(rows[0],rows[2:]))
        else:parts.append('<p style="white-space:pre-wrap">'+html.escape(paragraph)+'</p>')
    return ''.join(parts)

def graph(minutes,key,color,max_y,label):
    W,H=1000,160;N=max(1,len(minutes));boxes=[];lines=[];path=[]
    for i,m in enumerate(minutes):
        fill='#bfe4d1' if m['steady'] else '#ffe0a4' if m['reason'].startswith('recovery') else '#f0e6e6'
        boxes.append(f'<rect x="{i/N*W:.2f}" y="20" width="{W/N+0.2:.2f}" height="130" fill="{fill}"/>')
        v=m.get(key)
        if v is None:
            if path:lines.append('<polyline points="'+' '.join(path)+'"/>');path=[]
            continue
        y=145-v/max_y*115 if key!='ride_drift' else 85-v/max_y*60
        path.append(f'{(i+.5)/N*W:.2f},{y:.2f}')
    if path:lines.append('<polyline points="'+' '.join(path)+'"/>')
    return '<svg viewBox="0 0 1000 160" role="img" aria-label="'+html.escape(label)+'"><text x="4" y="14">'+html.escape(label)+'</text>'+''.join(boxes)+'<g fill="none" stroke="'+color+'" stroke-width="2">'+''.join(lines)+'</g></svg>'
modelrows=[[m['model'],m['valid'],m['newly_valid'],m['lost_valid'],m['changed_rides'],m['included_minutes'],m['excluded_minutes'],m['coverage_delta']['median'],m['drift_delta_pp']['n'],m['drift_delta_pp']['median']] for m in s['models']]
sections=[prose(findings),'<h2>Все варианты: результат и изменение состава минут</h2>',table(['Модель','VALID','Новых VALID','Потеряно VALID','Поездок с изменением отбора','Добавлено минут','Исключено минут','Δ coverage median п.п.','Пар VALID','Δ drift median п.п.'],modelrows),'<h2>14 показательных поездок</h2><p>Зелёный фон — accepted, жёлтый — recovery, светлый красный — остальные исключения. Ось X — running minutes; паузы сжаты. Мощность и ЧСС показаны отдельно. CV относится к минутным средним, если не указано иначе. Причины выбора технические, это не автоматическая разметка Z2.</p>']
for case in r['cases']:
    c=lookup[case['id']];a=json.loads((ROOT/'.data/analysis'/(c['id']+'.json')).read_text('utf8'));m=a['models']['current']['minutes']
    rows=[]
    for name,model in a['models'].items():
        d=model['summary'];rows.append([name,d['ride']['state'],d['ride']['drift'],d['last60']['drift'],d['coverage'],d['ride']['power_change']])
    sections.append('<details><summary>'+html.escape(str(c['start'])[:10]+' · Garmin '+str(c['garmin_id'])+' · '+case['reason']+' · '+c['ride_state'])+'</summary>')
    sections.append('<p>'+html.escape(f"{c['minutes']} полных running minutes; качество {c['quality']}; minute-power CV {fmt(c['power_cv'])}; early/late coverage {fmt(c['early_coverage'])}/{fmt(c['late_coverage'])}%. Причины: {c['reasons']}")+'</p>')
    sections.append(graph(m,'power','#176e87',max(1,max((v['power'] or 0) for v in m)),'Мощность: минутное среднее по valid seconds, W'))
    sections.append(graph(m,'hr','#a4483d',210,'ЧСС: минутное среднее по valid seconds, bpm'))
    sections.append(graph(m,'ride_drift','#6943a0',30,'RIDE drift, %: только VALID; вертикальная шкала ±30%'))
    sections.append(table(['Модель','State','RIDE %','LAST60 %','Coverage %','Power Δ %'],rows))
    sections.append('<p><a href="https://connect.garmin.com/modern/activity/'+str(c['garmin_id'])+'">Открыть активность Garmin</a> · <a href="../report/index.html">Полный отчёт с поминутным выбором модели</a></p></details>')
sections+=['<h2>Сравнение записанных значений устройства</h2>',table(['Поездка','Записанное state','Oracle state','Δ VALID drift, п.п.','Recorded coverage','Oracle coverage','Δ compat, п.п.'],[[lookup[d['id']]['garmin_id'],d['recorded_state'],d['oracle_state'],d['drift_delta_pp'],d['recorded_coverage'],d['oracle_coverage'],d['compat_delta_pp']] for d in r['device_comparisons']]),'<h2>Наибольшие расхождения с Intervals</h2><p>Это не список ошибок Garmin. Сопоставление ID не устанавливает одинаковые потоки и настройки.</p>',table(['Garmin','Intervals','decoupling %','oracle compat %','Δ п.п.'],[[lookup[x['id']]['garmin_id'],x['intervals_id'],x['decoupling'],x['oracle_compat'],x['delta_compat_pp']] for x in sorted([v for v in r['intervals_matches'] if v['delta_compat_pp'] is not None],key=lambda v:-abs(v['delta_compat_pp']))[:15]]),prose(plan)]
css='body{font:16px/1.65 system-ui;background:#f4f4ef;color:#22332f;margin:0}main{max-width:1180px;margin:auto;padding:40px 28px}h1{font-size:34px;line-height:1.25;color:#164b40}h2{margin-top:44px;color:#164b40;font-size:25px}p{max-width:1000px}a{color:#126c80}.hero{background:#174e43;color:white;padding:24px;border-radius:12px}.hero strong{font-size:30px}.scroll{overflow:auto}table{border-collapse:collapse;font-size:14px;width:100%;background:white}td,th{padding:10px;border:1px solid #d4ddd7;text-align:left}th{background:#e1eee6}details{background:white;border:1px solid #d4ddd7;border-radius:8px;margin:16px 0;padding:18px}summary{cursor:pointer;font-weight:600}svg{display:block;width:100%;margin:10px 0}svg text{font:12px system-ui}.notice{background:#fff0c9;padding:18px;border-radius:8px}nav a{margin-right:18px}'
page='<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DriftGuard — исследовательский вывод</title><style>'+css+'</style><main><div class="hero"><strong>DriftGuard · Validation Review</strong><br>122 Garmin FIT · 20 вариантов · 112 сопоставлений Intervals · 30.10.2026</div><p class="notice">Рекомендация: сначала диагностическая наблюдаемость и проверка replay. Изменение production-порогов пока не обосновано. Физиологическая точность этим архивом не установлена.</p><nav><a href="FINDINGS_RU.md">Выводы Markdown</a><a href="IMPROVEMENT_PLAN_RU.md">План улучшений</a><a href="research.json">Исходные результаты JSON</a><a href="../report/index.html">Все поездки</a></nav>'+''.join(sections)+'</main></html>'
(OUT/'index.html').write_text(page,encoding='utf8')
print('Research report:',OUT/'index.html')
print('Case studies:',len(r['cases']),'HTML size KiB:',round(len(page.encode())/1024,1))
