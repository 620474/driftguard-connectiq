"""Reproducible offline comparison; original FIT values are never model truth.

python -m driftlab.model_study --archive DIR --manifest manifest.json --output NEW_DIR
--ftp-history JSON supplies dated settings; without it run explicit FTP sensitivities.
No model/threshold is selected by maximising availability on this archive.
"""
import argparse
import ast
from collections import Counter
import csv
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

from . import fitio
from .auto_exp import ExperimentalDetector
from .oracle import Engine
from .model_candidates import RelativeDetector, minute_features, regression, fixed_reference, recoveries, detection_scores
from .model_protocols import protocol, suite


PLAN = dict(version='model-study-1', tau_seconds=[0, 40, 60], hac_minute_lags=3,
            reference_minutes=[16, 35], comparison_last_minutes=10,
            relative_auto=dict(entry_ftp=.60, entry_ratio=1.20, entry_delta_ftp=.10,
                               exit_ratio=1.08, exit_delta_ftp=.05, entry_floor=.70, confirm=[3, 5], minimum_s=20),
            peak_hrr=dict(
    minimum_effort_s=180,
    search_after_end_s=15,
    recovery_ftp_limit=.40),
    match_iou=.5, retrospective_late_fraction=.20, seed=20261101,
    intended_target='planned_effort', selection='none; report all frozen candidates',
    warning='Retrospective archive was previously inspected; late split is not pristine external validation.')


def save(path, value):
    path.write_text(
        json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            allow_nan=False),
        encoding='utf8')


def csvfile(path, rows):
    if not rows:
        return
    with path.open('w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(
            f, fieldnames=list(
                dict.fromkeys(
                    k for row in rows for k in row)))
        w.writeheader()
        w.writerows(rows)


def normalizer_hash():
    source = Path(fitio.__file__).read_text(encoding='utf8')
    functions = {
        n.name: ast.get_source_segment(
            source,
            n) for n in ast.parse(source).body if isinstance(
            n,
            ast.FunctionDef)}
    return hashlib.sha256(
        (functions['read_fit'] + functions['normalize']).encode()).hexdigest()


def load_samples(path, digest, cache):
    if cache:
        key = cache / (digest + '.json.gz')
        if key.exists():
            with gzip.open(key, 'rt', encoding='utf8') as f:
                stored = json.load(f)
            if stored.get('source_sha256') == digest and stored.get(
                    'normalizer_sha256') == normalizer_hash():
                return stored['samples'], stored['quality'], stored.get(
                    'origin', 'versioned_cache')
    samples, quality, _ = fitio.read_fit(path)
    if cache:
        cache.mkdir(parents=True, exist_ok=True)
        with gzip.open(cache / (digest + '.json.gz'), 'wt', encoding='utf8') as f:
            json.dump(dict(source_sha256=digest, normalizer_sha256=normalizer_hash(), samples=samples,
                           quality=quality, origin='fresh_fitdecode_crc_checked'), f)
    return samples, quality, 'fresh_fitdecode_crc_checked'


def ftp_for(date, history):
    applicable = [row for row in history if row['since'] <= date[:10]]
    return applicable[-1]['ftp'] if applicable else None


def analyse(samples, ftp_values):
    engine = Engine()
    auto = ExperimentalDetector()
    for s in samples:
        engine.add(s['power'], s['hr'], s['running'])
        auto.sample(s['power'], s['running'])
    support = {m['minute'] for m in engine.minutes if m['steady']}
    rows = minute_features(samples, 40)
    drifts = {
        str(tau): regression(
            rows if tau == 40 else minute_features(
                samples,
                tau)) for tau in PLAN['tau_seconds']}
    common = regression(rows, support)
    candidates = {}
    for ftp in ftp_values:
        detector = RelativeDetector(ftp)
        for s in samples:
            detector.sample(s['power'], s['running'])
        candidates[str(ftp)] = dict(events=detector.events, active_tail=detector.active is not None,
                                    hrr_current_boundaries=recoveries(
                                        samples, auto.events, ftp),
                                    hrr_candidate_boundaries=recoveries(samples, detector.events, ftp))
    return dict(ride=engine.result['ride'], last60=engine.result['last60'], steady_minutes=engine.steady,
                fixed_reference=fixed_reference(rows), regression=drifts, common_support_regression=common,
                current_auto=auto.events, current_active_tail=auto.active, candidates=candidates)


