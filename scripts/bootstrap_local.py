#!/usr/bin/env python3
"""Configure files with stdlib; initialize and serve the private app in Docker."""
from __future__ import annotations

import argparse
import asyncio
import html
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import plistlib
import re
import secrets
import sys
import tempfile
import uuid
from urllib.parse import quote
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
REQUIRED_INTEGRATIONS = (
    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY", "AWS_S3_BUCKET", "SLACK_BOT_TOKEN",
    "MARKETING_HUB_API_KEY",
    "GA4_CREDENTIALS_PRIVATE_KEY_B64", "GA4_CREDENTIALS_KEY_ID",
    "GA4_CREDENTIALS_SERVICE_TOKEN",
)
DEFAULT_MARKETING_HUB_BASE_URL = "https://100.55.149.93.nip.io"
LOCAL_ADMIN_EMAIL = "admin@example.com"


def validate_credentials(values: dict[str, str]) -> dict[str, str]:
    missing = [key for key in REQUIRED_INTEGRATIONS
               if not values.get(key) or values[key] == "local-demo-disabled"]
    for prefix in ("MERCHANT", "JOBBER"):
        if values.get(f"{prefix}_MCP_ENABLED", "false").lower() in {"true", "1", "yes", "on"}:
            if not values.get(f"{prefix}_MCP_URL"):
                missing.append(f"{prefix}_MCP_URL")
            if values.get(f"{prefix}_MCP_AUTH_REQUIRED", "false").lower() in {"true", "1", "yes", "on"}:
                # The Jobber client uses the shared Merchant transport token.
                if not values.get("MERCHANT_MCP_AUTH_TOKEN"):
                    missing.append("MERCHANT_MCP_AUTH_TOKEN")
    if values.get("GITHUB_MCP_ENABLED", "false").lower() in {"true", "1", "yes", "on"}:
        missing.extend(key for key in ("GITHUB_CREDENTIALS_PRIVATE_KEY_B64", "GITHUB_CREDENTIALS_KEY_ID",
                                       "GITHUB_CREDENTIALS_SERVICE_TOKEN") if not values.get(key))
    if missing:
        raise ValueError("Credenciais incompletas no segredo AWS ou em .local/integrations.override.env: "
                         + ", ".join(sorted(set(missing))))
    hub = urlparse(values.get("MARKETING_HUB_BASE_URL") or DEFAULT_MARKETING_HUB_BASE_URL)
    if hub.scheme != "https" or not hub.hostname or hub.username or hub.password or hub.query or hub.fragment:
        raise ValueError("MARKETING_HUB_BASE_URL deve ser um endereco HTTPS sem credenciais, query ou fragmento.")
    return values


def import_secret(root: Path, raw: str, require_complete: bool = False) -> None:
    """Consume AWS JSON over stdin; never log or save the raw secret response."""
    if require_complete:
        marker = "\nINSIGHTS_SECRET_COMPLETE\n"
        if not raw.endswith(marker):
            raise ValueError("A consulta AWS nao terminou com sucesso. Configuracao anterior preservada.")
        raw = raw[:-len(marker)]
    try:
        values = json.loads(raw.lstrip("\ufeff"))
        if isinstance(values, str):
            values = json.loads(values)
    except (ValueError, TypeError):
        raise ValueError("Nao foi possivel ler o segredo AWS como JSON. Nenhum valor foi exibido.") from None
    if not isinstance(values, dict) or not values:
        raise ValueError("O segredo AWS deve conter um objeto JSON nao vazio.")
    for key, value in values.items():
        if not re.fullmatch(r"[A-Z_][A-Z_0-9]*", key) or not isinstance(value, str):
            raise ValueError("O segredo deve conter nomes de variaveis validos e valores de texto.")
        if key == "GOOGLE_SHEETS_PRIVATE_KEY":
            values[key] = value.replace("\r\n", "\n").replace("\n", "\\n")
    overrides = read_env(root / ".local" / "integrations.override.env")
    validate_credentials({**values, **overrides})
    content = env_text(values)
    private_write(root / ".local" / "integrations.env", content)
    print("Credenciais obtidas da AWS e salvas com acesso restrito. Valores nao exibidos.")


