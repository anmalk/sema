import os, requests
from fastapi import FastAPI, HTTPException
import pandas as pd

from sklearn.linear_model import LogisticRegression
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline

COLLECTOR_URL = os.getenv("COLLECTOR_URL", "http://collector:8000")
app = FastAPI(title="AI/Analytics Service")

def fetch_posts(dataset_id: str) -> list[dict]:
    r = requests.get(f"{COLLECTOR_URL}/datasets/{dataset_id}", timeout=60)
    if r.status_code == 404:
        raise HTTPException(404, "dataset not found")
    r.raise_for_status()
    return r.json().get("posts", [])

def to_df(posts: list[dict]) -> pd.DataFrame:
    df = pd.DataFrame(posts)
    if df.empty:
        return df

    for c in ["likes_count", "comments_count", "reposts_count", "views_count"]:
        if c not in df.columns:
            df[c] = 0

    df["views_count"] = pd.to_numeric(df["views_count"], errors="coerce").fillna(0).astype(int)

    if "text" not in df.columns:
        df["text"] = ""
    else:
        df["text"] = df["text"].fillna("")

    if "url_photos" not in df.columns:
        df["url_photos"] = [[] for _ in range(len(df))]
    else:
        # гарантируем list[str], даже если пришло None/NaN
        df["url_photos"] = df["url_photos"].apply(
            lambda x: x if isinstance(x, list) else ([] if pd.isna(x) else [str(x)])
        )

    return df

@app.post("/analytics/basic")
def analytics_basic(body: dict):
    dataset_id = body.get("dataset_id")
    if not dataset_id:
        raise HTTPException(400, "dataset_id required")

    posts = fetch_posts(dataset_id)
    if not posts:
        return {"dataset_id": dataset_id, "total_posts": 0, "top_posts_by_likes": []}

    df = to_df(posts)
    n = len(df)

    total_likes = int(df["likes_count"].sum())
    total_comments = int(df["comments_count"].sum())
    total_reposts = int(df["reposts_count"].sum())
    total_views = int(df["views_count"].sum())

    top = df.sort_values("likes_count", ascending=False).head(10).to_dict(orient="records")

    return {
        "dataset_id": dataset_id,
        "total_posts": n,
        "total_likes": total_likes,
        "total_comments": total_comments,
        "total_reposts": total_reposts,
        "total_views": total_views,
        "avg_likes": round(total_likes / n, 2),
        "avg_comments": round(total_comments / n, 2),
        "avg_reposts": round(total_reposts / n, 2),
        "avg_views": round(total_views / n, 2),
        "top_posts_by_likes": top,
    }

@app.post("/analytics/predict")
def analytics_predict(body: dict):
    dataset_id = body.get("dataset_id")
    if not dataset_id:
        raise HTTPException(400, "dataset_id required")

    posts = fetch_posts(dataset_id)
    df = to_df(posts)
    if df.empty or len(df) < 5:
        raise HTTPException(400, "not enough data for predict (need at least 5 posts)")

    X = df[["likes_count", "comments_count", "reposts_count", "views_count"]].values
    threshold = float(df["likes_count"].median())
    y = (df["likes_count"] >= threshold).astype(int).values

    model = Pipeline([
        ("scaler", StandardScaler()),
        ("lr", LogisticRegression(max_iter=500)),
    ])
    model.fit(X, y)

    proba_top = model.predict_proba(X)[:, 1]

    out = df[[
        "id",
        "date",
        "text",
        "url_photos",
        "likes_count",
        "comments_count",
        "reposts_count",
        "views_count",
    ]].copy()

    out["score_top"] = [round(float(p), 4) for p in proba_top]
    out["predicted_top"] = out["score_top"] >= 0.5

    return {
        "dataset_id": dataset_id,
        "label_rule": f"top if likes_count >= median({threshold})",
        "items": out.sort_values("score_top", ascending=False).to_dict(orient="records"),
    }
