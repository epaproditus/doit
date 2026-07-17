"""Tests for connector pending model setting apply."""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch


class ProfileDirTests(unittest.TestCase):
    """_profiles_dir resolves from env or default."""

    def test_uses_env_when_set(self) -> None:
        from runner.connector import _profiles_dir

        with patch.dict(os.environ, {"HERMES_PROFILES_DIR": "/custom/path"}):
            self.assertEqual(_profiles_dir(), Path("/custom/path"))

    def test_defaults_when_env_unset(self) -> None:
        from runner.connector import _profiles_dir

        with patch.dict(os.environ, {}, clear=True):
            result = _profiles_dir()
        self.assertEqual(result, Path.home() / ".hermes" / "profiles")


class ReplaceTopLevelBlockTests(unittest.TestCase):
    """_replace_top_level_block replaces top-level YAML blocks."""

    def _call(self, existing: str, key: str, block: str) -> str:
        from runner.model_settings import _replace_top_level_block

        return _replace_top_level_block(existing, key, block)

    def test_replaces_existing_block(self) -> None:
        existing = """\
model:
  provider: openrouter
  default: google/gemini-2.5-flash
  base_url: https://openrouter.ai/api/v1

agent:
  max_turns: 50
"""
        new_block = "model:\n  provider: openai\n  default: gpt-4.1"
        result = self._call(existing, "model", new_block)
        self.assertIn("provider: openai", result)
        self.assertIn("default: gpt-4.1", result)
        self.assertNotIn("google/gemini-2.5-flash", result)
        self.assertIn("agent:", result)
        self.assertIn("max_turns: 50", result)

    def test_adds_block_when_missing(self) -> None:
        existing = """\
agent:
  max_turns: 50
"""
        new_block = "model:\n  provider: openai\n  default: gpt-4.1"
        result = self._call(existing, "model", new_block)
        self.assertIn("provider: openai", result)
        self.assertIn("max_turns: 50", result)

    def test_preserves_trailing_newline(self) -> None:
        existing = "model:\n  provider: openrouter\n  default: test\n"
        new_block = "model:\n  provider: anthropic\n  default: claude-sonnet-4"
        result = self._call(existing, "model", new_block)
        self.assertTrue(result.endswith("\n"))
        self.assertIn("anthropic", result)


