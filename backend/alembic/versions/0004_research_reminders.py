"""add opt-in research re-engagement reminders

Revision ID: 0005_research_reminders
Revises: 0004_monitoring_update_evidence
Create Date: 2026-09-22
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0005_research_reminders"
down_revision: Union[str, None] = "0004_monitoring_update_evidence"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "device_tokens",
        sa.Column(
            "research_reminders_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
    )
    op.add_column(
        "device_tokens",
        sa.Column("last_reengagement_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("device_tokens", "last_reengagement_at")
    op.drop_column("device_tokens", "research_reminders_enabled")