from __future__ import annotations

import asyncio
import os

from app.db.session import SessionLocal
from app.notifications.fcm import send_test_notification_to_all_devices


CONFIRMATION = "I_UNDERSTAND_SEND_TO_ALL_ACTIVE_DEVICES"


async def run() -> int:
    if os.getenv("CONFIRM_FCM_BROADCAST") != CONFIRMATION:
        raise SystemExit(
            "Refusing to broadcast. Set "
            f"CONFIRM_FCM_BROADCAST={CONFIRMATION}"
        )

    async with SessionLocal() as db:
        sent, invalidated = await send_test_notification_to_all_devices(
            db,
            confirmation=CONFIRMATION,
        )

    print(f"FCM test sent={sent} invalidated={invalidated}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(run()))