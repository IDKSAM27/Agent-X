from typing import Dict, Any, List
import logging
from functions.base import BaseFunctionExecutor
from services.smart_news_service import SmartNewsService
from database.operations import get_user_profile_by_uuid

logger = logging.getLogger(__name__)

class NewsFunctions(BaseFunctionExecutor):
    """News-related function executor following your pattern"""

    def __init__(self):
        self.news_service = SmartNewsService()

    async def execute(self, function_name: str, firebase_uid: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Execute news functions"""
        try:
            if function_name == "get_recent_news":
                return await self._get_recent_news(firebase_uid, arguments)
            elif function_name == "get_news_insights":
                return await self._get_news_insights(firebase_uid, arguments)
            else:
                return self._error_response(f"Unknown news function: {function_name}")

        except Exception as e:
            logger.error(f"Error executing news function {function_name}: {e}")
            return self._error_response(str(e))

    async def _get_recent_news(self, firebase_uid: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Get recent news for the user"""
        try:
            # SMART FIX: Try to get profession from multiple sources
            profession = "Professional"  # Default fallback
            location = "India"

            # Method 1: Check if arguments contain profession (from main chat context)
            if 'profession' in arguments:
                profession = arguments['profession']
                logger.info(f"🎯 Using profession from arguments: {profession}")

            # Method 2: Try database as fallback
            else:
                logger.info(f"🔍 Getting user profile from database for Firebase UID: {firebase_uid}")
                user_profile = get_user_profile_by_uuid(firebase_uid)
                logger.info(f"👤 Database user profile: {user_profile}")

                if user_profile:
                    profession = user_profile.get('profession', 'Professional')
                    location = user_profile.get('location', 'India')

            logger.info(f"📋 Final values: profession={profession}, location={location}")

            # Get days back from arguments
            days_back = arguments.get('days_back', 3)

            # Use the fast method with fixed caching
            news_context = await self.news_service.get_news_context_for_chat_fast(
                profession=profession,
                location=location,
                days_back=days_back
            )

            logger.info(f"📰 News context loaded: {news_context.get('total_articles', 0)} articles for {profession}")

            if news_context.get('total_articles', 0) > 0:
                # Format for chat response with proper Markdown spacing
                response_text = f"📰 **Recent news for {profession}s:**\n\n"

                # Add top articles with proper line breaks
                for category, articles in news_context.get('categories', {}).items():
                    if articles:
                        category_name = category.replace('_', ' ').title()
                        response_text += f"**{category_name}:**\n\n"  # Double newline after header
                        for article in articles[:2]:  # Top 2 per category
                            response_text += f"• {article['title']}  \n"  # Two spaces + newline for hard break
                        response_text += "\n"  # Single newline between categories

                # Add actionable items with proper spacing
                if news_context.get('local_events'):
                    response_text += f"🎯 **{len(news_context['local_events'])} local events** you might want to attend  \n"

                if news_context.get('learning_opportunities'):
                    response_text += f"📚 **{len(news_context['learning_opportunities'])} learning opportunities** found  \n"

                response_text += "\nWould you like me to create tasks or calendar events from any of these?"

                return self._success_response(
                    message=response_text,
                    data={
                        "total_articles": news_context['total_articles'],
                        "categories": list(news_context.get('categories', {}).keys()),
                        "actionable_items": {
                            "local_events": len(news_context.get('local_events', [])),
                            "learning_opportunities": len(news_context.get('learning_opportunities', []))
                        }
                    }
                )
            else:
                return self._success_response(
                    message=f"I couldn't find recent news specifically relevant to {profession}s, but I can help you with your tasks and schedule."
                )

        except Exception as e:
            logger.error(f"❌ Error in _get_recent_news: {e}")
            return self._error_response(f"Failed to get recent news: {str(e)}")

    async def _get_news_insights(self, firebase_uid: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Get news insights and trends"""
        try:
            # FIX: Use the same profession logic as _get_recent_news
            profession = "Professional"  # Default fallback
            location = "India"

            # Method 1: Check if arguments contain profession (from main chat context)
            if 'profession' in arguments:
                profession = arguments['profession']
                logger.info(f"🎯 Using profession from arguments: {profession}")

            # Method 2: Try database as fallback
            else:
                logger.info(f"🔍 Getting user profile from database for Firebase UID: {firebase_uid}")
                user_profile = get_user_profile_by_uuid(firebase_uid)
                logger.info(f"👤 Database user profile: {user_profile}")

                if user_profile:
                    profession = user_profile.get('profession', 'Professional')
                    location = user_profile.get('location', 'India')

            logger.info(f"📋 Final values for insights: profession={profession}, location={location}")

            # Get contextual news
            news_response = await self.news_service.get_contextual_news(
                profession=profession,
                location=location,
                limit=10
            )

            articles = news_response.get('articles', [])

            if articles:
                # Format with proper Markdown spacing
                insights_text = f"🔍 **News insights for {profession}s:**\n\n"

                # Group by categories
                categories = {}
                for article in articles:
                    cat = article.get('category', 'general')
                    if cat not in categories:
                        categories[cat] = []
                    categories[cat].append(article)

                # Generate insights with proper line breaks
                for category, cat_articles in categories.items():
                    if cat_articles:
                        category_name = category.replace('_', ' ').title()
                        insights_text += f"**{category_name} ({len(cat_articles)} articles):**\n\n"  # ✅ Double newline

                        # Show high-relevance articles
                        high_relevance = [a for a in cat_articles if a.get('relevance_score', 0) > 0.7]
                        if high_relevance:
                            insights_text += f"• {len(high_relevance)} highly relevant updates  \n"  # ✅ Two spaces

                        # Show most recent
                        if cat_articles:
                            latest = max(cat_articles, key=lambda x: x.get('published_at', ''))
                            insights_text += f"• Latest: {latest.get('title', '')[:60]}...  \n"  # ✅ Two spaces

                        insights_text += "\n"  # Single newline between categories

                insights_text += "💡 I can help you create learning tasks or add important events to your calendar!"

                return self._success_response(
                    message=insights_text,
                    data={
                        "total_articles": len(articles),
                        "categories": list(categories.keys()),
                        "high_relevance_count": len([a for a in articles if a.get('relevance_score', 0) > 0.7])
                    }
                )
            else:
                return self._success_response(
                    message=f"No specific insights available for {profession}s right now, but I'm ready to help with your tasks and events!"
                )

        except Exception as e:
            logger.error(f"❌ Error in _get_news_insights: {e}")
            return self._error_response(f"Failed to get news insights: {str(e)}")
