"""separate update notifications from hidden re-engagement reminders

Revision ID: 0007_notification_preferences
Revises: 0006_monitoring_scan_status
Create Date: 2026-09-22
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0007_notification_preferences"
down_revision: Union[str, None] = "0006_monitoring_scan_status"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "device_tokens",
        sa.Column(
            "research_updates_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
    )
    # Re-engagement reminders are an automatic product behavior, not a
    # user-facing preference. Existing registered devices should participate.
    op.execute(
        "UPDATE device_tokens "
        "SET research_reminders_enabled = TRUE "
        "WHERE is_active = TRUE"
    )


def downgrade() -> None:
    op.drop_column("device_tokens", "research_updates_enabled")