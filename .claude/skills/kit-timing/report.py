#!/usr/bin/env python3
# Назначение: свод по docs/ai/timing.csv — куда уходит время и токены (для скилла kit-timing).
# Запуск из корня проекта: python .claude/skills/kit-timing/report.py [сколько последних ходов]
# Побочные эффекты: ничего не пишет, только читает и печатает.
import os
import sys

COLS = ['when', 'total', 'tools', 'model_s', 'calls', 'req', 'tin', 'cread', 'cwrite',
        'tout', 'think', 'model', 'effort', 'speed', 'outside', 'names', 'look', 'ask']
NUM = {'total': float, 'tools': float, 'model_s': float, 'calls': int, 'req': int,
       'tin': int, 'cread': int, 'cwrite': int, 'tout': int, 'think': int, 'outside': int}


QCOLS = ['q_code', 'q_docs', 'q_rep', 'q_agents', 'q_agent_s', 'q_ret', 'q_compl']


def load(path):
    rows = []
    with open(path, encoding='utf-8-sig', errors='replace') as fh:
        for line in fh:
            line = line.rstrip('\n').rstrip('\r')
            if not line.strip() or line.startswith('начало;'):
                continue
            p = line.split(';')
            if len(p) < len(COLS):
                continue
            row = dict(zip(COLS, p))
            # Столбцы качества появились позже: в старых строках их нет.
            for i, k in enumerate(QCOLS):
                try:
                    row[k] = int(float(p[len(COLS) + i]))
                except (IndexError, ValueError):
                    row[k] = None
            try:
                for k, f in NUM.items():
                    row[k] = f(row[k] or 0)
            except ValueError:
                continue
            rows.append(row)
    return rows


