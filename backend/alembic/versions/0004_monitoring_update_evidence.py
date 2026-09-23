"""store evidence for research-update relationships

Revision ID: 0004_monitoring_update_evidence
Revises: 0003_discovery
Create Date: 2026-09-20
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0004_monitoring_update_evidence"
down_revision: Union[str, None] = "0003_discovery"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "research_updates",
        sa.Column("evidence", sa.JSON(), nullable=False, server_default="{}"),
    )


def downgrade() -> None:
    op.drop_column("research_updates", "evidence")