#!/usr/bin/env python3
# Назначение: единая реализация хуков claude-starter для Linux/macOS/Git Bash
# (Windows использует такие же по смыслу скрипты *.ps1). Запуск: run.sh <команда>.
# Команды: guard-shell, guard-cyrillic, guard-instructions, rules-on-write,
#          check-python, turn-start, session-start, check-docs.
# Побочные эффекты: пишет снимки хода в каталог состояния сеанса (scratchpad или temp).
import json
import os
import re
import subprocess
import sys
import tempfile
import time

CYR = r'[Ѐ-ӿ]'
W = r'[\wЀ-ӿ$]*'
CODE_EXT = {'.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.vue', '.svelte', '.py', '.php', '.go',
            '.rs', '.java', '.kt', '.rb', '.cs', '.swift', '.dart', '.sh', '.bash', '.ps1', '.sql',
            '.yaml', '.yml', '.toml', '.json', '.prisma', '.env', '.conf', '.html', '.htm', '.css',
            '.scss', '.less', '.graphql', '.gql'}
HEADER_EXT = {'.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.vue', '.svelte', '.py', '.php', '.go',
              '.rs', '.java', '.kt', '.rb', '.cs', '.swift', '.dart', '.sh', '.bash', '.ps1', '.sql'}
SPECIAL_NAMES = re.compile(r'^(Dockerfile|Caddyfile|Makefile|compose.*\.ya?ml|docker-compose.*\.ya?ml)$', re.I)
GENERATED = re.compile(r'(^|/)(node_modules|dist|build|\.next|out|coverage|vendor|__pycache__|migrations|\.venv|venv|target)/|\.min\.|\.lock$|lock\.json$|\.generated\.', re.I)
C_LIKE = {'.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.vue', '.svelte', '.php', '.go', '.rs', '.java',
          '.kt', '.cs', '.swift', '.dart', '.sql', '.prisma', '.css', '.scss', '.less'}
JS_LIKE = {'.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.vue', '.svelte'}
MARKUP = {'.tsx', '.jsx', '.vue', '.svelte', '.html', '.htm', '.php'}
HASH_COMMENT = {'.py', '.sh', '.bash', '.ps1', '.yaml', '.yml', '.toml', '.env', '.conf', '.rb', '.graphql', '.gql'}
# языки с многострочными строками, которые надо вырезать целиком
TRIPLE_Q = {'.py', '.java', '.kt', '.swift', '.cs', '.dart', '.graphql', '.gql'}
BACKTICK_RAW = JS_LIKE | {'.go'}
HEREDOC = {'.sh', '.bash', '.ps1', '.php', '.rb'}
TYPED = {'.java', '.kt', '.cs', '.go', '.rs', '.swift', '.dart', '.php'}
CSS_LIKE = {'.css', '.scss', '.less'}
DOC_EXT = {'.md', '.txt', '.rst', '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.odt', '.rtf'}
I18N_PATH = re.compile(r'(^|/)(locales?|i18n|lang|langs|translations?|messages|l10n)/|(^|/|\.)(ru|en|uk|be|kk|uz|ky|tg|hy|ka|az|de|fr|es|it|pt|pl|cs|tr|zh|ja|ko|ar|he)([-_][A-Za-z]{2,4})?\.(json|ya?ml)$', re.I)


def read_input():
    try:
        raw = sys.stdin.buffer.read().decode('utf-8-sig', 'replace')
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def out_json(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.flush()


def ask(reason):
    out_json({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                     "permissionDecision": "ask",
                                     "permissionDecisionReason": reason}})
    sys.exit(0)


def block(lines):
    sys.stderr.write("\n".join(lines) + "\n")
    sys.stderr.flush()
    sys.exit(2)


def trust_full():
    return os.environ.get('CLAUDE_TRUST_LEVEL', '').strip().lower() == 'full'


def project_dir(data):
    d = os.environ.get('CLAUDE_PROJECT_DIR') or data.get('cwd') or os.getcwd()
    return os.path.abspath(d)


def state_dir(data):
    base = data.get('scratchpad_dir') or os.path.join(tempfile.gettempdir(), 'claude-starter')
    try:
        os.makedirs(base, exist_ok=True)
    except Exception:
        base = tempfile.gettempdir()
    return base


def state_file(data, kind):
    sid = re.sub(r'[^\w.-]', '_', str(data.get('session_id') or 'nosession'))
    return os.path.join(state_dir(data), f'starter-{sid}.{kind}.json')


def rel_path(path, root):
    p = path.replace('\\', '/')
    r = root.replace('\\', '/').rstrip('/')
    if p.lower().startswith(r.lower() + '/'):
        return p[len(r) + 1:]
    return None


def git(root, *args):
    try:
        res = subprocess.run(['git', '-C', root, '-c', 'core.quotepath=off'] + list(args),
                             capture_output=True, timeout=20)
        if res.returncode != 0:
            return None
        return res.stdout.decode('utf-8', 'replace')
    except Exception:
        return None


# ---------------------------------------------------------------- guard-shell
# PRE — начало команды: добавлены кавычки и обратные кавычки (bash -c "...", eval "...", `...`)
PRE = r'(^|[\s;|&(\'"`])'
GITF = r'git\s+(?:(?:-[cC]\s+\S+|--[\w-]+(?:=\S*)?|-[a-zA-Z])\s+)*'  # git с глобальными флагами: git -C x, git --no-pager
SSH_RE = re.compile(r'(^|[\s;|&(])ssh(\.exe)?\s', re.I)
INSTALL_RE = re.compile(
    PRE + r'(npm|pnpm|yarn|bun)\s+(i|install|add|ci|create|exec|dlx|x|update|upgrade|up)\b'
    r'|' + PRE + r'yarn\s*($|[;&|])'
    r'|\b(npx|bunx)\s+(-y\s+|--yes\s+|-p\s+\S+\s+)?(?!(skills\s+find|prisma|tsc|eslint|prettier|vitest|jest|playwright|next|vite|tailwindcss|drizzle-kit|nodemon|ts-node|tsx)(\s|$))\S'
    r'|\buvx\s|pipx\s+(run|install)|pip3?\s+install|python3?\s+-m\s+pip\s+install|\buv\s+(pip\s+install|add|sync|tool\s+(install|run))|poetry\s+(add|install|update)|pipenv\s+(install|update|sync)|conda\s+(install|create|update)'
    r'|apt(-get)?\s+(-\S+\s+)*install|dnf\s+install|yum\s+install|snap\s+install|winget\s+install|choco\s+install|brew\s+(install|tap|upgrade)|scoop\s+install|pacman\s+-S|apk\s+add|zypper\s+(in|install)|nix-shell|nix\s+(shell|run|profile\s+install)|pkg\s+install'
    r'|cargo\s+(add|install)|\bgo\s+((get|install)\s|mod\s+download\b)|\bgo\s+run\s+\S+@|gem\s+install|bundle\s+(install|update)|composer\s+(require|global|install|update)|dotnet\s+(add\s+package|tool\s+install|restore)'
    r'|deno\s+(install|add|run\s+https?://)|\bmake\s+install\b|cmake\s+--install|setup\.py\s+install'
    r'|claude\s+(mcp\s+add(-json)?|plugins?\s+(install|marketplace\s+add)|install)|/plugin\s+(install|marketplace)'
    r'|docker(\s+|-)(pull|compose\s+(pull|up|build)|run|build)\b'
    r'|(curl|wget|Invoke-WebRequest|iwr|irm|Invoke-RestMethod)\b[^|\n]*\|\s*(sudo\s+)?(ba|z|da|k)?sh\b'
    r'|(curl|wget|Invoke-WebRequest|iwr|irm|Invoke-RestMethod)\b[^|\n]*\|\s*(python3?|node|pwsh|powershell|perl|ruby)\b'
    r'|(curl|wget|irm|iwr)\b[^|\n]*[;&]{1,2}[^|\n]*\b(ba|z|da|k)?sh\s+(-\S+\s+)*\S+\.(sh|bash)\b'
    r'|\|\s*(sudo\s+)?(ba|z|da|k)?sh\b\s*(-s\b|$|[;&|])'
    r'|Invoke-WebRequest|\biwr\b|Invoke-Expression|\biex\b|Install-Module|Install-Package|\birm\b[^|;&]*-OutFile', re.I)