def read_env(path: Path) -> dict[str, str]:
    """Parse literal dotenv values without eval, shell execution or expansion."""
    if not path.exists():
        return {}
    result = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if not separator or not re.fullmatch(r"[A-Z_][A-Z_0-9]*", key):
            raise ValueError(f"{path.name}: linha {number} invalida.")
        if value.startswith(("'", '"')):
            if len(value) < 2 or value[-1] != value[0]:
                raise ValueError(f"{path.name}: aspas incompletas na linha {number}.")
            quote = value[0]
            value = value[1:-1].replace("\\" + quote, quote)
        result[key] = value
    return result


def env_text(values: dict[str, str]) -> str:
    lines = []
    for key, value in values.items():
        value = str(value)
        if "\n" in value or "\r" in value or "\x00" in value:
            raise ValueError(f"{key}: use um valor em uma unica linha.")
        quoted = value.replace("'", "\\'")
        lines.append(f"{key}='{quoted}'")
    return "\n".join(lines) + "\n"


def private_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
        os.chmod(name, 0o600)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def codex_shortcuts(host_root: str, host_platform: str) -> dict[str, str]:
    """Use the host path, never the Docker mount path, for desktop deep links."""
    if host_platform not in {"macos", "linux", "windows"}:
        raise ValueError("Sistema dos atalhos Codex invalido.")
    if not host_root or any(char in host_root for char in ("\n", "\r", "\x00")):
        raise ValueError("Pasta do host invalida para os atalhos Codex.")
    host = PureWindowsPath(host_root) if host_platform == "windows" else PurePosixPath(host_root)
    if not host.is_absolute():
        raise ValueError("Atalhos Codex exigem uma pasta absoluta do host.")
    projects = {}
    files = {}
    cards = []
    for name, label in (("frontend", "Frontend Insights"), ("backend", "Backend Insights")):
        path = str(host / "sources" / name)
        url = "codex://new?path=" + quote(path, safe="")
        projects[name] = {"path": path, "url": url}
        # A single-line URL lets the OS launchers read it without host Python.
        files[f"codex/{name}.link"] = url + "\n"
        if host_platform == "macos":
            files[f"codex/{name}.webloc"] = plistlib.dumps({"URL": url}).decode("utf-8")
        elif host_platform == "windows":
            files[f"codex/{name}.url"] = f"[InternetShortcut]\r\nURL={url}\r\n"
        cards.append(
            f'<li><a href="{html.escape(url, quote=True)}">Abrir {label} no Codex</a>'
            f'<p><code>{html.escape(path)}</code></p></li>'
        )
    files["codex-projects.json"] = json.dumps(projects, ensure_ascii=False, indent=2) + "\n"
    files["codex-projects.html"] = """<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Avanti Insights no Codex</title>
<style>body{font:18px system-ui;max-width:760px;margin:48px auto;padding:0 24px;line-height:1.6}
li{margin:24px 0}code{overflow-wrap:anywhere;font-size:14px}a{font-weight:600}</style>
</head><body><h1>Avanti Insights no Codex</h1>
<p>Os links abrem uma conversa no Codex usando a pasta local de cada aplicativo.
O navegador pode pedir confirmacao para abrir o aplicativo.</p><ul>""" + "".join(cards) + """</ul>
<p>Confira se as pastas aparecem como projetos na barra lateral. Se ainda nao
aparecerem, use Criar projeto e selecione a pasta correspondente indicada acima.
A abertura da conversa nao garante o cadastro permanente do projeto.</p>
</body></html>
"""
    return files


