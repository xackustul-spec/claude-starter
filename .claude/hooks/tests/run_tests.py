#!/usr/bin/env python3
# Назначение: проверка хуков claude-starter — ~850 готовых случаев (cases.json) и сценарии с git
# для обеих версий (Python и PowerShell); показывает расхождения между версиями.
# Запуск из корня проекта:  python3 .claude/hooks/tests/run_tests.py [--impl py|ps|both]
# (Windows: py -3 .claude\hooks\tests\run_tests.py). Нужен git; для ps — pwsh или powershell.exe.
# Побочные эффекты: создаёт и удаляет временные папки; проект не трогает.
import argparse
import json
import os
import shutil
import re
import subprocess
import sys
import tempfile
import time

HOOKS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HOOKS)
import kit_hooks as K  # noqa: E402


class Verdict(Exception):
    pass


def find_ps():
    for c in (os.environ.get('KIT_PWSH'), 'pwsh', '/opt/pwsh/pwsh', 'powershell.exe', 'powershell'):
        if c and shutil.which(c):
            return shutil.which(c)
    return None


def fill(obj, root):
    return json.loads(json.dumps(obj, ensure_ascii=False).replace('{ROOT}', root.replace('\\', '/')))


# ------------------------------------------------------------ случаи (в одном процессе)
def static_py(cases, root):
    def _ask(reason):
        raise Verdict('ask\n' + reason)

    def _block(lines):
        raise Verdict('block\n' + '\n'.join(lines))
    K.ask, K.block = _ask, _block
    fn = {'guard-cyrillic': K.guard_cyrillic, 'guard-shell': K.guard_shell, 'guard-instructions': K.guard_instructions}
    res = {}
    for c in cases:
        os.environ['CLAUDE_PROJECT_DIR'] = root
        os.environ['CLAUDE_TRUST_LEVEL'] = (c.get('env') or {}).get('CLAUDE_TRUST_LEVEL', 'normal')
        try:
            fn[c['hook']](fill(c['data'], root))
            res[c['id']] = ('allow', '')
        except Verdict as v:
            kind, _, msg = str(v).partition('\n')
            res[c['id']] = (kind, msg)
        except Exception as e:  # noqa: BLE001
            res[c['id']] = ('error', repr(e))
    return res


def static_ps(ps, root, tmp):
    out = os.path.join(tmp, 'ps_out.json')
    r = subprocess.run([ps, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', os.path.join(HOOKS, 'tests', 'ps_batch.ps1'),
                        '-CasesFile', os.path.join(HOOKS, 'tests', 'cases.json'), '-OutFile', out, '-Root', root],
                       capture_output=True, timeout=3600)
    if r.returncode != 0 or not os.path.isfile(out):
        print('PowerShell: прогон не удался:', r.stdout.decode('utf-8', 'replace'), r.stderr.decode('utf-8', 'replace'))
        return {}
    data = json.load(open(out, encoding='utf-8-sig'))
    if isinstance(data, dict):
        data = [data]
    return {x['id']: (x['verdict'], x['msg']) for x in data}