DANGER_RE = re.compile(
    r'docker(\s+|-)compose\s+down[^|;&]*\s(-v|--volumes)\b|docker(\s+|-)(compose\s+)?(volume\s+(rm|prune)|system\s+prune|container\s+(prune|rm|kill)|image\s+prune|rm\b|rmi|kill\b)'
    r'|' + PRE + r'rm\s+(?:(?:-[a-zA-Z]+|--\w+|[^\s|;&-]\S*)\s+)*(-[a-zA-Z]*[rRf][a-zA-Z]*|--recursive|--force)\b'
    r'|' + PRE + r'(ri|rd|del|erase)\s+(-r\b|-Recurse|/[sq])|rmdir\s+/s|Remove-Item\b[^|;&]*(-Recurse|-Force|\s-r\b)|\bClear-Content\b'
    r'|find\b[^|;&]*\s(-delete\b|-exec\s+rm\b)|xargs\s+(-\S+\s+)*rm\b|\bshred\b|rsync\b[^|;&]*--delete'
    r'|(^|[\s;|&(\'"])(DROP\s+(TABLE|DATABASE|SCHEMA|INDEX)|TRUNCATE\s+(TABLE\s+)?\w+|DELETE\s+FROM|ALTER\s+TABLE\s+\w+\s+DROP)\b'
    r'|\bflush(all|db)\b|\.drop(Database|Collection)?\(\)|db\.\w+\.drop\('
    r'|prisma\s+(migrate\s+(reset|deploy|dev)|db\s+push)|drizzle-kit\s+(push|drop|migrate)|(alembic|flask\s+db|manage\.py)\s+(downgrade|migrate|upgrade|flush)\b'
    r'|rails\s+db:(drop|reset|migrate|rollback|purge|schema:load)|artisan\s+(migrate|db:wipe)|typeorm\s+schema:(drop|sync)|knex\s+migrate:rollback|sequelize\s+db:migrate:undo'
    r'|' + GITF + r'(push\b[^|;&]*?\s(--force|--delete|-d\b|-[a-zA-Z]*f[a-zA-Z]*(?=\s|$)|\+\w|:\w)|reset\s+--hard|clean\s+-[a-z]*f|checkout\s+--\s|checkout\s+\.|restore\s(?![^|;&]*--staged)|branch\s+(?-i:-D)|stash\s+(drop|clear)|filter-branch|filter-repo|rebase\b|commit\s+[^|;&]*--amend|tag\s+(-d|--delete)|reflog\s+expire|gc\s+[^|;&]*--prune|update-ref\s+-d|worktree\s+remove\s+[^|;&]*(--force|-f\b)|config\s+[^|;&]*alias\.)'
    r'|(terraform|tofu)\s+(destroy|apply)|pulumi\s+(destroy|up)|cdk\s+(deploy|destroy)|helm\s+(uninstall|delete|upgrade|install|rollback)|kubectl\s+(delete|apply|scale|rollout\s+(restart|undo)|drain|cordon)'
    r'|gh\s+(repo\s+delete|release\s+delete|pr\s+merge|api\s+[^|;&]*(-X|--method)\s+DELETE)'
    r'|systemctl\s+(stop|disable|restart)\s|\bservice\s+\S+\s+(stop|restart)\b|\b(Stop|Restart)-(Service|Computer)\b|Set-Service\b[^|;&]*Disabled'
    r'|\b(Format-Volume|Clear-Disk|Remove-Partition|Initialize-Disk)\b|\bdiskpart\b|\breg\s+delete\b|Remove-ItemProperty\b[^|;&]*HK(LM|CU)'
    r'|\bshutdown\b|\breboot\b|\bmkfs|\bdd\s+[^|;&]*\b(if|of)=|\btruncate\s+(-s|--size)|^\s*(:\s*)?>{1,2}\s*\S+\s*$|(^|[\s;&|])>\s*\S+\.(db|sqlite3?|mdb|accdb|env)\b'
    r'|\b(chmod|chown|chgrp)\s+(-[a-zA-Z]*R|--recursive)|crontab\s+-r\b|iptables\s+(-F|--flush)|ufw\s+disable'
    r'|\b(vercel|netlify|wrangler|railway|serverless|sls|sam|kamal|firebase|amplify)\s+(deploy|publish|up|release)\b|\b(vercel|netlify)\b[^|;&]*--prod\b|(^|[\s;|&(])vercel\s*$|render\s+deploys?\s+create|\b(fly|flyctl)\s+deploy\b|gcloud\s+(run|app|functions)\s+deploy|az\s+webapp\s+(deploy|up)|\beb\s+deploy|git\s+push\s+\S*heroku|aws\s+s3\s+(sync|cp)\b[^|;&]*s3://'
    r'|(^|[\s;|&(])(mail|mailx|sendmail|msmtp|mutt)\s+(-|\S+@)|twilio\s+api|hooks\.slack\.com|api\.telegram\.org/bot|stripe\s+(charges|payment_intents|refunds|payouts)\s+create|curl\b[^|;&]*(-X|--request)\s+DELETE\b[^|;&]*https://(?!localhost)'
    r'|shutil\.rmtree|\brmSync\(|\brimraf\s', re.I)
SECRET_RE = re.compile(
    r'(^|[\s;|&(])(cat|less|more|head|tail|grep|rg|type|Get-Content|gc|printenv|env|strings|awk|sed|xxd|od|base64|hexdump|bat|nl|cut|sort|tac|Select-String|sls|cp|copy|Copy-Item|scp|python3?|node|perl|ruby|php|source|\.)\b[^|;&]*(\bsecrets?[\\/.]|(^|[\s/\\"\'])(?!process\.env|import\.meta\.env)[\w.*-]*\.env(rc)?(?!\.example)(\.\w+)?\b|\.pem\b|\.key\b|id_rsa|id_ed25519|credentials|\.(netrc|npmrc|pypirc|git-credentials|pgpass)\b|\.docker/config\.json|\.kube/config|service[-_]?account\S*\.json)'
    r'|docker\s+(compose\s+)?(exec|inspect)[^|;&]*\b(env|printenv|\.env)\b|docker\s+(container\s+)?inspect\b(?![^|;&]*(--format|-f\s))|git\s+(show|log|diff)[^|;&]*\.env(?!\.example)\b'
    r'|(^|[\s;|&(])((printenv|env)(\s+[A-Za-z_]\w*)?|set|export\s+-p|declare\s+-x)\s*($|[;|&)])|\$env:\w*(KEY|SECRET|TOKEN|PASS|PWD|URL|DSN|CRED|AUTH|PRIVATE|API)|(Get-ChildItem|gci|ls|dir|Get-Item|gi)\s+env:|cmd\s+/c\s+set\b'
    r'|echo\s+"?\$\{?[A-Za-z_]*(KEY|SECRET|TOKEN|PASS|PWD|URL|DSN|CRED|AUTH|PRIVATE|API)'
    r'|\bsops\s+(-d|--decrypt)|\bop\s+(read|item\s+get)|\bvault\s+(kv\s+get|read)\b|\bpass\s+show\b|gcloud\s+auth\s+print-access-token|az\s+account\s+get-access-token|aws\s+(secretsmanager\s+get-secret-value|ssm\s+get-parameters?\b[^|;&]*--with-decryption)|kubectl\s+get\s+secrets?\b[^|;&]*(-o|--output)|heroku\s+config(?!:set)|vercel\s+env\s+pull|doppler\s+secrets|dotenv\s+-p\b', re.I)
