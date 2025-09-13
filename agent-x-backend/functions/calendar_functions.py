from typing import Dict, Any
from datetime import datetime
from .base import BaseFunctionExecutor
from database import save_event, get_all_events  # Import your existing DB functions
import logging

logger = logging.getLogger(__name__)

class CalendarFunctions(BaseFunctionExecutor):
    """Handle calendar-related function calls"""

    async def execute(self, function_name: str, firebase_uid: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Execute calendar function"""
        try:
            if function_name == "create_event":
                return await self._create_event(firebase_uid, arguments)
            elif function_name == "get_events":
                return await self._get_events(firebase_uid, arguments)
            else:
                return self._error_response(f"Unknown calendar function: {function_name}")

        except Exception as e:
            logger.error(f"❌ Calendar function error: {e}")
            return self._error_response(str(e))

    async def _create_event(self, firebase_uid: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Create a calendar event"""
        title = args.get("title", "").strip()
        date = args.get("date", "").strip()
        time = args.get("time", "10:00")

        if not title:
            return self._error_response("Event title is required")

        if not date:
            return self._error_response("Event date is required")

        # Validate date format
        try:
            datetime.strptime(date, "%Y-%m-%d")
        except ValueError:
            return self._error_response("Date must be in YYYY-MM-DD format")

        # Use your existing save_event function
        event_id = save_event(
            firebase_uid=firebase_uid,
            title=title,
            date=date,
            time_=time
        )

        logger.info(f"✅ LLM created event: {title} on {date} for {firebase_uid}")

        return self._success_response(
            f"Event '{title}' scheduled for {date} at {time}",
            {
                "event_id": event_id,
                "title": title,
                "date": date,
                "time": time,
                "created_at": datetime.now().isoformat()
            }
        )

    async def _get_events(self, firebase_uid: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Get user events"""
        # Use your existing get_all_events function
        events = get_all_events(firebase_uid)

        if not events:
            return self._success_response(
                "No events found",
                {"events": [], "count": 0}
            )

        # Format events for LLM
        formatted_events = []
        for event in events:
            title, start_time = event
            formatted_events.append({
                "title": title,
                "datetime": start_time
            })

        return self._success_response(
            f"Found {len(events)} events",
            {
                "events": formatted_events,
                "count": len(events)
            }
        )
