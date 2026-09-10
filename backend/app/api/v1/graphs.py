from typing import Optional
from fastapi import APIRouter, Depends, status
from app.schemas.graph import (
    CreateGraphRequest,
    CreateGraphResponse,
    GraphStatusResponse,
)
from app.workers.job_manager import GraphJobManager
from app.core.errors import NotFoundError
from app.core.auth import get_optional_auth_user, AuthenticatedUser

router = APIRouter(tags=["Graphs"])


@router.post(
    "/graphs",
    response_model=CreateGraphResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
async def create_graph_job(
    request: CreateGraphRequest,
    auth_user: Optional[AuthenticatedUser] = Depends(get_optional_auth_user),
) -> CreateGraphResponse:
    """
    Dispatches asynchronous graph synthesis for a seed paper.
    Returns HTTP 202 Accepted with a job ID and polling URL immediately.
    Supports idempotency: repeated identical requests reuse active or completed jobs.
    """
    manager = GraphJobManager.get_instance()
    job = await manager.get_or_create_job(request)

    return CreateGraphResponse(
        graph_id=job.job_id,
        status=job.status,
        poll_url=job.poll_url,
        created_at=job.created_at,
    )


@router.get("/graphs/{graph_id}", response_model=GraphStatusResponse)
async def get_graph_status(
    graph_id: str,
    auth_user: Optional[AuthenticatedUser] = Depends(get_optional_auth_user),
) -> GraphStatusResponse:
    """
    Polls the status of an asynchronous graph generation job.
    Exposes all 16 discrete lifecycle stages, progressive progress,
    warnings, data completeness, and the final synthesized GraphSnapshot.
    """
    manager = GraphJobManager.get_instance()
    job = manager.get_job(graph_id)

    if not job:
        raise NotFoundError(f"Graph job '{graph_id}' not found.")

    completeness = None
    if job.result:
        completeness = job.result.data_completeness

    return GraphStatusResponse(
        graph_id=job.job_id,
        status=job.status,
        progress=job.progress,
        current_stage=job.current_stage,
        poll_url=job.poll_url,
        snapshot=job.result,
        warnings=job.warnings,
        data_completeness=completeness,
        error=job.error,
    )