# правка файлов-инструкций через оболочку (guard-instructions видит только Write/Edit)
INSTR_PATH_SHELL_RE = re.compile(r'(^|[\s/"\'=])(CLAUDE(\.local|\.starter)?\.md|AGENTS\.md|\.mcp\.json|\.claude\.json|\.claude[/\\](rules|skills|hooks|agents|output-styles|commands|plugins|settings)[\w./\\-]*)', re.I)
WRITE_VERB_RE = re.compile(r'\b(sed\s+-[a-zA-Z]*i|perl\s+-[a-zA-Z]*i|tee|Set-Content|Out-File|Add-Content|New-Item|Copy-Item|Move-Item|Remove-Item|Rename-Item|Clear-Content|cp|mv|rm|ri|del|erase|chmod|chattr|attrib|truncate|ln|install|rsync|patch|git\s+(checkout|restore|apply|stash\s+pop)|python3?\s+-|dd|unzip|tar)\b|>|<<', re.I)


def guard_shell(data):
    cmd = str((data.get('tool_input') or {}).get('command') or '')
    if not cmd.strip():
        return
    if SSH_RE.search(cmd):
        bad = []
        if '<<' in cmd:
            bad.append('heredoc (<<)')
        if '$(' in cmd:
            bad.append('подстановка $(...)')
        if "'\"'\"'" in cmd:
            bad.append("кавычки '\"'\"'")
        if "@'" in cmd or '@"' in cmd:
            bad.append('here-string PowerShell (@\' / @")')
        if re.search(r'(^|[\s;"\'])[^\x00-\x7F]+=', cmd):
            bad.append('переменная с кириллицей')
        if bad:
            block([
                'Заблокировано: команда ssh содержит ' + ', '.join(bad) + '.',
                'Такие конструкции ломаются при передаче через оболочку. Запиши скрипт в файл (LF, ASCII-имя), '
                "отправь scp в /tmp и выполни: ssh <сервер> 'bash /tmp/<файл>.sh' (см. правило .claude/rules/code.md).",
            ])
    if SECRET_RE.search(cmd):
        ask('Чтение секретов: значения ключей не выводить и не читать. Имена переменных взять из .env.example '
            'или спросить у владельца.')
    if INSTR_PATH_SHELL_RE.search(cmd) and WRITE_VERB_RE.search(cmd):
        if re.search(r'\.claude[/\\](hooks|settings)|\.claude\.json', cmd, re.I):
            ask('Изменение защит набора (разрешений или хуков) через оболочку. Покажите владельцу, что меняется, '
                'и получите «да».')
        if not trust_full():
            ask('Изменение инструкций Claude через оболочку. Покажите владельцу, что меняется, и получите «да».')
    if INSTALL_RE.search(cmd) and not trust_full():
        ask('Установка или запуск стороннего кода: нужна явная команда владельца именно на это '
            '(скилл compat-check выполнен?). Если «да» уже было — подтвердите.')
    if DANGER_RE.search(cmd):
        ask('Опасное действие (данные, база, удаление, история git, инфраструктура). '
            'Перед выполнением: бэкап и «да» владельца.')


# ------------------------------------------------------------- guard-cyrillic
def _keep_newlines(m):
    return '\n' * m.group(0).count('\n')


def strip_multiline(text, ext, leaf):
    if ext in C_LIKE or ext in ('.json', '.jsonc', '.html', '.htm'):
        text = re.sub(r'/\*.*?\*/', _keep_newlines, text, flags=re.S)
    if ext in TRIPLE_Q:
        text = re.sub(r'"""(?:\\.|[^\\])*?"""', _keep_newlines, text, flags=re.S)
    if ext in ('.py', '.dart'):
        text = re.sub(r"'''(?:\\.|[^\\])*?'''", _keep_newlines, text, flags=re.S)
    if ext in BACKTICK_RAW:
        text = re.sub(r'`(?:\\.|[^`\\])*`', _keep_newlines, text, flags=re.S)
    if ext == '.rs':
        text = re.sub(r'r(#*)"[\s\S]*?"\1', _keep_newlines, text)
    if ext == '.cs':
        text = re.sub(r'(?:@\$?|\$@)"(?:[^"]|"")*"', _keep_newlines, text, flags=re.S)
    if ext in MARKUP or ext in ('.html', '.htm'):
        text = re.sub(r'<!--.*?-->', _keep_newlines, text, flags=re.S)
    if ext in HEREDOC or SPECIAL_NAMES.match(leaf):
        text = re.sub(r"<<[<~-]?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\b", _keep_newlines, text, flags=re.S)
        text = re.sub(r"@['\"]\n.*?\n['\"]@", _keep_newlines, text, flags=re.S)
    if ext == '.ps1':
        text = re.sub(r'<#.*?#>', _keep_newlines, text, flags=re.S)
    if ext in ('.yaml', '.yml'):
        # блочные скаляры: строки после "key: |" / "key: >" / "- |" с большим отступом — текст
        lines = text.split('\n')
        out, i = [], 0
        while i < len(lines):
            ln = lines[i]
            out.append(ln)
            m = re.match(r'^(\s*)(?:[^#\n]*:|-)\s*[|>][-+]?\s*$', ln)
            if m:
                ind = len(m.group(1))
                i += 1
                while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > ind):
                    out.append('')
                    i += 1
                continue
            i += 1
        text = '\n'.join(out)
    return text


JS_REGEX_LIT = re.compile(r'(?<![\w)\]])/(?![\s*/])(?:\\.|\[(?:\\.|[^\]\\])*\]|[^/\\\n\[])+/[a-z]*')


def strip_inline(s, ext):
    s = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
    s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s)
    if ext in JS_LIKE:
        s = re.sub(r'`[^`]*`', '``', s)
        s = JS_REGEX_LIT.sub('/re/', s)
    if ext in HASH_COMMENT or SPECIAL_NAMES.match(ext or ''):
        s = re.sub(r'(^|\s)#.*$', '', s)
    if ext == '.php':
        s = re.sub(r'(^|\s)#(?!\[).*$', '', s)
    if ext in C_LIKE or ext in ('.html', '.htm'):
        s = re.sub(r'//.*$', '', s)
        s = re.sub(r'/\*.*?(\*/|$)', '', s)
        s = re.sub(r'^\s*\*.*$', '', s)
    if ext == '.sql':
        s = re.sub(r'--.*$', '', s)
        s = re.sub(r'(^|\s)#.*$', '', s)
    return s


def strip_comments_only(s, ext):
    if ext in HASH_COMMENT or ext == '.php' or SPECIAL_NAMES.match(ext or ''):
        s = re.sub(r'(^|\s)#(?!\[).*$', '', s)
    if ext in C_LIKE:
        s = re.sub(r'//.*$', '', s)
    return s


def strip_quotes_only(s, ext):
    # для проверок «код внутри строк»: убрать только одинарные строки и комментарии, двойные оставить
    s = re.sub(r"'(?:\\.|[^'\\])*'", "''", s)
    if ext in HASH_COMMENT or ext == '.php' or SPECIAL_NAMES.match(ext or ''):
        s = re.sub(r'(^|\s)#(?!\[).*$', '', s)
    if ext in C_LIKE:
        s = re.sub(r'//.*$', '', s)
    return s


CODE_SEG_RE = re.compile(r'[=;(]|^\s*(?:export\s+|default\s+|async\s+|static\s+|public\s+|private\s+|protected\s+)*'
                         r'(?:class|function|interface|enum|type|const|let|var|def|if|for|while|switch|import|return|struct|model|namespace|foreach|catch|else|try|do|with|match|case|await|yield|new|throw|use)\b')
