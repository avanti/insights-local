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
        shutil.copytree(ROOT / "templates", self.root / "templates")
        self.keys = {key: f"synthetic-{key}" for key in bootstrap.REQUIRED_INTEGRATIONS}
        self.keys["AWS_REGION"] = "test-region"
        bootstrap.private_write(self.root / ".local/integrations.env", bootstrap.env_text(self.keys))

    def tearDown(self):
        self.temp.cleanup()

    def configure(self, port=None, api_port=None):
        with contextlib.redirect_stdout(io.StringIO()):
            return bootstrap.configure(self.root, port, api_port)

    def values(self, name):
        return bootstrap.read_env(self.root / ".local" / name)

    def test_real_credentials_and_private_services_remain_local(self):
        result = self.configure()
        self.assertEqual(result["mode"], "connected")
        backend = self.values("backend.env")
        self.assertTrue(all(backend[key] == self.keys[key] for key in bootstrap.REQUIRED_INTEGRATIONS))
        self.assertIn("@db:5432/avanti_insights", backend["DATABASE_URL"])
        self.assertEqual(backend["CELERY_BROKER_URL"], "redis://redis:6379/0")
        self.assertEqual(backend["MARKETING_HUB_BASE_URL"], "https://100.55.149.93.nip.io")
        self.assertEqual(backend["MARKETING_HUB_VERIFY_SSL"], "true")
        self.assertNotEqual(backend["SECRET_KEY"], backend["REFRESH_TOKEN_PEPPER"])
        self.assertEqual(backend["REFRESH_COOKIE_SECURE"], "false")
        frontend = self.values("frontend.env")
        self.assertEqual(frontend["BACKEND_API_BEARER_TOKEN"], backend["API_TOKEN"])
        self.assertNotIn("AWS_SECRET_ACCESS_KEY", frontend)
        self.assertNotIn("MARKETING_HUB_API_KEY", frontend)
        self.assertNotIn("GA4_CREDENTIALS_PRIVATE_KEY_B64", frontend)
        self.assertEqual(frontend["ANTHROPIC_API_KEY"], self.keys["ANTHROPIC_API_KEY"])

    def test_repeated_setup_preserves_database_and_login_passwords(self):
        self.configure()
        original = (self.root / ".local/secrets.json").read_text()
        self.configure()
        self.assertEqual(original, (self.root / ".local/secrets.json").read_text())

    def test_ports_survive_omitted_options(self):
        self.configure(3100, 8100)
        self.configure()
        self.assertEqual(self.values("compose.env")["LOCAL_WEB_PORT"], "3100")
        self.assertEqual(self.values("backend.env")["FRONTEND_URL"], "http://localhost:3100")
        self.assertEqual(self.values("frontend.env")["NEXT_PUBLIC_API_URL"], "http://localhost:8100")

    def test_missing_credentials_preserves_runtime_files(self):
        self.configure()
        original = (self.root / ".local/backend.env").read_text()
        bootstrap.private_write(self.root / ".local/integrations.env", "OPENAI_API_KEY='synthetic'\n")
        with self.assertRaisesRegex(ValueError, "Credenciais incompletas"):
            self.configure()
        self.assertEqual(original, (self.root / ".local/backend.env").read_text())

    def test_old_demo_settings_migrate_without_changing_passwords(self):
        self.configure()
        original = (self.root / ".local/secrets.json").read_text()
        bootstrap.private_write(self.root / ".local/settings.json", json.dumps({"mode": "demo", "port": 3100, "api_port": 8100}))
        self.configure()
        self.assertEqual(self.values("compose.env")["LOCAL_MODE"], "connected")
        self.assertEqual(original, (self.root / ".local/secrets.json").read_text())
        self.assertEqual(self.values("compose.env")["LOCAL_WEB_PORT"], "3100")

    def test_cloud_or_overrides_cannot_redirect_local_database_or_auth(self):
        overrides = {"DATABASE_URL": "postgresql://shared.invalid/production", "DEBUG_MODE": "false",
                     "API_TOKEN": "synthetic-cloud-token", "POSTGRES_PASSWORD": "synthetic-cloud-db",
                     "MARKETING_HUB_VERIFY_SSL": "false", "GA4_AGENT_MODEL": "synthetic-model"}
        bootstrap.private_write(self.root / ".local/integrations.override.env", bootstrap.env_text(overrides))
        self.configure()
        backend = self.values("backend.env")
        self.assertIn("@db:5432/avanti_insights", backend["DATABASE_URL"])
        self.assertEqual(backend["DEBUG_MODE"], "true")
        self.assertNotEqual(backend["API_TOKEN"], overrides["API_TOKEN"])
        self.assertNotEqual(backend["POSTGRES_PASSWORD"], overrides["POSTGRES_PASSWORD"])
        self.assertEqual(backend["MARKETING_HUB_VERIFY_SSL"], "true")
        self.assertEqual(backend["GA4_AGENT_MODEL"], overrides["GA4_AGENT_MODEL"])

    def test_import_handles_cli_json_string_and_does_not_print_values(self):
        keys = {**self.keys, "RESEND_API_KEY": "synthetic-$HOME-$(never)-quote'", "GA4_AGENT_MODEL": "synthetic-model"}
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            bootstrap.import_secret(self.root, json.dumps(json.dumps(keys)))
        self.assertEqual(self.values("integrations.env"), keys)
        for value in keys.values():
            self.assertNotIn(value, output.getvalue())

    def test_failed_aws_stream_cannot_replace_previous_secret(self):
        original = (self.root / ".local/integrations.env").read_text()
        with self.assertRaisesRegex(ValueError, "nao terminou"):
            bootstrap.import_secret(self.root, json.dumps(self.keys), require_complete=True)
        self.assertEqual(original, (self.root / ".local/integrations.env").read_text())
        bootstrap.import_secret(self.root, json.dumps(self.keys) + "\nINSIGHTS_SECRET_COMPLETE\n", require_complete=True)
        self.assertEqual(self.values("integrations.env"), self.keys)

    def test_invalid_secret_preserves_previous_credentials_and_hides_content(self):
        original = (self.root / ".local/integrations.env").read_text()
        for raw in ('synthetic-sensitive-invalid-json', '[]', json.dumps({"SECRET": "synthetic-sensitive"}),
                    json.dumps({**self.keys, "BAD": "synthetic\nmultiline"})):
            with self.assertRaises(ValueError) as error:
                bootstrap.import_secret(self.root, raw)
            self.assertNotIn("synthetic-sensitive", str(error.exception))
            self.assertEqual(original, (self.root / ".local/integrations.env").read_text())

    def test_google_sheets_is_optional_and_pem_is_serialized_safely(self):
        keys = {**self.keys, "GOOGLE_SHEETS_PRIVATE_KEY": "synthetic\nprivate\nkey"}
        bootstrap.import_secret(self.root, json.dumps(keys))
        self.assertEqual(self.values("integrations.env")["GOOGLE_SHEETS_PRIVATE_KEY"], "synthetic\\nprivate\\nkey")
        self.configure()

    def test_enabled_github_requires_envelope_configuration(self):
        keys = {**self.keys, "GITHUB_MCP_ENABLED": "true"}
        with self.assertRaisesRegex(ValueError, "GITHUB_CREDENTIALS_SERVICE_TOKEN"):
            bootstrap.import_secret(self.root, json.dumps(keys))

    def test_hub_must_use_https_and_no_embedded_credentials(self):
        for url in ("http://hub.invalid", "https://secret@hub.invalid", "https://hub.invalid?token=synthetic"):
            with self.assertRaisesRegex(ValueError, "HTTPS"):
                bootstrap.import_secret(self.root, json.dumps({**self.keys, "MARKETING_HUB_BASE_URL": url}))

    def test_literal_values_are_not_expanded_or_executed(self):
        values = {"SAMPLE": r"a'$(touch NEVER_CREATED)$HOME\literal\n"}
        path = self.root / "literal.env"
        path.write_text(bootstrap.env_text(values))
        self.assertEqual(bootstrap.read_env(path), values)
        self.assertFalse((self.root / "NEVER_CREATED").exists())

    def test_malformed_environment_and_control_characters_fail(self):
        path = self.root / "malformed.env"
        for content in ("export TOKEN=x", "TOKEN='unfinished", "TOKEN"):
            path.write_text(content)
            with self.assertRaises(ValueError):
                bootstrap.read_env(path)
        for value in ("line1\nline2", "null\x00byte"):
            with self.assertRaises(ValueError):
                bootstrap.env_text({"TOKEN": value})

    def test_port_validation_preserves_configuration(self):
        self.configure()
        original = (self.root / ".local/compose.env").read_text()
        for port, api_port in ((1, 8000), (70000, 8000), (3000, 3000)):
            with self.assertRaises(ValueError):
                self.configure(port, api_port)
        self.assertEqual(original, (self.root / ".local/compose.env").read_text())

    @unittest.skipIf(os.name == "nt", "Windows ACLs are verified by native script")
    def test_secret_files_are_owner_only(self):
        self.configure()
        for name in ("backend.env", "frontend.env", "compose.env", "secrets.json", "access.txt", "integrations.env"):
            self.assertEqual((self.root / ".local" / name).stat().st_mode & 0o777, 0o600)

    def test_generated_local_passwords_are_not_printed(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            bootstrap.configure(self.root)
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
                bootstrap.private_write(root / ".local/integrations.env", bootstrap.env_text({key: "synthetic" for key in bootstrap.REQUIRED_INTEGRATIONS}))
                bootstrap.configure(root, None, None, "/Users/person/insights-local", "macos")
            projects = json.loads((root / ".local/codex-projects.json").read_text())
            self.assertEqual(projects["backend"]["path"], "/Users/person/insights-local/sources/backend")
            self.assertNotIn(str(root), projects["backend"]["url"])


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
        for arguments in (["setup", "--mode", "demo"], ["unknown"], ["start", "--mode", "connected"], ["setup", "--port", "1"]):
            result = subprocess.run(["bash", str(ROOT / "scripts/local.sh"), *arguments], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
