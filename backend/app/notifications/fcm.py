from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

import httpx
from google.auth.transport.requests import Request
from google.oauth2 import service_account
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.models.monitoring import MonitoredGraph
from app.repositories.monitoring import (
    deactivate_device_token,
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
    display_count = min(update_count, 5)
    count_label = "relevant paper" if display_count == 1 else "relevant papers"
    graph_title = graph.graph_title.strip() or "your saved graph"
    return {
        "message": {
            "token": token,
            "data": {
                "type": "research_updates",
                "title": f"New research for {graph_title}",
                "body": (
                    f"{display_count} {count_label} found. "
                    "Tap to review the updates."
                ),
                "local_graph_id": graph.local_graph_id,
                "graph_id": graph.local_graph_id,
                "graph_title": graph_title,
                "update_count": str(display_count),
                "deep_link": (
                    f"papergraph://graphs/{graph.local_graph_id}/updates"
                ),
            },
            "android": {
                "priority": "HIGH",
            },
            "apns": {
                "headers": {
                    "apns-push-type": "background",
                    "apns-priority": "5",
                },
                "payload": {
                    "aps": {
                        "content-available": 1,
                    }
                },
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


async def send_research_navigation_test(
    db: AsyncSession,
    *,
    local_graph_id: str,
    confirmation: str,
) -> tuple[int, str, str]:
    """Send one navigation-only push using an existing persisted update.

    This is deliberately scoped to the most recently updated graph matching
    the supplied local ID and its most recently seen device token. It never
    creates a research update and never broadcasts to all devices.
    """
    if confirmation != "I_UNDERSTAND_SEND_ONE_GRAPH_TEST":
        raise ValueError("Explicit one-graph confirmation is required.")

    result = await db.execute(
        select(MonitoredGraph)
        .options(selectinload(MonitoredGraph.updates))
        .where(MonitoredGraph.local_graph_id == local_graph_id)
        .order_by(MonitoredGraph.updated_at.desc())
        .limit(1)
    )
    graph = result.scalar_one_or_none()
    if graph is None:
        raise ValueError(f"No monitored graph found for {local_graph_id}.")
    if not graph.updates:
        raise ValueError(
            "This graph has no persisted research updates. "
            "Run the monitoring scanner first."
        )

    devices = await list_active_device_tokens(db, graph.user_id)
    if not devices:
        raise ValueError("This graph owner has no active device token.")
    device = devices[0]

    credentials = _credentials()
    if credentials is None:
        raise ValueError("Firebase service-account credentials are not configured.")
    try:
        credentials.refresh(Request())
        access_token = credentials.token
    except Exception as exc:
        raise RuntimeError("Could not refresh Firebase service-account token.") from exc

    graph_title = graph.graph_title.strip() or "your saved graph"
    update_count = len(graph.updates)
    now = datetime.now(timezone.utc).isoformat()
    payload = {
        "message": {
            "token": device.fcm_token,
            "data": {
                "type": "research_updates",
                "title": f"Research updates for {graph_title}",
                "body": (
                    f"{update_count} persisted update(s) available. "
                    "Tap to review the updates."
                ),
                "local_graph_id": graph.local_graph_id,
                "graph_id": graph.local_graph_id,
                "graph_title": graph_title,
                "update_count": str(update_count),
                "deep_link": (
                    f"papergraph://graphs/{graph.local_graph_id}/updates"
                ),
                "test_id": now,
                "test_mode": "navigation_only",
            },
            "android": {
                "priority": "HIGH",
            },
            "apns": {
                "headers": {
                    "apns-push-type": "background",
                    "apns-priority": "5",
                },
                "payload": {
                    "aps": {
                        "content-available": 1,
                    }
                },
            },
        }
    }
    endpoint = _FCM_ENDPOINT.format(project_id=settings.FIREBASE_PROJECT_ID)
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    async with httpx.AsyncClient(timeout=settings.PROVIDER_TIMEOUT_SECONDS) as client:
        response = await client.post(endpoint, headers=headers, json=payload)
    if not response.is_success:
        raise RuntimeError(
            f"FCM navigation test failed with status {response.status_code}."
        )

    latest_update = max(graph.updates, key=lambda item: item.detected_at)
    return 1, graph_title, latest_update.title