def configure(root: Path, port: int | None = None, api_port: int | None = None,
              host_root: str | None = None, host_platform: str | None = None) -> dict:
    local = root / ".local"
    platform = host_platform or ("windows" if os.name == "nt" else "macos" if sys.platform == "darwin" else "linux")
    shortcuts = codex_shortcuts(host_root or str(root.resolve()), platform)
    previous = json.loads((local / "settings.json").read_text()) if (local / "settings.json").exists() else {}
    selected_mode = "connected"
    web_port = port if port is not None else previous.get("port", 3000)
    backend_port = api_port if api_port is not None else previous.get("api_port", 8000)
    if not all(isinstance(v, int) and 1024 <= v <= 65535 for v in (web_port, backend_port)):
        raise ValueError("Portas devem estar entre 1024 e 65535.")
    if web_port == backend_port:
        raise ValueError("Front-end e API precisam de portas diferentes.")

    credentials = validate_credentials({**read_env(local / "integrations.env"),
                                        **read_env(local / "integrations.override.env")})

    lock = read_env(root / "sources.lock")
    for key in ("BACKEND_REF", "FRONTEND_REF"):
        if not re.fullmatch(r"[0-9a-f]{40}", lock.get(key, "")):
            raise ValueError(f"sources.lock: {key} deve ser um SHA completo.")
    stored = json.loads((local / "secrets.json").read_text()) if (local / "secrets.json").exists() else {}
    for key in ("db_password", "secret_key", "refresh_pepper", "api_token", "health_token", "admin_password"):
        stored.setdefault(key, secrets.token_urlsafe(32))
    if stored["secret_key"] == stored["refresh_pepper"]:
        raise ValueError("Chaves de sessao devem ser distintas.")

    app_url = f"http://localhost:{web_port}"
    backend = {
        **{key: value for key, value in credentials.items() if value},
        "LOCAL_MODE": selected_mode,
        "LOCAL_ADMIN_EMAIL": LOCAL_ADMIN_EMAIL,
        "LOCAL_ADMIN_PASSWORD": stored["admin_password"],
        "API_TOKEN": stored["api_token"],
        "HEALTHCHECK_TOKEN": stored["health_token"],
        "SECRET_KEY": stored["secret_key"],
        "REFRESH_TOKEN_PEPPER": stored["refresh_pepper"],
        "REFRESH_COOKIE_SECURE": "false",
        "DEBUG_MODE": "true",
        "DATABASE_SSL_MODE": "disable",
        "DATABASE_URL": f"postgresql+asyncpg://postgres:{stored['db_password']}@db:5432/avanti_insights",
        "POSTGRES_PASSWORD": stored["db_password"],
        "CELERY_BROKER_URL": "redis://redis:6379/0",
        "CELERY_RESULT_BACKEND": "redis://redis:6379/0",
        "FRONTEND_URL": app_url,
        "CORS_ORIGINS": f"{app_url},http://127.0.0.1:{web_port}",
        "OPENAI_MODEL": credentials.get("OPENAI_MODEL") or "gpt-5.4-mini",
        "AWS_REGION": credentials.get("AWS_REGION") or "us-east-1",
        "MARKETING_HUB_BASE_URL": credentials.get("MARKETING_HUB_BASE_URL") or DEFAULT_MARKETING_HUB_BASE_URL,
        "MARKETING_HUB_VERIFY_SSL": "true",
        "GA4_ADC_RUNTIME_DIR": "/run/ga4-credentials",
        "MERCHANT_MCP_ENABLED": credentials.get("MERCHANT_MCP_ENABLED") or "false",
        "JOBBER_MCP_ENABLED": credentials.get("JOBBER_MCP_ENABLED") or "false",
        "GITHUB_MCP_ENABLED": credentials.get("GITHUB_MCP_ENABLED") or "false",
    }
    frontend = {
        **{
            key: value for key, value in credentials.items()
            if value and (key in {"ENABLE_LOGGING", "ENABLE_PIPELINE_TIMING"} or key.startswith((
                "OPENAI_", "ANTHROPIC_", "GOOGLE_", "SHEETS_", "RAG_",
                "CRO_", "JIRA_", "MAIL_", "RESEND_", "GEMINI_",
            )))
        },
        "NODE_ENV": "development",
        "NEXT_PUBLIC_APP_URL": app_url,
        "NEXT_PUBLIC_API_URL": f"http://localhost:{backend_port}",
        "BACKEND_API_URL": "http://api:8000",
        "EXTERNAL_BACKEND_URL": "http://api:8000",
        "CRO_DASHBOARD_BACKEND_URL": "http://api:8000",
        "BACKEND_API_BEARER_TOKEN": stored["api_token"],
        "CRO_DASHBOARD_BACKEND_BEARER_TOKEN": stored["api_token"],
        "ALLOWED_ORIGINS": app_url,
        "ALLOW_INSECURE_AUTH_COOKIES": "true",
    }
    compose = {
        "LOCAL_MODE": selected_mode,
        "LOCAL_WEB_PORT": str(web_port),
        "LOCAL_API_PORT": str(backend_port),
        "LOCAL_DB_PASSWORD": stored["db_password"],
        "LOCAL_BACKEND_REF": lock["BACKEND_REF"],
        "LOCAL_FRONTEND_REF": lock["FRONTEND_REF"],
    }
    settings = {"mode": selected_mode, "port": web_port, "api_port": backend_port}
    # All values are validated before replacing any previously working file.
    contents = {
        **shortcuts,
        "backend.env": env_text(backend),
        "frontend.env": env_text(frontend),
        "compose.env": env_text(compose),
        "secrets.json": json.dumps(stored, indent=2) + "\n",
        "settings.json": json.dumps(settings, indent=2) + "\n",
        "nginx.conf": (root / "templates" / "nginx.conf").read_text(),
        "access.txt": (
            f"Modo: {selected_mode}\nInterface: {app_url}\n"
            f"Usuario: {LOCAL_ADMIN_EMAIL}\nSenha: {stored['admin_password']}\n\n"
            "Contas sinteticas do Review App usam a mesma senha. Consulte a lista em "
            "sources/backend/scripts/seed_review_app.py.\n"
        ),
    }
    for name, content in contents.items():
        private_write(local / name, content)
    print(f"Configuracao local pronta. Modo: {selected_mode}. Acesso salvo em .local/access.txt.")
    return settings


