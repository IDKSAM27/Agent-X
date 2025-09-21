import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, List

from smart_news_service import SmartNewsService
from database.operations import get_all_active_users

logger = logging.getLogger(__name__)

class NewsScheduler:
    """Background service for periodic news updates"""

    def __init__(self):
        self.news_service = SmartNewsService()
        self.is_running = False

    async def start_background_updates(self):
        """Start background news update process"""
        if self.is_running:
            return

        self.is_running = True
        logger.info("🔄 Starting background news updates...")

        while self.is_running:
            try:
                await self._update_news_cache()
                await asyncio.sleep(3600)  # Update every hour
            except Exception as e:
                logger.error(f"Error in background news update: {e}")
                await asyncio.sleep(1800)  # Wait 30 minutes on error

    async def stop_background_updates(self):
        """Stop background updates"""
        self.is_running = False
        logger.info("⏸️ Stopped background news updates")

    async def _update_news_cache(self):
        """Update news cache for common profession/location combinations"""
        try:
            # Get popular combinations from user base
            popular_combinations = await self._get_popular_combinations()

            for profession, location in popular_combinations:
                logger.info(f"Updating news cache for {profession} in {location}")

                await self.news_service.get_contextual_news(
                    profession=profession,
                    location=location,
                    limit=50,
                    force_refresh=True
                )

                await asyncio.sleep(10)  # Rate limiting

        except Exception as e:
            logger.error(f"Error updating news cache: {e}")

    async def _get_popular_combinations(self) -> List[tuple]:
        """Get popular profession/location combinations from user base"""
        try:
            # This would query your database for popular combinations
            # For now, return common Indian combinations
            return [
                ('teacher', 'India'),
                ('engineer', 'Bangalore'),
                ('student', 'India'),
                ('developer', 'Pune'),
                ('teacher', 'Mumbai'),
                ('student', 'Delhi'),
            ]
        except Exception as e:
            logger.error(f"Error getting popular combinations: {e}")
            return [('professional', 'India')]

# Global scheduler instance
news_scheduler = NewsScheduler()