def pct(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    return s[min(len(s) - 1, max(0, int(round((len(s) - 1) * q))))]


def counts(rows, key):
    out = {}
    for r in rows:
        v = (r[key] or '—').strip() or '—'
        out[v] = out.get(v, 0) + 1
    return sorted(out.items(), key=lambda kv: -kv[1])


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
    n = len(rows)
    tot = [r['total'] for r in rows]
    print('Файл: ' + path)
    print('Ходов: %d, с %s по %s' % (n, rows[0]['when'], rows[-1]['when']))
    print('Всего времени: %.0f мин. Средний ход: %.0f с, середина %.0f с, девять из десяти до %.0f с, худший %.0f с.'
          % (sum(tot) / 60.0, sum(tot) / n, pct(tot, 0.5), pct(tot, 0.9), max(tot)))
    ts = sum(r['tools'] for r in rows)
    ms = sum(r['model_s'] for r in rows)
    share = 100 * ts / (ts + ms) if (ts + ms) > 0 else 0
    print('Из них инструменты: %.0f мин (%.0f%%), модель: %.0f мин (%.0f%%).' % (ts / 60.0, share, ms / 60.0, 100 - share))
    print('Вызовов инструментов: всего %d, на ход в среднем %.1f, максимум %d.'
          % (sum(r['calls'] for r in rows), sum(r['calls'] for r in rows) / float(n), max(r['calls'] for r in rows)))

    tin = sum(r['tin'] for r in rows); cre = sum(r['cread'] for r in rows)
    cwr = sum(r['cwrite'] for r in rows); out = sum(r['tout'] for r in rows)
    thi = sum(r['think'] for r in rows); req = sum(r['req'] for r in rows)
    allin = tin + cre + cwr
    print('\nТокены: вход %.1f млн (свежий %.0f тыс., из кэша %.1f млн, запись кэша %.0f тыс.), выход %.0f тыс.'
          % (allin / 1e6, tin / 1e3, cre / 1e6, cwr / 1e3, out / 1e3))
    print('На ход в среднем: вход %.0f тыс., выход %.1f тыс., из них размышление %.1f тыс. (%.0f%% выхода).'
          % (allin / n / 1e3, out / n / 1e3, thi / n / 1e3, 100 * thi / out if out else 0))
    print('Запросов к модели: %d, на ход в среднем %.1f (каждый запрос заново подаёт весь контекст).'
          % (req, req / float(n)))

    print('\nЧем работали:')
    for key, label in (('model', 'модель'), ('effort', 'усилие'), ('speed', 'скорость')):
        vals = counts(rows, key)
        print('  %-9s %s' % (label, ', '.join('%s — %d ход.' % (v, c) for v, c in vals[:4])))

    names = {}
    for r in rows:
        for part in r['names'].split():
            if '*' in part:
                nm, c = part.rsplit('*', 1)
                try:
                    names[nm] = names.get(nm, 0) + int(c)
                except ValueError:
                    pass
    if names:
        print('\nЧем пользовались (вызовов):')
        for nm, c in sorted(names.items(), key=lambda kv: (-kv[1], kv[0]))[:12]:
            print('  %-22s %d' % (nm, c))

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
    print('  %-19s %6s %6s %6s %4s %8s  %s' % ('начало', 'всего', 'инстр', 'модель', 'выз', 'токенов', 'вопрос'))
    for r in sorted(rows, key=lambda x: -x['total'])[:10]:
        print('  %-19s %6.0f %6.0f %6.0f %4d %8d  %s'
              % (r['when'], r['total'], r['tools'], r['model_s'], r['calls'],
                 r['tin'] + r['cread'] + r['cwrite'] + r['tout'], r['ask'][:50]))

    print('\nСамые дорогие ходы (по токенам):')
    for r in sorted(rows, key=lambda x: -(x['tin'] + x['cread'] + x['cwrite'] + x['tout']))[:5]:
        print('  %-19s %8d токенов, запросов %2d, выход %5d  %s'
              % (r['when'], r['tin'] + r['cread'] + r['cwrite'] + r['tout'], r['req'], r['tout'], r['ask'][:50]))

    slow = [r for r in rows if r['total'] >= 120]
    heavy = [r for r in rows if r['calls'] >= 25]
    thinky = [r for r in rows if r['model_s'] >= 90 and r['calls'] <= 5]
    ctx = [r for r in rows if r['req'] and (r['cread'] + r['cwrite']) / float(r['req']) >= 200000]
    print('\nПризнаки:')
    print('  ходов дольше 2 мин: %d из %d' % (len(slow), n))
    print('  ходов с 25+ вызовами: %d' % len(heavy))
    print('  ходов, где долго думала модель при 5 и меньше вызовах: %d' % len(thinky))
    print('  ходов, где в каждый запрос уходило 200 тыс. токенов и больше (контекст раздут): %d' % len(ctx))
    out_turns = [r for r in rows if r['outside'] > 0]
    if out_turns:
        print('  ходов, где трогали файлы вне папки проекта: %d — так нельзя, назвать владельцу' % len(out_turns))
        for r in out_turns[-5:]:
            print('    %s  %s' % (r['when'], r['ask'][:60]))

    quality(rows)


def quality(rows):
    # Качество обработки: где работа шла впустую. Считается по ходам, где столбцы качества уже есть.
    q = [r for r in rows if r.get('q_code') is not None]
    if not q:
        print('\nКачество: столбцов ещё нет — появятся с первых ходов после обновления набора.')
        return
    n = len(q)
    code = sum(r['q_code'] for r in q); docs = sum(r['q_docs'] for r in q)
    print('\nКачество обработки (ходов со счётом: %d):' % n)
    print('  правок: в код %d, в документы %d (%.0f%% — писанина)' % (code, docs, 100.0 * docs / (code + docs) if code + docs else 0))
    compl = [r for r in q if r['q_compl']]
    print('  ходов, начатых с претензии владельца («не то», «опять», «наезжает»): %d из %d (%.0f%%)' % (len(compl), n, 100.0 * len(compl) / n))
    # Ход, после которого владелец пришёл с претензией, — это и есть плохо выполненное задание.
    bad = [q[i - 1] for i in range(1, n) if q[i]['q_compl']]
    if bad:
        print('  задания, выполненные плохо (следом пришла претензия), и чего они стоили:')
        for r in bad[-8:]:
            print('    %s  %4.0f с, выход %5d, правок код/док %d/%d  %s' % (r['when'], r['total'], r['tout'], r['q_code'], r['q_docs'], r['ask'][:46]))
        print('    всего на них: %.0f мин и %.0f тыс. токенов выхода' % (sum(r['total'] for r in bad) / 60.0, sum(r['tout'] for r in bad) / 1e3))
    ret = [r for r in q if r['q_ret']]
    print('  ходов, которые хук вернул на доработку: %d (возвратов всего %d)' % (len(ret), sum(r['q_ret'] for r in q)))
    idle = [r for r in q if r['total'] >= 90 and r['q_code'] == 0 and not r['q_agents']]
    print('  ходов дольше 1,5 мин без единой правки кода и без субагента: %d — ответ словами или писанина' % len(idle))
    for r in idle[-5:]:
        print('    %s  %4.0f с, думал %5d, правок в документы %d  %s' % (r['when'], r['total'], r['think'], r['q_docs'], r['ask'][:46]))
    ag = [r for r in q if r['q_agents']]
    if ag:
        s = sum(r['q_agent_s'] for r in ag); c = sum(r['q_agents'] for r in ag)
        print('  субагенты: %d вызовов в %d ходах, ждали их %.0f мин, в среднем %.0f с на вызов' % (c, len(ag), s / 60.0, s / c))
        for r in sorted(ag, key=lambda x: -x['q_agent_s'])[:3]:
            print('    %s  субагент %4.0f с из %4.0f с хода  %s' % (r['when'], r['q_agent_s'], r['total'], r['ask'][:46]))
    rep = sum(r['q_rep'] for r in q)
    print('  повторных чтений одного файла внутри хода: %d' % rep)
    docsonly = [r for r in q if r['q_docs'] >= 3 and r['q_docs'] > 2 * r['q_code']]
    print('  ходов, где в документы писали втрое больше, чем в код: %d' % len(docsonly))


if __name__ == '__main__':
    main()
