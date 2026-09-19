"""add server-managed discovery topics

Revision ID: 0003_discovery
Revises: 0002_monitoring_scan_claim
Create Date: 2026-09-19
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0003_discovery"
down_revision: Union[str, None] = "0002_monitoring_scan_claim"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "discovery_topics",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("label", sa.String(length=120), nullable=False),
        sa.Column("query", sa.String(length=500), nullable=False),
        sa.Column("rank", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )

    topics = sa.table(
        "discovery_topics",
        sa.column("id", sa.String),
        sa.column("label", sa.String),
        sa.column("query", sa.String),
        sa.column("rank", sa.Integer),
        sa.column("is_active", sa.Boolean),
    )
    op.bulk_insert(
        topics,
        [
            {
                "id": "topic_ml",
                "label": "Machine Learning",
                "query": "machine learning",
                "rank": 10,
                "is_active": True,
            },
            {
                "id": "topic_biotech",
                "label": "Biotechnology",
                "query": "biotechnology",
                "rank": 20,
                "is_active": True,
            },
            {
                "id": "topic_genetics",
                "label": "Genetics",
                "query": "genetics",
                "rank": 30,
                "is_active": True,
            },
            {
                "id": "topic_materials",
                "label": "Materials science",
                "query": "materials science",
                "rank": 40,
                "is_active": True,
            },
        ],
    )


def downgrade() -> None:
    op.drop_table("discovery_topics")
