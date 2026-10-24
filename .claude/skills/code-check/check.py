# Назначение: проверка изменённых файлов кода по своду (размеры, типы, ошибки, журнал, секреты); замечания — только по изменённым строкам.
# Запуск: python3 check.py [файлы]; без аргументов — изменённые по git. Код возврата: 0 — чисто, 1 — есть замечания.
import ast
import os
import re
import shutil
import subprocess
import sys

MAX_FILE = 400
MAX_FUNC = 40
EXTS = ('.py', '.js', '.jsx', '.mjs', '.cjs', '.ts', '.tsx', '.vue', '.svelte')
SECRET_RE = re.compile(r'(?i)\b(password|passwd|secret|token|api[_-]?key|apikey)\b\s*[:=]\s*["\'][^"\'\s]{6,}["\']')
SKIP_RE = re.compile(r'(^|/)(node_modules|dist|build|vendor|migrations|\.venv|venv|tests?|__tests__)/|\.min\.|\.test\.|\.spec\.|conftest')


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    except Exception:
        return ''


def git_files():
    out = run(['git', 'status', '--porcelain'])
    return [ln[3:].strip().strip('"') for ln in out.splitlines() if ln[:2].strip() and not ln.startswith(' D')]


def changed_lines(path, total):
    """Номера изменённых строк; новый или неотслеживаемый файл — все строки."""
    diff = run(['git', 'diff', '-U0', 'HEAD', '--', path])
    if not diff.strip():
        return set(range(1, total + 1))
    res = set()
    for m in re.finditer(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', diff, re.M):
        start, cnt = int(m.group(1)), int(m.group(2) or 1)
        res.update(range(start, start + max(cnt, 1)))
    return res


def check_python(path, text, lines, ch, out):
    try:
        tree = ast.parse(text)
    except SyntaxError as e:
        out.append((e.lineno or 1, 'синтаксическая ошибка: %s' % e.msg))
        return
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            end = getattr(node, 'end_lineno', node.lineno)
            if not (set(range(node.lineno, end + 1)) & ch):
                continue
            if end - node.lineno + 1 > MAX_FUNC:
                out.append((node.lineno, 'функция %s — %d строк (предел %d)' % (node.name, end - node.lineno + 1, MAX_FUNC)))
            if not node.name.startswith('_'):
                args = node.args.args + node.args.kwonlyargs
                bad = [a.arg for a in args if a.annotation is None and a.arg not in ('self', 'cls')]
                if bad or node.returns is None:
                    out.append((node.lineno, 'функция %s без аннотаций типов (%s)' % (node.name, ', '.join(bad[:3]) or 'результат')))
                if not ast.get_docstring(node):
                    out.append((node.lineno, 'публичная функция %s без docstring' % node.name))
        if isinstance(node, ast.ExceptHandler) and node.lineno in ch:
            broad = node.type is None or (isinstance(node.type, ast.Name) and node.type.id in ('Exception', 'BaseException'))
            reraises = any(isinstance(n, ast.Raise) for n in ast.walk(node))
            if broad and not reraises:
                out.append((node.lineno, 'except без конкретного исключения и без raise'))
            if all(isinstance(n, ast.Pass) for n in node.body):
                out.append((node.lineno, 'except: pass — ошибка проглочена'))
    for i, ln in enumerate(lines, 1):
        if i in ch and re.match(r'\s*print\(', ln):
            out.append((i, 'print() — использовать logging'))


def check_js(path, lines, ch, out):
    ts = path.endswith(('.ts', '.tsx'))
    for i, ln in enumerate(lines, 1):
        if i not in ch:
            continue
        code = re.sub(r'//.*$', '', ln)
        if re.search(r'\bconsole\.(log|debug)\(', code):
            out.append((i, 'console.log — использовать pino/winston'))
        if re.search(r'\bvar\s+\w', code):
            out.append((i, 'var — использовать const/let'))
        if re.search(r'[^=!<>]==[^=]|!=[^=]', code):
            out.append((i, '== / != — использовать === / !=='))
        if ts and re.search(r':\s*any\b|<any>|\bas any\b', code):
            out.append((i, 'any — использовать unknown или конкретный тип'))
        if re.search(r'catch\s*(\(\w*\))?\s*\{\s*\}', code) or re.search(r'\.catch\(\s*\(\)\s*=>\s*\{\s*\}\s*\)', code):
            out.append((i, 'пустой catch — ошибка проглочена'))
    depth, start, name = 0, None, None
    for i, ln in enumerate(lines, 1):
        m = re.search(r'(?:function\s+(\w+)|(\w+)\s*[:=]\s*(?:async\s*)?(?:function\b|\([^)]*\)\s*=>))', ln)
        if m and depth == 0 and '{' in ln:
            start, name = i, m.group(1) or m.group(2)
        depth += ln.count('{') - ln.count('}')
        if start and depth <= 0:
            if i - start + 1 > MAX_FUNC and (set(range(start, i + 1)) & ch):
                out.append((start, 'функция %s — %d строк (предел %d)' % (name, i - start + 1, MAX_FUNC)))
            start = None
            depth = 0


def check_file(path):
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return []
    lines = text.split('\n')
    ch = changed_lines(path, len(lines))
    out = []
    if len(lines) > MAX_FILE:
        out.append((1, 'файл %d строк (предел %d) — новый код в новый модуль' % (len(lines), MAX_FILE)))
    for i, ln in enumerate(lines, 1):
        if i in ch and SECRET_RE.search(ln):
            out.append((i, 'похоже на секрет в тексте — вынести в окружение'))
    if path.endswith('.py'):
        check_python(path, text, lines, ch, out)
    else:
        check_js(path, lines, ch, out)
    return sorted(out)


def main():
    files = [a for a in sys.argv[1:] if not a.startswith('-')] or git_files()
    files = [f for f in files if f.endswith(EXTS) and not SKIP_RE.search(f.replace('\\', '/')) and os.path.isfile(f)]
    if not files:
        print('Код-проверка: файлов кода для проверки нет.')
        return 0
    total = 0
    for f in files:
        for ln, msg in check_file(f):
            print('%s:%d — %s' % (f, ln, msg))
            total += 1
    py = [f for f in files if f.endswith('.py')]
    if py and shutil.which('ruff'):
        res = subprocess.run(['ruff', 'check', '--quiet', '--output-format=concise'] + py, capture_output=True, text=True)
        if res.stdout.strip():
            print(res.stdout.strip())
            total += len([x for x in res.stdout.splitlines() if x.strip()])
    print('Код-проверка: %d замечаний в %d файлах.' % (total, len(files)))
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