async def seed_database() -> None:
    # Imports are delayed so configure works in a plain Python image.
    from fastapi_users.password import PasswordHelper
    from sqlalchemy import select, update
    from app.core.db import AsyncSessionLocal, connect_db, engine
    from app.models.models import (
        Customer, Goal, Role, ScheduledTask, User, UserGroup,
        UserGroupGoalAccess, UserPreference, UserRole, UserRoleLink,
    )
    from scripts.seed_goals import seed as seed_goals
    from scripts.seed_permissions import seed as seed_permissions
    try:
        from scripts.seed_review_app import seed_review_app, stable_id as review_seed_id
    except ModuleNotFoundError as exc:
        if exc.name != "scripts.seed_review_app":
            raise
        seed_review_app = None
        review_seed_id = None
        print("Seeder do Review App ausente neste checkout existente do backend; banco mantido sem fixtures sintéticas.")

    if os.environ.get("DEBUG_MODE") != "true" or "@db:5432/avanti_insights" not in os.environ.get("DATABASE_URL", ""):
        raise RuntimeError("Bootstrap permitido apenas no banco desta stack local.")
    password = os.environ.get("LOCAL_ADMIN_PASSWORD", "")
    if len(password) < 12:
        raise RuntimeError("Senha local deve ter pelo menos 12 caracteres.")
    await connect_db()
    review_seed_exists = True
    if seed_review_app is not None:
        async with AsyncSessionLocal() as db:
            review_seed_exists = await db.get(Customer, review_seed_id("customer", "northstar")) is not None
    await seed_goals()
    await seed_permissions()
    namespace = uuid.UUID("fd920d66-248b-4f0c-9fbd-7936547c0a26")

    def ident(key: str) -> str:
        return str(uuid.uuid5(namespace, key))

    async with AsyncSessionLocal() as db:
        group = await db.get(UserGroup, ident("group"))
        if group is None:
            group = UserGroup(id=ident("group"), name="Administradores locais", description="Ambiente local independente.")
            db.add(group)
            await db.flush()
        user = await db.scalar(select(User).where(User.email == LOCAL_ADMIN_EMAIL))
        if user is None:
            user = User(
                id=ident("admin"), email=LOCAL_ADMIN_EMAIL, name="Administrador local",
                hashed_password=PasswordHelper().hash(password), role=UserRole.SUPER_ADMIN,
                is_active=True, is_superuser=True, is_verified=True,
                emailVerified=True, groupId=group.id,
            )
            db.add(user)
            await db.flush()
        role = await db.scalar(select(Role).where(Role.name == "super_admin"))
        if role is None:
            raise RuntimeError("Seed de permissoes nao criou super_admin.")
        if await db.get(UserRoleLink, (user.id, role.id)) is None:
            db.add(UserRoleLink(userId=user.id, roleId=role.id))
        if await db.scalar(select(UserPreference).where(UserPreference.userId == user.id)) is None:
            db.add(UserPreference(userId=user.id, wantsSlackNotifications=False, wantsEmailNotifications=False))
        goals = (await db.scalars(select(Goal))).all()
        for goal in goals:
            link = await db.scalar(select(UserGroupGoalAccess).where(
                UserGroupGoalAccess.groupId == group.id,
                UserGroupGoalAccess.goalType == goal.goalType,
            ))
            if link is None:
                db.add(UserGroupGoalAccess(groupId=group.id, goalType=goal.goalType, enabled=True))
        await db.commit()
    await engine.dispose()
    if seed_review_app is not None and not review_seed_exists:
        # The Review App uses one password for its synthetic sample users.
        # Reuse the private local admin password; no extra secret is introduced.
        os.environ["REVIEW_APP_SEED_PASSWORD"] = password
        summary = await seed_review_app()
        async with AsyncSessionLocal() as db:
            await db.execute(
                update(ScheduledTask)
                .where(ScheduledTask.taskLabel.like("Review — %"))
                .values(isActive=False)
            )
            await db.commit()
        await engine.dispose()
        print(
            "Dataset sintetico do Review App preparado no banco local: "
            f"clientes={summary.customers}, historicos={summary.histories}, "
            f"resumos={summary.summaries}, tarefas de exemplo inativas."
        )
    print("Banco local preparado. Usuario disponivel: " + LOCAL_ADMIN_EMAIL)


