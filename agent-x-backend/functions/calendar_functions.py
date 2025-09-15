from typing import Dict, Any
from datetime import datetime
from functions.base import BaseFunctionExecutor
from database.operations import save_event, get_all_events
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
        description = args.get("description", "")
        date = args.get("date", "")
        time = args.get("time", "10:00")
        category = args.get("category", "general")
        priority = args.get("priority", "medium")
        location = args.get("location", "")

        if not title:
            return self._error_response("Event title is required")

        if not date:
            # Default to tomorrow if no date provided
            from datetime import datetime, timedelta
            date = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")

        # Combine date and time for start_time
        start_time = f"{date} {time}"

        try:
            event_id = save_event(
                firebase_uid=firebase_uid,
                title=title,
                description=description,
                start_time=start_time,
                category=category,
                priority=priority,
                location=location
            )

            logger.info(f"✅ LLM created event: {title} for {firebase_uid}")

            return self._success_response(
                f"✅ Created event '{title}' on {date} at {time}",
                {
                    "event_id": event_id,
                    "title": title,
                    "date": date,
                    "time": time,
                    "category": category,
                    "priority": priority
                }
            )

        except Exception as e:
            logger.error(f"❌ Error creating event: {e}")
            return self._error_response(f"Failed to create event: {str(e)}")

    async def _get_events(self, firebase_uid: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Get user events"""
        events = get_all_events(firebase_uid)

        if not events:
            return self._success_response(
                "📅 You don't have any scheduled events yet. Would you like to create one?",
                {"events": [], "count": 0}
            )

        # Format events for display
        formatted_events = []
        event_summaries = []

        for event in events:
            event_id, title, description, start_time, end_time, category, priority, location, created_at = event

            formatted_events.append({
                "id": event_id,
                "title": title,
                "description": description,
                "start_time": start_time,
                "category": category,
                "priority": priority,
                "location": location
            })

            # Create summary for natural response
            event_summaries.append(f"📅 **{title}** - {start_time}")

        detailed_message = f"📅 **Your Upcoming Events ({len(events)} total):**\n\n" + "\n".join(event_summaries)

        return self._success_response(
            detailed_message,
            {
                "events": formatted_events,
                "count": len(events)
            }
        )
