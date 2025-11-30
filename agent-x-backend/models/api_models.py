from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from datetime import datetime

class NewsResponse(BaseModel):
    success: bool
    message: str
    data: Optional[Dict[str, Any]] = None

class NewsRequest(BaseModel):
    action_type: str = Field(..., description="Type of action to execute")
    article_id: str = Field(..., description="ID of the news article")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Additional action metadata")

class NewsArticleResponse(BaseModel):
    id: str
    title: str
    description: str
    summary: str
    url: str
    image_url: Optional[str]
    published_at: datetime
    source: str
    category: str
    relevance_score: float
    quality_score: float
    engagement_score: float
    tags: List[str]
    keywords: List[str]
    is_local_event: bool
    is_urgent: bool
    event_date: Optional[datetime]
    event_location: Optional[str]
    available_actions: List[Dict[str, Any]]

class NewsCategoryResponse(BaseModel):
    category: str
    articles: List[NewsArticleResponse]
    total_count: int

#Sams On Fire
