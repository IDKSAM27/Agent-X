import asyncio
from typing import Dict, List, Optional
import logging
from datetime import datetime
from smart_news_service import SmartNewsService
from database.operations import get_user_profile_by_firebase_uid, store_user_news_preferences

logger = logging.getLogger(__name__)

class NewsIntegrationService:
    """Integration layer between news service and Agent-X features"""

    def __init__(self):
        self.news_service = SmartNewsService()

    async def get_personalized_news_for_user(
            self,
            firebase_uid: str,
            limit: int = 30,
            force_refresh: bool = False
    ) -> Dict:
        """Get personalized news for a specific user based on their profile"""
        try:
            # Get user profile
            user_profile = await get_user_profile_by_firebase_uid(firebase_uid)

            if not user_profile:
                # Default profile for new users
                profession = "Professional"
                location = "India"
                interests = []
            else:
                profession = user_profile.get('profession', 'Professional')
                location = user_profile.get('location', 'India')
                interests = user_profile.get('interests', [])

            # Fetch contextual news
            news_data = await self.news_service.get_contextual_news(
                profession=profession,
                location=location,
                interests=interests,
                limit=limit,
                force_refresh=force_refresh
            )

            # Add user-specific enhancements
            enhanced_data = await self._enhance_news_for_user(news_data, user_profile)

            return enhanced_data

        except Exception as e:
            logger.error(f"Error getting personalized news for user {firebase_uid}: {e}")
            raise

    async def _enhance_news_for_user(self, news_data: Dict, user_profile: Dict) -> Dict:
        """Add user-specific enhancements to news data"""

        # Add productivity suggestions based on user's tasks and events
        for article in news_data['articles']:
            article['productivity_suggestions'] = self._generate_productivity_suggestions(
                article, user_profile
            )

        return news_data

    def _generate_productivity_suggestions(self, article: Dict, user_profile: Dict) -> List[str]:
        """Generate productivity-focused suggestions for each article"""
        suggestions = []

        # Event-based suggestions
        if article.get('is_local_event'):
            suggestions.append("Block time in your calendar to attend this event")
            if article.get('event_date'):
                suggestions.append("Set a reminder to prepare for this event")

        # Learning-based suggestions
        if 'course' in article['title'].lower() or 'tutorial' in article['description'].lower():
            suggestions.append("Create a learning task to follow up on this")
            suggestions.append("Schedule dedicated study time for this topic")

        # Career-based suggestions
        if 'job' in article['title'].lower() or 'opportunity' in article['description'].lower():
            suggestions.append("Update your resume to match these requirements")
            suggestions.append("Research the company and role")

        return suggestions[:2]  # Limit to 2 suggestions

    async def create_task_from_news_article(
            self,
            firebase_uid: str,
            article_data: Dict,
            custom_title: Optional[str] = None
    ) -> Dict:
        """Create a task based on a news article"""
        try:
            from functions.task_functions import TaskFunctions
            task_functions = TaskFunctions()

            title = custom_title or f"Follow up: {article_data['title']}"
            description = f"From news article: {article_data['url']}\n\n{article_data['summary']}"

            # Determine task category based on article category
            category_mapping = {
                'local_events': 'networking',
                'career_opportunities': 'career',
                'education': 'learning',
                'technology': 'research',
                'productivity': 'productivity'
            }

            task_category = category_mapping.get(article_data['category'], 'general')

            task_data = {
                'title': title,
                'description': description,
                'category': task_category,
                'priority': 'high' if article_data.get('is_urgent') else 'medium',
                'tags': ['news', 'follow-up'] + article_data.get('tags', [])[:3]
            }

            result = await task_functions.execute('create_task', firebase_uid, task_data)

            logger.info(f"Created task from news article for user {firebase_uid}")
            return result

        except Exception as e:
            logger.error(f"Error creating task from news: {e}")
            raise

    async def add_news_event_to_calendar(
            self,
            firebase_uid: str,
            article_data: Dict,
            custom_title: Optional[str] = None
    ) -> Dict:
        """Add a news event to the user's calendar"""
        try:
            from functions.calendar_functions import CalendarFunctions
            calendar_functions = CalendarFunctions()

            if not article_data.get('event_date'):
                raise ValueError("Article does not contain event date information")

            title = custom_title or article_data['title']
            description = f"Event from news: {article_data['url']}\n\n{article_data['summary']}"

            event_data = {
                'title': title,
                'description': description,
                'date': article_data['event_date'],
                'time': article_data.get('event_time', '10:00'),
                'location': article_data.get('event_location'),
                'category': 'professional'
            }

            result = await calendar_functions.execute('create_event', firebase_uid, event_data)

            logger.info(f"Added news event to calendar for user {firebase_uid}")
            return result

        except Exception as e:
            logger.error(f"Error adding news event to calendar: {e}")
            raise

    async def get_news_analytics(self, firebase_uid: str) -> Dict:
        """Get analytics about user's news consumption"""
        # This would typically involve database queries
        # For now, return basic analytics
        return {
            'articles_read_this_week': 0,
            'favorite_categories': [],
            'local_events_attended': 0,
            'tasks_created_from_news': 0,
            'events_added_from_news': 0
        }
