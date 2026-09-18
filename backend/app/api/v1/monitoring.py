from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import AuthenticatedUser, get_required_auth_user
from app.db.session import get_db
from app.repositories.monitoring import (
    deactivate_device_token,
    delete_monitored_graph,
    get_owned_graph,
    get_owned_graph_by_local_id,
    list_monitored_graphs,
    list_updates,
    mark_update_added,
    mark_update_read,
    update_monitored_graph,
    upsert_device_token,
    upsert_monitored_graph,
)
from app.schemas.monitoring import (
    CreateMonitoredGraphRequest,
    DeviceTokenRequest,
    MonitoredGraphResponse,
    ResearchUpdateResponse,
    UpdateMonitoredGraphRequest,
)

router = APIRouter(prefix="/monitoring", tags=["Research Monitoring"])
RequiredUser = Annotated[AuthenticatedUser, Depends(get_required_auth_user)]
Database = Annotated[AsyncSession, Depends(get_db)]


@router.post(
    "/graphs",
    response_model=MonitoredGraphResponse,
    status_code=status.HTTP_201_CREATED,
)
async def save_monitored_graph(
    request: CreateMonitoredGraphRequest,
    user: RequiredUser,
    db: Database,
) -> MonitoredGraphResponse:
    graph = await upsert_monitored_graph(db, user.user_id, request)
    return MonitoredGraphResponse.model_validate(graph)


@router.get("/graphs", response_model=list[MonitoredGraphResponse])
async def get_monitored_graphs(
    user: RequiredUser,
    db: Database,
) -> list[MonitoredGraphResponse]:
    graphs = await list_monitored_graphs(db, user.user_id)
    return [MonitoredGraphResponse.model_validate(graph) for graph in graphs]


@router.patch(
    "/graphs/{monitor_id}",
    response_model=MonitoredGraphResponse,
)
async def patch_monitored_graph(
    monitor_id: str,
    request: UpdateMonitoredGraphRequest,
    user: RequiredUser,
    db: Database,
) -> MonitoredGraphResponse:
    graph = await get_owned_graph(db, user.user_id, monitor_id)
    if graph is None:
        raise HTTPException(status_code=404, detail="Monitored graph not found.")
    graph = await update_monitored_graph(db, graph, request)
    return MonitoredGraphResponse.model_validate(graph)


@router.delete("/graphs/{monitor_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_monitored_graph(
    monitor_id: str,
    user: RequiredUser,
    db: Database,
) -> None:
    graph = await get_owned_graph(db, user.user_id, monitor_id)
    if graph is None:
        raise HTTPException(status_code=404, detail="Monitored graph not found.")
    await delete_monitored_graph(db, graph)


@router.delete(
    "/graphs/by-local/{local_graph_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def remove_monitored_graph_by_local_id(
    local_graph_id: str,
    user: RequiredUser,
    db: Database,
) -> None:
    graph = await get_owned_graph_by_local_id(db, user.user_id, local_graph_id)
    if graph is not None:
        await delete_monitored_graph(db, graph)


@router.get(
    "/graphs/{monitor_id}/updates",
    response_model=list[ResearchUpdateResponse],
)
async def get_graph_updates(
    monitor_id: str,
    user: RequiredUser,
    db: Database,
    limit: int = Query(default=50, ge=1, le=100),
) -> list[ResearchUpdateResponse]:
    graph = await get_owned_graph(db, user.user_id, monitor_id)
    if graph is None:
        raise HTTPException(status_code=404, detail="Monitored graph not found.")
    updates = await list_updates(db, graph.id, limit)
    return [ResearchUpdateResponse.model_validate(update) for update in updates]


@router.post(
    "/graphs/{monitor_id}/updates/{update_id}/read",
    response_model=ResearchUpdateResponse,
)
async def read_graph_update(
    monitor_id: str,
    update_id: str,
    user: RequiredUser,
    db: Database,
) -> ResearchUpdateResponse:
    graph = await get_owned_graph(db, user.user_id, monitor_id)
    if graph is None:
        raise HTTPException(status_code=404, detail="Monitored graph not found.")
    update = await mark_update_read(db, update_id, graph.id)
    if update is None:
        raise HTTPException(status_code=404, detail="Research update not found.")
    return ResearchUpdateResponse.model_validate(update)


@router.post(
    "/graphs/{monitor_id}/updates/{update_id}/add-to-graph",
    response_model=ResearchUpdateResponse,
)
async def add_graph_update(
    monitor_id: str,
    update_id: str,
    user: RequiredUser,
    db: Database,
) -> ResearchUpdateResponse:
    graph = await get_owned_graph(db, user.user_id, monitor_id)
    if graph is None:
        raise HTTPException(status_code=404, detail="Monitored graph not found.")
    update = await mark_update_added(db, update_id, graph.id)
    if update is None:
        raise HTTPException(status_code=404, detail="Research update not found.")
    return ResearchUpdateResponse.model_validate(update)


@router.post("/device-token", status_code=status.HTTP_204_NO_CONTENT)
async def register_device_token(
    request: DeviceTokenRequest,
    user: RequiredUser,
    db: Database,
) -> None:
    await upsert_device_token(db, user.user_id, request.fcm_token, request.platform)


@router.delete("/device-token", status_code=status.HTTP_204_NO_CONTENT)
async def remove_device_token(
    request: DeviceTokenRequest,
    user: RequiredUser,
    db: Database,
) -> None:
    await deactivate_device_token(db, user.user_id, request.fcm_token)