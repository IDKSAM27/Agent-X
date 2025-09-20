from abc import ABC, abstractmethod
from typing import List, Optional
from datetime import datetime
import logging
from ..models.news_models import RawArticle, NewsSource

logger = logging.getLogger(__name__)

class BaseNewsSource(ABC):
    """Abstract base class for all news sources"""

    def __init__(self, source_config: NewsSource):
        self.config = source_config
        self.last_fetch: Optional[datetime] = None
        self.fetch_count = 0
        self.error_count = 0

    @abstractmethod
    async def fetch_articles(self, **kwargs) -> List[RawArticle]:
        """Fetch raw articles from the source"""
        pass

    def can_fetch(self) -> bool:
        """Check if we can fetch from this source (rate limiting)"""
        if not self.config.is_active:
            return False

        if not self.config.rate_limit:
            return True

        if not self.last_fetch:
            return True

        hours_since_last = (datetime.now() - self.last_fetch).total_seconds() / 3600
        return hours_since_last >= (1.0 / self.config.rate_limit)

    def record_fetch(self, success: bool = True):
        """Record fetch attempt for rate limiting and monitoring"""
        self.last_fetch = datetime.now()
        self.fetch_count += 1
        if not success:
            self.error_count += 1

    def get_health_score(self) -> float:
        """Get source health score for monitoring"""
        if self.fetch_count == 0:
            return 1.0
        return 1.0 - (self.error_count / self.fetch_count)