# ------------------------------------------------------------ сценарии (настоящие процессы)
def call(impl, ps, cmd, data, root, env=None, args=None):
    e = dict(os.environ, CLAUDE_PROJECT_DIR=root, CLAUDE_TRUST_LEVEL='normal', PYTHONUTF8='1', KIT_NO_UPDATE_CHECK='1')
    e.update(env or {})
    if impl == 'py':
        argv = [sys.executable, os.path.join(HOOKS, 'kit_hooks.py'), cmd] + (args or [])
    else:
        if cmd in ('manifest', 'update-plan'):
            name, args = 'kit-version', [cmd] + (args or [])
        else:
            name = cmd
        argv = [ps, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', os.path.join(HOOKS, name + '.ps1')] + (args or [])
    raw = data if isinstance(data, bytes) else json.dumps(data, ensure_ascii=False).encode('utf-8')
    r = subprocess.run(argv, input=raw, capture_output=True, cwd=root, env=e, timeout=120)
    out = r.stdout.decode('utf-8', 'replace').strip()
    err = r.stderr.decode('utf-8', 'replace').strip()
    if r.returncode == 2:
        kind = 'block'
    elif r.returncode != 0:
        kind = 'error'
    elif '"permissionDecision"' in out:
        kind = 'ask'
    elif out:
        kind = 'ctx'
    else:
        kind = 'allow'
    if out.startswith('{'):
        try:
            out = json.dumps(json.loads(out), ensure_ascii=False, sort_keys=True)
        except Exception:
            pass
    return kind, out, err


def git(root, *a):
    subprocess.run(['git', '-C', root, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false'] + list(a),
                   capture_output=True, check=True)


def write(root, rel, text, bom=False):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8-sig' if bom else 'utf-8', newline='') as f:
        f.write(text)


def new_project(tmp, name):
    root = os.path.join(tmp, name)
    shutil.copytree(os.path.dirname(HOOKS), os.path.join(root, '.claude'),
                    ignore=shutil.ignore_patterns('tests', '__pycache__'))
    write(root, 'docs/ai/STATE.md', '## Сейчас (обновлено: 2026-01-01, head: TODO)\n- Работает: тест\n')
    return root


def scenarios(impl, ps, tmp):
    out = []
    sid = [0]

    def S(name, cmd, data, root, expect, contains=None, env=None, args=None):
        sid[0] += 1
        data = dict(data) if isinstance(data, dict) else data
        if isinstance(data, dict):
            data.setdefault('session_id', f'{impl}-{sid[0]}-{os.getpid()}')
            data.setdefault('cwd', root)
            data.setdefault('scratchpad_dir', os.path.join(tmp, 'state'))
        kind, o, e = call(impl, ps, cmd, data, root, env, args)
        ok = kind == expect and (contains is None or contains in (o + '\n' + e))
        out.append((name, ok, kind, expect, o, e))
        return data.get('session_id') if isinstance(data, dict) else None

    def turn(root, s):
        return {'session_id': s, 'cwd': root, 'prompt': 'сделай экран записи клиентов', 'scratchpad_dir': os.path.join(tmp, 'state')}

    # session-start
    r = new_project(tmp, f'{impl}-s1')
    S('старт: не репозиторий', 'session-start', {'source': 'startup'}, r, 'ctx', 'не репозиторий')
    git(r, 'init', '-q')
    S('старт: без коммитов', 'session-start', {'source': 'startup'}, r, 'ctx', 'без коммитов')
    git(r, 'add', '-A'); git(r, 'commit', '-qm', 'c1')
    h1 = subprocess.run(['git', '-C', r, 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
    write(r, 'docs/ai/STATE.md', f'## Сейчас (обновлено: 2026-01-02, head: {h1})\n- Работает: тест\n')
    git(r, 'add', '-A'); git(r, 'commit', '-qm', 'c2')
    S('старт: head = HEAD~1 — норма', 'session-start', {'source': 'resume'}, r, 'ctx')
    k = out[-1]
    if '⚠' in k[4]:
        out[-1] = (k[0], False, 'ctx+⚠', 'ctx без ⚠', k[4], k[5])
    write(r, 'a.txt', 'x'); git(r, 'add', '-A'); git(r, 'commit', '-qm', 'c3')
    S('старт: head отстал на 2 — предупредить', 'session-start', {'source': 'startup'}, r, 'ctx', '⚠')
    S('старт: fork', 'session-start', {'source': 'fork'}, r, 'ctx', 'Старт сеанса (fork)')
    write(r, 'docs/ai/PROFILE.md', '## Профиль работы\n- Доверие: полное (осторожное / обычное / полное)\n')
    S('старт: профиль полное, а хуки не видят', 'session-start', {'source': 'startup'}, r, 'ctx', 'settings.local.json')
    S('старт: полное доверие включено — молчит', 'session-start', {'source': 'startup'}, r, 'ctx',
      env={'CLAUDE_TRUST_LEVEL': 'full'})
    if 'settings.local.json' in out[-1][4]:
        out[-1] = (out[-1][0], False, 'есть подсказка', 'без подсказки', out[-1][4], '')
    os.remove(os.path.join(r, 'docs/ai/STATE.md'))
    S('старт: нет STATE', 'session-start', {'source': 'startup'}, r, 'ctx', 'STATE.md нет')

    # ход: turn-start → check-docs
    r = new_project(tmp, f'{impl}-s2')
    git(r, 'init', '-q'); git(r, 'add', '-A'); git(r, 'commit', '-qm', 'init')
    write(r, 'notes/owner.py', 'x = 1\n')
    s = f'{impl}-turn-{os.getpid()}'
    S('ход: начало', 'turn-start', turn(r, s), r, 'ctx', 'Набор:')
    def ask(text):
        return {'session_id': f'{impl}-hint-{sid[0]}-{os.getpid()}', 'cwd': r, 'prompt': text,
                'scratchpad_dir': os.path.join(tmp, 'state')}
    S('подсказка: просят варианты', 'turn-start', ask('покажи варианты готовых шаблонов панели'), r, 'ctx',
      'Как выдавать выбор')
    S('подсказка: варианты — про своё мнение', 'turn-start', ask('какие есть готовые темы'), r, 'ctx',
      'своё мнение')
    S('подсказка: варианты — бесплатное по умолчанию', 'turn-start', ask('подбери библиотеку для графиков'), r,
      'ctx', 'Бесплатное по умолчанию')
    S('подсказка: «не то» — искать чужое готовое', 'turn-start', ask('это не то'), r, 'ctx',
      'не переделывать')
    S('подсказка: «не то» коротким сообщением — всё равно срабатывает', 'turn-start', ask('не подходит'), r,
      'ctx', 'tool-scout')
    S('подсказка: обычная просьба — молчит', 'turn-start', ask('поправь опечатку в файле README'), r, 'ctx')
    if 'Как выдавать выбор' in out[-1][4]:
        out[-1] = (out[-1][0], False, 'подсказка', 'без подсказки', out[-1][4], '')
    S('подсказка: команда со слэшем — молчит', 'turn-start', ask('/kit-audit покажи варианты'), r, 'allow')
    S('точность: «повторяю в пятый раз»', 'turn-start', ask('повторяю в пятый раз: справа от легенды'), r,
      'ctx', 'дословности')
    S('точность: «я такого не говорил»', 'turn-start', ask('я такого не говорил про плитки'), r, 'ctx', 'ничего сверх')
    S('точность: «отсебятина не нужна»', 'turn-start', ask('делать только то что прошу, отсебятина не нужна'), r,
      'ctx', 'удалить в этом же ходе')
    S('точность: слово !точно', 'turn-start', ask('!точно перенеси выбор ООО вправо от легенды'), r,
      'ctx', 'дословности')
    S('точность: слово !переделай', 'turn-start', ask('!переделай убери пунктиры'), r, 'ctx', 'ничего сверх')
    S('точность: сверка платежей — не команда', 'turn-start', ask('сделай сверку платежей за август'), r, 'ctx')
    if 'дословности' in out[-1][4]:
        out[-1] = (out[-1][0], False, 'напоминание', 'без напоминания', out[-1][4], '')
    S('точность: обычная просьба — без напоминания', 'turn-start', ask('добавь колонку с датой оплаты'), r, 'ctx')
    if 'дословности' in out[-1][4]:
        out[-1] = (out[-1][0], False, 'напоминание', 'без напоминания', out[-1][4], '')
    S('ход: чужой файл не считается', 'check-docs', {'session_id': s, 'stop_hook_active': False}, r, 'allow')
    write(r, 'src/app.py', 'print(1)\n')
    S('ход: код без шапки и документов', 'check-docs', {'session_id': s}, r, 'block', 'src/app.py')
    write(r, 'src/app.py', '# Назначение: тест\nprint(1)\n')
    S('ход: шапка есть, документов нет', 'check-docs', {'session_id': s}, r, 'block', 'docs/ai не обновлены')
    write(r, 'docs/ai/previews/p.html', '<p>x</p>')
    S('ход: превью — не документ', 'check-docs', {'session_id': s}, r, 'block', 'docs/ai не обновлены')
    S('ход: повторный Stop пропускается', 'check-docs', {'session_id': s, 'stop_hook_active': True}, r, 'allow')
    write(r, 'docs/ai/STATE.md', '## Сейчас (обновлено: 2026-01-03, head: 0000000)\n- Работает: экран\n')
    S('ход: код + STATE — можно', 'check-docs', {'session_id': s}, r, 'allow')
    st = open(os.path.join(r, 'docs/ai/STATE.md'), encoding='utf-8').read()
    hd = subprocess.run(['git', '-C', r, 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
    if f'head: {hd}' not in st or '2026-01-03' in st:
        out.append(('ход: дата и head в STATE ставятся хуком', False, 'нет', 'да', st[:120], ''))
    else:
        out.append(('ход: дата и head в STATE ставятся хуком', True, 'да', 'да', '', ''))
    write(r, 'src/bom.py', '# Назначение: файл с BOM\r\nprint(1)\r\n', bom=True)
    S('ход: шапка в файле с BOM и CRLF', 'check-docs', {'session_id': s}, r, 'allow')
    git(r, 'add', '-A'); git(r, 'commit', '-qm', 'turn')
    s2 = s + '-b'
    S('ход 2: начало', 'turn-start', turn(r, s2), r, 'ctx')
    write(r, 'src/util.ts', '// Назначение: утилиты\nexport const a = 1\n')
    git(r, 'add', '-A'); git(r, 'commit', '-qm', 'util')
    S('ход 2: закоммиченный код без документов', 'check-docs', {'session_id': s2}, r, 'block', 'docs/ai не обновлены')

    # документы: указатель и пределы
    r = new_project(tmp, f'{impl}-s5')
    write(r, 'docs/ai/INDEX.md', '| Файл | Какие данные | Когда читать |\n| STATE.md | x | всегда |\n')
    git(r, 'init', '-q'); git(r, 'add', '-A'); git(r, 'commit', '-qm', 'init')
    s5 = f'{impl}-docs-{os.getpid()}'
    S('документы: начало', 'turn-start', turn(r, s5), r, 'ctx')
    write(r, 'docs/ai/API_YANDEX.md', '# API Яндекса\n- токен: в .env\n')
    S('документы: новый без строки в INDEX', 'check-docs', {'session_id': s5}, r, 'block', 'API_YANDEX.md')
    write(r, 'docs/ai/INDEX.md', '| Файл | Какие данные | Когда читать |\n| API_YANDEX.md | вход, лимиты | при работе с API |\n')
    S('документы: записан в INDEX — можно', 'check-docs', {'session_id': s5}, r, 'allow')
    write(r, 'docs/ai/KNOWLEDGE.md', ''.join(f'- факт {i}\n' for i in range(81)))
    S('документы: KNOWLEDGE переполнен', 'check-docs', {'session_id': s5}, r, 'block', 'KNOWLEDGE.md (81')
    write(r, 'docs/ai/KNOWLEDGE.md', ''.join(f'- факт {i}\n' for i in range(80)))
    write(r, 'docs/ai/API_YANDEX.md', ''.join(f'- метод {i}\n' for i in range(301)))
    S('документы: тематический переполнен', 'check-docs', {'session_id': s5}, r, 'block', 'API_YANDEX.md (301')

    # точность: владелец требовал дословности, а в ходе правились файлы
    rx = new_project(tmp, f'{impl}-s8')
    git(rx, 'init', '-q'); git(rx, 'add', '-A'); git(rx, 'commit', '-qm', 'init')
    sx = f'{impl}-exact-{os.getpid()}'
    S('точность: начало хода', 'turn-start',
      {'session_id': sx, 'cwd': rx, 'prompt': 'повторяю в третий раз: только то, что прошу',
       'scratchpad_dir': os.path.join(tmp, 'state')}, rx, 'ctx', 'дословности')
    S('точность: файлов не трогали — можно заканчивать', 'check-docs', {'session_id': sx}, rx, 'allow')
    write(rx, 'docs/ai/KNOWLEDGE.md', '- факт\n')
    S('точность: файлы правились — сверка перед завершением', 'check-docs', {'session_id': sx}, rx, 'block',
      'добавленное сверх просьбы')
    S('точность: повторный Stop не зацикливается', 'check-docs',
      {'session_id': sx, 'stop_hook_active': True}, rx, 'allow')

    # хронометраж: строка на каждый ответ
    r = new_project(tmp, f'{impl}-s7')
    git(r, 'init', '-q'); git(r, 'add', '-A'); git(r, 'commit', '-qm', 'init')
    s7 = f'{impl}-timing-{os.getpid()}'
    tr = os.path.join(r, 'transcript.jsonl')
    t0 = time.time() - 40

    def iso(t):
        return time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(t)) + '.000Z'

    def usage(inp, out, think, cread, cwrite):
        return {'input_tokens': inp, 'output_tokens': out, 'cache_read_input_tokens': cread,
                'cache_creation_input_tokens': cwrite, 'speed': 'standard',
                'output_tokens_details': {'thinking_tokens': think}}

    def use(t, tid, name, inp, u):
        return {'type': 'assistant', 'timestamp': iso(t), 'effort': 'high',
                'message': {'model': 'claude-opus-5', 'usage': u,
                            'content': [{'type': 'tool_use', 'id': tid, 'name': name, 'input': inp}]}}

    def res(t, tid):
        return {'type': 'user', 'timestamp': iso(t),
                'message': {'content': [{'type': 'tool_result', 'tool_use_id': tid, 'content': 'ok'}]}}

    recs = [use(t0 - 600, 'old', 'Read', {'file_path': '/tmp/prev.txt'}, usage(9, 9, 9, 9, 9)),
            use(t0 + 2, 'a1', 'Bash', {'command': 'grep -n foo src/app.py'}, usage(10, 100, 40, 1000, 500)),
            res(t0 + 9, 'a1'),
            use(t0 + 12, 'a2', 'Read', {'file_path': os.path.join(r, 'docs', 'ai', 'STATE.md')},
                usage(5, 50, 10, 2000, 0)),
            res(t0 + 13, 'a2'),
            use(t0 + 20, 'a3', 'WebSearch', {'query': 'shadcn dashboard template'}, usage(5, 50, 0, 3000, 0)),
            res(t0 + 34, 'a3'),
            use(t0 + 35, 'a4', 'Read', {'file_path': '/etc/hosts'}, usage(1, 10, 0, 100, 0)),
            res(t0 + 36, 'a4'),
            {'type': 'assistant', 'timestamp': iso(t0 + 38), 'effort': 'high',
             'message': {'model': 'claude-opus-5', 'usage': usage(1, 200, 30, 4000, 0),
                         'content': [{'type': 'text', 'text': 'готово'}]}}]
    with open(tr, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(json.dumps(x, ensure_ascii=False) for x in recs) + '\n')
    tdata = {'session_id': s7, 'cwd': r, 'prompt': 'почему   ответ идёт так долго; посмотри',
             'transcript_path': tr, 'scratchpad_dir': os.path.join(tmp, 'state')}
    S('хронометраж: начало хода', 'turn-start', tdata, r, 'ctx')
    snapf = os.path.join(tmp, 'state', 'starter-%s.turn.json' % re.sub(r'[^\w.-]', '_', s7))

    def back_date():
        try:
            snap = json.load(open(snapf, encoding='utf-8'))
            snap['ts'] = t0
            json.dump(snap, open(snapf, 'w', encoding='utf-8'), ensure_ascii=False)
            return True
        except Exception:
            return False

    def check(name, cond, got=''):
        out.append((name, bool(cond), 'да' if cond else 'нет', 'да', str(got)[:160], ''))

    csvf = os.path.join(r, 'docs', 'ai', 'timing.csv')
    check('хронометраж: снимок хода записан', back_date(), snapf)
    S('хронометраж: конец хода', 'check-docs', {'session_id': s7, 'transcript_path': tr}, r, 'allow')
    rows = []
    try:
        rows = [x for x in open(csvf, encoding='utf-8-sig').read().split('\n') if x.strip()]
    except Exception:
        pass
    check('хронометраж: файл и заголовок', rows and rows[0].startswith('начало;всего_с'), rows[:1])
    check('хронометраж: заголовок со столбцами токенов', rows and 'вход_т;кэш_чт_т;кэш_зап_т;выход_т;думал_т' in rows[0], rows[:1])
    cells = rows[1].split(';') if len(rows) > 1 else []
    check('хронометраж: одна строка на ход', len(rows) == 2, len(rows))
    check('хронометраж: столбцов ровно столько же, сколько в заголовке',
          rows and len(cells) == len(rows[0].split(';')), len(cells))
    check('хронометраж: всего секунд посчитано', len(cells) > 1 and 39.0 <= float(cells[1] or 0) <= 60.0, cells[1:2])
    check('хронометраж: время инструментов посчитано', len(cells) > 2 and abs(float(cells[2] or 0) - 23.0) < 1.5, cells[2:3])
    check('хронометраж: время модели = всего минус инструменты',
          len(cells) > 3 and abs(float(cells[1]) - float(cells[2]) - float(cells[3])) < 0.2, cells[1:4])
    check('хронометраж: чужой ход не попал', len(cells) > 4 and cells[4] == '4', cells[4:5])
    check('хронометраж: запросов к модели посчитано', len(cells) > 5 and cells[5] == '5', cells[5:6])
    check('хронометраж: токены входа сложены', len(cells) > 6 and cells[6] == '22', cells[6:7])
    check('хронометраж: чтение кэша сложено', len(cells) > 7 and cells[7] == '10100', cells[7:8])
    check('хронометраж: запись кэша сложена', len(cells) > 8 and cells[8] == '500', cells[8:9])
    check('хронометраж: токены выхода сложены', len(cells) > 9 and cells[9] == '410', cells[9:10])
    check('хронометраж: токены размышления сложены', len(cells) > 10 and cells[10] == '80', cells[10:11])
    check('хронометраж: модель названа', len(cells) > 11 and cells[11] == 'opus-5', cells[11:12])
    check('хронометраж: усилие записано', len(cells) > 12 and cells[12] == 'high', cells[12:13])
    check('хронометраж: скорость записана', len(cells) > 13 and cells[13] == 'standard', cells[13:14])
    check('хронометраж: файлы вне папки проекта посчитаны', len(cells) > 14 and cells[14] == '1', cells[14:15])
    check('хронометраж: инструменты названы', len(cells) > 15 and 'Bash*1' in cells[15] and 'WebSearch*1' in cells[15], cells[15:16])
    check('хронометраж: куда смотрел', len(cells) > 16 and 'STATE.md' in cells[16] and 'grep' in cells[16], cells[16:17])
    check('хронометраж: вопрос владельца', len(cells) > 17 and 'почему ответ идёт так долго' in cells[17], cells[17:18])
    back_date()
    S('хронометраж: повторный Stop', 'check-docs', {'session_id': s7, 'stop_hook_active': True, 'transcript_path': tr}, r, 'allow')
    try:
        rows2 = [x for x in open(csvf, encoding='utf-8-sig').read().split('\n') if x.strip()]
    except Exception:
        rows2 = []
    check('хронометраж: строка заменяется, а не двоится', len(rows2) == 2, len(rows2))
    # второй ход дописывается, старые строки остаются
    s7b = s7 + '-b'
    S('хронометраж: второй ход', 'turn-start', dict(tdata, session_id=s7b, prompt='а теперь другой вопрос про панель'), r, 'ctx')
    S('хронометраж: конец второго хода', 'check-docs', {'session_id': s7b, 'transcript_path': tr}, r, 'allow')
    try:
        rows3 = [x for x in open(csvf, encoding='utf-8-sig').read().split('\n') if x.strip()]
    except Exception:
        rows3 = []
    check('хронометраж: лог растёт, прошлые ходы на месте',
          len(rows3) == 3 and rows3[1] == rows2[1], len(rows3))
    # сменились столбцы — старый файл откладывается, новый начинается с заголовка
    with open(csvf, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('старый;заголовок\n2026-01-01 00:00:00;1\n')
    back_date()
    S('хронометраж: старые столбцы', 'check-docs', {'session_id': s7, 'transcript_path': tr}, r, 'allow')
    try:
        rows4 = [x for x in open(csvf, encoding='utf-8-sig').read().split('\n') if x.strip()]
    except Exception:
        rows4 = []
    check('хронометраж: при смене столбцов новый файл с заголовком',
          len(rows4) == 2 and rows4[0].startswith('начало;всего_с'), rows4[:1])
    check('хронометраж: старый файл отложен, не потерян',
          os.path.isfile(os.path.join(r, 'docs', 'ai', 'timing.old.csv')), '')

    # версия набора: отпечатки, план обновления, уведомление о новой версии
    kit = os.path.dirname(os.path.dirname(HOOKS))
    r = new_project(tmp, f'{impl}-s6')
    skip = shutil.ignore_patterns('__pycache__', 'tests', '.git', 'docs', 'node_modules',
                                  '.venv', '.next', 'dist', 'build')
    # Заготовка набора: тесты запускают и из папки проекта, где нет VERSION и INSTALL.md,
    # а без них папка не считается исходником набора — дописываем, чтобы сценарии не зависели
    # от того, откуда запущено.
    basekit = os.path.join(tmp, f'{impl}-basekit')
    shutil.copytree(kit, basekit, ignore=skip)
    for name, body in (('VERSION', '1.0.0\n'), ('INSTALL.md', '# установка\n'), ('README.md', '# набор\n')):
        if not os.path.isfile(os.path.join(basekit, name)):
            write(basekit, name, body)
    newkit = os.path.join(tmp, f'{impl}-newkit')
    shutil.copytree(basekit, newkit, ignore=skip)
    S('версия: записать отпечатки', 'manifest', b'', r, 'ctx', 'версия', args=[basekit, newkit])
    # личные настройки и метка обновления в список файлов набора не попадают
    man = json.load(open(os.path.join(r, '.claude', 'starter.json'), encoding='utf-8'))
    bad = [x for x in man.get('files', {}) if x.endswith('.claude/settings.local.json') or 'starter.lock' in x]
    out.append(('версия: личные настройки не в манифесте', not bad, 'нет' if not bad else 'есть',
                'нет', str(bad)[:80], ''))
    S('версия: та же версия — без уведомления', 'session-start', {'source': 'startup'}, r, 'ctx')
    if 'новая версия' in out[-1][4]:
        out[-1] = (out[-1][0], False, 'уведомление', 'без уведомления', out[-1][4], '')
    write(newkit, 'VERSION', '99.0.0\n')
    write(newkit, '.claude/rules/new-rule.md', '# новое\n')
    write(newkit, '.claude/rules/code.md', '# изменено в новой версии\n')
    write(newkit, '.claude/rules/ui.md', '# изменено в новой версии\n')
    write(r, '.claude/rules/ui.md', '# владелец поправил\n')
    os.remove(os.path.join(newkit, '.claude/rules/security.md'))
    S('версия: план обновления', 'update-plan', b'', r, 'ctx', 'добавить: .claude/rules/new-rule.md', args=[newkit])
    plan = out[-1][4]
    for need in ('заменить: .claude/rules/code.md', 'изменён владельцем — показать разницу и спросить: .claude/rules/ui.md',
                 'удалить (нет в новой версии): .claude/rules/security.md', 'новая 99.0.0'):
        if need not in plan:
            out.append(('версия: в плане есть «' + need + '»', False, 'нет', 'да', plan[:400], ''))
    cache = os.path.join(tempfile.gettempdir(), 'claude-starter', 'starter-update-check.json')
    if os.path.exists(cache):
        os.remove(cache)
    S('версия: вышла новая — уведомление', 'session-start', {'source': 'startup'}, r, 'ctx', 'новая версия набора: 99.0.0',
      env={'KIT_NO_UPDATE_CHECK': ''})

    S('исходник набора распознаётся', 'session-start', {'source': 'startup'}, newkit, 'ctx', 'исходник набора')

    # папка без VERSION не затирает записанную версию (последним: переписывает манифест)
    noverkit = os.path.join(tmp, f'{impl}-noverkit')
    shutil.copytree(basekit, noverkit, ignore=skip)
    os.remove(os.path.join(noverkit, 'VERSION'))
    verwas = json.load(open(os.path.join(r, '.claude', 'starter.json'), encoding='utf-8')).get('version')
    S('версия: папка без VERSION — старая версия сохранена', 'manifest', b'', r, 'ctx',
      'оставлена прежней', args=[noverkit, 'https://example.invalid'])
    man2 = json.load(open(os.path.join(r, '.claude', 'starter.json'), encoding='utf-8'))
    out.append(('версия: поле version не затёрто', man2.get('version') == verwas,
                man2.get('version') or 'пусто', verwas, '', ''))


    # запуск из подпапки
    r = new_project(tmp, f'{impl}-s3')
    write(r, 'web/index.ts', '// Назначение: x\n')
    git(r, 'init', '-q'); git(r, 'add', '-A'); git(r, 'commit', '-qm', 'init')
    write(r, 'api/scratch.py', 'x = 1\n'); write(r, 'web/notes.py', 'y = 1\n')
    sub = os.path.join(r, 'web')
    s3 = f'{impl}-sub-{os.getpid()}'
    S('подпапка: начало', 'turn-start', dict(turn(sub, s3)), sub, 'ctx')
    S('подпапка: ничего не менял — можно', 'check-docs', {'session_id': s3}, sub, 'allow')

    # rules-on-write и pre-write
    r = new_project(tmp, f'{impl}-s4')
    S('правила: .tsx получает 4 правила', 'rules-on-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/src/App.tsx', 'content': 'x'}, 'session_id': f'{impl}-rw'}, r, 'ctx', 'ui.md')
    S('правила: повтор в сеансе молчит', 'rules-on-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/src/B.tsx', 'content': 'x'}, 'session_id': f'{impl}-rw'}, r, 'allow')
    S('правила: docs/ai пропускается', 'rules-on-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/docs/ai/x.ts', 'content': 'x'}}, r, 'allow')
    rule = os.path.join(r, '.claude/rules/code.md')
    txt = open(rule, encoding='utf-8').read()
    write(r, '.claude/rules/code.md', txt.replace('\n', '\r\n'), bom=True)
    S('правила: файл правила с BOM и CRLF', 'rules-on-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/Dockerfile', 'content': 'x'}}, r, 'ctx', 'code.md')
    S('pre-write: кириллица — блок', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/docs/ai/previews/_test.ts', 'content': 'const ПРОБА = 1'}}, r, 'block', 'ПРОБА')
    S('pre-write: settings.json — вопрос', 'pre-write',
      {'tool_name': 'Edit', 'tool_input': {'file_path': r + '/.claude/settings.json', 'old_string': 'a', 'new_string': 'b'}}, r, 'ask')
    S('pre-write: settings.json при полном доверии — вопрос', 'pre-write',
      {'tool_name': 'Edit', 'tool_input': {'file_path': r + '/.claude/settings.json', 'old_string': 'a', 'new_string': 'b'}}, r, 'ask',
      env={'CLAUDE_TRUST_LEVEL': 'full'})
    S('pre-write: CLAUDE.md при полном доверии — можно', 'pre-write',
      {'tool_name': 'Edit', 'tool_input': {'file_path': r + '/CLAUDE.md', 'old_string': 'a', 'new_string': 'b'}}, r, 'allow',
      env={'CLAUDE_TRUST_LEVEL': 'full'})
    write(r, 'docs/ai/PROFILE.md', '## Профиль работы\n- Доверие: полное (осторожное / обычное / полное)\n')
    S('личные настройки: доверие по профилю — молча', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/.claude/settings.local.json',
       'content': '{"env": {"CLAUDE_TRUST_LEVEL": "full"}}'}}, r, 'allow')
    S('личные настройки: чужие ключи — вопрос', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/.claude/settings.local.json',
       'content': '{"permissions": {"allow": ["Bash(rm -rf *)"]}}'}}, r, 'ask')
    S('личные настройки: правка кусочком — вопрос', 'pre-write',
      {'tool_name': 'Edit', 'tool_input': {'file_path': r + '/.claude/settings.local.json',
       'old_string': 'a', 'new_string': 'b'}}, r, 'ask')
    write(r, 'docs/ai/PROFILE.md', '## Профиль работы\n- Доверие: обычное (осторожное / обычное / полное)\n')
    S('личные настройки: полное без профиля — вопрос', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/.claude/settings.local.json',
       'content': '{"env": {"CLAUDE_TRUST_LEVEL": "full"}}'}}, r, 'ask')
    S('личные настройки: осторожный режим — молча', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/.claude/settings.local.json',
       'content': '{"permissions": {"defaultMode": "default"}, "outputStyle": "Concise"}'}}, r, 'allow')
    write(r, '.claude/rules/upd.md', '---\npaths:\n  - "**/*.zzz"\n---\n# правило\n')
    # манифест пишем прямо, без CLI: здесь проверяется режим обновления, а не запись отпечатков
    man_files = {rel: K.file_hash(os.path.join(r, rel))
                 for rel in ('.claude/rules/upd.md', '.claude/rules/code.md')}
    write(r, '.claude/starter.json', json.dumps(
        {'version': '1.0.0', 'source': 'src', 'installed': '2026-01-01', 'files': man_files},
        ensure_ascii=False, indent=1, sort_keys=True))
    write(r, '.claude/starter.lock', '{"mode": "update"}')
    S('обновление набора: свой файл — молча', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/.claude/rules/upd.md', 'content': '# новое'}}, r, 'allow')
    write(r, '.claude/rules/upd.md', '# владелец поправил\n')
    S('обновление набора: файл правил владельца — вопрос', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/.claude/rules/upd.md', 'content': '# новое'}}, r, 'ask')
    os.remove(os.path.join(r, '.claude/starter.lock'))
    S('без метки обновления: свой файл — вопрос', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/.claude/rules/code.md', 'content': '# новое'}}, r, 'ask')
    S('pre-write: обычный .py — правила', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/app/main.py', 'content': '# Назначение: x\nprint("Привет")\n'}}, r, 'ctx', 'code.md')
    S('своя папка: файл соседнего проекта — вопрос', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': '/etc/hosts', 'content': 'x'}}, r, 'ask', 'вне папки проекта')
    S('своя папка: документ соседней папки — вопрос', 'pre-write',
      {'tool_name': 'Edit', 'tool_input': {'file_path': '/opt/чужое/СОСТОЯНИЕ.md', 'content': 'x'}}, r, 'ask', 'вне папки проекта')
    S('своя папка: временный файл — молча', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': os.path.join(tempfile.gettempdir(), 'scratch.txt'), 'content': 'x'}}, r, 'allow')
    S('своя папка: файл внутри проекта — молча', 'pre-write',
      {'tool_name': 'Write', 'tool_input': {'file_path': r + '/app/ok.txt', 'content': 'x'}}, r, 'allow')
    bom_input = b'\xef\xbb\xbf' + json.dumps({'session_id': 'bom', 'cwd': r, 'tool_input': {
        'file_path': r + '/a.py', 'content': 'имя = 1'}}, ensure_ascii=False).encode('utf-8')
    S('guard-cyrillic: JSON с BOM на входе', 'guard-cyrillic', bom_input, r, 'block')

    # своя папка и оболочка: запись файла кода мимо проверок
    S('оболочка: файл кода через heredoc — вопрос', 'guard-shell',
      {'tool_input': {'command': 'cat > src/app.py <<EOF\nprint(1)\nEOF'}}, r, 'ask', 'через оболочку')
    S('оболочка: Set-Content в .ts — вопрос', 'guard-shell',
      {'tool_input': {'command': "Set-Content -Path src/util.ts -Value 'export const a = 1'"}}, r, 'ask', 'через оболочку')
    S('оболочка: временный файл — молча', 'guard-shell',
      {'tool_input': {'command': 'echo "x" > /tmp/scratch.py'}}, r, 'allow')
    S('оболочка: вывод программы в .txt — молча', 'guard-shell',
      {'tool_input': {'command': 'python manage.py check > out.txt'}}, r, 'allow')

    # .ps1 с русским текстом без BOM (урок 17.09.2026)
    write(r, 'tools/rus.ps1', '# Назначение: проверка\nWrite-Host "Привет"\n')
    S('ps1: русский текст без BOM — блок', 'check-python', {'tool_input': {'file_path': r + '/tools/rus.ps1'}}, r,
      'block', 'BOM')
    write(r, 'tools/rus_bom.ps1', '# Назначение: проверка\nWrite-Host "Привет"\n', bom=True)
    S('ps1: русский текст с BOM — можно', 'check-python', {'tool_input': {'file_path': r + '/tools/rus_bom.ps1'}}, r, 'allow')
    write(r, 'tools/ascii.ps1', '# Purpose: check\nWrite-Host "ok"\n')
    S('ps1: только латиница без BOM — можно', 'check-python', {'tool_input': {'file_path': r + '/tools/ascii.ps1'}}, r, 'allow')

    # check-python
    write(r, 'src/bad.py', 'def f(:\n')
    S('python: синтаксическая ошибка', 'check-python', {'tool_input': {'file_path': r + '/src/bad.py'}}, r, 'block', 'SyntaxError')
    write(r, 'src/bom_ok.py', 'print("ок")\n', bom=True)
    S('python: файл с BOM — можно', 'check-python', {'tool_input': {'file_path': r + '/src/bom_ok.py'}}, r, 'allow')
    S('python: не .py', 'check-python', {'tool_input': {'file_path': r + '/src/App.tsx'}}, r, 'allow')

    # scan
    write(r, 'src/bad_ident.ts', 'const ИМЯ = 1\n')
    S('scan: находит и считает', 'scan', b'', r, 'ctx', 'bad_ident.ts', args=['src'])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--impl', choices=['py', 'ps', 'both'], default='both')
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()
    ps = find_ps()
    impls = ['py', 'ps'] if a.impl == 'both' else [a.impl]
    if 'ps' in impls and not ps:
        print('PowerShell не найден — проверяю только Python-версию.')
        impls = ['py']
    cases = json.load(open(os.path.join(HOOKS, 'tests', 'cases.json'), encoding='utf-8'))
    tmp = tempfile.mkdtemp(prefix='kit-tests-')
    bad = 0
    try:
        root = os.path.join(tmp, 'proj')
        os.makedirs(root)
        res = {}
        if 'py' in impls:
            res['py'] = static_py(cases, root)
        if 'ps' in impls:
            res['ps'] = static_ps(ps, root, tmp)
        for c in cases:
            got = {i: res[i].get(c['id'], ('missing', '')) for i in impls}
            wrong = [i for i in impls if got[i][0] != c['expect']]
            diverge = len(impls) == 2 and got['py'][0] != got['ps'][0]
            if wrong or diverge:
                bad += 1
                print(f"СЛУЧАЙ {c['id']}: ожидалось {c['expect']}, " + ', '.join(f'{i}={got[i][0]}' for i in impls))
                if a.verbose:
                    for i in impls:
                        print(f'   {i}: {got[i][1][:300]}')
        print(f'Случаи: {len(cases)} × {"+".join(impls)}, не так: {bad}.')
        sbad = 0
        sc = {}
        for i in impls:
            sc[i] = scenarios(i, ps, tmp)
            for name, ok, kind, exp, o, e in sc[i]:
                if not ok:
                    sbad += 1
                    print(f'СЦЕНАРИЙ [{i}] {name}: получено {kind}, ожидалось {exp}\n   out: {o[:300]}\n   err: {e[:300]}')
        if len(impls) == 2:
            for (n1, _, k1, _, o1, e1), (n2, _, k2, _, o2, e2) in zip(sc['py'], sc['ps']):
                norm = lambda s: s.replace('\\', '/').replace('py-', '').replace('ps-', '')
                if k1 != k2 or (n1.startswith(('ход', 'правила', 'python')) and norm(o1 + e1) != norm(o2 + e2)
                                and 'SyntaxError' not in e1):
                    sbad += 1
                    print(f'РАСХОЖДЕНИЕ {n1}: py={k1} ps={k2}\n   py: {(o1 + e1)[:300]}\n   ps: {(o2 + e2)[:300]}')
        total = sum(len(v) for v in sc.values())
        print(f'Сценарии: {total}, не так: {sbad}.')
        bad += sbad
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('ИТОГ: всё в порядке.' if bad == 0 else f'ИТОГ: проблем — {bad}.')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
