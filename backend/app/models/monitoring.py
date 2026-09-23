from datetime import datetime, timezone
from typing import List

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class MonitoredGraph(Base):
    __tablename__ = "monitored_graphs"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "local_graph_id",
            name="uq_monitored_graph_owner_local_id",
        ),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    local_graph_id: Mapped[str] = mapped_column(String(128), nullable=False)
    graph_title: Mapped[str] = mapped_column(String(500), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16), nullable=False, default="active", server_default="active"
    )
    frequency: Mapped[str] = mapped_column(
        String(16), nullable=False, default="daily", server_default="daily"
    )
    timezone: Mapped[str] = mapped_column(
        String(64), nullable=False, default="Asia/Riyadh", server_default="Asia/Riyadh"
    )
    last_checked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_scan_status: Mapped[str] = mapped_column(
        String(16), nullable=False, default="pending", server_default="pending"
    )
    last_scan_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    next_check_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    last_notified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    scan_claimed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=utc_now
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=utc_now, onupdate=utc_now
    )

    papers: Mapped[List["MonitoredGraphPaper"]] = relationship(
        back_populates="graph",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )
    updates: Mapped[List["ResearchUpdate"]] = relationship(
        back_populates="graph",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class MonitoredGraphPaper(Base):
    __tablename__ = "monitored_graph_papers"
    __table_args__ = (
        UniqueConstraint(
            "monitored_graph_id",
            "canonical_id",
            name="uq_monitored_graph_paper",
        ),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    monitored_graph_id: Mapped[str] = mapped_column(
        String(64),
        ForeignKey("monitored_graphs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    canonical_id: Mapped[str] = mapped_column(String(255), nullable=False)
    doi: Mapped[str | None] = mapped_column(String(255), nullable=True)
    openalex_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    semantic_scholar_id: Mapped[str | None] = mapped_column(
        String(255), nullable=True
    )
    title: Mapped[str] = mapped_column(String(1000), nullable=False)
    year: Mapped[int | None] = mapped_column(Integer, nullable=True)

    graph: Mapped[MonitoredGraph] = relationship(back_populates="papers")


class ResearchUpdate(Base):
    __tablename__ = "research_updates"
    __table_args__ = (
        UniqueConstraint(
            "monitored_graph_id",
            "canonical_paper_id",
            name="uq_research_update_paper",
        ),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    monitored_graph_id: Mapped[str] = mapped_column(
        String(64),
        ForeignKey("monitored_graphs.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    canonical_paper_id: Mapped[str] = mapped_column(String(255), nullable=False)
    doi: Mapped[str | None] = mapped_column(String(255), nullable=True)
    title: Mapped[str] = mapped_column(String(1000), nullable=False)
    abstract: Mapped[str | None] = mapped_column(Text, nullable=True)
    published_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    relevance_score: Mapped[float] = mapped_column(
        Float, nullable=False, default=0.0, server_default="0"
    )
    relation_type: Mapped[str] = mapped_column(
        String(64), nullable=False, default="related", server_default="related"
    )
    explanation: Mapped[str] = mapped_column(Text, nullable=False)
    detected_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=utc_now
    )
    is_read: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    is_added_to_graph: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )

    graph: Mapped[MonitoredGraph] = relationship(back_populates="updates")


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    fcm_token: Mapped[str] = mapped_column(String(4096), nullable=False, unique=True)
    platform: Mapped[str] = mapped_column(String(16), nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=utc_now
    )
    research_updates_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    research_reminders_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    last_reengagement_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )