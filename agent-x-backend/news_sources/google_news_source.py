from typing import List
import aiohttp
import feedparser
import logging
from urllib.parse import quote_plus
from news_sources.base_source import BaseNewsSource
from models.news_models import RawArticle

logger = logging.getLogger((__name__))

class GoogleNewsSource(BaseNewsSource):
    """Google News RSS source with custom queries"""

    BASE_URL = "https://news.google.com/rss/search"

    async def fetch_articles(self, profession: str, location: str = "India", limit: int = 20) -> List[RawArticle]:
        """Fetch articles from Google News with contextual queries"""
        if not self.can_fetch():
            return []

        queries = self._build_queries(profession, location)
        all_articles = []

        for query in queries:
            try:
                articles = await self._fetch_query_results(query, limit // len(queries))
                all_articles.extend(articles)
            except Exception as e:
                logger.error(f"Error fetching Google News query '{query}': {e}")
                continue

        self.record_fetch(success=True)
        return all_articles[:limit]

    def _build_queries(self, profession: str, location: str) -> List[str]:
        """Build contextual search queries"""
        base_params = "hl=en&gl=IN&ceid=IN:en"

        queries = [
            # Local events
            f"q={quote_plus(f'{profession} conference {location}')}&{base_params}",
            f"q={quote_plus(f'{profession} meetup {location}')}&{base_params}",
            f"q={quote_plus(f'{profession} workshop {location}')}&{base_params}",

            # Career opportunities
            f"q={quote_plus(f'{profession} job opportunity India')}&{base_params}",
            f"q={quote_plus(f'{profession} career India')}&{base_params}",

            # Learning and development
            f"q={quote_plus(f'{profession} course certification')}&{base_params}",
            f"q={quote_plus(f'{profession} training program')}&{base_params}",

            # Industry trends
            f"q={quote_plus(f'{profession} trends 2025')}&{base_params}",
            f"q={quote_plus(f'{profession} industry news India')}&{base_params}",
        ]

        return queries

    async def _fetch_query_results(self, query: str, limit: int) -> List[RawArticle]:
        """Fetch results for a specific query"""
        url = f"{self.BASE_URL}?{query}"

        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as response:
                content = await response.text()

        feed = feedparser.parse(content)
        articles = []

        for entry in feed.entries[:limit]:
            try:
                article = RawArticle(
                    title=clean_html(entry.title),
                    description=clean_html(entry.get('summary', '')),
                    url=entry.link,
                    published_at=datetime(*entry.published_parsed[:6]) if hasattr(entry, 'published_parsed') else datetime.now(),
                    source_name=f"Google News ({entry.get('source', {}).get('title', 'Unknown')})",
                    content=clean_html(entry.get('summary', ''))
                )
                articles.append(article)
            except Exception as e:
                logger.error(f"Error parsing Google News entry: {e}")
                continue

        return articles