KEY_BEFORE_BRACE_LC = re.compile(r'^\s*(?![А-ЯЁ][а-яё])[\w$]*' + CYR + W + r'\s*[:=]\s*$')
KEY_BEFORE_BRACE_ANY = re.compile(r'^\s*[\w$]*' + CYR + W + r'\s*[:=]\s*$')
CODE_TAIL_RE = re.compile(r'[,;{(]\s*$')


def strip_markup_text(s):
    s = re.sub(r'>[^<>{}]*<', '><', s)
    s = re.sub(r'>[^<>{}]*$', '>', s)
    s = re.sub(r'^[^<>{}=;()]*<', '<', s)
    if not re.search(r'[<>{}=;()\[\]]', s):
        return ''
    if '{' in s:
        code_tail = bool(CODE_TAIL_RE.search(s))

        def repl(m):
            seg = m.group(2)
            if CODE_SEG_RE.search(seg) or KEY_BEFORE_BRACE_LC.match(seg) or (code_tail and KEY_BEFORE_BRACE_ANY.match(seg)):
                return m.group(0)
            return m.group(1) + m.group(3)
        s = re.sub(r'(^|})([^{}<>]*)({|$)', repl, s)
    return s


DECL_RE = re.compile(r'\b(const|let|var|function|class|def|interface|type|enum|fn|func|struct|impl|trait|package|namespace|import|from|as|lambda|export|public|private|protected|static|async|final|abstract|record|object|val|ENV|ARG|declare|local|readonly|module|property|event'
                     r'|for|foreach|model|read|typedef|using|global|nonlocal|new|throw|raise|return|yield|await|del|if|elif|while|in|is|not|and|or|use|case|match|instanceof|typeof)\s+(?:-{0,2}\w+\s+)?[$*&]?_*' + CYR)
CALL_RE = re.compile(CYR + W + r'\(')
MEMBER_RE = re.compile(r'(?:[A-Za-z0-9_$)\]]\??\.|[Ѐ-ӿ]{3}\.|->)_*' + CYR + r'[\wЀ-ӿ$]')
ASSIGN_RE = re.compile(r'(^|[\s;{(,])[\w$]*' + CYR + W + r'\s*(?:,[^=\n]*)?(=[^=>]|:=|\+=|-=|\|\|=|\?\?=)')
KEY_RE = re.compile(r'(^|[{,])\s*[\'"]?(?![А-ЯЁ][а-яё])[\w$]*' + CYR + W + r'[\'"]?\s*:(?!:)')
KEY_ANY_RE = re.compile(r'(^|[{,])\s*[\'"]?[\w$]*' + CYR + W + r'[\'"]?\s*:(?!:)')
JSON_KEY_RE = re.compile(r'(^|[{,])\s*"[^"]*' + CYR + r'[^"]*"\s*:')
TAG_RE = re.compile(r'<\s*/?\s*' + CYR)
YAML_KEY_RE = re.compile(r'^\s*-?\s*[^:#\'"\n]*' + CYR + r'[^:#\n]*:(\s|$)')
YAML_QKEY_RE = re.compile(r'^\s*-?\s*["\'][^"\'\n]*' + CYR + r'[^"\'\n]*["\']\s*:(\s|$)')
YAML_FLOW_RE = re.compile(r'[{,]\s*[^:,{}\s"\']*' + CYR + r'[^:,{}]*:')
YAML_ENVLIST_RE = re.compile(r'^\s*-\s*[\w]*' + CYR + W + r'=')
YAML_TEXTKEY_RE = re.compile(r'^\s*-?\s*[А-ЯЁ][а-яё][^:]*:\s*(?=.*(' + CYR + r'|[{$%]))')
ENV_LEFT_RE = re.compile(r'^\s*(export\s+)?[\w]*' + CYR + W + r'\s*=')
SHELL_VAR_RE = re.compile(r'(^|[\s;])[\w]*' + CYR + W + r'=|\$\{?' + CYR + r'|^\s*(function\s+)?' + CYR + W + r'\s*\(\)')
DOLLAR_RE = re.compile(r'\$\{?_*' + CYR)
PS_HASH_RE = re.compile(r'[{;]\s*_*' + CYR + W + r'\s*=')
MAKE_RE = re.compile(r'^_*' + CYR + W + r'\s*(?::|[:?+!]?=)')
PARAM_CALL_RE = re.compile(r'[A-Za-z0-9_$\]>=]\s*\(|=>')
PARAM_RE = re.compile(r'[(,]\s*(?:[\w.\[\]<>*&?]+\s+)?[*&$]*_*' + CYR + W + r'\s*(?:[:,)=]|\s+[A-Za-z*\[][\w.\[\]*]*\s*[,)])')
ARROW_RE = re.compile(r'(^|[\s(,])_*' + CYR + W + r'\s*=>')
DESTRUCT_RE = re.compile(r'[{\[,]\s*[$*&]*_*' + CYR + W + r'\s*[,}\]=]')
DECOR_RE = re.compile(r'^\s*@_*' + CYR)
GENERIC_RE = re.compile(r'<\s*' + CYR)
CSS_SEL_RE = re.compile(r'(^|[\s,>+~(:])[#.]' + CYR + r'|--[\w-]*' + CYR)
PRIVATE_RE = re.compile(r'(^|[\s.;({,])#_*' + CYR + W + r'\s*(?:[=;(,)}.]|$)')
FIELD_RE = re.compile(r'^\s+_*' + CYR + W + r'\s+[A-Za-z*\[@]')
TYPE_DECL_RE = re.compile(r'^\s*(?:[A-Za-z_][\w<>\[\],?.]*\s+)+[*&$]*_*' + CYR + W + r'\s*[;=,)({]')
STRUCT_LIT_RE = re.compile(r'[A-Za-z0-9_\]>]\{\s*_*' + CYR + W + r'\s*:')
SYMBOL_RE = re.compile(r'(^|[\s(,\[]):_*' + CYR)
TOML_TABLE_RE = re.compile(r'^\s*\[\[?\s*[^\]]*' + CYR)
TEMPLATE_EXPR_RE = re.compile(r'\$\{\s*[\w$.]*' + CYR)
FSTRING_RE = re.compile(r'\b[rR]?[fF][rR]?["\']')
FSTRING_EXPR_RE = re.compile(r'(?<!\{)\{\s*[\w.]*' + CYR)
ROUTE_RE = re.compile(r'["\'`]/(?!/)[\w/:.{}<>*@$~-]*' + CYR)
DJANGO_PATH_RE = re.compile(r'\b(path|re_path|url)\(\s*r?["\'][^"\']*' + CYR)
GO_TAG_RE = re.compile(r'`[^`]*\b\w+:"[^"`]*' + CYR)
PRISMA_MAP_RE = re.compile(r'@@?map\(\s*"[^"]*' + CYR)
ATTR_ID_RE = re.compile(r'\b(id|class|className|for|name|slot)\s*=\s*["\'][^"\'<>]*' + CYR)
ATTR_NAME_RE = re.compile(r'\s(?:data-|aria-|v-|x-|hx-|ng-|:|@)?[\w-]*' + CYR + r'[\w-]*\s*=')
ATTR_URL_RE = re.compile(r'\b(href|src|action|to|routerLink|formaction)\s*=\s*["\'](?:/(?!/)|#|\.{0,2}/)[^"\']*' + CYR)
ATTR_CODE_RE = re.compile(r'(?:\s|^)(?:on\w+|@[\w.:-]+|v-[\w.:-]+|:[\w.-]+|x-[\w-]+|hx-[\w-]+|\*ng[A-Za-z]+|\[[\w.]+\]|\([\w.]+\)|formControlName|ng-[\w-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\')')
TEXT_LINE_RE = re.compile(r'^\s*(?:[А-ЯЁ][а-яё]|[А-ЯЁ]{2,}(?![а-яё\w])|[а-яё]+\s+[а-яё]|[а-яё]{1,2}\.|[«"“„+\d№•–—-])')
TEXT_TAIL_RE = re.compile(r'=|[,;{(]\s*$')
CYR_RE = re.compile(CYR)


