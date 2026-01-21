import os, json, requests
from fastapi import FastAPI, Depends, HTTPException, BackgroundTasks
from sqlmodel import Session, select, delete

from .db import init_db, get_session, engine
from .models import Project, Run, Dataset, Report
from .schemas import ProjectCreate, ProjectOut, RunCreate, RunOut, ReportOut

COLLECTOR_URL = os.getenv("COLLECTOR_URL", "http://collector:8000")
AI_URL = os.getenv("AI_URL", "http://ai:8000")

app = FastAPI(title="Core Service")

@app.on_event("startup")
def startup():
    init_db()

@app.post("/projects", response_model=ProjectOut)
def create_project(body: ProjectCreate, session: Session = Depends(get_session)):
    p = Project(name=body.name)
    session.add(p)
    session.commit()
    session.refresh(p)
    return ProjectOut(id=p.id, name=p.name)

@app.get("/projects", response_model=list[ProjectOut])
def list_projects(session: Session = Depends(get_session)):
    items = session.exec(select(Project)).all()
    return [ProjectOut(id=p.id, name=p.name) for p in items]

def pipeline_run(run_id: int, run_params: dict):
    from sqlmodel import Session
    with Session(engine) as session:
        run = session.get(Run, run_id)
        if not run:
            return

        try:
            # collecting
            run.status = "collecting"
            session.commit() 

            payload = {
                "owner_id": run.group_id,
                "count": run_params["count"],
                "start_date": run_params.get("start_date"),
                "end_date": run_params.get("end_date"),
                "min_likes": run_params.get("min_likes"),
                "min_comments": run_params.get("min_comments"),
                "min_reposts": run_params.get("min_reposts"),
                "min_views": run_params.get("min_views"),
                "sort_by": run_params.get("sort_by"),
                "sort_order": run_params.get("sort_order", "desc"),
            }

            print(f"Calling collector: {payload}")  # debug
            r = requests.post(f"{COLLECTOR_URL}/vk/wall/posts", json=payload, timeout=180)
            r.raise_for_status()
            collector_dataset_id = r.json()["dataset_id"]
            print(f"Got dataset_id: {collector_dataset_id}")

            
            session.exec(delete(Dataset).where(Dataset.run_id == run.id))
            session.add(Dataset(run_id=run.id, collector_dataset_id=collector_dataset_id))
            session.commit()

            # analyzing
            run.status = "analyzing"
            session.commit()

            basic = requests.post(f"{AI_URL}/analytics/basic", json={"dataset_id": collector_dataset_id}, timeout=180)
            basic.raise_for_status()

            pred = requests.post(f"{AI_URL}/analytics/predict", json={"dataset_id": collector_dataset_id}, timeout=180)
            pred.raise_for_status()

            report_obj = {
                "basic": basic.json(),
                "predict": pred.json()
            }

          
            session.exec(delete(Report).where(Report.run_id == run.id))
            session.add(Report(run_id=run.id, report_json=json.dumps(report_obj, ensure_ascii=False)))

            run.status = "done"
            run.error_message = None
            session.add(run)
            session.commit()  

            print(f"Pipeline complete for run {run_id}")

        except Exception as e:
            run.status = "error"
            run.error_message = str(e)
            session.commit()
            print(f"Pipeline failed for run {run_id}: {e}")

@app.post("/projects/{project_id}/runs", response_model=RunOut)
def create_run(project_id: int, body: RunCreate, bg: BackgroundTasks,
               session: Session = Depends(get_session)):
    p = session.get(Project, project_id)
    if not p:
        raise HTTPException(404, "project not found")

    run = Run(project_id=project_id, group_id=body.group_id, status="created")
    session.add(run); session.commit(); session.refresh(run)

    bg.add_task(pipeline_run, run.id, body.model_dump())
    return RunOut(id=run.id, project_id=run.project_id, group_id=run.group_id, status=run.status)

@app.get("/runs/{run_id}", response_model=RunOut)
def get_run(run_id: int, session: Session = Depends(get_session)):
    run = session.get(Run, run_id)
    if not run:
        raise HTTPException(404, "run not found")
    return RunOut(id=run.id, project_id=run.project_id, group_id=run.group_id, status=run.status, error_message=run.error_message)

@app.get("/runs/{run_id}/report", response_model=ReportOut)
def get_report(run_id: int, session: Session = Depends(get_session)):
    rep = session.exec(select(Report).where(Report.run_id == run_id)).first()
    if not rep:
        raise HTTPException(404, "report not ready")
    return ReportOut(run_id=run_id, report=json.loads(rep.report_json))
