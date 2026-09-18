from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

import httpx
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.monitoring import MonitoredGraph
from app.repositories.monitoring import (
    deactivate_device_token,
    list_all_active_device_tokens,
    list_active_device_tokens,
)

logger = logging.getLogger("papergraph.notifications.fcm")

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_FCM_ENDPOINT = (
    "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
)


def _credentials() -> service_account.Credentials | None:
    raw = settings.FIREBASE_SERVICE_ACCOUNT_JSON
    if not settings.FIREBASE_PROJECT_ID or not raw:
        return None
    try:
        info = json.loads(raw)
        return service_account.Credentials.from_service_account_info(
            info,
            scopes=[_FCM_SCOPE],
        )
    except (TypeError, ValueError, json.JSONDecodeError):
        logger.exception("Invalid FIREBASE_SERVICE_ACCOUNT_JSON configuration.")
        return None


def _message(graph: MonitoredGraph, update_count: int, token: str) -> dict[str, Any]:
    count_label = "new paper" if update_count == 1 else "new papers"
    return {
        "message": {
            "token": token,
            "notification": {
                "title": f"New research for {graph.graph_title}",
                "body": f"{update_count} {count_label} matched this saved graph.",
            },
            "data": {
                "type": "research_updates",
                "local_graph_id": graph.local_graph_id,
                "graph_id": graph.local_graph_id,
                "graph_title": graph.graph_title,
                "update_count": str(update_count),
            },
            "android": {
                "notification": {
                    "channel_id": "paper_graph_channel",
                    "click_action": "FLUTTER_NOTIFICATION_CLICK",
                }
            },
            "apns": {
                "payload": {
                    "aps": {
                        "sound": "default",
                    }
                }
            },
        }
    }


async def send_research_update_notifications(
    db: AsyncSession,
    graph: MonitoredGraph,
    update_count: int,
) -> int:
    """Send one FCM message per active device for a graph.

    If the service-account secret is not configured, this is intentionally a
    safe no-op. Scanning and in-app update history must continue to work
    independently of push delivery.
    """
    if update_count < 1:
        return 0

    credentials = _credentials()
    if credentials is None:
        logger.info(
            "FCM delivery skipped for graph %s; service account is not configured.",
            graph.id,
        )
        return 0

    try:
        credentials.refresh(Request())
        access_token = credentials.token
    except Exception:
        logger.exception("Could not refresh Firebase service-account token.")
        return 0

    devices = await list_active_device_tokens(db, graph.user_id)
    if not devices:
        return 0

    endpoint = _FCM_ENDPOINT.format(project_id=settings.FIREBASE_PROJECT_ID)
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    delivered = 0

    async with httpx.AsyncClient(timeout=settings.PROVIDER_TIMEOUT_SECONDS) as client:
        for device in devices:
            try:
                response = await client.post(
                    endpoint,
                    headers=headers,
                    json=_message(graph, update_count, device.fcm_token),
                )
                if response.is_success:
                    delivered += 1
                    continue

                # FCM uses NOT_FOUND/UNREGISTERED for tokens that should no
                # longer be retried. Keep bad tokens from failing future scans.
                body = response.text.upper()
                if response.status_code in {400, 404} and (
                    "UNREGISTERED" in body
                    or "NOT_FOUND" in body
                    or "INVALID_ARGUMENT" in body
                ):
                    await deactivate_device_token(
                        db,
                        graph.user_id,
                        device.fcm_token,
                    )
                logger.warning(
                    "FCM delivery failed for device %s: status=%s",
                    device.id,
                    response.status_code,
                )
            except httpx.HTTPError:
                logger.exception("FCM request failed for device %s.", device.id)

    return delivered


async def send_test_notification_to_all_devices(
    db: AsyncSession,
    *,
    confirmation: str,
) -> tuple[int, int]:
    """Send one explicitly confirmed smoke-test message to all active devices.

    This is intentionally only called by a manually dispatched, one-off
    workflow. It is not part of the normal monitoring scan.
    """
    if confirmation != "I_UNDERSTAND_SEND_TO_ALL_ACTIVE_DEVICES":
        raise ValueError("Explicit all-device confirmation is required.")

    credentials = _credentials()
    if credentials is None:
        logger.info("FCM broadcast test skipped; service account is not configured.")
        return 0, 0

    try:
        credentials.refresh(Request())
        access_token = credentials.token
    except Exception:
        logger.exception("Could not refresh Firebase service-account token.")
        return 0, 0

    devices = await list_all_active_device_tokens(db)
    if not devices:
        return 0, 0

    endpoint = _FCM_ENDPOINT.format(project_id=settings.FIREBASE_PROJECT_ID)
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    sent = 0
    invalidated = 0
    now = datetime.now(timezone.utc).isoformat()

    async with httpx.AsyncClient(timeout=settings.PROVIDER_TIMEOUT_SECONDS) as client:
        for device in devices:
            payload = {
                "message": {
                    "token": device.fcm_token,
                    "notification": {
                        "title": "PaperGraph test notification",
                        "body": "FCM delivery is connected.",
                    },
                    "data": {
                        "type": "fcm_test",
                        "test_id": now,
                    },
                    "android": {
                        "notification": {
                            "channel_id": "paper_graph_channel",
                        }
                    },
                    "apns": {
                        "payload": {"aps": {"sound": "default"}},
                    },
                }
            }
            try:
                response = await client.post(
                    endpoint,
                    headers=headers,
                    json=payload,
                )
                if response.is_success:
                    sent += 1
                    continue

                body = response.text.upper()
                if response.status_code in {400, 404} and (
                    "UNREGISTERED" in body
                    or "NOT_FOUND" in body
                    or "INVALID_ARGUMENT" in body
                ):
                    await deactivate_device_token(
                        db,
                        device.user_id,
                        device.fcm_token,
                    )
                    invalidated += 1
                logger.warning(
                    "FCM test delivery failed for device %s: status=%s",
                    device.id,
                    response.status_code,
                )
            except httpx.HTTPError:
                logger.exception("FCM test request failed for device %s.", device.id)

    return sent, invalidated