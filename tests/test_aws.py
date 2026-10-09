"""AWS authentication and installer contracts with synthetic credentials only."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


@unittest.skipIf(os.name == "nt", "Bash contracts run on Linux and macOS")
class AwsFlowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "Insights com espacos"
        self.root.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def run_flow(self, body):
        script = r'''
set -euo pipefail
export INSIGHTS_ROOT="$INSIGHTS_TEST_ROOT"
INSIGHTS_NONINTERACTIVE=false
INSIGHTS_DOCKER=(docker)
CI=""
. "$INSIGHTS_SOURCE_ROOT/scripts/aws.sh"
fail() { printf '%s\n' "$*" >&2; exit 2; }
event() { printf '%s\n' "$*" >> "$INSIGHTS_ROOT/events"; }
aws() {
  if [ "${1:-}" = --version ]; then printf 'aws-cli/%s Python/3.13\n' "${TEST_AWS_VERSION:-2.32.0}"; return; fi
  event "$*"
  case "$*" in
    *get-caller-identity*) [ -f "$INSIGHTS_ROOT/session" ]; return;;
    *'sso login'*|*' login') touch "$INSIGHTS_ROOT/session";;
    *get-secret-value*) printf '"synthetic-json"\n'; return "${TEST_FETCH_EXIT:-0}";;
  esac
}
''' + body
        return subprocess.run(["bash", "-c", script], text=True, capture_output=True,
                              env={**os.environ, "INSIGHTS_SOURCE_ROOT": str(ROOT),
                                   "INSIGHTS_TEST_ROOT": str(self.root)})

    def events(self):
        path = self.root / "events"
        return path.read_text() if path.exists() else ""

    def test_expired_session_opens_console_login_and_checks_new_session(self):
        result = self.run_flow("ensure_aws_session\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertIn("--profile avanti-insights-local --region us-east-1 configure set region us-east-1", events)
        self.assertIn("--profile avanti-insights-local --region us-east-1 login\n", events)
        self.assertEqual(events.count("get-caller-identity"), 2)

    def test_valid_session_does_not_reopen_login(self):
        (self.root / "session").touch()
        result = self.run_flow("ensure_aws_session\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(" login", self.events())
        self.assertEqual(self.events().count("get-caller-identity"), 1)

    def test_noninteractive_missing_session_does_not_open_browser(self):
        result = self.run_flow("INSIGHTS_NONINTERACTIVE=true\nensure_aws_session\n")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn(" login", self.events())

    def test_custom_sso_profile_uses_existing_configuration(self):
        result = self.run_flow("INSIGHTS_AWS_PROFILE=colaborador\nINSIGHTS_AWS_REGION=sa-east-1\nINSIGHTS_AWS_LOGIN_METHOD=sso\nensure_aws_session\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--profile colaborador --region sa-east-1 sso login", self.events())
        self.assertNotIn("configure set", self.events())

    def test_cli_version_boundary(self):
        for version, expected in (("2.31.9", 1), ("2.32.0", 0), ("2.40.1", 0), ("1.99.0", 1)):
            result = self.run_flow(f"TEST_AWS_VERSION={version}\naws_version_ready\n")
            self.assertEqual(result.returncode, expected, version)

    def test_secret_transferred_only_via_stdin_and_success_marker(self):
        result = self.run_flow(r'''
docker() { event "docker:$*"; cat > "$INSIGHTS_ROOT/stdin"; }
fetch_integrations
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "stdin").read_text(), '"synthetic-json"\n\nINSIGHTS_SECRET_COMPLETE\n')
        self.assertNotIn("synthetic-json", self.events() + result.stdout + result.stderr)
        self.assertIn("--network none --user", self.events())
        self.assertIn("--require-complete", self.events())

    def test_partial_aws_failure_cannot_signal_success(self):
        result = self.run_flow(r'''
TEST_FETCH_EXIT=7
docker() { cat > "$INSIGHTS_ROOT/stdin"; }
fetch_integrations
''')
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("INSIGHTS_SECRET_COMPLETE", (self.root / "stdin").read_text())
        self.assertNotIn("synthetic-json", result.stdout + result.stderr)

    def test_linux_rejects_unsigned_download_before_extraction(self):
        result = self.run_flow(r'''
uname() { printf 'aarch64\n'; }
curl() { event "download:$*"; }
gpg() { event "gpg:$*"; case "$*" in *--verify*) return 1;; esac; }
unzip() { event 'unexpected-extraction'; }
install_aws_linux
''')
        self.assertEqual(result.returncode, 2)
        events = self.events()
        self.assertIn("awscli-exe-linux-aarch64.zip.sig", events)
        self.assertIn("--verify", events)
        self.assertNotIn("unexpected-extraction", events)

    def test_macos_old_cli_is_upgraded_through_brew(self):
        result = self.run_flow(r'''
TEST_AWS_VERSION=2.31.0
uname() { printf 'Darwin\n'; }
mac_prepare_askpass() { event askpass; }
mac_prepare_brew() { event brew-ready; }
mac_run() { shift; "$@"; }
mac_brew_run() { event "brew:$*"; if [ "$1" = upgrade ]; then TEST_AWS_VERSION=2.32.0; fi; }
install_aws
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("brew:upgrade awscli", self.events())


if __name__ == "__main__":
    unittest.main()
