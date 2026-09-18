#!/usr/bin/env python3
# Назначение: свод по docs/ai/timing.csv — куда уходит время ответов (для скилла kit-timing).
# Запуск из корня проекта: python .claude/skills/kit-timing/report.py [сколько последних ходов]
# Побочные эффекты: ничего не пишет, только читает и печатает.
import os
import sys

HEAD = 'начало;всего_с;инструменты_с;модель_с;вызовов;инструменты;куда смотрел;вопрос'


def load(path):
    rows = []
    with open(path, encoding='utf-8-sig', errors='replace') as fh:
        for line in fh:
            line = line.rstrip('\n').rstrip('\r')
            if not line.strip() or line.startswith('начало;'):
                continue
            p = line.split(';')
            if len(p) < 8:
                continue
            try:
                rows.append({'when': p[0], 'total': float(p[1]), 'tools': float(p[2]),
                             'model': float(p[3]), 'calls': int(p[4]), 'names': p[5],
                             'look': p[6], 'ask': p[7]})
            except ValueError:
                continue
    return rows


def pct(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    i = min(len(s) - 1, max(0, int(round((len(s) - 1) * q))))
    return s[i]


def main():
    root = os.environ.get('CLAUDE_PROJECT_DIR') or os.getcwd()
    path = os.path.join(root, 'docs', 'ai', 'timing.csv')
    if not os.path.isfile(path):
        print('Файла нет: ' + path + ' — хронометраж ещё не набрался (пишется при завершении каждого ответа).')
        return
    limit = 0
    if len(sys.argv) > 1:
        try:
            limit = int(sys.argv[1])
        except ValueError:
            limit = 0
    rows = load(path)
    if limit > 0:
        rows = rows[-limit:]
    if not rows:
        print('Строк нет: ' + path)
        return
    tot = [r['total'] for r in rows]
    print('Файл: ' + path)
    print('Ходов: %d, с %s по %s' % (len(rows), rows[0]['when'], rows[-1]['when']))
    print('Всего времени: %.0f мин. Средний ход: %.0f с, середина %.0f с, девять из десяти до %.0f с, худший %.0f с.'
          % (sum(tot) / 60.0, sum(tot) / len(tot), pct(tot, 0.5), pct(tot, 0.9), max(tot)))
    ts = sum(r['tools'] for r in rows)
    ms = sum(r['model'] for r in rows)
    share = 100 * ts / (ts + ms) if (ts + ms) > 0 else 0
    print('Из них инструменты: %.0f мин (%.0f%%), модель: %.0f мин (%.0f%%).' % (ts / 60.0, share, ms / 60.0, 100 - share))
    print('Вызовов инструментов: всего %d, на ход в среднем %.1f, максимум %d.'
          % (sum(r['calls'] for r in rows), sum(r['calls'] for r in rows) / float(len(rows)),
             max(r['calls'] for r in rows)))

    names = {}
    for r in rows:
        for part in r['names'].split():
            if '*' in part:
                n, c = part.rsplit('*', 1)
                try:
                    names[n] = names.get(n, 0) + int(c)
                except ValueError:
                    pass
    if names:
        print('\nЧем пользовались (вызовов):')
        for n, c in sorted(names.items(), key=lambda kv: (-kv[1], kv[0]))[:12]:
            print('  %-22s %d' % (n, c))

    look = {}
    for r in rows:
        for t in set(r['look'].split()):
            look[t] = look.get(t, 0) + 1
    repeats = [(t, c) for t, c in look.items() if c >= 3]
    if repeats:
        print('\nОдно и то же в разных ходах (кандидаты в docs/ai или в память):')
        for t, c in sorted(repeats, key=lambda kv: -kv[1])[:12]:
            print('  %-28s в %d ходах' % (t[:28], c))

    print('\nСамые долгие ходы:')
    print('  %-19s %7s %7s %7s %5s  %s' % ('начало', 'всего', 'инстр', 'модель', 'выз', 'вопрос'))
    for r in sorted(rows, key=lambda x: -x['total'])[:10]:
        print('  %-19s %7.0f %7.0f %7.0f %5d  %s' % (r['when'], r['total'], r['tools'], r['model'],
                                                     r['calls'], r['ask'][:60]))

    slow = [r for r in rows if r['total'] >= 120]
    heavy = [r for r in rows if r['calls'] >= 25]
    thinky = [r for r in rows if r['model'] >= 90 and r['calls'] <= 5]
    print('\nПризнаки:')
    print('  ходов дольше 2 мин: %d из %d' % (len(slow), len(rows)))
    print('  ходов с 25+ вызовами: %d' % len(heavy))
    print('  ходов, где долго думала модель при 5 и меньше вызовах: %d' % len(thinky))


if __name__ == '__main__':
    main()