def synthetic():
    rows = []
    details = {}
    for name, config, truth_slope in suite():
        samples, truth = protocol(**config)
        a = analyse(samples, [250])
        details[name] = a
        for tau, reg in a['regression'].items():
            rows.append(dict(case=name, tau_s=int(tau), truth_bpm_h=truth_slope, ride_state=a['ride']['state'],
                             ride_percent=a['ride']['drift'], fixed_state=a['fixed_reference']['status'],
                             fixed_percent=a['fixed_reference']['drift_percent'], regression_state=reg['status'],
                             bpm_h=reg['bpm_per_hour'], ci95=reg['ci95'],
                             current_detection=detection_scores(
                                 a['current_auto'], truth),
                             relative_detection=detection_scores(a['candidates']['250']['events'], truth)))
    return rows, details


def read_labels(path):
    if path is None:
        return {}
    result = {}
    with path.open(encoding='utf-8-sig', newline='') as f:
        for row in csv.DictReader(f):
            if row['source'] != 'manual_blind':
                raise ValueError('label source must be manual_blind')
            if row['label'] not in ('reviewed', 'effort'):
                raise ValueError('unknown label')
            start, end = int(row['start']), int(row['end'])
            if start < 0 or end < start:
                raise ValueError('invalid label bounds')
            result.setdefault(
                row['sha256'],
                []).append(
                dict(
                    start=start,
                    end=end,
                    label=row['label']))
    return result


def labelled_scores(events, rows, length):
    coverage = [r for r in rows if r['label'] == 'reviewed']
    if coverage != [dict(start=0, end=length - 1, label='reviewed')]:
        raise ValueError(
            'one full-ride reviewed declaration is required before scoring negatives')
    truth = [r for r in rows if r['label'] == 'effort']
    if any(r['end'] >= length for r in truth):
        raise ValueError('label outside activity')
    for a, b in zip(sorted(truth, key=lambda r: r['start']), sorted(
            truth, key=lambda r: r['start'])[1:]):
        if b['start'] <= a['end']:
            raise ValueError('overlapping reference efforts')
    return detection_scores(events, truth)


def review_page(path, rides):
    # All traces are sampled on a fixed clock, independent of model outputs.
    payload = json.dumps(
        rides,
        ensure_ascii=False,
        separators=(
            ',',
            ':')).replace(
        '<',
        r'\u003c')
    page = r"""<!doctype html><html lang="ru"><meta charset="utf-8"><title>Слепая разметка</title>
<style>body{font:16px system-ui;max-width:1150px;margin:30px auto;padding:15px}canvas{width:100%;border:1px solid #ccc}input,button,select{font:inherit;padding:7px}pre{white-space:pre-wrap}</style>
<h1>Независимая разметка planned efforts</h1><p>Здесь только мощность и ЧСС, без предсказаний детекторов.
Сначала определите намеренные рабочие интервалы по плану/записям тренера и потоку. Подъём сам по себе не означает плановый интервал.
При отсутствии уверенности не отмечайте поездку полностью просмотренной. График сглажен фиксированными 10-с блоками только для обзора;
границы проверяйте по исходному FIT. Время — wall seconds от первого RECORD, с паузами.</p>
<select id="ride"></select><canvas id="chart" width="1100" height="320"></canvas><p id="meta"></p>
<input id="start" type="number" min="0" placeholder="начало, s"><input id="end" type="number" min="0" placeholder="конец, s">
<button id="add">Добавить усилие</button><button id="reviewed">Вся поездка просмотрена</button>
<button id="undo">Удалить последнюю метку</button><button id="download">Экспорт CSV</button><pre id="labels"></pre>
<script>const rides=__DATA__,labels=[];const select=document.querySelector('#ride'),canvas=document.querySelector('#chart'),ctx=canvas.getContext('2d');
rides.forEach((r,i)=>select.add(new Option(r.id+' · '+r.date,i)));
function draw(){if(!rides.length)return;const r=rides[select.value];ctx.clearRect(0,0,1100,320);ctx.font='14px sans-serif';
ctx.fillText('Мощность W (синий), ЧСС bpm (красный); шкалы раздельные',10,18);
for(const [k,color,max] of [['power','#167ba1',Math.max(400,...r.trace.map(x=>x.power||0))],['hr','#b53b38',220]]){
ctx.strokeStyle=color;ctx.beginPath();let open=false;for(const p of r.trace){if(p[k]===null){open=false;continue;}const x=40+p.t/r.length*1040,y=280-p[k]/max*240;if(open)ctx.lineTo(x,y);else ctx.moveTo(x,y);open=true;}ctx.stroke();}
for(let i=0;i<=5;i++)ctx.fillText(Math.round(i*r.length/5)+' s',40+i*1040/5,310);
document.querySelector('#meta').textContent=r.id+' · SHA '+r.sha256+' · '+r.length+' s; '+r.split;
document.querySelector('#labels').textContent=JSON.stringify(labels.filter(x=>x.sha256===r.sha256),null,2);}
function add(label){const r=rides[select.value],a=label==='reviewed'?0:Number(document.querySelector('#start').value),b=label==='reviewed'?r.length-1:Number(document.querySelector('#end').value);
if(!Number.isInteger(a)||!Number.isInteger(b)||a<0||b<a||b>=r.length){alert('Проверьте границы');return;}
if(label==='reviewed'&&labels.some(x=>x.sha256===r.sha256&&x.label==='reviewed'))return;
labels.push({sha256:r.sha256,start:a,end:b,label,source:'manual_blind'});draw();}
document.querySelector('#add').onclick=()=>add('effort');document.querySelector('#reviewed').onclick=()=>add('reviewed');
document.querySelector('#undo').onclick=()=>{labels.pop();draw();};select.onchange=draw;
document.querySelector('#download').onclick=()=>{const text='sha256,start,end,label,source\n'+labels.map(x=>[x.sha256,x.start,x.end,x.label,x.source].join(',')).join('\n');
const a=document.createElement('a'),url=URL.createObjectURL(new Blob([text],{type:'text/csv;charset=utf-8'}));a.href=url;a.download='manual-labels.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};draw();</script></html>"""
    path.write_text(page.replace('__DATA__', payload), encoding='utf8')


