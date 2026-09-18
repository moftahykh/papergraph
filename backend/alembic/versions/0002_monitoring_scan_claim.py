"""add monitoring scan claim timestamp

Revision ID: 0002_monitoring_scan_claim
Revises: 0001_monitoring
Create Date: 2026-09-18
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0002_monitoring_scan_claim"
down_revision: Union[str, None] = "0001_monitoring"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "monitored_graphs",
        sa.Column("scan_claimed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_monitored_graphs_scan_claimed_at",
        "monitored_graphs",
        ["scan_claimed_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_monitored_graphs_scan_claimed_at", table_name="monitored_graphs")
    op.drop_column("monitored_graphs", "scan_claimed_at")