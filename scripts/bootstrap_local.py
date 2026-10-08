#!/usr/bin/env python3
"""Configure files with stdlib; initialize and serve the private app in Docker."""
from __future__ import annotations

import argparse
import asyncio
from datetime import datetime, timedelta, timezone
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

ROOT = Path(__file__).resolve().parent.parent
REQUIRED_INTEGRATIONS = (
    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY", "AWS_S3_BUCKET", "SLACK_BOT_TOKEN",
)
LOCAL_ADMIN_EMAIL = "admin@example.com"
AUTH_WRITES = {
    "/api/auth/jwt/login", "/api/auth/jwt/logout", "/api/auth/refresh",
}
DEMO_DETAIL = "Modo demonstracao: operacao desativada. Use o modo connected para executar analises."


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
        if "\n" in value or "\r" in value:
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


def configure(root: Path, mode: str | None, port: int | None, api_port: int | None,
              host_root: str | None = None, host_platform: str | None = None) -> dict:
    local = root / ".local"
    platform = host_platform or ("windows" if os.name == "nt" else "macos" if sys.platform == "darwin" else "linux")
    shortcuts = codex_shortcuts(host_root or str(root.resolve()), platform)
    previous = json.loads((local / "settings.json").read_text()) if (local / "settings.json").exists() else {}
    selected_mode = mode or previous.get("mode", "demo")
    if selected_mode not in {"demo", "connected"}:
        raise ValueError("Modo invalido.")
    web_port = port if port is not None else previous.get("port", 3000)
    backend_port = api_port if api_port is not None else previous.get("api_port", 8000)
    if not all(isinstance(v, int) and 1024 <= v <= 65535 for v in (web_port, backend_port)):
        raise ValueError("Portas devem estar entre 1024 e 65535.")
    if web_port == backend_port:
        raise ValueError("Front-end e API precisam de portas diferentes.")

    credentials = read_env(local / "integrations.env") if selected_mode == "connected" else {}
    missing = [key for key in REQUIRED_INTEGRATIONS if not credentials.get(key)]
    if selected_mode == "connected" and missing:
        local.mkdir(parents=True, exist_ok=True, mode=0o700)
        if not (local / "integrations.env").exists():
            private_write(local / "integrations.env", (root / ".env.example").read_text())
        raise ValueError("Preencha .local/integrations.env: " + ", ".join(missing))

    lock = read_env(root / "sources.lock")
    for key in ("BACKEND_REF", "FRONTEND_REF"):
        if not re.fullmatch(r"[0-9a-f]{40}", lock.get(key, "")):
            raise ValueError(f"sources.lock: {key} deve ser um SHA completo.")
    stored = json.loads((local / "secrets.json").read_text()) if (local / "secrets.json").exists() else {}
    for key in ("db_password", "secret_key", "refresh_pepper", "api_token", "health_token", "admin_password"):
        stored.setdefault(key, secrets.token_urlsafe(32))
    if stored["secret_key"] == stored["refresh_pepper"]:
        raise ValueError("Chaves de sessao devem ser distintas.")
    if selected_mode == "demo":
        credentials = {key: "local-demo-disabled" for key in REQUIRED_INTEGRATIONS}

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
        "CELERY_BROKER_URL": "redis://redis:6379/0",
        "CELERY_RESULT_BACKEND": "redis://redis:6379/0",
        "FRONTEND_URL": app_url,
        "CORS_ORIGINS": f"{app_url},http://127.0.0.1:{web_port}",
        "OPENAI_MODEL": credentials.get("OPENAI_MODEL") or "gpt-5.4-mini",
        "AWS_REGION": credentials.get("AWS_REGION") or "us-east-1",
        "MARKETING_HUB_BASE_URL": credentials.get("MARKETING_HUB_BASE_URL") or "http://disabled.invalid",
        "MERCHANT_MCP_ENABLED": credentials.get("MERCHANT_MCP_ENABLED") or "false",
        "JOBBER_MCP_ENABLED": credentials.get("JOBBER_MCP_ENABLED") or "false",
        "GITHUB_MCP_ENABLED": credentials.get("GITHUB_MCP_ENABLED") or "false",
    }
    frontend = {
        **{
            key: value for key, value in credentials.items()
            if value and key.startswith((
                "OPENAI_", "ANTHROPIC_", "GOOGLE_", "SHEETS_", "RAG_",
                "CRO_", "JIRA_", "MAIL_", "RESEND_", "GEMINI_",
            ))
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
        "LOCAL_NETWORK_INTERNAL": "true" if selected_mode == "demo" else "false",
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
        "nginx.conf": (root / "templates" / f"nginx.{selected_mode}.conf").read_text(),
        "access.txt": f"Modo: {selected_mode}\nInterface: {app_url}\nUsuario: {LOCAL_ADMIN_EMAIL}\nSenha: {stored['admin_password']}\n",
    }
    for name, content in contents.items():
        private_write(local / name, content)
    print(f"Configuracao local pronta. Modo: {selected_mode}. Acesso salvo em .local/access.txt.")
    return settings


async def seed_database() -> None:
    # Imports are delayed so configure works in a plain Python image.
    from fastapi_users.password import PasswordHelper
    from sqlalchemy import select
    from app.core.db import AsyncSessionLocal, connect_db, engine
    from app.models.models import (
        AnalysisHistory, Area, Customer, Goal, Role, User, UserGroup,
        UserGroupGoalAccess, UserPreference, UserRole, UserRoleLink,
    )
    from scripts.seed_goals import seed as seed_goals
    from scripts.seed_permissions import seed as seed_permissions

    if os.environ.get("DEBUG_MODE") != "true" or "@db:5432/avanti_insights" not in os.environ.get("DATABASE_URL", ""):
        raise RuntimeError("Bootstrap permitido apenas no banco desta stack local.")
    password = os.environ.get("LOCAL_ADMIN_PASSWORD", "")
    if len(password) < 12:
        raise RuntimeError("Senha local deve ter pelo menos 12 caracteres.")
    await connect_db()
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
        if os.environ["LOCAL_MODE"] == "demo":
            area = await db.get(Area, ident("area"))
            if area is None:
                area = Area(id=ident("area"), name="Demonstracao")
                db.add(area)
            customer = await db.get(Customer, ident("customer"))
            if customer is None:
                customer = Customer(id=ident("customer"), name="Loja demonstracao", slug="loja-demonstracao", description="Cliente ficticio.", active=True)
                db.add(customer)
            await db.flush()
            now = datetime.now(timezone.utc)
            for index, goal in enumerate(goals[:6]):
                if await db.get(AnalysisHistory, ident(f"history-{index}")) is None:
                    timestamp = now - timedelta(days=index + 1)
                    db.add(AnalysisHistory(
                        id=ident(f"history-{index}"), threadId=f"insights-local-demo-{index}",
                        userId=user.id, customerId=customer.id, areaId=area.id,
                        goal=f"[Demonstracao] {goal.name}", goalType=goal.goalType,
                        timestamp=timestamp, completedAt=timestamp, filesCount=0,
                        status="completed", questions={}, answers={},
                        preview={"summary": "Exemplo ficticio para navegacao."},
                        analysisData={"summary": "Dados ficticios. Nenhuma analise de IA foi executada."},
                    ))
        await db.commit()
    await engine.dispose()
    print("Banco local preparado. Usuario disponivel: " + LOCAL_ADMIN_EMAIL)


def demo_request_allowed(method: str, path: str) -> bool:
    normalized = path.rstrip("/") or "/"
    if normalized.startswith("/api/auth/slack"):
        return False
    return method in {"GET", "HEAD", "OPTIONS"} or normalized in AUTH_WRITES


class DemoGuard:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http" and not demo_request_allowed(scope["method"], scope["path"]):
            payload = json.dumps({"detail": DEMO_DETAIL}).encode()
            await send({"type": "http.response.start", "status": 503, "headers": [(b"content-type", b"application/json")]})
            await send({"type": "http.response.body", "body": payload})
            return
        await self.app(scope, receive, send)


def serve() -> None:
    import uvicorn
    from app.main import app
    mode = os.environ.get("LOCAL_MODE")
    if mode not in {"demo", "connected"}:
        raise RuntimeError("LOCAL_MODE precisa ser demo ou connected.")
    target = DemoGuard(app) if mode == "demo" else app
    uvicorn.run(target, host="0.0.0.0", port=8000, access_log=False)


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
    if os.environ["LOCAL_MODE"] == "demo":
        for path in ("/api/analyze", "/api/upload", "/api/auth/register"):
            try:
                client.open(urllib.request.Request(base + path, data=b"{}", headers={"Content-Type": "application/json"}), timeout=10)
            except urllib.error.HTTPError as exc:
                if exc.code == 503:
                    continue
                raise
            raise RuntimeError(f"Operacao deveria estar bloqueada no modo demo: {path}")
    print("Verificacao concluida: interface, login e sessao funcionando.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    config = commands.add_parser("configure")
    config.add_argument("--root", type=Path, default=ROOT)
    config.add_argument("--mode", choices=("demo", "connected"))
    config.add_argument("--port", type=int)
    config.add_argument("--api-port", type=int)
    config.add_argument("--host-root", help="Pasta absoluta no computador, fora do container.")
    config.add_argument("--host-platform", choices=("macos", "linux", "windows"))
    commands.add_parser("seed")
    commands.add_parser("serve")
    commands.add_parser("smoke")
    args = parser.parse_args()
    try:
        if args.command == "configure":
            configure(args.root.resolve(), args.mode, args.port, args.api_port, args.host_root, args.host_platform)
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
