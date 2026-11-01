"""Render a local comparison and an explicitly anonymised public snapshot."""
import argparse
import ast
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
from statistics import median


def table(headers, rows):
    def fmt(v):
        if v is None or v == '':
            return '—'
        if isinstance(v, (list, tuple)):
            return '[' + ', '.join(fmt(x) for x in v) + ']'
        if isinstance(v, float):
            return f'{v:.3f}'
        return str(v).replace('|', '/').replace('\n', ' ')
    return '| ' + ' | '.join(headers) + ' |\n| ' + ' | '.join('---' for _ in headers) + \
        ' |\n' + ''.join('| ' + ' | '.join(fmt(v)
                         for v in row) + ' |\n' for row in rows)


def render(root, public_output=None):
    summary = json.loads((root / 'summary.json').read_text(encoding='utf8'))
    details = []
    for path in sorted(root.glob('*.json')):
        if len(path.stem) != 64:
            continue
        item = json.loads(path.read_text(encoding='utf8'))
        if 'models' in item and 'summary' in item:
            details.append(item)
    if len(details) != summary['files']:
        raise ValueError('incomplete model result set')
    with (root / 'synthetic.csv').open(encoding='utf-8-sig', newline='') as f:
        synthetic = [r for r in csv.DictReader(f) if r['tau_s'] == '40']
    selected = []
    sensitivity = []
    hrr = []
    slopes = []
    common = []
    paired_support = []
    by_split = {}
    for item in details:
        s = item['summary']
        m = item['models']
        f = s['ftp_history_w']
        if f is not None:
            candidate = m['candidates'][str(f)]
            selected.append(len(candidate['events']))
            for channel in ('hrr_current_boundaries',
                            'hrr_candidate_boundaries'):
                rows = candidate[channel]
                pairs = [r['peak_hrr60'] - r['end_hrr60']
                         for r in rows if r['peak_hrr60'] is not None and r['end_hrr60'] is not None]
                hrr.append(dict(channel=channel, end=sum(r['end_hrr60'] is not None for r in rows),
                                peak=sum(r['peak_hrr60'] is not None for r in rows), paired_deltas=pairs))

            scenario_counts = {
                f'scenario_{value}': len(
                    v['events']) for value,
                v in m['candidates'].items()}
            sensitivity.append(dict(activity=s['activity'], date=s['date'], history_ftp=f,
                                    history_count=len(candidate['events']), **scenario_counts))
        if s['bpm_h'] is not None:
            slopes.append(s['bpm_h'])
        if s['common_support_bpm_h'] is not None:
            common.append(s['common_support_bpm_h'])
            if s['bpm_h'] is not None:
                paired_support.append((s['bpm_h'], s['common_support_bpm_h']))
        by_split.setdefault(s['split'], []).append(s)
    if sensitivity:
        with (root / 'ftp-sensitivity.csv').open('w', encoding='utf-8-sig', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=list(sensitivity[0]))
            writer.writeheader()
            writer.writerows(sensitivity)
    hrr_counts = {}
    for channel in ('hrr_current_boundaries', 'hrr_candidate_boundaries'):
        values = [v for v in hrr if v['channel'] == channel]
        deltas = [d for v in values for d in v['paired_deltas']]
        hrr_counts[channel] = dict(end=sum(v['end'] for v in values), peak=sum(v['peak'] for v in values),
                                   paired=len(deltas), median_peak_minus_end=median(deltas) if deltas else None)
    aggregates = dict(files=summary['files'], labelled_activities=summary['labelled_activities'],
                      regression_states=summary['regression_tau40_states'], fixed_states=summary['fixed_states'],
                      current_auto=summary['current_auto'], relative_history_auto=sum(
                          selected) if selected else None,
                      hrr_history=hrr_counts, regression_median=median(
                          slopes) if slopes else None,
                      common_support_estimates=len(common),
                      support_paired_count=len(paired_support),
                      support_paired_delta=median(b - a for a, b in paired_support) if paired_support else None, common_support_median=median(common) if common else None,
                      splits={k: dict(n=len(v), regression_estimates=sum(r['bpm_h'] is not None for r in v),
                                      ride_valid=sum(r['ride_state'] == 'VALID' for r in v)) for k, v in by_split.items()})
    (root / 'comparison-summary.json').write_text(json.dumps(aggregates,
                                                             ensure_ascii=False, indent=2), encoding='utf8')
    synthetic_table = table(['Сценарий', 'Задано, bpm/h', 'RIDE %', 'Регрессия bpm/h', '95% HAC interval'],
                            [[r['case'], r['truth_bpm_h'], float(r['ride_percent']) if r['ride_percent'] else None,
                              float(r['bpm_h']) if r['bpm_h'] else None, ast.literal_eval(r['ci95']) if r['ci95'] else None] for r in synthetic])
    auto_table = table(['Сценарий', 'Текущий TP/FP/FN', 'Relative TP/FP/FN'],
                       [[r['case'], '/'.join(str(ast.literal_eval(r['current_detection'])[k]) for k in ('tp', 'fp', 'fn')),
                         '/'.join(str(ast.literal_eval(r['relative_detection'])[k]) for k in ('tp', 'fp', 'fn'))]
                        for r in synthetic if r['case'] in ('steady', 'repeats', 'climb', 'sprints', 'hills')])
    split_table = table(['Группа', 'Поездок', 'Число регрессионных оценок', 'VALID RIDE'],
                        [[k, v['n'], v['regression_estimates'], v['ride_valid']] for k, v in aggregates['splits'].items()])
    hrr_table = table(['Границы', 'HRR от конца', 'Peak candidate', 'Оба доступны', 'Median peak − end'],
                      [[k, v['end'], v['peak'], v['paired'], v['median_peak_minus_end']] for k, v in hrr_counts.items()])
    tau_summary = {}
    for tau in ('0', '40', '60'):
        values = [v['models']['regression'][tau]['bpm_per_hour'] for v in details
                  if v['models']['regression'][tau]['bpm_per_hour'] is not None]
        tau_summary[tau] = dict(n=len(values), median=median(values) if values else None,
                                minimum=min(values) if values else None, maximum=max(values) if values else None)
    tau_table = table(['Tau, s', 'Оценок', 'Median bpm/h', 'Min', 'Max'],
                      [[k, v['n'], v['median'], v['minimum'], v['maximum']] for k, v in tau_summary.items()])
    aggregates['tau_sensitivity'] = tau_summary
    (root / 'comparison-summary.json').write_text(json.dumps(aggregates,
                                                             ensure_ascii=False, indent=2), encoding='utf8')
    body = f"""## Численные сравнения и решение

### Синтетический DRIFT

{synthetic_table}

Сценарии linear используют совместимую с регрессией модель; близость к заданному коэффициенту
проверяет арифметику и свойства модели. Это не независимая физиологическая валидация.
Temperature добавляет HR-сдвиг без тренировочного дрейфа: регрессия приписывает его времени.
Таким образом, даже узкий interval не исключает систематическую ошибку из-за пропущенного фактора.
В pause-сценарии генератор задаёт дрейф по wall time, а модель — по running time; различие
отдельно показывает зависимость вывода от выбора часов. Фиксированный EF baseline тоже
не нормализует длительность автоматически: его процент растёт по мере удаления текущего окна.

### Синтетический AUTO, цель planned_effort

{auto_table}

В hills расписание намеренно не содержит плановых интервалов. Поэтому бугры считаются FP
именно относительно planned_effort. Для задачи «любое изменение нагрузки» разметка была бы другой.
Оба детектора имеют minimum 20 s и пропускают 15-s sprint protocol — это явное ограничение.

### Архив

{split_table}

Регрессия tau=40 s выдаёт {len(slopes)} оценок, медиана {median(slopes) if slopes else None} bpm/h.
На common support доступно {len(common)} оценок. Медианная парная разница
common − full на {len(paired_support)} одних и тех же поездках: {aggregates['support_paired_delta']} bpm/h. Отбор минут и разрешающие условия моделей
разные: частоту выхода числа нельзя считать показателем точности. Fixed-reference состояния:
{summary['fixed_states']}. По предоставленной FTP history relative даёт {aggregates['relative_history_auto']}
завершений против {summary['current_auto']} текущих; больше завершений не означает больше истинных интервалов.
Размеченных реальных поездок: {summary['labelled_activities']}; precision/recall остаются неизвестными,
если полная независимая разметка не предоставлена.

### Чувствительность к лагу

{tau_table}

Это три фиксированные модели, а не оценка индивидуального лага. По доступности или минимуму
остатков на всём архиве победитель не выбирался. Различия коэффициентов могут отражать
и модель, и состав поддержанных минут; интерпретировать их как изменение формы нельзя.

### HRR на FTP history, без суммирования чувствительности

{hrr_table}

Peak candidate имеет другое определение, более строгий отбор длительности и мощности восстановления.
Нельзя трактовать уменьшение доступности как улучшение достоверности. Выбор максимума HR в окне
может повышать HRR из-за шума и регрессии к среднему. Для сравнения формы между неделями
нужен стандартизированный протокол и воспроизводимость, которых этот архив не устанавливает.

### Решение

Ни один кандидат не переносится в production по этому исследованию. Регрессию стоит проверять
на контролируемых нагрузках с независимыми возмущениями мощности, температуры и времени;
relative AUTO требует независимой разметки planned_effort; условия peak HRR требуют отдельного
протокола. Изменять пороги после просмотра этих результатов означало бы начать новую версию
эксперимента, которую нельзя выдавать за независимую проверку прежнего кандидата.
"""
    path = root / 'REPORT_RU.md'
    old = path.read_text(encoding='utf8')
    marker = '## Численные сравнения и решение'
    local_context = ''
    context_path = root / 'input-context.json'
    if context_path.exists():
        context = json.loads(context_path.read_text(encoding='utf8'))
        local_context = '\n## Локальный контекст входов\n\n' + \
            context['notes'] + '\n'
    path.write_text(
        old.split(marker)[0] +
        body +
        local_context,
        encoding='utf8')
    if public_output:
        # Deliberately omit activity IDs, file hashes, dates, FTP history and
        # traces.
        public_output.write_text(f"""# Сравнение моделей: воспроизводимый снимок исследования

Базовый commit: `{summary['source_commit']}`.
Fingerprint модельного кода: `{summary['source_fingerprint']}`.
Production Monkey C, detector parameters and FIT schema were not changed in this study.
15 synthetic protocols / three lag settings; {summary['files']} private FIT grids,
SHA/size checks and a separate full CRC audit. Cached read_fit/normalize source is identical
to the audited decoder. The archive has previously been inspected; this is retrospective.
No independent real-ride truth labels were supplied. Raw rides, IDs, FTP history and traces
are local-only. The code and anonymised aggregate snapshot are public.

""" + body, encoding='utf8')
    return aggregates


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--public-output', type=Path)
    args = parser.parse_args()
    print(
        json.dumps(
            render(
                args.input,
                args.public_output),
            ensure_ascii=False,
            indent=2))


if __name__ == '__main__':
    main()
