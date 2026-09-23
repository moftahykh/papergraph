"""store the last monitoring scan status

Revision ID: 0006_monitoring_scan_status
Revises: 0005_research_reminders
Create Date: 2026-09-22
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0006_monitoring_scan_status"
down_revision: Union[str, None] = "0005_research_reminders"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "monitored_graphs",
        sa.Column(
            "last_scan_status",
            sa.String(length=16),
            nullable=False,
            server_default="pending",
        ),
    )
    op.add_column(
        "monitored_graphs",
        sa.Column("last_scan_error", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("monitored_graphs", "last_scan_error")
    op.drop_column("monitored_graphs", "last_scan_status")