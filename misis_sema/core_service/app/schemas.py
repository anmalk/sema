from pydantic import BaseModel, validator
from typing import Optional, Any, Union
import re

class ProjectCreate(BaseModel):
    name: str

class ProjectOut(BaseModel):
    id: int
    name: str

class RunCreate(BaseModel):
    group_id: str
    count: int = 200
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    min_likes: Optional[int] = None
    min_comments: Optional[int] = None
    min_reposts: Optional[int] = None
    min_views: Optional[int] = None
    sort_by: Optional[str] = None
    sort_order: str = "desc"


class RunOut(BaseModel):
    id: int
    project_id: int
    group_id: str
    status: str
    error_message: Optional[str] = None

class ReportOut(BaseModel):
    run_id: int
    report: Any