def attr_code_hit(raw):
    for m in ATTR_CODE_RE.finditer(raw):
        val = m.group(1) if m.group(1) is not None else m.group(2)
        val = re.sub(r"'[^']*'|`[^`]*`|\"[^\"]*\"", '', val)
        if CYR_RE.search(val):
            return True
    return False


def is_text_line(s):
    return bool(TEXT_LINE_RE.match(s)) and not TEXT_TAIL_RE.search(s)


def cyrillic_problems(text, ext, leaf, i18n=False):
    problems = []
    if not text or not CYR_RE.search(text):
        return problems
    ext = (ext or '').lower()
    special = bool(SPECIAL_NAMES.match(leaf))
    orig_lines = text.split('\n')
    text = strip_multiline(text, ext, leaf)
    for i, raw in enumerate(text.split('\n'), 1):
        orig = orig_lines[i - 1] if i - 1 < len(orig_lines) else raw
        if not CYR_RE.search(raw) and not CYR_RE.search(orig):
            continue
        hit = False
        if ext == '.json':
            hit = bool(JSON_KEY_RE.search(raw)) and not i18n
        elif ext in ('.yaml', '.yml') or (special and leaf.lower().startswith(('compose', 'docker-compose'))):
            s = re.sub(r'(^|\s)#.*$', '', raw)
            hit = bool(YAML_ENVLIST_RE.search(s)) or (not i18n and bool(YAML_FLOW_RE.search(s)))
            if not hit and not i18n:
                if YAML_KEY_RE.search(s):
                    hit = not YAML_TEXTKEY_RE.search(s)
                elif YAML_QKEY_RE.search(s):
                    hit = True
        elif ext == '.env':
            hit = bool(ENV_LEFT_RE.search(raw))
        else:
            e = ext if not special else '.sh'
            shell = e in ('.sh', '.bash', '.ps1', '.conf') or special
            # код внутри строк: переменные оболочки/PHP, выражения шаблонных строк, маршруты, атрибуты
            pre = strip_comments_only(orig, e)
            if shell or e == '.php':
                q = strip_quotes_only(orig, e)
                if DOLLAR_RE.search(q) or (e in ('.ps1', '.php') and MEMBER_RE.search(q)):
                    hit = True
            if not hit and e in JS_LIKE and TEMPLATE_EXPR_RE.search(pre):
                hit = True
            if not hit and e == '.py' and FSTRING_RE.search(pre) and FSTRING_EXPR_RE.search(pre):
                hit = True
            if not hit and e not in CSS_LIKE and e != '.sql' and (ROUTE_RE.search(pre) or (e == '.py' and DJANGO_PATH_RE.search(pre))):
                hit = True
            if not hit and e == '.go' and GO_TAG_RE.search(pre):
                hit = True
            if not hit and e == '.prisma' and PRISMA_MAP_RE.search(pre):
                hit = True
            if not hit and ext in MARKUP and (ATTR_ID_RE.search(pre) or ATTR_URL_RE.search(pre) or attr_code_hit(pre)):
                hit = True
            if hit:
                problems.append(f'строка {i}: {orig.strip()}')
                continue
            if not CYR_RE.search(raw):
                continue
            s = strip_inline(raw, e)
            if not CYR_RE.search(s):
                continue
            if ext in MARKUP:
                if TAG_RE.search(s):
                    problems.append(f'строка {i}: {raw.strip()}')
                    continue
                s = strip_markup_text(s)
                if not CYR_RE.search(s):
                    continue
            if ATTR_NAME_RE.search(s) and ext in MARKUP:
                hit = True
            elif e == '.sql':
                hit = True
            elif shell:
                hit = bool(SHELL_VAR_RE.search(s) or DECL_RE.search(s) or CALL_RE.search(s))
                if not hit and special and leaf.lower() == 'makefile':
                    hit = bool(MAKE_RE.search(s))
                if not hit and e == '.ps1':
                    hit = bool(PS_HASH_RE.search(s))
            else:
                if e in ('.go', '.prisma') and FIELD_RE.search(s):
                    hit = True
                elif is_text_line(s):
                    continue
                hit = hit or bool(DECL_RE.search(s) or CALL_RE.search(s) or MEMBER_RE.search(s) or ASSIGN_RE.search(s)
                           or ARROW_RE.search(s) or DESTRUCT_RE.search(s) or DECOR_RE.search(s)
                           or (PARAM_CALL_RE.search(s) and PARAM_RE.search(s)))
                if not hit and e in C_LIKE and ext not in MARKUP and e not in CSS_LIKE:
                    hit = bool(GENERIC_RE.search(s))
                if not hit and e in C_LIKE:
                    hit = bool(STRUCT_LIT_RE.search(s))
                if not hit and e in CSS_LIKE:
                    hit = bool(CSS_SEL_RE.search(s))
                if not hit and e in JS_LIKE:
                    hit = bool(PRIVATE_RE.search(s))
                if not hit and e in TYPED:
                    hit = bool(TYPE_DECL_RE.search(s))
                if not hit and e == '.rb':
                    hit = bool(SYMBOL_RE.search(s))
                if not hit and e == '.toml':
                    hit = bool(TOML_TABLE_RE.search(s))
                if not hit and (KEY_RE.search(s) or (CODE_TAIL_RE.search(s) and KEY_ANY_RE.search(s))):
                    if ext in MARKUP:
                        after = s.split(':', 1)[1] if ':' in s else ''
                        hit = not CYR_RE.search(after)
                    else:
                        hit = True
        if hit:
            problems.append(f'строка {i}: {raw.strip()}')
    return problems


def file_ext(leaf):
    if re.match(r'^\.env(\..*)?$', leaf, re.I):
        return '.env'
    return os.path.splitext(leaf)[1].lower()


def cyrillic_report(path, text, root):
    p = path.replace('\\', '/')
    leaf = p.rsplit('/', 1)[-1]
    ext = file_ext(leaf)
    is_code = ext in CODE_EXT or bool(SPECIAL_NAMES.match(leaf))
    if not is_code and ext in DOC_EXT:
        return []
    problems = []
    if CYR_RE.search(leaf):
        problems.append('имя файла: ' + leaf)
    rel = rel_path(p, root)
    if rel:
        for part in rel.split('/')[:-1]:
            if CYR_RE.search(part):
                problems.append('папка: ' + part)
    if is_code:
        i18n = bool(I18N_PATH.search(rel or p))
        problems += cyrillic_problems(str(text or ''), ext, leaf, i18n)
    return problems


def guard_cyrillic(data):
    ti = data.get('tool_input') or {}
    path = str(ti.get('file_path') or '')
    if not path.strip():
        return
    text = ti.get('content')
    if text is None:
        text = ti.get('new_string')
    problems = cyrillic_report(path, text, project_dir(data))
    if problems:
        lines = ['Заблокировано: кириллица в идентификаторах или путях кода (' + path + ').']
        lines += ['  - ' + x for x in problems[:8]]
        lines.append('Имена файлов, папок, маршрутов, переменных, функций, ключей и заголовков — только латиница. '
                     'Русский текст — в строках, комментариях и тексте интерфейса. '
                     'Файл переводов с русскими ключами — положить в папку locales/ (или i18n/, lang/).')
        block(lines)


# --------------------------------------------------------- guard-instructions
INSTR_RE = re.compile(r'(^|/)(CLAUDE(\.local|\.starter)?\.md|AGENTS\.md|\.mcp\.json|\.claude\.json)$'
                      r'|(^|/)\.claude/(rules|skills|hooks|agents|output-styles|commands|plugins)/'
                      r'|(^|/)\.claude/settings[\w.]*\.json$', re.I)


# Защиты (разрешения и хуки) — вопрос при любом доверии: сам себе их Claude не отключает.
PROTECT_RE = re.compile(r'(^|/)\.claude/(hooks/|settings[\w.]*\.json$)|(^|/)\.claude\.json$', re.I)


