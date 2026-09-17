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
import subprocess
import sys
import tempfile

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
    import json as _json
    write(r, '.claude/rules/upd.md', '---\npaths:\n  - "**/*.zzz"\n---\n# правило\n')
    h = subprocess.run([sys.executable, os.path.join(HOOKS, 'kit_hooks.py'), 'manifest', r, 'src'],
                       capture_output=True, cwd=r, env=dict(os.environ, CLAUDE_PROJECT_DIR=r))
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
    bom_input = b'\xef\xbb\xbf' + json.dumps({'session_id': 'bom', 'cwd': r, 'tool_input': {
        'file_path': r + '/a.py', 'content': 'имя = 1'}}, ensure_ascii=False).encode('utf-8')
    S('guard-cyrillic: JSON с BOM на входе', 'guard-cyrillic', bom_input, r, 'block')

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
