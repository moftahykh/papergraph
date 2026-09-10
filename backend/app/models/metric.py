from typing import Optional, Literal
from pydantic import BaseModel, Field
from app.models.enums import MetricAvailability


class MetricResult(BaseModel):
    """
    Encapsulates a nullable metric value with explicit availability tracking.
    Guarantees that null/missing signals are never conflated with evaluated zero signals.
    """
    value: Optional[float] = Field(
        default=None,
        description="Calculated metric value in [0, 1]. Null if signal could not be evaluated.",
    )
    availability: MetricAvailability = Field(
        default=MetricAvailability.UNAVAILABLE,
        description="Explicit signal status: available, unavailable, provider_error, not_applicable.",
    )
    reason: Optional[str] = Field(
        default=None,
        description="Diagnostic explanation for unavailable, error, or not_applicable states.",
    )

    model_config = {
        "use_enum_values": True,
        "json_schema_extra": {
            "example": {
                "value": None,
                "availability": "unavailable",
                "reason": "references_not_loaded",
            }
        },
    }
