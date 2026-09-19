from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class DiscoveryTopicResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    label: str
    query: str
    rank: int


class DiscoveryRecommendationResponse(BaseModel):
    canonical_id: str
    doi: str | None = None
    title: str
    reason: str
    local_graph_id: str
    graph_title: str
    relation_type: str
    relevance_score: float
    detected_at: datetime


class DiscoveryHomeResponse(BaseModel):
    topics: list[DiscoveryTopicResponse] = Field(default_factory=list)
    recommendation: DiscoveryRecommendationResponse | None = None