def run(args):
    manifest = json.loads(args.manifest.read_text(encoding='utf8'))
    entries = sorted(
        manifest['files'],
        key=lambda v: (
            v['start_local'],
            v['sha256']))
    if args.output.exists():
        raise ValueError('output must be a new directory')
    args.output.mkdir(parents=True)
    history = json.loads(args.ftp_history.read_text()
                         ) if args.ftp_history else []
    if history != sorted(
        history,
        key=lambda r: r['since']): raise ValueError('FTP history must be chronological')
    from datetime import date
    if len({r['since'] for r in history}) != len(history):
        raise ValueError('duplicate FTP effective date')
    for r in history:
        date.fromisoformat(r['since'])
        if not 50 <= r['ftp'] <= 600:
            raise ValueError('invalid FTP')
    if any(not 50 <= f <= 600 for f in args.ftp_scenarios):
        raise ValueError('invalid FTP scenario')
    labels = read_labels(args.labels)
    revision = subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=Path(__file__).parents[2], text=True).strip()
    fingerprint = hashlib.sha256(b''.join(Path(__file__).with_name(name).read_bytes() for name in
                                          ['model_candidates.py', 'model_protocols.py', 'model_study.py', 'oracle.py', 'auto_exp.py'])).hexdigest()
    save(args.output / 'plan.json', dict(PLAN, source_commit=revision, source_fingerprint=fingerprint,
         normalizer_sha256=normalizer_hash(), ftp_history=history,
        manifest_sha256=hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
        labels_sha256=hashlib.sha256(args.labels.read_bytes()).hexdigest() if args.labels else None,
        ftp_history_sha256=hashlib.sha256(args.ftp_history.read_bytes()).hexdigest() if args.ftp_history else None, ftp_scenarios=args.ftp_scenarios,
         source_tree_dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=Path(__file__).parents[2]))))
    for entry in entries:
        p = args.archive / entry['file']
        if p.stat().st_size != entry['bytes'] or hashlib.sha256(
                p.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('manifest mismatch: ' + entry['file'])
    syn, details = synthetic()
    save(args.output / 'synthetic.json', details)
    csvfile(args.output / 'synthetic.csv', syn)
    rows = []
    events = []
    hrr = []
    reviews = []
    score_rows = []
    cut = int(len(entries) * .8)
    origins = Counter()
    regstates = Counter()
    fixedstates = Counter()
    for i, entry in enumerate(entries):
        digest = entry['sha256']
        samples, quality, origin = load_samples(
            args.archive / entry['file'], digest, args.cache)
        origins[origin] += 1
        ftp = ftp_for(entry['start_local'], history)
        ftps = sorted(set(([ftp] if ftp is not None else []) +
                      args.ftp_scenarios + [r['ftp'] for r in history]))
        a = analyse(samples, ftps)
        regstates[a['regression']['40']['status']] += 1
        fixedstates[a['fixed_reference']['status']] += 1
        split = 'retrospective_early' if i < cut else 'retrospective_late'
        row = dict(sha256=digest, activity=entry.get('activity_id'), date=entry['start_local'], split=split, quality=quality['status'],
                   ftp_history_w=ftp, ride_state=a['ride']['state'], ride_percent=a[
                       'ride']['drift'], last60_percent=a['last60']['drift'],
                   fixed_state=a['fixed_reference']['status'], fixed_percent=a['fixed_reference']['drift_percent'],
                   regression_state=a['regression']['40']['status'], bpm_h=a['regression']['40']['bpm_per_hour'],
                   ci95=a['regression']['40']['ci95'], common_support_bpm_h=a['common_support_regression']['bpm_per_hour'],
                   current_auto_count=len(a['current_auto']), real_precision=None, real_recall=None)
        rows.append(row)
        for ev in a['current_auto']:
            events.append(dict(sha256=digest, model='current', ftp=None, **ev))
        for f, candidate in a['candidates'].items():
            for ev in candidate['events']:
                events.append(
                    dict(
                        sha256=digest,
                        model='relative',
                        ftp=int(f),
                        **ev))
            for channel in ('hrr_current_boundaries',
                            'hrr_candidate_boundaries'):
                hrr.extend(
                    dict(
                        sha256=digest,
                        ftp=int(f),
                        boundaries=channel,
                        **v) for v in candidate[channel])
        if digest in labels:
            score_rows.append(dict(sha256=digest,
                                   model='current',
                                   **labelled_scores(a['current_auto'],
                                                     labels[digest],
                                                     len(samples))))
            for f, candidate in a['candidates'].items():
                score_rows.append(dict(sha256=digest, model='relative', ftp=int(
                    f), **labelled_scores(candidate['events'], labels[digest], len(samples))))
        trace = []
        if i >= cut:
            for t in range(0, len(samples), 10):
                block = samples[t:t + 10]

                def avg(key):
                    v = [s[key] for s in block if s['running']
                         and s.get(key) is not None]
                    return sum(v) / len(v) if v else None
                trace.append(dict(t=t, power=avg('power'), hr=avg('hr')))
            reviews.append(
                dict(
                    id=entry.get('activity_id'),
                    sha256=digest,
                    date=entry['start_local'],
                    length=len(samples),
                    split=split,
                    trace=trace))
        # Full results stay local; no GPS/coordinates or FIT bytes are emitted.
        save(args.output / (digest + '.json'), dict(summary=row,
             models=a, input_quality=quality, cache_origin=origin))
        if (i + 1) % 10 == 0:
            print(f'{i + 1}/{len(entries)}', flush=True)
    for name, data in [('rides', rows), ('events', events),
                       ('hrr', hrr), ('label_scores', score_rows)]:
        csvfile(args.output / (name + '.csv'), data)
    unknown = set(labels) - {e['sha256'] for e in entries}
    if unknown:
        raise ValueError('labels reference unknown source SHA')
    review_page(args.output / 'blind-review.html', reviews)
    summary = dict(source_commit=revision, source_fingerprint=fingerprint, files=len(entries), hashes_verified=len(entries),
                   split_counts=dict(Counter(r['split'] for r in rows)), cache_origins=dict(origins),
                   regression_tau40_states=dict(regstates), fixed_states=dict(fixedstates),
                   ride_states=dict(Counter(r['ride_state'] for r in rows)), labelled_activities=len(labels),
                   real_accuracy='unknown' if not labels else 'manual labels only; target=planned_effort',
                   current_auto=sum(r['current_auto_count'] for r in rows),
                   relative_counts={
        str(f): sum(
            e['model'] == 'relative' and e['ftp'] == f for e in events) for f in sorted(
            {
                e['ftp'] for e in events if e['model'] == 'relative'})},
        hrr_statuses=dict(Counter(v['status'] for v in hrr)),
        hrr_current_available=sum(
        v['end_hrr60'] is not None for v in hrr),
        hrr_peak_available=sum(v['peak_hrr60'] is not None for v in hrr))
    save(args.output / 'summary.json', summary)
    text = f"""# DriftGuard: сравнительное исследование моделей

Базовый commit (новые модели определяются fingerprint): `{revision}`; fingerprint исходников: `{fingerprint}`.
Оригинальных FIT: {len(entries)}; все размеры и SHA-256 сверены.
Сетка входа: {dict(origins)}. Offline-модели не являются записанными показаниями приложения.
Результаты всех кандидатов опубликованы, победитель автоматически не выбран.

## DRIFT

Итоговые состояния RIDE: {dict(Counter(r['ride_state'] for r in rows))}.
Состояния регрессии tau=40 s: {dict(regstates)}; фиксированного эталона: {dict(fixedstates)}.
Регрессия HR ~ lagged power + running time оценивает уд/мин в час. HAC(3) interval —
приближённая неопределённость коэффициента при заданной модели, а не доверительный интервал
аэробной формы. При почти постоянной мощности применяется только time slope; при сильной
коллинеарности мощности и времени результат отклоняется. В nonlinear/temperature синтетике
линейная модель может ошибаться. Средняя мощность, running time и поддержка минут различаются
между моделями; common_support_bpm_h отдельно ограничен steady-минутами текущего алгоритма.
Tau 0/40/60 s — заранее заданная чувствительность, не индивидуально измеренный лаг HR.

## AUTO и HRR

Текущий AUTO: {summary['current_auto']} завершений. Relative counts по FTP-сценариям:
{summary['relative_counts']}. Частоты — не precision/recall; цель planned_effort отличается
от любого изменения мощности на холме. Численные precision/recall доступны на синтетических
расписаниях и только на полностью просмотренных ручных разметках.
HRR от конца и peak HRR рассчитаны парно на одинаковых границах; результаты current и
candidate boundaries находятся отдельно в hrr.csv. Суммарные counts HRR включают несколько
FTP-сценариев и наборов границ: это не число независимых физиологических измерений.
Длительность 180 s, поиск пика +15 s и recovery <=40% FTP — инженерные гипотезы.
Не использовать для оценки адаптации/перетренированности или замены тренерского протокола.

## Разметка и ограничения

Независимо размеченных активностей: {len(labels)}. Реальная точность: {summary['real_accuracy']}.
Поздние поездки ({len(entries) - cut}) оставлены отдельной ретроспективной группой;
этот архив ранее просматривался, поэтому она не является чистой внешней валидацией.
blind-review.html показывает только входы, без детекторов; экспорт CSV можно передать
через --labels. Требуется декларация полного просмотра, иначе отрицательные интервалы
не считаются размеченными. Метки, полученные тем же детектором, не являются истиной.
Синтетика содержит линейные и конфликтующие модели; успех в линейных случаях не доказывает
точность на людях. История FTP дана пользователем; неопределённые даты должны читаться
по plan.json. Дополнительные FTP-сценарии чувствительности перечислены в plan.json.

## Источники и воспроизведение

Фиксированный эталон и decoupling обсуждаются в [Smyth et al.](https://pmc.ncbi.nlm.nih.gov/articles/PMC9388405/)
на беговой выборке; это не велосипедная валидация наших окон.
Зависимость HR-метрик от протокола и контекста: [Buchheit](https://pmc.ncbi.nlm.nih.gov/articles/PMC3936188/).
HAC covariance: [Newey & West](https://doi.org/10.2307/1913610).
Эти работы мотивируют эксперименты, но не подтверждают их параметры.
Команда: python -m driftlab.model_study --archive DIR --manifest manifest.json --output NEW_DIR
--cache CACHE_DIR --ftp-history history.json [--labels manual-labels.csv].
Все параметры, commit и fingerprint сохранены в plan.json. Исходные FIT не изменялись.
"""
    (args.output / 'REPORT_RU.md').write_text(text, encoding='utf8')
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cache', type=Path)
    parser.add_argument('--ftp-history', type=Path)
    parser.add_argument('--labels', type=Path)
    parser.add_argument(
        '--ftp-scenarios',
        type=int,
        nargs='+',
        default=[
            180,
            240,
            270,
            360])
    run(parser.parse_args())


if __name__ == '__main__':
    main()