def guard_instructions(data):
    path = str((data.get('tool_input') or {}).get('file_path') or '').replace('\\', '/')
    if not path or not INSTR_RE.search(path):
        return
    if PROTECT_RE.search(path):
        ask('Изменение защит набора — разрешений или хуков (' + path + '). Покажите владельцу, что меняется, '
            'и получите «да».')
    if not trust_full():
        ask('Изменение инструкций Claude (' + path + '). Покажите владельцу, что меняется, и получите «да».')


def pre_write(data):
    # Один процесс на Write/Edit: кириллица (блок) → инструкции (вопрос) → правила в контекст.
    guard_cyrillic(data)
    guard_instructions(data)
    rules_on_write(data)


# ------------------------------------------------------------ rules-on-write
def glob_to_re(pat):
    pat = pat.replace('\\', '/').lstrip('./')
    out, i = '', 0
    while i < len(pat):
        c = pat[i]
        if pat.startswith('**/', i):
            out += '(?:.*/)?'
            i += 3
        elif pat.startswith('**', i):
            out += '.*'
            i += 2
        elif c == '*':
            out += '[^/]*'
            i += 1
        elif c == '?':
            out += '[^/]'
            i += 1
        else:
            out += re.escape(c)
            i += 1
    return re.compile('^' + out + '$', re.I)


def expand_braces(pat):
    m = re.search(r'\{([^{}]*)\}', pat)
    if not m:
        return [pat]
    res = []
    for alt in m.group(1).split(','):
        res += expand_braces(pat[:m.start()] + alt + pat[m.end():])
    return res


def parse_rule(path):
    try:
        txt = open(path, encoding='utf-8-sig', errors='replace').read().replace('\r\n', '\n')
    except Exception:
        return None, None
    m = re.match(r'^---\n(.*?)\n---\n?(.*)$', txt, re.S)
    if not m:
        return None, txt
    fm, body = m.group(1), m.group(2)
    pm = re.search(r'^paths:\s*(.*?)(?=^\S|\Z)', fm, re.S | re.M)
    paths = []
    if pm:
        blockp = pm.group(1)
        inline = re.match(r'\s*\[(.*)\]', blockp)
        if inline:
            paths = [x.strip().strip('"\'') for x in inline.group(1).split(',') if x.strip()]
        else:
            paths = [x.strip().strip('"\'') for x in re.findall(r'^\s*-\s*(.+)$', blockp, re.M)]
    return paths, body


