from typing import List, Dict
import asyncio
from datetime import datetime, timedelta
import logging
from models.news_models import ProcessedArticle, UserProfile, NewsSource, NewsCategory, RawArticle
from news_sources.base_source import BaseNewsSource
from news_sources.rss_source import RSSNewsSource
from news_sources.google_news_source import GoogleNewsSource
from services.content_processor import (ContentProcessor)
from utils.caching import CacheManager
from config.news_config import NEWS_SOURCES_CONFIG

logger = logging.getLogger(__name__)

class SmartNewsService:
    """Main orchestrator for intelligent news fetching and processing"""

    def __init__(self):
        self.content_processor = ContentProcessor()
        self.cache_manager = CacheManager(ttl_hours=2)
        self.sources = self._initialize_sources()

    def _initialize_sources(self) -> Dict[str, BaseNewsSource]:
        """Initialize all news sources"""
        sources = {}

        # RSS Sources
        for source_config in NEWS_SOURCES_CONFIG['rss']:
            sources[source_config.name] = RSSNewsSource(source_config)

        # Google News Source
        google_config = NewsSource(
            name="Google News",
            url="https://news.google.com/rss/search",
            type="api",
            categories=[NewsCategory.LOCAL_EVENTS, NewsCategory.CAREER_OPPORTUNITIES],
            priority=3
        )
        sources['google_news'] = GoogleNewsSource(google_config)

        return sources

    async def get_contextual_news(
            self,
            profession: str,
            location: str,
            interests: List[str] = None,
            limit: int = 50,
            force_refresh: bool = False
    ) -> Dict[str, any]:
        """Main entry point for fetching contextual news"""

        # Create user profile
        user_profile = UserProfile(
            profession=profession,
            location=location,
            interests=interests or [],
            skill_level="intermediate",
            career_stage="mid_career"
        )

        logger.info(f"🔍 Getting news for: {profession} in {location}, force_refresh={force_refresh}")

        # Check cache first
        cache_key = f"news:{profession}:{location}:{':'.join(interests or [])}"
        if not force_refresh:
            cached_result = await self.cache_manager.get(cache_key)
            if cached_result:
                logger.info("📦 Returning cached news results")
                return cached_result

        try:
            # Fetch from all sources concurrently
            logger.info("🌐 Fetching from all sources...")
            raw_articles = await self._fetch_from_all_sources(user_profile)
            logger.info(f"📥 Fetched {len(raw_articles)} raw articles")

            if not raw_articles:
                logger.warning("❌ No raw articles fetched from any source!")
                return self._empty_response()

            # Process and enrich articles
            logger.info(f"⚙️ Processing {len(raw_articles)} articles...")
            processed_articles = await self.content_processor.process_articles(
                raw_articles, user_profile
            )
            logger.info(f"✅ Successfully processed {len(processed_articles)} articles")

            if not processed_articles:
                logger.warning("❌ No articles survived processing!")
                # Return raw articles for debugging
                return self._debug_response(raw_articles)

            # Organize by categories
            categorized_news = self._organize_by_categories(processed_articles)

            # Build response
            response = {
                'articles': [article.to_dict() for article in processed_articles[:limit]],
                'categories': categorized_news,
                'metadata': {
                    'total_articles': len(processed_articles),
                    'raw_articles_fetched': len(raw_articles),  # Add for debugging
                    'sources_used': len([s for s in self.sources.values() if s.last_fetch]),
                    'last_updated': datetime.now().isoformat(),
                    'user_profile': {
                        'profession': profession,
                        'location': location,
                        'interests': interests
                    }
                }
            }

            # Cache the result
            await self.cache_manager.set(cache_key, response)

            logger.info(f"🎉 Successfully returned {len(processed_articles)} articles")
            return response

        except Exception as e:
            logger.error(f"💥 Error in get_contextual_news: {e}", exc_info=True)
            return self._error_response(str(e))

    async def _fetch_from_all_sources(self, user_profile: UserProfile) -> List[RawArticle]:
        """Fetch articles from all available sources concurrently"""
        fetch_tasks = []

        for source_name, source in self.sources.items():
            if source.can_fetch():
                if isinstance(source, GoogleNewsSource):
                    task = source.fetch_articles(
                        profession=user_profile.profession,
                        location=user_profile.location
                    )
                else:
                    task = source.fetch_articles()
                fetch_tasks.append(task)

        # Execute all fetches concurrently
        results = await asyncio.gather(*fetch_tasks, return_exceptions=True)

        # Combine all articles
        all_articles = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(f"Source fetch failed: {result}")
                continue
            all_articles.extend(result)

        logger.info(f"Fetched {len(all_articles)} raw articles from {len(fetch_tasks)} sources")
        return all_articles

    def _organize_by_categories(self, articles: List[ProcessedArticle]) -> Dict[str, List[Dict]]:
        """Organize articles by categories for easier frontend consumption"""
        categories = {}

        for article in articles:
            category_key = article.category.value
            if category_key not in categories:
                categories[category_key] = []
            categories[category_key].append(article.to_dict())

        # Sort each category by relevance
        for category in categories:
            categories[category].sort(key=lambda x: x['relevance_score'], reverse=True)
            categories[category] = categories[category][:10]  # Limit per category

        return categories

    async def get_source_health(self) -> Dict[str, any]:
        """Get health status of all news sources"""
        health_report = {
            'sources': {},
            'overall_health': 0.0,
            'last_check': datetime.now().isoformat()
        }

        total_health = 0.0
        active_sources = 0

        for name, source in self.sources.items():
            if source.config.is_active:
                health_score = source.get_health_score()
                health_report['sources'][name] = {
                    'health_score': health_score,
                    'last_fetch': source.last_fetch.isoformat() if source.last_fetch else None,
                    'fetch_count': source.fetch_count,
                    'error_count': source.error_count,
                    'can_fetch': source.can_fetch()
                }
                total_health += health_score
                active_sources += 1

        health_report['overall_health'] = total_health / active_sources if active_sources > 0 else 0.0
        return health_report

    def _empty_response(self):
        """Return empty response when no articles found"""
        return {
            'articles': [],
            'categories': {},
            'metadata': {
                'total_articles': 0,
                'raw_articles_fetched': 0,
                'sources_used': 0,
                'last_updated': datetime.now().isoformat(),
                'error': 'No articles fetched from sources'
            }
        }
    def _debug_response(self, raw_articles):
        """Return debug info when processing fails"""
        return {
            'articles': [],
            'categories': {},
            'debug_info': [
                {
                    'title': article.title[:100],
                    'source': article.source_name,
                    'published': article.published_at.isoformat(),
                    'description_length': len(article.description or ''),
                }
                for article in raw_articles[:5]  # Show first 5 for debugging
            ],
            'metadata': {
                'total_articles': 0,
                'raw_articles_fetched': len(raw_articles),
                'sources_used': len(set(a.source_name for a in raw_articles)),
                'last_updated': datetime.now().isoformat(),
                'error': 'Articles fetched but processing failed'
            }
        }

    def _error_response(self, error_msg):
        """Return error response"""
        return {
            'articles': [],
            'categories': {},
            'metadata': {
                'total_articles': 0,
                'raw_articles_fetched': 0,
                'sources_used': 0,
                'last_updated': datetime.now().isoformat(),
                'error': error_msg
            }
        }
