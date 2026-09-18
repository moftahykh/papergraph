"""create research monitoring tables

Revision ID: 0001_monitoring
Revises:
Create Date: 2026-09-18
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0001_monitoring"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "monitored_graphs",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("user_id", sa.String(length=128), nullable=False),
        sa.Column("local_graph_id", sa.String(length=128), nullable=False),
        sa.Column("graph_title", sa.String(length=500), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="active"),
        sa.Column("frequency", sa.String(length=16), nullable=False, server_default="daily"),
        sa.Column("timezone", sa.String(length=64), nullable=False, server_default="Asia/Riyadh"),
        sa.Column("last_checked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("next_check_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_notified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "local_graph_id", name="uq_monitored_graph_owner_local_id"),
    )
    op.create_index("ix_monitored_graphs_user_id", "monitored_graphs", ["user_id"])
    op.create_index("ix_monitored_graphs_next_check_at", "monitored_graphs", ["next_check_at"])

    op.create_table(
        "monitored_graph_papers",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("monitored_graph_id", sa.String(length=64), nullable=False),
        sa.Column("canonical_id", sa.String(length=255), nullable=False),
        sa.Column("doi", sa.String(length=255), nullable=True),
        sa.Column("openalex_id", sa.String(length=255), nullable=True),
        sa.Column("semantic_scholar_id", sa.String(length=255), nullable=True),
        sa.Column("title", sa.String(length=1000), nullable=False),
        sa.Column("year", sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(
            ["monitored_graph_id"],
            ["monitored_graphs.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "monitored_graph_id",
            "canonical_id",
            name="uq_monitored_graph_paper",
        ),
    )
    op.create_index(
        "ix_monitored_graph_papers_monitored_graph_id",
        "monitored_graph_papers",
        ["monitored_graph_id"],
    )

    op.create_table(
        "research_updates",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("monitored_graph_id", sa.String(length=64), nullable=False),
        sa.Column("canonical_paper_id", sa.String(length=255), nullable=False),
        sa.Column("doi", sa.String(length=255), nullable=True),
        sa.Column("title", sa.String(length=1000), nullable=False),
        sa.Column("abstract", sa.Text(), nullable=True),
        sa.Column("published_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("relevance_score", sa.Float(), nullable=False, server_default="0"),
        sa.Column("relation_type", sa.String(length=64), nullable=False, server_default="related"),
        sa.Column("explanation", sa.Text(), nullable=False),
        sa.Column("detected_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_read", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_added_to_graph", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.ForeignKeyConstraint(
            ["monitored_graph_id"],
            ["monitored_graphs.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint(
            "monitored_graph_id",
            "canonical_paper_id",
            name="uq_research_update_paper",
        ),
    )
    op.create_index(
        "ix_research_updates_monitored_graph_id",
        "research_updates",
        ["monitored_graph_id"],
    )

    op.create_table(
        "device_tokens",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("user_id", sa.String(length=128), nullable=False),
        sa.Column("fcm_token", sa.String(length=4096), nullable=False, unique=True),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.create_index("ix_device_tokens_user_id", "device_tokens", ["user_id"])


def downgrade() -> None:
    op.drop_table("device_tokens")
    op.drop_table("research_updates")
    op.drop_table("monitored_graph_papers")
    op.drop_table("monitored_graphs")