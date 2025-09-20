import feedparser
import aiohttp
from typing import List
from datetime import datetime
import logging
from .base_source import BaseNewsSource
from ..models.news_models import RawArticle
from ..utils.text_utils import clean_html, extract_text

logger = logging.getLogger(__name__)

class RSSNewsSource(BaseNewsSource):
    """RSS feed news source implementation"""

    async def fetch_articles(self, limit: int = 20) -> List[RawArticle]:
        """Fetch articles from RSS feed"""
        if not self.can_fetch():
            logger.warning(f"Rate limit exceeded for {self.config.name}")
            return []

        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                        self.config.url,
                        timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    content = await response.text()

            feed = feedparser.parse(content)
            articles = []

            for entry in feed.entries[:limit]:
                try:
                    article = self._parse_rss_entry(entry)
                    if article:
                        articles.append(article)
                except Exception as e:
                    logger.error(f"Error parsing RSS entry from {self.config.name}: {e}")
                    continue

            self.record_fetch(success=True)
            logger.info(f"Fetched {len(articles)} articles from {self.config.name}")
            return articles

        except Exception as e:
            logger.error(f"Error fetching RSS from {self.config.name}: {e}")
            self.record_fetch(success=False)
            return []

    def _parse_rss_entry(self, entry) -> RawArticle:
        """Parse individual RSS entry into RawArticle"""
        # Handle different date formats
        published_at = self._parse_date(entry)

        # Clean and extract content
        title = clean_html(getattr(entry, 'title', ''))
        description = self._extract_description(entry)
        content = self._extract_content(entry)

        return RawArticle(
            title=title,
            description=description,
            url=getattr(entry, 'link', ''),
            published_at=published_at,
            source_name=self.config.name,
            content=content,
            image_url=self._extract_image_url(entry),
            tags=self._extract_tags(entry)
        )

    def _parse_date(self, entry) -> datetime:
        """Parse publication date from RSS entry"""
        for date_field in ['published_parsed', 'updated_parsed']:
            date_tuple = getattr(entry, date_field, None)
            if date_tuple:
                try:
                    return datetime(*date_tuple[:6])
                except (TypeError, ValueError):
                    continue

        # Fallback to current time
        return datetime.now()

    def _extract_description(self, entry) -> str:
        """Extract description from RSS entry"""
        for field in ['summary', 'description', 'subtitle']:
            content = getattr(entry, field, '')
            if content:
                return clean_html(content)[:500]  # Limit length
        return ''

    def _extract_content(self, entry) -> str:
        """Extract full content from RSS entry"""
        content_fields = ['content', 'summary', 'description']
        for field in content_fields:
            content = getattr(entry, field, '')
            if content:
                if isinstance(content, list) and content:
                    content = content[0].get('value', '')
                return clean_html(str(content))
        return ''

    def _extract_image_url(self, entry) -> Optional[str]:
        """Extract image URL from RSS entry"""
        # Try media content
        if hasattr(entry, 'media_content') and entry.media_content:
            return entry.media_content[0]['url']

        # Try enclosures
        if hasattr(entry, 'enclosures') and entry.enclosures:
            for enclosure in entry.enclosures:
                if enclosure.type and 'image' in enclosure.type:
                    return enclosure.href

        # Try to extract from content
        content = self._extract_content(entry)
        img_urls = extract_image_urls(content)
        return img_urls[0] if img_urls else None

    def _extract_tags(self, entry) -> List[str]:
        """Extract tags from RSS entry"""
        tags = []

        # RSS tags
        if hasattr(entry, 'tags'):
            tags.extend([tag.term for tag in entry.tags])

        # Categories
        if hasattr(entry, 'categories'):
            tags.extend(entry.categories)

        return list(set(tags))  # Remove duplicates
