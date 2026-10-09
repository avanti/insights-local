"""Exercise the real macOS flow with fake system commands; never install anything."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


@unittest.skipIf(os.name == "nt", "macOS Bash contracts run on Linux and macOS")
@unittest.skipUnless(shutil.which("bash"), "Bash is not available")
class MacInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "Insights com espacos"
        (self.root / ".local").mkdir(parents=True)
        (self.root / "scripts").mkdir()
        shutil.copy(ROOT / "scripts/macos-askpass.sh", self.root / "scripts")

    def tearDown(self):
        self.temp.cleanup()

    def run_flow(self, body):
        script = r'''
set -euo pipefail
export INSIGHTS_ROOT="$INSIGHTS_TEST_ROOT"
INSIGHTS_NONINTERACTIVE=false
INSIGHTS_MAC_LOG="$INSIGHTS_ROOT/.local/install-macos.log"
INSIGHTS_MAC_WAIT_ATTEMPTS=2
INSIGHTS_INSTALL_WAIT_ATTEMPTS=2
. "$INSIGHTS_SOURCE_ROOT/scripts/macos.sh"
fail() { printf '%s\n' "$*" >&2; exit 2; }
event() { printf '%s\n' "$*" >> "$INSIGHTS_ROOT/events"; }
git() { return 0; }
uname() { printf '%s\n' arm64; }
sleep() { event "wait:$*"; touch "$INSIGHTS_ROOT/ready"; }
open() { event "open:$*"; }
command() {
  if [ "$1" = -v ] && [ "$2" = gh ]; then
    [ -f "$INSIGHTS_ROOT/gh" ]
  else builtin command "$@"
  fi
}
docker() {
  [ -f "$INSIGHTS_ROOT/app" ] || return 1
  if [ "$1" = compose ]; then return 0; fi
  [ -f "$INSIGHTS_ROOT/ready" ]
}
mac_docker_app() {
  [ -f "$INSIGHTS_ROOT/app" ] || return 1
  printf '%s\n' "$INSIGHTS_ROOT/Docker.app"
}
mac_find_brew() {
  [ -f "$INSIGHTS_ROOT/brew" ] || return 1
  INSIGHTS_BREW=brew
}
mac_download_verified() {
  event "download:$1:$3"
  [ "${#3}" -eq 64 ]
  printf 'touch "$INSIGHTS_ROOT/brew"\n' > "$2"
}
mac_admin() { event "admin:$*"; touch "$INSIGHTS_ROOT/brew"; }
brew() {
  event "brew:$*"
  printf 'askpass=%s\nno_sudo=%s\n' "${SUDO_ASKPASS:-}" "${HOMEBREW_NO_SUDO:-}" > "$INSIGHTS_ROOT/brew-environment"
  if [ "$2" = gh ]; then touch "$INSIGHTS_ROOT/gh"
  else touch "$INSIGHTS_ROOT/app"
  fi
}
hdiutil() { event 'unexpected-mount'; return 97; }
''' + body
        return subprocess.run(
            ["bash", "-c", script], text=True, capture_output=True,
            env={**os.environ, "INSIGHTS_SOURCE_ROOT": str(ROOT), "INSIGHTS_TEST_ROOT": str(self.root)},
        )

    def events(self):
        path = self.root / "events"
        return path.read_text() if path.exists() else ""

    def test_fresh_apple_silicon_installs_brew_gh_and_docker_then_waits(self):
        result = self.run_flow("install_macos\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertIn("Homebrew-7.0.9.pkg -target /", events)
        self.assertIn("brew:install gh", events)
        self.assertIn("brew:install --cask --require-sha docker-desktop", events)
        self.assertIn("open:" + str(self.root / "Docker.app"), events)
        self.assertIn("wait:5", events)
        self.assertNotIn("unexpected-mount", events)
        self.assertNotIn("https://", "\n".join(line for line in events.splitlines() if line.startswith("open:")))
        self.assertEqual((self.root / ".local/macos-sudo-askpass.sh").stat().st_mode & 0o777, 0o700)
        self.assertIn("askpass=" + str(self.root / ".local/macos-sudo-askpass.sh"), (self.root / "brew-environment").read_text())

    def test_existing_tools_need_no_brew_installation_or_window(self):
        result = self.run_flow('touch "$INSIGHTS_ROOT/gh" "$INSIGHTS_ROOT/app" "$INSIGHTS_ROOT/ready"\ninstall_macos\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), "")

    def test_installed_docker_is_opened_without_reinstalling(self):
        result = self.run_flow('touch "$INSIGHTS_ROOT/gh" "$INSIGHTS_ROOT/app"\ninstall_macos\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("open:", self.events())
        self.assertNotIn("brew:", self.events())

    def test_existing_brew_is_reused(self):
        result = self.run_flow('touch "$INSIGHTS_ROOT/brew"\ninstall_macos\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("download:", self.events())
        self.assertIn("brew:install --cask --require-sha docker-desktop", self.events())

    def test_failed_cask_keeps_original_error_and_does_not_open_browser(self):
        result = self.run_flow('''
touch "$INSIGHTS_ROOT/brew" "$INSIGHTS_ROOT/gh"
brew() { event "brew:$*"; printf 'original mounting failure code 77\n' >&2; return 77; }
install_macos
''')
        self.assertEqual(result.returncode, 2)
        self.assertIn("original mounting failure code 77", (self.root / ".local/install-macos.log").read_text())
        self.assertIn("consultar", result.stderr)
        self.assertNotIn("open:", self.events())
        self.assertNotIn("original mounting failure", result.stdout)

    def test_apple_tools_wait_and_continue_without_rerunning_setup(self):
        result = self.run_flow('''
git() { [ -f "$INSIGHTS_ROOT/ready" ]; }
xcode-select() { if [ "$1" = --install ]; then event 'apple-tools-requested'; else [ -f "$INSIGHTS_ROOT/ready" ]; fi; }
mac_prepare_git
event 'continued'
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events().splitlines(), ["apple-tools-requested", "wait:5", "continued"])

    def test_noninteractive_missing_git_opens_no_window(self):
        result = self.run_flow('''
INSIGHTS_NONINTERACTIVE=true
git() { return 1; }
xcode-select() { event 'unexpected-window'; }
mac_prepare_git
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.events(), "")

    def test_docker_timeout_requests_only_the_pending_confirmation(self):
        result = self.run_flow('''
touch "$INSIGHTS_ROOT/gh" "$INSIGHTS_ROOT/app"
sleep() { event "wait:$*"; }
install_macos
''')
        self.assertEqual(result.returncode, 2)
        self.assertIn("Conclua a janela do Docker", result.stderr)
        self.assertEqual(self.events().count("wait:5"), 2)
        self.assertNotIn("brew:", self.events())

    def test_noninteractive_brew_does_not_request_a_password(self):
        result = self.run_flow('''
INSIGHTS_NONINTERACTIVE=true
INSIGHTS_BREW=brew
mac_brew_run install gh
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        environment = (self.root / "brew-environment").read_text()
        self.assertIn("askpass=\n", environment)
        self.assertIn("no_sudo=1", environment)

    def test_checksum_mismatch_stops_before_installation(self):
        result = self.run_flow('''
# Restore the real download validation function, but replace its network command.
. "$INSIGHTS_SOURCE_ROOT/scripts/macos.sh"
curl() { while [ "$1" != -o ]; do shift; done; printf 'corrupted' > "$2"; }
mac_download_verified https://example.invalid/package "$INSIGHTS_ROOT/package" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
event 'unexpected-install'
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("verificacao", result.stderr)
        self.assertEqual(self.events(), "")

    def test_verified_cached_package_is_not_downloaded_again(self):
        expected = hashlib.sha256(b"verified").hexdigest()
        result = self.run_flow('''
. "$INSIGHTS_SOURCE_ROOT/scripts/macos.sh"
printf verified > "$INSIGHTS_ROOT/package"
curl() { event 'unexpected-download'; return 97; }
mac_download_verified https://example.invalid/package "$INSIGHTS_ROOT/package" ''' + expected + "\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(), "")

    def test_intel_uses_reviewed_shell_installer(self):
        result = self.run_flow('''
uname() { printf 'x86_64\n'; }
install_macos
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("8ab1549dfa1189fd4d818a2116592d8f0ee06d8c/install.sh", self.events())
        self.assertNotIn("admin:", self.events())

    def test_admin_confirmation_uses_local_macos_dialog_with_quoted_arguments(self):
        result = self.run_flow('''
. "$INSIGHTS_SOURCE_ROOT/scripts/macos.sh"
id() { printf '1000\n'; }
sudo() { return 1; }
osascript() { event "dialog:$*"; }
mac_admin /usr/sbin/installer -pkg "$INSIGHTS_ROOT/Homebrew.pkg" -target /
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("with administrator privileges", self.events())
        self.assertIn("Insights\\ com\\ espacos", self.events())

    def test_noninteractive_admin_opens_no_dialog(self):
        result = self.run_flow('''
. "$INSIGHTS_SOURCE_ROOT/scripts/macos.sh"
INSIGHTS_NONINTERACTIVE=true
id() { printf '1000\n'; }
sudo() { return 1; }
osascript() { event 'unexpected-dialog'; }
mac_admin /usr/sbin/installer -pkg "$INSIGHTS_ROOT/Homebrew.pkg" -target /
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.events(), "")

    def test_launcher_failure_records_stage_and_preserves_exit_code(self):
        for name in ("bootstrap_local.py", "macos.sh", "aws.sh", "aws-cli-public-key.asc"):
            shutil.copy(ROOT / "scripts" / name, self.root / "scripts")
        (self.root / "templates").mkdir()
        shutil.copy(ROOT / "templates/nginx.conf", self.root / "templates")
        for name in ("compose.local.yml", "sources.lock"):
            shutil.copy(ROOT / name, self.root)
        binary = self.root / "bin"
        binary.mkdir()
        uname = binary / "uname"
        uname.write_text("#!/bin/sh\nprintf 'Darwin\\n'\n")
        uname.chmod(0o755)
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/local.sh"), "setup", "--root", str(self.root)],
            env={**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"],
                 "INSIGHTS_INSTALL_WAIT_ATTEMPTS": "invalid"},
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("Tempo de espera", result.stderr)
        progress = (self.root / ".local/setup-progress.txt").read_text()
        self.assertIn("Preparando as ferramentas", progress)
        self.assertIn("interrompido (codigo 2)", progress)
        self.assertIn(str(self.root), progress)

    def test_incomplete_clone_fails_before_any_dependency_installation(self):
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/local.sh"), "setup", "--root", str(self.root)],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Repositorio incompleto", result.stderr)
        self.assertIn("interrompido", (self.root / ".local/setup-progress.txt").read_text())

    @unittest.skipUnless(sys.platform == "darwin", "AppleScript compilation requires macOS")
    def test_password_dialog_compiles_without_opening_or_collecting_password(self):
        helper = (ROOT / "scripts/macos-askpass.sh").read_text()
        source = helper.split("<<'APPLESCRIPT'\n", 1)[1].rsplit("\nAPPLESCRIPT", 1)[0]
        result = subprocess.run(
            ["/usr/bin/osacompile", "-o", str(self.root / "dialog.scpt")],
            input=source, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