def rules_on_write(data):
    ti = data.get('tool_input') or {}
    path = str(ti.get('file_path') or '').replace('\\', '/')
    if not path:
        return
    root = project_dir(data)
    rel = rel_path(path, root)
    if not rel or rel.startswith(('.claude/', 'docs/')):
        return
    rules_dir = os.path.join(root, '.claude', 'rules')
    if not os.path.isdir(rules_dir):
        return
    sf = state_file(data, 'rules')
    try:
        done = set(json.load(open(sf, encoding='utf-8')))
    except Exception:
        done = set()
    inject = []
    for name in sorted(os.listdir(rules_dir)):
        if not name.endswith('.md') or name in done:
            continue
        paths, body = parse_rule(os.path.join(rules_dir, name))
        if not paths or not body:
            continue
        matched = False
        for pat in paths:
            for p in expand_braces(pat):
                if glob_to_re(p).match(rel):
                    matched = True
                    break
            if matched:
                break
        if matched:
            inject.append((name, body.strip()))
    if not inject:
        return
    done |= {n for n, _ in inject}
    try:
        json.dump(sorted(done), open(sf, 'w', encoding='utf-8'))
    except Exception:
        pass
    text = 'Правила проекта для этого файла (из .claude/rules — соблюдать при записи):\n\n' + \
           '\n\n'.join(f'### {n}\n{b}' for n, b in inject)
    out_json({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": text}})


# -------------------------------------------------------------- check-python
def find_python():
    for cand in (['python3'], ['python'], ['py', '-3']):
        try:
            r = subprocess.run(cand + ['-c', 'import sys;print(sys.version_info[0])'], capture_output=True, timeout=10)
            if r.returncode == 0 and r.stdout.decode().strip() == '3':
                return cand
        except Exception:
            continue
    return [sys.executable] if sys.executable else None


def check_python(data):
    path = str((data.get('tool_input') or {}).get('file_path') or '')
    if not path.lower().endswith('.py') or not os.path.isfile(path):
        return
    py = find_python()
    if not py:
        return
    r = subprocess.run(py + ['-c', 'import ast,sys; ast.parse(open(sys.argv[1],"rb").read(), sys.argv[1])', path],
                       capture_output=True, timeout=30)
    if r.returncode != 0:
        block(['Синтаксическая ошибка Python в ' + path + ' :', r.stderr.decode('utf-8', 'replace').strip(),
               'Исправь до запуска и отправки.'])


# ---------------------------------------------------- turn-start / check-docs
def git_status_map(root):
    out = git(root, 'status', '--porcelain', '--untracked-files=all')
    if out is None:
        return None
    res = {}
    for ln in out.splitlines():
        if len(ln) < 4:
            continue
        st, f = ln[:2], ln[3:].strip().strip('"')
        if ' -> ' in f:
            f = f.split(' -> ')[-1]
        f = f.replace('\\', '/')
        full = os.path.join(root, f)
        try:
            stt = os.stat(full)
            sig = f'{stt.st_mtime_ns}:{stt.st_size}'
        except Exception:
            sig = 'gone'
        res[f] = (st.strip(), sig)
    return res


def turn_start(data):
    root = project_dir(data)
    snap = {'ts': time.time(), 'head': None, 'status': {}}
    head = git(root, 'rev-parse', 'HEAD')
    if head is not None:
        snap['head'] = head.strip()
        top = (git(root, 'rev-parse', '--show-toplevel') or root).strip() or root
        st = git_status_map(top) or {}
        snap['status'] = {k: v[1] for k, v in st.items()}
    try:
        with open(state_file(data, 'turn'), 'w', encoding='utf-8') as fh:
            json.dump(snap, fh)
    except Exception:
        pass
    prompt = str(data.get('prompt') or '').strip()
    if prompt.startswith('/') or len(prompt) < 12:
        return
    sys.stdout.write('Набор: сверь запрос с «Что запускать» в CLAUDE.md; первая строка ответа — «режим — итог». '
                     'Изменил код — сам, молча, в том же шаге: шапка файла и docs/ai.\n')


def check_docs(data):
    if data.get('stop_hook_active') is True:
        return
    root = project_dir(data)
    head = git(root, 'rev-parse', 'HEAD')
    if head is None:
        return
    top = (git(root, 'rev-parse', '--show-toplevel') or root).strip() or root
    head = head.strip()
    try:
        snap = json.load(open(state_file(data, 'turn'), encoding='utf-8'))
    except Exception:
        snap = None
    now = git_status_map(top) or {}
    touched = set()
    if snap and snap.get('head'):
        prev = snap.get('status') or {}
        for f, (st, sig) in now.items():
            if prev.get(f) != sig:
                touched.add(f)
        if snap['head'] != head:
            diff = git(top, 'diff', '--name-only', '--diff-filter=AMR', snap['head'], head) or ''
            touched |= {x.strip().replace('\\', '/') for x in diff.splitlines() if x.strip()}
    else:
        cutoff = time.time() - 1800
        for f, (st, sig) in now.items():
            try:
                if os.stat(os.path.join(top, f)).st_mtime >= cutoff:
                    touched.add(f)
            except Exception:
                pass
    deleted = {f for f, (st, sig) in now.items() if 'D' in st}
    code, docs = [], False
    for f in sorted(touched):
        if f in deleted:
            continue
        if re.search(r'(^|/)docs/ai/([^/]+\.md$|(specs|solutions)/)', f) or re.search(r'(^|/)CLAUDE(\.local)?\.md$', f) or '/.claude/rules/' in ('/' + f):
            docs = True
            continue
        ext = os.path.splitext(f)[1].lower()
        if ext in HEADER_EXT and not GENERATED.search(f):
            code.append(f)
    doc_msgs = doc_problems(root, top, touched - deleted)
    if not code:
        if doc_msgs:
            block(['Перед завершением: ' + ' '.join(doc_msgs)])
        if touched:
            stamp_state(root, top)
        return
    no_header = []
    for f in code:
        full = os.path.join(top, f)
        if not os.path.isfile(full):
            continue
        try:
            with open(full, encoding='utf-8-sig', errors='replace') as fh:
                head15 = [fh.readline(2000) for _ in range(15)]
        except Exception:
            continue
        if not re.search(r'назначение:', '\n'.join(head15), re.I):
            no_header.append(f)
    msgs = list(doc_msgs)
    if not docs:
        msgs.append(f'В этом ходе изменён код ({len(code)} файл.), а docs/ai не обновлены. Обнови сейчас: STATE.md '
                    '(что сделано, следующий шаг) и по необходимости KNOWLEDGE / PROJECT_MAP / FOUNDATION / SPEC / '
                    'DECISIONS / TOOLS / LESSONS. Если обновлять нечего — просто заверши ответ, владельцу об этом не писать.')
    if no_header:
        msgs.append("Нет строки 'Назначение:' в начале файлов: " + ', '.join(no_header[:10]) +
                    '. Добавь шапку (правило .claude/rules/code-headers.md).')
    if msgs:
        block(['Перед завершением: ' + ' '.join(msgs)])
    stamp_state(root, top)


# Лимиты строк: подключённые всегда документы — жёстче, остальные — 300.
DOC_LIMITS = {'PROFILE.md': 40, 'STATE.md': 60, 'KNOWLEDGE.md': 80, 'LESSONS.md': 40, 'INDEX.md': 60}
DOC_LIMIT_DEFAULT = 300


def doc_problems(root, top, touched):
    # Документы docs/ai, изменённые в этом ходе: не переполнены и записаны в INDEX.md.
    try:
        index = open(os.path.join(root, 'docs', 'ai', 'INDEX.md'), encoding='utf-8-sig').read()
    except Exception:
        index = None
    over, unreg = [], []
    for f in sorted(touched):
        m = re.search(r'(^|/)docs/ai/([^/]+\.md)$', f)
        if not m:
            continue
        name = m.group(2)
        try:
            txt = open(os.path.join(top, f), encoding='utf-8-sig', errors='replace').read()
            n = txt.count('\n') + (0 if (not txt or txt.endswith('\n')) else 1)
        except Exception:
            continue
        limit = DOC_LIMITS.get(name, DOC_LIMIT_DEFAULT)
        if n > limit:
            over.append(f'{name} ({n} строк, предел {limit})')
        if index is not None and name not in DOC_LIMITS and name not in index:
            unreg.append(name)
    msgs = []
    if over:
        msgs.append('Документ переполнен: ' + ', '.join(over) + '. Раздели молча: отдельная тема — в свой '
                    'docs/ai/<ТЕМА>.md; продолжение той же темы — в <ИМЯ>_2.md, <ИМЯ>_3.md; из STATE/KNOWLEDGE/'
                    'LESSONS — старое и крупные темы вынести. В docs/ai/INDEX.md у каждой части: какие данные в ней.')
    if unreg:
        msgs.append('Документ не записан в docs/ai/INDEX.md: ' + ', '.join(unreg) + '. Добавь строку: файл · какие '
                    'данные в нём · когда читать.')
    return msgs


STAMP_RE = re.compile(r'(обновлено:\s*)([^,)\n]*)(,\s*head:\s*)([^)\n]*)(\))')


def stamp_state(root, top):
    # Техническая часть STATE.md (дата и коммит) — хуком, без участия Claude.
    p = os.path.join(root, 'docs', 'ai', 'STATE.md')
    try:
        raw = open(p, 'rb').read()
        bom = raw.startswith(b'\xef\xbb\xbf')
        txt = raw.decode('utf-8-sig')
        m = STAMP_RE.search(txt)
        if not m or 'TODO' in m.group(0):
            return
        head = (git(top, 'rev-parse', '--short', 'HEAD') or '').strip()
        new = m.group(1) + time.strftime('%Y-%m-%d') + m.group(3) + (head or m.group(4)) + m.group(5)
        if new == m.group(0):
            return
        txt = txt[:m.start()] + new + txt[m.end():]
        open(p, 'wb').write((b'\xef\xbb\xbf' if bom else b'') + txt.encode('utf-8'))
    except Exception:
        pass


# ------------------------------------------------------------- session-start
def same_commit(a, b):
    a, b = (a or '').strip().lower(), (b or '').strip().lower()
    return bool(a and b) and (a.startswith(b) or b.startswith(a))


def state_head_ok(root, rec):
    # STATE пишут до коммита, поэтому записанный head = HEAD или HEAD~1 — норма.
    if same_commit(rec, git(root, 'rev-parse', 'HEAD')):
        return True
    return same_commit(rec, git(root, 'rev-parse', 'HEAD~1'))


def cleanup_state(data):
    try:
        base = state_dir(data)
        old = time.time() - 7 * 86400
        for f in os.listdir(base):
            if f.startswith('starter-') and f.endswith('.json'):
                full = os.path.join(base, f)
                if os.path.getmtime(full) < old:
                    os.remove(full)
    except Exception:
        pass


def session_start(data):
    root = project_dir(data)
    src = str(data.get('source') or '')
    lines = ['[claude-starter] Старт сеанса' + (f' ({src})' if src else '') + '.']
    state_path = os.path.join(root, 'docs', 'ai', 'STATE.md')
    cleanup_state(data)
    if os.path.isfile(os.path.join(root, 'INSTALL.md')) and os.path.isfile(os.path.join(root, 'VERSION')):
        lines.append(f'Это исходник набора claude-starter (версия {read_version(root)}), не проект: не устанавливать '
                     'и не заполнять docs/ai. Работа здесь — /kit-harvest (уроки из проектов), выпуск версий.')
    head = git(root, 'rev-parse', '--short', 'HEAD')
    inside = (git(root, 'rev-parse', '--is-inside-work-tree') or '').strip() == 'true'
    if head is not None:
        branch = (git(root, 'rev-parse', '--abbrev-ref', 'HEAD') or '').strip()
        st = git(root, 'status', '--porcelain') or ''
        n = len([x for x in st.splitlines() if x.strip()])
        lines.append(f'git: ветка {branch}, HEAD {head.strip()}, незакоммиченных файлов: {n}.')
    elif inside:
        lines.append('git: репозиторий без коммитов — сделать первый коммит (после .gitignore).')
    else:
        lines.append('git: не репозиторий — без истории откат невозможен; предложить git init.')
    if os.path.isfile(state_path):
        try:
            txt = open(state_path, encoding='utf-8', errors='replace').read()
        except Exception:
            txt = ''
        m = re.search(r'head:\s*([0-9a-f]{7,40})', txt, re.I)
        if m and head is not None and not state_head_ok(root, m.group(1).lower()):
            lines.append(f'⚠ STATE.md записан на коммите {m.group(1)[:7]}, а сейчас {head.strip()} — сначала сверить с git log.')
        body = [ln.rstrip() for ln in txt.splitlines() if ln.strip() and not ln.strip().startswith('<!--')]
        keep = []
        for ln in body:
            if ln.startswith('## ') and keep:
                break
            keep.append(ln)
        keep = keep[:8]
        if keep:
            lines.append('STATE.md: ' + keep[0])
            lines += ['  ' + x for x in keep[1:]]
        if 'TODO' in txt[:400]:
            lines.append('STATE.md ещё не заполнен — набор не инициализирован: предложить владельцу /kit-setup.')
    else:
        lines.append('docs/ai/STATE.md нет — набор не инициализирован: предложить владельцу /kit-setup.')
    note = update_notice(root)
    if note:
        lines.append(note)
    lines.append('Дальше: сверить запрос с «Что запускать» (CLAUDE.md); подробности состояния — в docs/ai/STATE.md.')
    sys.stdout.write('\n'.join(lines) + '\n')


# ------------------------------------------------------------- версия набора
# Файлы набора (без документов проекта и сливаемых файлов) и их отпечатки — в .claude/starter.json.
KIT_SKIP_TOP = {'.git', 'docs', 'inbox', 'README.md', 'INSTALL.md', 'CLAUDE.md', '.mcp.json', 'VERSION', 'CHANGELOG.md'}
KIT_SKIP_REL = {'.claude/settings.json', '.claude/settings.unix.json', '.claude/starter.json'}


def file_hash(path):
    import hashlib
    with open(path, 'rb') as fh:
        return hashlib.sha256(fh.read().replace(b'\r\n', b'\n')).hexdigest()[:16]


def kit_files(kit):
    res = []
    for d, dirs, fs in os.walk(kit):
        rel_d = os.path.relpath(d, kit).replace('\\', '/')
        dirs[:] = [x for x in dirs if x != '__pycache__' and not (rel_d == '.' and x in KIT_SKIP_TOP)]
        for f in fs:
            rel = f if rel_d == '.' else rel_d + '/' + f
            if (rel_d == '.' and f in KIT_SKIP_TOP) or rel in KIT_SKIP_REL:
                continue
            res.append(rel)
    return sorted(res)


def read_version(kit):
    try:
        return open(os.path.join(kit, 'VERSION'), encoding='utf-8-sig').read().strip()
    except Exception:
        return ''


def ver_tuple(v):
    return tuple(int(x) for x in re.findall(r'\d+', v or '')[:3]) or (0,)


def manifest_path(root):
    return os.path.join(root, '.claude', 'starter.json')


def write_manifest(kit, source, root):
    files = {}
    for rel in kit_files(kit):
        p = os.path.join(root, rel)
        if os.path.isfile(p):
            files[rel] = file_hash(p)
    data = {'version': read_version(kit), 'source': source, 'installed': time.strftime('%Y-%m-%d'), 'files': files}
    with open(manifest_path(root), 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, indent=1, sort_keys=True)
    sys.stdout.write(f'Записано: .claude/starter.json — версия {data["version"]}, файлов набора: {len(files)}.\n')


def update_plan(kit, root):
    try:
        man = json.load(open(manifest_path(root), encoding='utf-8-sig'))
    except Exception:
        man = {}
    old = man.get('files') or {}
    new_files = kit_files(kit)
    rows = []
    for rel in new_files:
        dst = os.path.join(root, rel)
        if not os.path.isfile(dst):
            rows.append(('добавить', rel))
            continue
        cur = file_hash(dst)
        if cur == file_hash(os.path.join(kit, rel)):
            continue
        rows.append(('заменить', rel) if old.get(rel) == cur else ('изменён владельцем — показать разницу и спросить', rel))
    for rel in sorted(old):
        dst = os.path.join(root, rel)
        if rel not in new_files and os.path.isfile(dst):
            rows.append(('удалить (нет в новой версии)', rel) if old[rel] == file_hash(dst)
                        else ('нет в новой версии, изменён владельцем — спросить', rel))
    sys.stdout.write(f'Версия: в проекте {man.get("version") or "?"}, новая {read_version(kit) or "?"}.\n')
    for action, rel in rows:
        sys.stdout.write(f'{action}: {rel}\n')
    sys.stdout.write(f'Действий с файлами набора: {len(rows)}. CLAUDE.md, settings.json, .mcp.json — сверить вручную.\n')


def fetch_remote_version(src):
    if os.path.isdir(src):
        return read_version(src)
    m = re.match(r'https?://github\.com/([^/\s]+)/([^/\s#?]+?)(?:\.git)?/?$', src)
    if not m:
        return ''
    url = f'https://raw.githubusercontent.com/{m.group(1)}/{m.group(2)}/HEAD/VERSION'
    try:
        import urllib.request
        with urllib.request.urlopen(url, timeout=3) as r:
            return r.read(64).decode('utf-8', 'replace').strip()
    except Exception:
        return ''


def update_notice(root):
    # Раз в сутки: версия набора в источнике новее установленной → строка для Claude.
    if os.environ.get('KIT_NO_UPDATE_CHECK'):
        return ''
    try:
        man = json.load(open(manifest_path(root), encoding='utf-8-sig'))
    except Exception:
        return ''
    local, src = str(man.get('version') or ''), str(man.get('source') or '')
    if not local or not src:
        return ''
    cache = os.path.join(tempfile.gettempdir(), 'claude-starter', 'starter-update-check.json')
    remote = None
    try:
        c = json.load(open(cache, encoding='utf-8'))
        if c.get('source') == src and time.time() - float(c.get('ts', 0)) < 86400:
            remote = c.get('version')
    except Exception:
        pass
    if remote is None:
        remote = fetch_remote_version(src)
        try:
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            with open(cache, 'w', encoding='utf-8') as fh:
                json.dump({'source': src, 'ts': time.time(), 'version': remote}, fh)
        except Exception:
            pass
    if remote and ver_tuple(remote) > ver_tuple(local):
        return (f'Вышла новая версия набора: {remote} (в проекте {local}). Предложить владельцу обновить '
                '(скилл kit-update).')
    return ''


SCAN_SKIP = {'.git', 'node_modules', '.venv', 'venv', '__pycache__', 'dist', 'build', '.next', 'vendor', 'target'}


def scan(paths, root):
    # Проверка без записи: как guard-cyrillic, но по файлам с диска. Для /kit-audit.
    files = []
    for a in paths:
        if os.path.isdir(a):
            for d, dirs, fs in os.walk(a):
                dirs[:] = [x for x in dirs if x not in SCAN_SKIP]
                files += [os.path.join(d, f) for f in fs]
        elif os.path.isfile(a):
            files.append(a)
    total, bad = 0, 0
    for f in sorted(files):
        try:
            if os.path.getsize(f) > 1_000_000:
                continue
            text = open(f, encoding='utf-8-sig', errors='replace').read().replace('\r\n', '\n')
        except Exception:
            continue
        total += 1
        probs = cyrillic_report(os.path.abspath(f), text, root)
        if probs:
            bad += 1
            sys.stdout.write(f'{os.path.relpath(f, root)}: {len(probs)} — ' + '; '.join(probs[:3]) + '\n')
    sys.stdout.write(f'Проверено файлов: {total}, с замечаниями: {bad}.\n')


COMMANDS = {
    'guard-shell': guard_shell, 'guard-cyrillic': guard_cyrillic, 'guard-instructions': guard_instructions,
    'rules-on-write': rules_on_write, 'check-python': check_python, 'turn-start': turn_start,
    'session-start': session_start, 'check-docs': check_docs, 'pre-write': pre_write,
}

if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    here = os.path.abspath(os.environ.get('CLAUDE_PROJECT_DIR') or os.getcwd())
    if cmd == 'scan':
        scan(sys.argv[2:] or ['.'], here)
        sys.exit(0)
    if cmd == 'manifest' and len(sys.argv) >= 3:
        write_manifest(os.path.abspath(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else '', here)
        sys.exit(0)
    if cmd == 'update-plan' and len(sys.argv) >= 3:
        update_plan(os.path.abspath(sys.argv[2]), here)
        sys.exit(0)
    fn = COMMANDS.get(cmd)
    if not fn:
        sys.exit(0)
    try:
        fn(read_input())
    except SystemExit:
        raise
    except Exception as e:  # хук не должен ломать работу: молча пропускаем
        sys.exit(0)
