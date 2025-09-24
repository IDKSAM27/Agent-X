from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional
from datetime import datetime
import logging

from services.smart_news_service import SmartNewsService
from database.operations import get_user_profile_by_uuid
from utils.auth import verify_firebase_token
from models.api_models import NewsResponse, NewsRequest
from functions.task_functions import TaskFunctions
from functions.calendar_functions import CalendarFunctions

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/news", tags=["news"])

# Initialize news service (singleton)
news_service = SmartNewsService()

@router.get("/contextual", response_model=NewsResponse)
async def get_contextual_news(
        profession: Optional[str] = Query(None, description="User profession"),
        location: Optional[str] = Query("India", description="User location"),
        interests: Optional[str] = Query(None, description="Comma-separated interests"),
        limit: int = Query(30, ge=1, le=100, description="Number of articles to return"),
        force_refresh: bool = Query(False, description="Force refresh cache"),
        current_user: dict = Depends(verify_firebase_token)
):
    """Get contextually relevant news based on profession, location, and interests"""
    try:
        firebase_uid = current_user.get('uid')

        # Get user profile from database if not provided in query
        if not profession:
            user_profile = get_user_profile_by_uuid(firebase_uid)  # NO await here!
            if user_profile:
                profession = user_profile.get('profession', 'Professional')
                location = user_profile.get('location', location or 'India')

        # Ensure we always have values
        profession = profession or "Professional"
        location = location or "India"

        # Parse interests
        interests_list = []
        if interests:
            interests_list = [interest.strip() for interest in interests.split(',')]

        # Fetch contextual news
        news_data = await news_service.get_contextual_news(
            profession=profession,
            location=location,
            interests=interests_list,
            limit=limit,
            force_refresh=force_refresh
        )

        logger.info(f"Served contextual news to user {firebase_uid}: {len(news_data['articles'])} articles")

        return NewsResponse(
            success=True,
            message=f"Found {len(news_data['articles'])} relevant articles",
            data=news_data
        )

    except Exception as e:
        logger.error(f"Error fetching contextual news for user {current_user.get('uid')}: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to fetch news: {str(e)}"
        )


@router.get("/categories/{category}")
async def get_news_by_category(
        category: str,
        limit: int = Query(20, ge=1, le=50),
        current_user: dict = Depends(verify_firebase_token)
):
    """Get news articles for a specific category"""
    try:
        firebase_uid = current_user.get('uid')

        # Get user profile for context
        user_profile = await get_user_profile_by_uuid(firebase_uid)
        profession = user_profile.get('profession', 'Professional') if user_profile else 'Professional'
        location = user_profile.get('location', 'India') if user_profile else 'India'

        # Fetch news
        news_data = await news_service.get_contextual_news(
            profession=profession,
            location=location,
            limit=limit * 2  # Fetch more to filter by category
        )

        # Filter by category
        category_articles = []
        for article in news_data['articles']:
            if article['category'] == category:
                category_articles.append(article)
                if len(category_articles) >= limit:
                    break

        return NewsResponse(
            success=True,
            message=f"Found {len(category_articles)} articles in category '{category}'",
            data={
                'articles': category_articles,
                'category': category,
                'total_found': len(category_articles)
            }
        )

    except Exception as e:
        logger.error(f"Error fetching category news: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/local-events")
async def get_local_events(
        location: Optional[str] = Query(None),
        days_ahead: int = Query(30, ge=1, le=90),
        current_user: dict = Depends(verify_firebase_token)
):
    """Get local events and opportunities"""
    try:
        firebase_uid = current_user.get('uid')

        # Get user context
        user_profile = await get_user_profile_by_uuid(firebase_uid)
        if not location and user_profile:
            location = user_profile.get('location', 'India')

        profession = user_profile.get('profession', 'Professional') if user_profile else 'Professional'

        # Fetch news with focus on local events
        news_data = await news_service.get_contextual_news(
            profession=profession,
            location=location or 'India',
            limit=50  # Fetch more to filter events
        )

        # Filter for local events
        local_events = []
        for article in news_data['articles']:
            if article['is_local_event'] or article['category'] == 'local_events':
                local_events.append(article)

        return NewsResponse(
            success=True,
            message=f"Found {len(local_events)} local events",
            data={
                'events': local_events,
                'location': location,
                'days_ahead': days_ahead
            }
        )

    except Exception as e:
        logger.error(f"Error fetching local events: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/action")
