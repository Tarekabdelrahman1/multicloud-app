from contextlib import asynccontextmanager
from uuid import UUID

from fastapi import FastAPI, HTTPException, Query, Request
from sqlalchemy import select

from common.events import EventEnvelope, EventPublisher
from common.http import add_http_middleware, configure_logging
from .domain import Base, SessionLocal, Workflow, WorkflowCreate, WorkflowRead, engine
from .settings import settings

configure_logging()


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    app.state.publisher = EventPublisher(settings.rabbitmq_url)
    await app.state.publisher.start()
    yield
    await app.state.publisher.close()


app = FastAPI(title="Workflow Service", version="3.0.0", lifespan=lifespan)
add_http_middleware(app, settings.service_name)


@app.get("/health/live")
def live():
    return {"status": "alive", "service": settings.service_name}


@app.get("/health/ready")
def ready():
    try:
        with engine.connect() as connection:
            connection.exec_driver_sql("SELECT 1")
        return {"status": "ready"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database not ready") from exc


@app.get("/api/v1/workflows", response_model=list[WorkflowRead])
def list_workflows(limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0)):
    with SessionLocal() as db:
        return list(db.scalars(select(Workflow).order_by(Workflow.created_at.desc()).offset(offset).limit(limit)))


@app.get("/api/v1/workflows/{workflow_id}", response_model=WorkflowRead)
def get_workflow(workflow_id: UUID):
    with SessionLocal() as db:
        workflow = db.get(Workflow, workflow_id)
        if not workflow:
            raise HTTPException(status_code=404, detail="Workflow not found")
        return workflow


@app.post("/api/v1/workflows", response_model=WorkflowRead, status_code=201)
async def create_workflow(payload: WorkflowCreate, request: Request):
    with SessionLocal() as db:
        workflow = Workflow(**payload.model_dump(), state="pending")
        db.add(workflow)
        db.commit()
        db.refresh(workflow)
    await request.app.state.publisher.publish(
        EventEnvelope(
            event_type="workflow.created",
            source=settings.service_name,
            correlation_id=getattr(request.state, "request_id", None),
            data=WorkflowRead.model_validate(workflow).model_dump(mode="json"),
        )
    )
    return workflow


@app.post("/api/v1/workflows/{workflow_id}/run", response_model=WorkflowRead, status_code=202)
async def queue_workflow(workflow_id: UUID, request: Request):
    with SessionLocal() as db:
        workflow = db.get(Workflow, workflow_id)
        if not workflow:
            raise HTTPException(status_code=404, detail="Workflow not found")
        if workflow.state not in {"pending", "failed"}:
            raise HTTPException(status_code=409, detail=f"Cannot run from state {workflow.state}")
        workflow.state = "queued"
        workflow.error_message = None
        db.commit()
        db.refresh(workflow)
        data = WorkflowRead.model_validate(workflow).model_dump(mode="json")
    await request.app.state.publisher.publish(
        EventEnvelope(
            event_type="workflow.execute",
            source=settings.service_name,
            correlation_id=getattr(request.state, "request_id", None),
            data=data,
        )
    )
    return workflow
