import importlib
from datetime import datetime, timezone


def test_discovery_schemas_serialization():
    from app.schemas.discovery import (
        DiscoveryTopicResponse,
        DiscoveryRecommendationResponse,
        DiscoveryHomeResponse,
    )

    topic = DiscoveryTopicResponse(
        id="topic_test",
        label="Quantum Computing",
        query="quantum computing",
        rank=5,
    )
    assert topic.label == "Quantum Computing"
    assert topic.query == "quantum computing"
    assert topic.rank == 5

    rec = DiscoveryRecommendationResponse(
        canonical_id="paper_xyz",
        doi="10.1000/182",
        title="Scalable Quantum Processors",
        reason="Direct citation to your graph seed",
        local_graph_id="monitored_graph_123",
        graph_title="Quantum Graph",
        relation_type="citation",
        relevance_score=0.95,
        detected_at=datetime.now(timezone.utc),
    )
    assert rec.canonical_id == "paper_xyz"
    assert rec.local_graph_id == "monitored_graph_123"
    assert rec.graph_title == "Quantum Graph"

    home = DiscoveryHomeResponse(topics=[topic], recommendation=rec)
    dumped = home.model_dump()
    assert len(dumped["topics"]) == 1
    assert dumped["recommendation"]["local_graph_id"] == "monitored_graph_123"


def test_discovery_migration_revision_chain():
    import importlib.util
    from pathlib import Path

    file_path = Path(__file__).parent.parent / "alembic" / "versions" / "0003_discovery.py"
    spec = importlib.util.spec_from_file_location("0003_discovery", file_path)
    migration_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration_mod)

    assert migration_mod.revision == "0003_discovery"
    assert migration_mod.down_revision == "0002_monitoring_scan_claim"


def test_discovery_model_metadata():
    from app.models.discovery import DiscoveryTopic
    assert DiscoveryTopic.__tablename__ == "discovery_topics"
    assert "local_graph_id" not in DiscoveryTopic.__table__.columns  # topics table only has topic fields
    assert "updated_at" in DiscoveryTopic.__table__.columns
