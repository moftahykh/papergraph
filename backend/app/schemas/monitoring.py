from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


Frequency = Literal["daily", "weekly"]
MonitoringStatus = Literal["active", "paused"]


class MonitoredPaperInput(BaseModel):
    canonical_id: str = Field(min_length=1, max_length=255)
    title: str = Field(min_length=1, max_length=1000)
    doi: str | None = Field(default=None, max_length=255)
    openalex_id: str | None = Field(default=None, max_length=255)
    semantic_scholar_id: str | None = Field(default=None, max_length=255)
    year: int | None = Field(default=None, ge=0, le=3000)


class CreateMonitoredGraphRequest(BaseModel):
    local_graph_id: str = Field(min_length=1, max_length=128)
    graph_title: str = Field(min_length=1, max_length=500)
    papers: list[MonitoredPaperInput] = Field(min_length=1, max_length=200)
    frequency: Frequency = "daily"
    timezone: str = Field(default="Asia/Riyadh", min_length=1, max_length=64)


class UpdateMonitoredGraphRequest(BaseModel):
    status: MonitoringStatus | None = None
    frequency: Frequency | None = None
    timezone: str | None = Field(default=None, min_length=1, max_length=64)


class MonitoredGraphResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    local_graph_id: str
    graph_title: str
    status: str
    frequency: str
    timezone: str
    last_checked_at: datetime | None
    next_check_at: datetime
    last_notified_at: datetime | None
    created_at: datetime
    updated_at: datetime


class ResearchUpdateResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    monitored_graph_id: str
    canonical_paper_id: str
    doi: str | None
    title: str
    abstract: str | None
    published_at: datetime | None
    relevance_score: float
    relation_type: str
    explanation: str
    detected_at: datetime
    is_read: bool
    is_added_to_graph: bool


class DeviceTokenRequest(BaseModel):
    fcm_token: str = Field(min_length=1, max_length=4096)
    platform: Literal["android", "ios", "web"] 