async def execute_news_action(
        request: NewsRequest,
        current_user: dict = Depends(verify_firebase_token)
):
    """Execute an action from a news article (create task, add to calendar, etc.)"""
    try:
        firebase_uid = current_user.get('uid')
        action_type = request.action_type
        article_id = request.article_id
        metadata = request.metadata or {}

        logger.info(f"Executing news action '{action_type}' for user {firebase_uid}")

        if action_type == "create_task":
            # Import your existing task creation logic
            task_functions = TaskFunctions()

            task_data = {
                'title': metadata.get('task_title', f"Follow up: {metadata.get('article_title', 'News Item')}"),
                'description': metadata.get('task_description', f"From news: {metadata.get('article_url', '')}"),
                'priority': metadata.get('priority', 'medium'),
                'category': metadata.get('category', 'research')
            }

            result = await task_functions.execute('create_task', firebase_uid, task_data)

            return NewsResponse(
                success=result.get('success', False),
                message=result.get('message', 'Task created from news article'),
                data={'task_id': result.get('data', {}).get('task_id')}
            )

        elif action_type == "add_to_calendar":
            # Import your existing calendar logic
            calendar_functions = CalendarFunctions()

            event_data = {
                'title': metadata.get('event_title', metadata.get('article_title', 'Event')),
                'description': f"From news: {metadata.get('article_url', '')}",
                'date': metadata.get('event_date'),
                'time': metadata.get('event_time', '10:00')
            }

            result = await calendar_functions.execute('create_event', firebase_uid, event_data)

            return NewsResponse(
                success=result.get('success', False),
                message=result.get('message', 'Event added to calendar'),
                data={'event_id': result.get('data', {}).get('event_id')}
            )

        else:
            raise HTTPException(status_code=400, detail=f"Unknown action type: {action_type}")

    except Exception as e:
        logger.error(f"Error executing news action: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/health")
async def get_news_service_health():
    """Get health status of news sources"""
    try:
        health_data = await news_service.get_source_health()
        return {
            'success': True,
            'message': 'News service health check',
            'data': health_data
        }
    except Exception as e:
        logger.error(f"Error getting news health: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/feedback")
async def submit_news_feedback(
        article_id: str,
        feedback_type: str,  # 'helpful', 'not_relevant', 'spam'
        current_user: dict = Depends(verify_firebase_token)
):
    """Submit feedback on news articles for improving recommendations"""
    try:
        firebase_uid = current_user.get('uid')

        # Store feedback for future ML improvements
        # For now, just log it
        logger.info(f"News feedback from {firebase_uid}: {feedback_type} for article {article_id}")

        return NewsResponse(
            success=True,
            message="Feedback submitted successfully",
            data={'feedback_recorded': True}
        )

    except Exception as e:
        logger.error(f"Error submitting news feedback: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/test")
async def get_test_news(
        profession: str = Query("teacher", description="User profession"),
        location: str = Query("India", description="User location"),
        interests: str = Query("", description="Comma-separated interests"),
        limit: int = Query(5, ge=1, le=20),
        force_refresh: bool = Query(True, description="Force refresh for testing"),  # Default to true
):
    """Test endpoint for news system - NO AUTH REQUIRED"""
    try:
        logger.info(f"🧪 TEST ENDPOINT: profession={profession}, location={location}, force_refresh={force_refresh}")

        # Parse interests
        interests_list = []
        if interests:
            interests_list = [interest.strip() for interest in interests.split(',')]

        # Fetch contextual news
        news_data = await news_service.get_contextual_news(
            profession=profession,
            location=location,
            interests=interests_list,
            limit=limit,
            force_refresh=force_refresh
        )

        logger.info(f"🧪 TEST RESULT: {len(news_data.get('articles', []))} articles returned")

        return {
            'success': True,
            'message': f"Found {len(news_data.get('articles', []))} relevant articles",
            'data': news_data,
            'test_mode': True,
            'debug_timestamp': datetime.now().isoformat()
        }

    except Exception as e:
        logger.error(f"💥 Error in test news endpoint: {e}", exc_info=True)
        return {
            'success': False,
            'error': str(e),
            'message': 'Failed to fetch news',
            'debug_timestamp': datetime.now().isoformat()
        }

# For debugging
@router.get("/debug/sources")
async def debug_sources():
    """Debug endpoint to check source status"""
    try:
        source_status = {}
        for name, source in news_service.sources.items():
            source_status[name] = {
                'can_fetch': source.can_fetch(),
                'last_fetch': source.last_fetch.isoformat() if source.last_fetch else None,
                'fetch_count': source.fetch_count,
                'error_count': source.error_count,
                'health_score': source.get_health_score(),
                'config_active': source.config.is_active
            }
        return {'sources': source_status}
    except Exception as e:
        return {'error': str(e)}