def serve() -> None:
    import uvicorn
    # Import string allows Uvicorn to reload the mounted backend source.
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, access_log=False,
                reload=True, reload_dirs=["/app/app"])


def smoke() -> None:
    """Check login through the frontend, including cookie persistence."""
    import http.cookiejar
    import urllib.error
    import urllib.request
    jar = http.cookiejar.CookieJar()
    client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    base = "http://gateway:3000"
    body = json.dumps({"email": LOCAL_ADMIN_EMAIL, "password": os.environ["LOCAL_ADMIN_PASSWORD"]}).encode()
    login = urllib.request.Request(base + "/api/auth/login", data=body, headers={"Content-Type": "application/json"})
    with client.open(login, timeout=90) as response:
        if response.status != 200:
            raise RuntimeError("Login pelo front-end falhou.")
    with client.open(base + "/api/auth/me", timeout=30) as response:
        current = json.load(response)
        if current.get("user", {}).get("email") != LOCAL_ADMIN_EMAIL:
            raise RuntimeError("Sessao do navegador nao persistiu.")
    # Verify the real Hub with a read-only call, never print its response.
    hub = os.environ.get("MARKETING_HUB_BASE_URL", "").rstrip("/")
    key = os.environ.get("MARKETING_HUB_API_KEY", "")
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    hub_client = urllib.request.build_opener(NoRedirect())
    try:
        with hub_client.open(urllib.request.Request(hub + "/api/customers",
                                                   headers={"X-API-Key": key}), timeout=30) as response:
            if response.status != 200:
                raise RuntimeError("O Hub nao confirmou a consulta autenticada.")
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Consulta autenticada ao Hub recusada (HTTP {exc.code}).") from None
    except (urllib.error.URLError, TimeoutError):
        raise RuntimeError("Nao foi possivel conectar ao Hub com HTTPS verificado.") from None
    print("Verificacao concluida: interface, login, sessao e conexao autenticada ao Hub funcionando.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    config = commands.add_parser("configure")
    config.add_argument("--root", type=Path, default=ROOT)
    config.add_argument("--port", type=int)
    config.add_argument("--api-port", type=int)
    config.add_argument("--host-root", help="Pasta absoluta no computador, fora do container.")
    config.add_argument("--host-platform", choices=("macos", "linux", "windows"))
    import_config = commands.add_parser("import-secret")
    import_config.add_argument("--root", type=Path, default=ROOT)
    import_config.add_argument("--require-complete", action="store_true")
    commands.add_parser("seed")
    commands.add_parser("serve")
    commands.add_parser("smoke")
    args = parser.parse_args()
    try:
        if args.command == "configure":
            configure(args.root.resolve(), args.port, args.api_port, args.host_root, args.host_platform)
        elif args.command == "import-secret":
            import_secret(args.root.resolve(), sys.stdin.read(1024 * 1024), args.require_complete)
        elif args.command == "seed":
            asyncio.run(seed_database())
        elif args.command == "serve":
            serve()
        else:
            smoke()
    except (ValueError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
