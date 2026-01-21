import os, uuid, json
from datetime import datetime
from fastapi import FastAPI, Depends, HTTPException
from sqlmodel import Session, select

from .db import init_db, get_session
from .models import Dataset
from .schemas import WallPostsRequest, DatasetOut, PostOut
from .vk_client import VKClient

app = FastAPI(title="VK Collector Service")

@app.on_event("startup")
def startup():
    init_db()

vk_token = os.getenv("VK_TOKEN")
if not vk_token:
    raise RuntimeError("VK_TOKEN env var is required")
vk = VKClient(vk_token)

def parse_date(d: str | None):
    return datetime.strptime(d, "%Y-%m-%d") if d else None

@app.post("/vk/wall/posts", response_model=DatasetOut)
def collect_wall_posts(req: WallPostsRequest, session: Session = Depends(get_session)):
    start = parse_date(req.start_date)
    end = parse_date(req.end_date)

    collected: list[PostOut] = []
    offset = 0

    while len(collected) < req.count:
        resp = vk.wall_get_batch(req.owner_id, offset=offset)
        items = resp.get("items", [])
        if not items:
            break

        for post in items:
            post_date = datetime.fromtimestamp(post["date"])

            if start and post_date < start:
                continue
            if end and post_date > end:
                continue

            likes = post["likes"]["count"]
            comments = post["comments"]["count"]
            reposts = post["reposts"]["count"]
            views = post.get("views", {}).get("count", 0)

            if req.min_likes is not None and likes < req.min_likes:
                continue
            if req.min_comments is not None and comments < req.min_comments:
                continue
            if req.min_reposts is not None and reposts < req.min_reposts:
                continue
            if req.min_views is not None and views < req.min_views:
                continue

            photo_urls = []
            for att in post.get("attachments", []):
                if att.get("type") == "photo":
                    sizes = att["photo"].get("sizes", [])
                    if sizes:
                        photo_urls.append(sizes[-1]["url"])

            collected.append(PostOut(
                id=post["id"],
                text=post.get("text", ""),
                date=post_date.strftime("%Y-%m-%d %H:%M:%S"),
                likes_count=likes,
                comments_count=comments,
                reposts_count=reposts,
                views_count=views,
                url_photos=photo_urls
            ))
            if len(collected) >= req.count:
                break

        offset += 100

    reverse = (req.sort_order == "desc")
    if req.sort_by == "views_count":
        collected.sort(key=lambda x: (x.views_count if isinstance(x.views_count, int) else 0), reverse=reverse)
    elif req.sort_by in {"likes_count", "comments_count", "reposts_count"}:
        collected.sort(key=lambda x: getattr(x, req.sort_by), reverse=reverse)
    else:
        collected.sort(key=lambda x: x.date, reverse=reverse)

    dataset_id = str(uuid.uuid4())
    ds = Dataset(id=dataset_id, json_data=json.dumps([p.model_dump() for p in collected], ensure_ascii=False))
    session.add(ds)
    session.commit()

    return DatasetOut(dataset_id=dataset_id, posts=collected)

@app.get("/datasets/{dataset_id}")
def get_dataset(dataset_id: str, session: Session = Depends(get_session)):
    ds = session.exec(select(Dataset).where(Dataset.id == dataset_id)).first()
    if not ds:
        raise HTTPException(404, "dataset not found")
    return {"dataset_id": dataset_id, "posts": json.loads(ds.json_data)}