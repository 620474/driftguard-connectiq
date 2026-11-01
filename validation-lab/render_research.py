"""Render the research conclusions and selected cases without a server."""
from pathlib import Path
from collections import Counter
import json,html,statistics,argparse

ROOT=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data',type=Path,default=ROOT/'.data')
args=parser.parse_args()
OUT=args.data/'research'
r=json.loads((OUT/'research.json').read_text('utf8'));s=r['summary'];cohort=r['cohort'];lookup={c['id']:c for c in cohort}
def fmt(v):return '—' if v is None else f'{v:.2f}' if isinstance(v,float) else str(v)
def table(headers,rows):
    return '<div class="scroll"><table><thead><tr>'+''.join('<th>'+html.escape(str(v))+'</th>' for v in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+html.escape(fmt(v))+'</td>' for v in row)+'</tr>' for row in rows)+'</tbody></table></div>'
insuff=Counter();origins=Counter()
for c in cohort:insuff.update(c['insufficient_minute_causes']);origins.update(c['recovery_origins'])
absolute=[abs(v['delta_compat_pp']) for v in r['intervals_matches'] if v['delta_compat_pp'] is not None]
accepted=sum(c['accepted_second_power_cv']['n'] for c in cohort);highcv=sum(c['accepted_cv_over_30'] for c in cohort)
reasons=Counter()
for c in cohort: reasons.update(c.get('reasons', {}))
period=s.get('period', ['не указан', 'не указан'])
findings=f'''# DriftGuard: результаты offline-пересчёта

Период входного исследования: {period[0]} — {period[1]}. FIT: {len(cohort)}.
Все числа ниже вычислены из текущего research.json. Offline-пересчёт не является показанием устройства.

## Покрытие

Качество входов: {dict(Counter(c['quality'] for c in cohort))}.
Итоговые состояния RIDE: {dict(Counter(c['ride_state'] for c in cohort))}.
Причины поминутного отбора: {dict(reasons)}.
Принятых минут с измеренным CV: {accepted}; из них CV >30%: {highcv}.

## Сравнения

Моделей в таблице: {len(s.get('models', []))}. Записанных сравнений dg_*: {len(r['device_comparisons'])}.
Сопоставлений Intervals: {len(r['intervals_matches'])}; с численным delta: {len(absolute)}.
Медиана абсолютной разницы compatibility: {fmt(statistics.median(absolute) if absolute else None)} п.п.

## Ограничения

Обычный FIT не доказывает равенство live callbacks и offline-секунд. Для атрибуции записанных полей
нужны application_id, версия схемы и контекст сборки. Старые поля без подтверждённого происхождения
не доказывают поведение текущего main. Отсутствие полей INTERVALS не означает отсутствие усилий.
Этот отчёт не измеряет точность детектора без независимой разметки. Он не подтверждает
аэробную форму, улучшение физической подготовки или прохождение тестов новой сборки.
'''
plan="""# Следующие проверки

1. Сверить версию анализа и схему FIT; replay одинаковых входов проверить на Monkey C и Python.
2. Разметить ускорения, длинные блоки, паузы и пропуски независимо от результата детектора.
3. На физическом Edge проверить запись нескольких повторений, reset, паузу и обе сборки.
4. Сравнивать drift и HRR только при сопоставимых нагрузках и условиях восстановления.
"""
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
sections=[prose(findings),'<h2>Все варианты: результат и изменение состава минут</h2>',table(['Модель','VALID','Новых VALID','Потеряно VALID','Поездок с изменением отбора','Добавлено минут','Исключено минут','Δ coverage median п.п.','Пар VALID','Δ drift median п.п.'],modelrows),f'<h2>Показательные поездки: {len(r["cases"])}</h2><p>Зелёный фон — accepted, жёлтый — recovery, светлый красный — остальные исключения. Ось X — running minutes; паузы сжаты. Мощность и ЧСС показаны отдельно. CV относится к минутным средним, если не указано иначе. Причины выбора технические, это не автоматическая разметка Z2.</p>']
for case in r['cases']:
    c=lookup[case['id']];a=json.loads((args.data/'analysis'/(c['id']+'.json')).read_text('utf8'));m=a['models']['current']['minutes']
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
page='<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>DriftGuard — исследовательский вывод</title><style>'+css+'</style><main><div class="hero"><strong>DriftGuard · Validation Review</strong><br>'+html.escape(f'{len(cohort)} FIT · период {period[0]} — {period[1]}')+'</div><p class="notice">Результаты относятся к версии анализа входного research.json. Проверяйте provenance перед сравнением со сборкой устройства. Физиологическая точность этим архивом не установлена.</p><nav><a href="FINDINGS_RU.md">Выводы Markdown</a><a href="IMPROVEMENT_PLAN_RU.md">План улучшений</a><a href="research.json">Исходные результаты JSON</a><a href="../report/index.html">Все поездки</a></nav>'+''.join(sections)+'</main></html>'
(OUT/'index.html').write_text(page,encoding='utf8')
print('Research report:',OUT/'index.html')
print('Case studies:',len(r['cases']),'HTML size KiB:',round(len(page.encode())/1024,1))
