"""Tests for Hermes runner error messages."""
from __future__ import annotations

import unittest

import httpx


def _status_error(status: int, url: str = "http://127.0.0.1:8643/v1/runs") -> httpx.HTTPStatusError:
    request = httpx.Request("POST", url)
    response = httpx.Response(status, request=request)
    return httpx.HTTPStatusError(
        f"Client error '{status}' for url '{url}'",
        request=request,
        response=response,
    )


class HermesHttpFailureMessageTests(unittest.TestCase):
    def test_401_uses_operational_message_without_local_url(self) -> None:
        from runner.runner import _hermes_http_failure_message

        message, detail = _hermes_http_failure_message(_status_error(401))

        self.assertIn("authentication failed", message)
        self.assertIn("repair your Hermes profile", message)
        self.assertNotIn("127.0.0.1", message)
        self.assertNotIn("127.0.0.1", detail)

    def test_connect_error_uses_retryable_gateway_message(self) -> None:
        from runner.runner import _hermes_http_failure_message

        error = httpx.ConnectError(
            "connection refused",
            request=httpx.Request("POST", "http://127.0.0.1:8643/v1/runs"),
        )
        message, detail = _hermes_http_failure_message(error)

        self.assertIn("not reachable", message)
        self.assertIn("could not connect", detail)


class BYOConnectorFailureMessageTests(unittest.TestCase):
    def test_connect_error_mentions_connector_and_configured_hermes_url(self) -> None:
        import httpx
        from runner.connector import _friendly_hermes_error
        from runner.hermes import HermesEndpoint

        endpoint = HermesEndpoint(
            profile_name="byo-hermes",
            host="127.0.0.1",
            port=8643,
            api_key="",
        )
        error = httpx.ConnectError(
            "All connection attempts failed",
            request=httpx.Request("POST", "http://127.0.0.1:8643/v1/runs"),
        )

        message = _friendly_hermes_error(endpoint, error)

        self.assertIn("connector is online", message)
        self.assertIn("cannot reach Hermes", message)
        self.assertIn("http://127.0.0.1:8643", message)
        self.assertNotIn("All connection attempts failed", message)


class HostedClaimExclusionTests(unittest.TestCase):
    def test_merge_excluded_user_ids_preserves_order_and_dedupes(self) -> None:
        from runner.runner import _merge_excluded_user_ids

        merged = _merge_excluded_user_ids(
            ["hosted-capped", "shared"],
            ["shared", "byo-user"],
            None,
        )

        self.assertEqual(merged, ["hosted-capped", "shared", "byo-user"])


class BrowserSessionFailureMessageTests(unittest.TestCase):
    def test_cdp_websocket_failure_uses_retryable_browser_message(self) -> None:
        from runner.runner import _browser_session_failure_message

        raw = "CDP WebSocket connect failed: HTTP error: 410 Gone"
        result = _browser_session_failure_message(raw)

        self.assertIsNotNone(result)
        assert result is not None
        message, detail = result
        self.assertIn("browser session disconnected", message)
        self.assertIn("Try again", message)
        self.assertEqual(detail, raw)
        self.assertNotIn("CDP", message)
        self.assertNotIn("410 Gone", message)

    def test_non_browser_failure_is_not_classified(self) -> None:
        from runner.runner import _browser_session_failure_message

        self.assertIsNone(_browser_session_failure_message("model provider overloaded"))


if __name__ == "__main__":
    unittest.main()
