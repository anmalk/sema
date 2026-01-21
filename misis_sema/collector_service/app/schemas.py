from pydantic import BaseModel, Field
from typing import Optional, List, Union

class WallPostsRequest(BaseModel):
    owner_id: Union[int, str] = Field(..., description="VK owner_id или screen_name/ссылка")
    count: int = Field(100, ge=1, le=5000)
    start_date: Optional[str] = Field(None, description="YYYY-MM-DD")
    end_date: Optional[str] = Field(None, description="YYYY-MM-DD")
    min_likes: Optional[int] = None
    min_comments: Optional[int] = None
    min_reposts: Optional[int] = None
    min_views: Optional[int] = None
    sort_by: Optional[str] = None
    sort_order: str = Field("desc", pattern="^(asc|desc)$")

class PostOut(BaseModel):
    id: int
    text: str
    date: str
    likes_count: int
    comments_count: int
    reposts_count: int
    views_count: Union[int, str]
    url_photos: List[str]

class DatasetOut(BaseModel):
    dataset_id: str
    posts: List[PostOut]