from datetime import UTC, datetime
from threading import Lock
from uuid import UUID, uuid4

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

router = APIRouter(prefix="/workflows", tags=["workflows"])
_lock = Lock()
_workflows: dict[UUID, "Workflow"] = {}


class WorkflowCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    device_id: UUID | None = None
    action: str = Field(min_length=1, max_length=255)
    parameters: dict[str, str | int | float | bool] = {}


class Workflow(WorkflowCreate):
    id: UUID
    state: str
    created_at: datetime


@router.get("", response_model=list[Workflow])
def list_workflows() -> list[Workflow]:
    return list(_workflows.values())


@router.post("", response_model=Workflow, status_code=status.HTTP_201_CREATED)
def create_workflow(payload: WorkflowCreate) -> Workflow:
    workflow = Workflow(
        id=uuid4(),
        state="pending",
        created_at=datetime.now(UTC),
        **payload.model_dump(),
    )
    with _lock:
        _workflows[workflow.id] = workflow
    return workflow


@router.post("/{workflow_id}/run", response_model=Workflow)
def run_workflow(workflow_id: UUID) -> Workflow:
    workflow = _workflows.get(workflow_id)
    if workflow is None:
        raise HTTPException(status_code=404, detail="Workflow not found")
    updated = workflow.model_copy(update={"state": "completed"})
    with _lock:
        _workflows[workflow_id] = updated
    return updated