class ApplyModelSettingTests(unittest.IsolatedAsyncioTestCase):
    """_apply_model_setting writes config and reports back."""

    def setUp(self) -> None:
        self._tmpdir = Path(tempfile.mkdtemp())
        self._profile_dir = self._tmpdir / "byo-hermes"
        self._profile_dir.mkdir(parents=True)
        self._config = self._profile_dir / "config.yaml"
        self._config.write_text(
            "model:\n  provider: openrouter\n  default: google/gemini-2.5-flash\n\nagent:\n  max_turns: 50\n"
        )

    def tearDown(self) -> None:
        import shutil
        shutil.rmtree(self._tmpdir, ignore_errors=True)

    @patch("runner.connector._profiles_dir")
    @patch("runner.connector._restart_hermes")
    async def test_success_applies_and_reports_applied(
        self, mock_restart: MagicMock, mock_profiles_dir: MagicMock
    ) -> None:
        from runner.connector import _apply_model_setting

        mock_profiles_dir.return_value = self._tmpdir
        api = AsyncMock()

        setting = {"provider": "openai", "model": "gpt-4.1", "base_url": None}
        await _apply_model_setting(api, "byo-hermes", setting)

        # Config was updated
        content = self._config.read_text()
        self.assertIn("provider: openai", content)
        self.assertIn("default: gpt-4.1", content)
        self.assertNotIn("google/gemini-2.5-flash", content)

        # Reported applied
        api.report_model_apply.assert_awaited_once_with(
            apply_status="applied",
            provider="openai",
            model="gpt-4.1",
        )

        # Restart called
        mock_restart.assert_called_once_with("byo-hermes")

    @patch("runner.connector._profiles_dir")
    @patch("runner.connector._restart_hermes")
    async def test_includes_base_url_when_present(
        self, mock_restart: MagicMock, mock_profiles_dir: MagicMock
    ) -> None:
        from runner.connector import _apply_model_setting

        mock_profiles_dir.return_value = self._tmpdir
        api = AsyncMock()

        setting = {
            "provider": "openai",
            "model": "gpt-4.1",
            "base_url": "https://api.openai.com/v1",
        }
        await _apply_model_setting(api, "byo-hermes", setting)

        content = self._config.read_text()
        self.assertIn("base_url: https://api.openai.com/v1", content)
        api.report_model_apply.assert_awaited_once_with(
            apply_status="applied",
            provider="openai",
            model="gpt-4.1",
        )

    @patch("runner.connector._profiles_dir")
    @patch("runner.connector._restart_hermes")
    async def test_missing_profile_dir_reports_failed(
        self, mock_restart: MagicMock, mock_profiles_dir: MagicMock
    ) -> None:
        from runner.connector import _apply_model_setting

        mock_profiles_dir.return_value = self._tmpdir
        api = AsyncMock()

        setting = {"provider": "openai", "model": "gpt-4.1"}
        await _apply_model_setting(api, "nonexistent", setting)

        api.report_model_apply.assert_awaited_once()
        args = api.report_model_apply.await_args
        assert args is not None
        self.assertEqual(args.kwargs["apply_status"], "failed")
        self.assertIn("not found", args.kwargs["apply_error"])

    @patch("runner.connector._profiles_dir")
    @patch("runner.connector._restart_hermes")
    async def test_report_failure_does_not_raise(
        self, mock_restart: MagicMock, mock_profiles_dir: MagicMock
    ) -> None:
        from runner.connector import _apply_model_setting

        mock_profiles_dir.return_value = self._tmpdir
        api = AsyncMock()
        api.report_model_apply.side_effect = RuntimeError("network error")

        setting = {"provider": "openai", "model": "gpt-4.1"}
        # Should not raise despite the report failure
        await _apply_model_setting(api, "byo-hermes", setting)

    @patch("runner.connector._profiles_dir")
    @patch("runner.connector._restart_hermes")
    async def test_apply_error_reports_failed(
        self, mock_restart: MagicMock, mock_profiles_dir: MagicMock
    ) -> None:
        from runner.connector import _apply_model_setting

        mock_profiles_dir.return_value = self._tmpdir
        api = AsyncMock()

        setting = {"provider": "openai", "model": "gpt-4.1", "base_url": None}

        # Remove write permission to trigger an error
        self._config.chmod(0o000)
        try:
            await _apply_model_setting(api, "byo-hermes", setting)
        finally:
            self._config.chmod(0o644)

        api.report_model_apply.assert_awaited_once()
        args = api.report_model_apply.await_args
        assert args is not None
        self.assertEqual(args.kwargs["apply_status"], "failed")


class RestartHermesTests(unittest.TestCase):
    """_restart_hermes tries profile-specific then default gateway."""

    @patch("subprocess.run")
    def test_tries_profile_gateway_first(self, mock_run: MagicMock) -> None:
        from runner.connector import _restart_hermes

        mock_run.return_value = MagicMock(returncode=0)

        _restart_hermes("byo-hermes")

        calls = [c[0][0] for c in mock_run.call_args_list]
        self.assertTrue(
            any("hermes-gateway-byo-hermes" in str(c) for c in calls)
        )

    @patch("subprocess.run")
    def test_falls_back_to_default_gateway(self, mock_run: MagicMock) -> None:
        from runner.connector import _restart_hermes

        import subprocess

        def side_effect(*args: object, **kwargs: object) -> MagicMock:
            cmd = args[0] if args else []
            if "hermes-gateway-byo-hermes" in str(cmd):
                raise subprocess.CalledProcessError(1, cmd, stderr="unit not found")
            return MagicMock(returncode=0)

        mock_run.side_effect = side_effect

        _restart_hermes("byo-hermes")

        self.assertGreaterEqual(mock_run.call_count, 2)


if __name__ == "__main__":
    unittest.main()
