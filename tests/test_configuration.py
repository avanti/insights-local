import asyncio
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

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


class CodexShortcutTests(unittest.TestCase):
    def test_host_paths_round_trip_for_all_systems(self):
        cases = (
            ("macos", "/Users/Pessoa/Insights com espaços & #", "/sources/frontend"),
            ("linux", "/home/pessoa/Insights com espaços & #", "/sources/frontend"),
            ("windows", r"C:\Users\Pessoa\Insights com espaços & #", r"\sources\frontend"),
        )
        for platform, host_root, suffix in cases:
            with self.subTest(platform=platform):
                files = bootstrap.codex_shortcuts(host_root, platform)
                projects = json.loads(files["codex-projects.json"])
                expected = host_root + suffix
                self.assertEqual(projects["frontend"]["path"], expected)
                url = urlsplit(projects["frontend"]["url"])
                self.assertEqual((url.scheme, url.netloc), ("codex", "new"))
                self.assertEqual(parse_qs(url.query), {"path": [expected]})
                self.assertEqual(url.fragment, "")
                self.assertIn("cadastro permanente", files["codex-projects.html"])
                if platform == "macos":
                    self.assertEqual(plistlib.loads(files["codex/frontend.webloc"].encode())["URL"], projects["frontend"]["url"])
                if platform == "windows":
                    self.assertIn("URL=" + projects["frontend"]["url"], files["codex/frontend.url"])

    def test_html_escapes_special_characters_in_host_folder(self):
        files = bootstrap.codex_shortcuts('/Users/person/<script>alert("test")</script>', "macos")
        self.assertNotIn("<script>", files["codex-projects.html"])
        self.assertIn("&lt;script&gt;", files["codex-projects.html"])

    def test_rejects_relative_and_multiline_host_paths(self):
        for platform, path in (("macos", "relative"), ("windows", r"C:relative"),
                               ("linux", "/tmp/invalid\nfolder"), ("linux", "/tmp/invalid\x00")):
            with self.assertRaises(ValueError):
                bootstrap.codex_shortcuts(path, platform)

    def test_configure_uses_host_path_instead_of_container_mount(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "container-mount"
            root.mkdir()
            shutil.copy(ROOT / "sources.lock", root)
            shutil.copytree(ROOT / "templates", root / "templates")
            with contextlib.redirect_stdout(io.StringIO()):
                bootstrap.configure(root, None, None, None, "/Users/person/insights-local", "macos")
            projects = json.loads((root / ".local/codex-projects.json").read_text())
            self.assertEqual(projects["backend"]["path"], "/Users/person/insights-local/sources/backend")
            self.assertNotIn(str(root), projects["backend"]["url"])


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
    @unittest.skipIf(os.name == "nt", "Windows launcher is tested in native PowerShell")
    @unittest.skipUnless(shutil.which("bash"), "Bash is not available")
    def test_codex_opens_selected_host_link_without_docker(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name, content in bootstrap.codex_shortcuts(str(root), "linux").items():
                bootstrap.private_write(root / ".local" / name, content)
            for name in ("frontend", "backend"):
                (root / "sources" / name / ".git").mkdir(parents=True)
            binary = root / "bin"
            binary.mkdir()
            opener = binary / "xdg-open"
            opener.write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$INSIGHTS_LAUNCH_LOG"\n')
            opener.chmod(0o755)
            log = root / "opened.txt"
            env = {**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"], "INSIGHTS_LAUNCH_LOG": str(log)}
            # Mock the macOS opener too: CI runs this test on Linux and macOS.
            shutil.copy(opener, binary / "open")
            result = subprocess.run(["bash", str(ROOT / "scripts/local.sh"), "codex", "--root", str(root),
                                     "--project", "backend"], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text(), (root / ".local/codex/backend.link").read_text())
            self.assertNotIn("cadastro concluido", result.stdout)
            log.unlink()
            (root / ".local/codex/backend.link").write_text("https://unexpected.invalid\n")
            result = subprocess.run(["bash", str(ROOT / "scripts/local.sh"), "codex", "--root", str(root)],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(log.exists(), "Validate all shortcuts before opening either project")

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
