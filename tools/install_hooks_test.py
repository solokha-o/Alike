#!/usr/bin/env python3
"""Regression tests for tools/install-hooks.

Each test copies the installer and the hook into a temporary Git repository
under build/ (ignored by Git) and runs the installer there.

Run:
  python3 tools/install_hooks_test.py
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DISPATCH = "#!/bin/sh\n# global dispatch\n"


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


class InstallHooksTests(unittest.TestCase):
    def setUp(self) -> None:
        scratch_root = ROOT / "build" / "install-hooks-test"
        scratch_root.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=scratch_root)
        self.repo = Path(self.tmp.name) / "repo"
        (self.repo / "tools/hooks").mkdir(parents=True)
        for name in ("tools/install-hooks", "tools/hooks/pre-commit"):
            shutil.copy2(ROOT / name, self.repo / name)
        # A stub tools/lint --staged that always fails, so a stopped commit
        # proves that the hook of the committing worktree ran.
        stub = self.repo / "tools/lint"
        stub.write_text('#!/bin/sh\n# --staged\necho "stub lint ran in $(pwd)"\nexit 1\n')
        stub.chmod(0o755)
        git(self.repo, "init", "-q", "-b", "develop")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "base")
        self.link = self.repo / ".git/hooks/pre-commit"
        # A fake global config with core.hooksPath, as on a machine with the
        # git-workflow dispatch. The installer must never write there.
        self.global_hooks = Path(self.tmp.name) / "global-hooks"
        self.global_hooks.mkdir()
        (self.global_hooks / "pre-commit").write_text(DISPATCH)
        self.global_config = Path(self.tmp.name) / "gitconfig"
        self.global_config.write_text(f"[core]\n\thooksPath = {self.global_hooks}\n")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def install(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        directory = cwd or self.repo
        return subprocess.run(
            [str(directory / "tools/install-hooks"), *args],
            cwd=directory,
            env=dict(os.environ, GIT_CONFIG_GLOBAL=str(self.global_config)),
            capture_output=True,
            text=True,
        )

    def assert_no_local_hooks_path(self) -> None:
        result = subprocess.run(
            ["git", "config", "--local", "--get", "core.hooksPath"],
            cwd=self.repo,
            capture_output=True,
        )
        self.assertNotEqual(result.returncode, 0, "install-hooks must not set core.hooksPath")

    def commit(self, cwd: Path) -> subprocess.CompletedProcess[str]:
        # No global config, so no global core.hooksPath: Git runs the shim directly.
        (cwd / "change.txt").write_text(str(cwd))
        subprocess.run(["git", "add", "change.txt"], cwd=cwd, check=True)
        return subprocess.run(
            ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
             "commit", "-q", "-m", "change"],
            cwd=cwd,
            env=dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull),
            capture_output=True,
            text=True,
        )

    def assert_is_shim(self) -> None:
        self.assertFalse(self.link.is_symlink())
        self.assertTrue(os.access(self.link, os.X_OK))
        self.assertIn("# alike-pre-commit-shim", self.link.read_text())

    def test_installs_the_shim(self) -> None:
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_is_shim()
        self.assert_no_local_hooks_path()
        stopped = self.commit(self.repo)
        self.assertEqual(stopped.returncode, 1, stopped.stdout + stopped.stderr)
        self.assertIn(f"stub lint ran in {self.repo}", stopped.stderr)

    def test_global_hooks_path_is_not_touched(self) -> None:
        for args in ((), ("--force",), ("--uninstall",), ()):
            result = self.install(*args)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_is_shim()
        self.assertEqual((self.global_hooks / "pre-commit").read_text(), DISPATCH)
        self.assertEqual([p.name for p in self.global_hooks.iterdir()], ["pre-commit"])
        self.assertIn("runs its checks, then runs", result.stdout)

    def test_install_is_idempotent(self) -> None:
        self.assertEqual(self.install().returncode, 0)
        again = self.install()
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertIn("already installed", again.stdout)
        self.assert_is_shim()

    def test_refuses_a_foreign_hook_unless_forced(self) -> None:
        self.link.parent.mkdir(exist_ok=True)
        self.link.write_text("#!/bin/sh\nexit 0\n")
        refused = self.install()
        self.assertEqual(refused.returncode, 1, refused.stdout + refused.stderr)
        self.assertIn("--force", refused.stderr)
        self.assertFalse(self.link.is_symlink())
        self.assertEqual(self.link.read_text(), "#!/bin/sh\nexit 0\n")
        forced = self.install("--force")
        self.assertEqual(forced.returncode, 0, forced.stdout + forced.stderr)
        self.assert_is_shim()

    def test_uninstall_removes_only_the_alike_hook(self) -> None:
        self.assertEqual(self.install().returncode, 0)
        removed = self.install("--uninstall")
        self.assertEqual(removed.returncode, 0, removed.stdout + removed.stderr)
        self.assertFalse(self.link.exists() or self.link.is_symlink())
        self.assertIn("No pre-commit hook", self.install("--uninstall").stdout)
        self.link.write_text("#!/bin/sh\nexit 0\n")
        foreign = self.install("--uninstall")
        self.assertEqual(foreign.returncode, 1, foreign.stdout + foreign.stderr)
        self.assertTrue(self.link.exists())

    def test_hook_survives_removal_of_the_installing_worktree(self) -> None:
        installer = Path(self.tmp.name) / "installer"
        other = Path(self.tmp.name) / "other"
        git(self.repo, "worktree", "add", "-q", "-b", "installer", str(installer))
        git(self.repo, "worktree", "add", "-q", "-b", "other", str(other))
        result = self.install(cwd=installer)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_is_shim()
        git(self.repo, "worktree", "remove", str(installer))
        self.assertFalse(installer.exists())
        for worktree in (other, self.repo):
            stopped = self.commit(worktree)
            self.assertEqual(stopped.returncode, 1, stopped.stdout + stopped.stderr)
            self.assertIn(f"stub lint ran in {worktree}", stopped.stderr)

    def test_branch_without_the_hook_file_can_commit(self) -> None:
        self.assertEqual(self.install().returncode, 0)
        git(self.repo, "rm", "-q", "tools/hooks/pre-commit")
        result = self.commit(self.repo)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("has no tools/hooks/pre-commit", result.stderr)

    def test_legacy_broken_symlink_is_upgraded(self) -> None:
        self.link.parent.mkdir(exist_ok=True)
        self.link.symlink_to(Path(self.tmp.name) / "removed/tools/hooks/pre-commit")
        self.assertFalse(self.link.exists())
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_is_shim()

    def test_unknown_option_is_a_usage_error(self) -> None:
        self.assertEqual(self.install("--nosuch").returncode, 64)


if __name__ == "__main__":
    unittest.main()
