import asyncio
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("bootstrap_local", ROOT / "scripts/bootstrap_local.py")
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        shutil.copy(ROOT / "sources.lock", self.root)
        shutil.copy(ROOT / ".env.example", self.root)
        shutil.copytree(ROOT / "templates", self.root / "templates")

    def tearDown(self):
        self.temp.cleanup()

    def configure(self, mode=None, port=None, api_port=None):
        with contextlib.redirect_stdout(io.StringIO()):
            return bootstrap.configure(self.root, mode, port, api_port)

    def values(self, name):
        return bootstrap.read_env(self.root / ".local" / name)

    def connected_keys(self):
        local = self.root / ".local"
        local.mkdir(exist_ok=True)
        keys = {key: f"synthetic-{key}" for key in bootstrap.REQUIRED_INTEGRATIONS}
        keys["AWS_REGION"] = "test-region"
        bootstrap.private_write(local / "integrations.env", bootstrap.env_text(keys))
        return keys

    def test_demo_works_without_any_provider_credentials(self):
        result = self.configure()
        self.assertEqual(result["mode"], "demo")
        self.assertEqual(self.values("compose.env")["LOCAL_NETWORK_INTERNAL"], "true")
        backend = self.values("backend.env")
        self.assertTrue(all(backend[key] == "local-demo-disabled" for key in bootstrap.REQUIRED_INTEGRATIONS))
        self.assertNotEqual(backend["SECRET_KEY"], backend["REFRESH_TOKEN_PEPPER"])
        self.assertEqual(backend["REFRESH_COOKIE_SECURE"], "false")
        self.assertEqual(self.values("frontend.env")["ALLOW_INSECURE_AUTH_COOKIES"], "true")

    def test_repeated_setup_preserves_database_and_login_passwords(self):
        self.configure()
        original = (self.root / ".local/secrets.json").read_text()
        self.configure()
        self.assertEqual(original, (self.root / ".local/secrets.json").read_text())

    def test_mode_and_ports_survive_omitted_options(self):
        self.configure("demo", 3100, 8100)
        self.configure()
        self.assertEqual(self.values("compose.env")["LOCAL_WEB_PORT"], "3100")
        self.assertEqual(self.values("backend.env")["FRONTEND_URL"], "http://localhost:3100")
        self.assertEqual(self.values("frontend.env")["NEXT_PUBLIC_API_URL"], "http://localhost:8100")
        self.assertEqual(self.values("frontend.env")["BACKEND_API_URL"], "http://api:8000")

    def test_missing_connected_credentials_preserves_working_demo(self):
        self.configure()
        original = (self.root / ".local/compose.env").read_text()
        with self.assertRaisesRegex(ValueError, "Preencha"):
            self.configure("connected")
        self.assertEqual(original, (self.root / ".local/compose.env").read_text())
        self.assertTrue((self.root / ".local/integrations.env").exists())

    def test_connected_mode_uses_supplied_credentials_and_enables_network(self):
        keys = self.connected_keys()
        self.configure("connected")
        self.configure()
        self.assertEqual(self.values("backend.env")["OPENAI_API_KEY"], keys["OPENAI_API_KEY"])
        self.assertEqual(self.values("compose.env")["LOCAL_NETWORK_INTERNAL"], "false")
        self.assertEqual(self.values("compose.env")["LOCAL_MODE"], "connected")
        self.assertNotIn("AWS_SECRET_ACCESS_KEY", self.values("frontend.env"))
        self.assertNotIn("SLACK_BOT_TOKEN", self.values("frontend.env"))

    def test_switch_to_demo_does_not_inherit_real_keys(self):
        keys = self.connected_keys()
        self.configure("connected")
        self.configure("demo")
        self.assertNotEqual(self.values("backend.env")["OPENAI_API_KEY"], keys["OPENAI_API_KEY"])
        self.assertEqual(self.values("compose.env")["LOCAL_NETWORK_INTERNAL"], "true")

    def test_credentials_cannot_override_local_database(self):
        keys = self.connected_keys()
        keys["DATABASE_URL"] = "postgresql://shared.invalid/production"
        keys["DEBUG_MODE"] = "false"
        bootstrap.private_write(self.root / ".local/integrations.env", bootstrap.env_text(keys))
        self.configure("connected")
        self.assertIn("@db:5432/avanti_insights", self.values("backend.env")["DATABASE_URL"])
        self.assertEqual(self.values("backend.env")["DEBUG_MODE"], "true")

    def test_literal_values_are_not_expanded_or_executed(self):
        values = {"SAMPLE": r"a'$(touch NEVER_CREATED)$HOME\literal\n"}
        path = self.root / "literal.env"
        path.write_text(bootstrap.env_text(values))
        self.assertEqual(bootstrap.read_env(path), values)
        self.assertFalse((self.root / "NEVER_CREATED").exists())

    def test_malformed_environment_and_multiline_values_fail(self):
        path = self.root / "malformed.env"
        for content in ("export TOKEN=x", "TOKEN='unfinished", "TOKEN"):
            path.write_text(content)
            with self.assertRaises(ValueError):
                bootstrap.read_env(path)
        with self.assertRaises(ValueError):
            bootstrap.env_text({"TOKEN": "line1\nline2"})

    def test_port_validation_does_not_replace_working_config(self):
        self.configure()
        original = (self.root / ".local/compose.env").read_text()
        for port, api_port in ((1, 8000), (70000, 8000), (3000, 3000)):
            with self.assertRaises(ValueError):
                self.configure(port=port, api_port=api_port)
        self.assertEqual(original, (self.root / ".local/compose.env").read_text())

    @unittest.skipIf(os.name == "nt", "Windows ACLs are not POSIX permissions")
    def test_secret_files_are_owner_only(self):
        self.configure()
        for name in ("backend.env", "frontend.env", "compose.env", "secrets.json", "access.txt"):
            self.assertEqual((self.root / ".local" / name).stat().st_mode & 0o777, 0o600)

    def test_generated_secrets_are_not_printed(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            bootstrap.configure(self.root, None, None, None)
        for secret in json.loads((self.root / ".local/secrets.json").read_text()).values():
            self.assertNotIn(secret, output.getvalue())


class DemoGuardTests(unittest.TestCase):
    def test_demo_allows_login_refresh_logout_and_reads(self):
        for path in bootstrap.AUTH_WRITES:
            self.assertTrue(bootstrap.demo_request_allowed("POST", path))
        self.assertTrue(bootstrap.demo_request_allowed("GET", "/customers"))
        self.assertTrue(bootstrap.demo_request_allowed("GET", "/goals/available"))

    def test_demo_blocks_mutation_registration_and_slack_oauth(self):
        for method, path in (("POST", "/analyze/start"), ("POST", "/api/auth/register"),
                             ("DELETE", "/customers/1"), ("PATCH", "/api/users/me"),
                             ("GET", "/api/auth/slack/authorize")):
            self.assertFalse(bootstrap.demo_request_allowed(method, path))

    def test_asgi_guard_rejects_without_calling_private_app(self):
        messages = []
        async def unexpected(scope, receive, send):
            self.fail("Application should not be called")
        async def send(message):
            messages.append(message)
        asyncio.run(bootstrap.DemoGuard(unexpected)(
            {"type": "http", "method": "POST", "path": "/analyze/start"}, None, send,
        ))
        self.assertEqual(messages[0]["status"], 503)
        self.assertIn("demonstracao", json.loads(messages[1]["body"])["detail"])

    def test_asgi_guard_forwards_lifespan(self):
        calls = []
        async def app(scope, receive, send):
            calls.append(scope["type"])
        asyncio.run(bootstrap.DemoGuard(app)({"type": "lifespan"}, None, None))
        self.assertEqual(calls, ["lifespan"])


class LauncherTests(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Windows Bash is validated by its native CI shell")
    @unittest.skipUnless(shutil.which("bash"), "Bash is not available")
    def test_help_needs_no_installed_dependencies(self):
        result = subprocess.run(["bash", str(ROOT / "scripts/local.sh"), "help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("setup", result.stdout)

    @unittest.skipIf(os.name == "nt", "Windows Bash is validated by its native CI shell")
    @unittest.skipUnless(shutil.which("bash"), "Bash is not available")
    def test_invalid_options_fail_before_system_changes(self):
        for arguments in (["setup", "--mode", "invalid"], ["unknown"], ["start", "--mode", "connected"], ["setup", "--port", "1"]):
            result = subprocess.run(["bash", str(ROOT / "scripts/local.sh"), *arguments], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
