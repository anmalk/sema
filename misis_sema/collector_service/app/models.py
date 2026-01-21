from sqlmodel import SQLModel, Field
from datetime import datetime

class Dataset(SQLModel, table=True):
    id: str = Field(primary_key=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    json_data: str