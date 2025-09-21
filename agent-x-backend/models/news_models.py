from typing import List, Optional, Dict, Any
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
import uuid

class NewsCategory(Enum):
    LOCAL_EVENTS = "local_events"
    PROFESSIONAL_DEV = "professional_dev"
    INDUSTRY_TRENDS = "industry_trends"
    PRODUCTIVITY = "productivity"
    CAREER_OPPORTUNITIES = "career_opportunities"
    EDUCATION = "education"
    TECHNOLOGY = "technology"

class ActionType(Enum):
    ADD_TO_CALENDAR = "add_to_calendar"
    CREATE_TASK = "create_task"
    SET_REMINDER = "set_reminder"
    BOOKMARK = "bookmark"
    APPLY = "apply"
    REGISTER = "register"

@dataclass
class NewsAction:
    """Represents an actionable item from a news article"""
    type: ActionType
    label: str
    icon: str
    color: str
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            'type': self.type.value,
            'label': self.label,
            'icon': self.icon,
            'color': self.color,
            'metadata': self.metadata
        }

@dataclass
class NewsSource:
    """Configuration for news sources"""
    name: str
    url: str
    type: str  # 'rss', 'api', 'scraper'
    categories: List[NewsCategory]
    region: Optional[str] = None
    profession: Optional[str] = None
    is_active: bool = True
    priority: int = 1  # Higher = more important
    rate_limit: Optional[int] = None  # requests per hour

@dataclass
class RawArticle:
    """Raw article data before processing"""
    title: str
    description: str
    url: str
    published_at: datetime
    source_name: str
    content: Optional[str] = None
    image_url: Optional[str] = None
    tags: List[str] = field(default_factory=list)

@dataclass
class ProcessedArticle:
    """Fully processed and enriched article"""
    id: str
    title: str
    description: str
    summary: str
    url: str
    image_url: Optional[str]
    published_at: datetime
    source: str
    category: NewsCategory

    # Scoring and relevance
    relevance_score: float  # 0.0 to 1.0
    quality_score: float   # 0.0 to 1.0
    engagement_score: float # 0.0 to 1.0

    # Contextual data
    tags: List[str]
    keywords: List[str]
    is_local_event: bool
    is_urgent: bool

    # Event-specific data
    event_date: Optional[datetime] = None
    event_location: Optional[str] = None
    event_deadline: Optional[datetime] = None

    # Actions
    available_actions: List[NewsAction] = field(default_factory=list)

    def __post_init__(self):
        if not self.id:
            self.id = str(uuid.uuid4())

    def to_dict(self) -> Dict[str, Any]:
        return {
            'id': self.id,
            'title': self.title,
            'description': self.description,
            'summary': self.summary,
            'url': self.url,
            'image_url': self.image_url,
            'published_at': self.published_at.isoformat(),
            'source': self.source,
            'category': self.category.value,
            'relevance_score': self.relevance_score,
            'quality_score': self.quality_score,
            'engagement_score': self.engagement_score,
            'tags': self.tags,
            'keywords': self.keywords,
            'is_local_event': self.is_local_event,
            'is_urgent': self.is_urgent,
            'event_date': self.event_date.isoformat() if self.event_date else None,
            'event_location': self.event_location,
            'event_deadline': self.event_deadline.isoformat() if self.event_deadline else None,
            'available_actions': [action.to_dict() for action in self.available_actions]
        }

@dataclass
class UserProfile:
    """User context for news personalization"""
    profession: str
    location: str
    interests: List[str]
    skill_level: str  # 'beginner', 'intermediate', 'advanced'
    career_stage: str  # 'student', 'early_career', 'mid_career', 'senior'
    preferred_categories: List[NewsCategory] = field(default_factory=list)
    blocked_sources: List[str] = field(default_factory=list)
