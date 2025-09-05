import json
from datetime import datetime, timedelta
import re
from typing import Dict, List, Optional

class EnhancedCalendarAgent:
    def __init__(self):
        self.events = []  # In-memory storage for demo

    async def process(self, request: AgentRequest) -> AgentResponse:
        message = request.message.lower()

        # Parse different calendar intents
        if any(word in message for word in ['schedule', 'book', 'create', 'add']):
            return await self.create_event(request)
        elif any(word in message for word in ['show', 'list', 'view', 'what']):
            return await self.list_events(request)
        elif any(word in message for word in ['free', 'available', 'busy']):
            return await self.check_availability(request)
        else:
            return await self.general_calendar_help(request)

    async def create_event(self, request: AgentRequest) -> AgentResponse:
        # Extract event details from natural language
        message = request.message.lower()

        # Simple event extraction (can be enhanced with NLP)
        event_data = self.extract_event_data(message)

        if event_data:
            # Create event
            event_id = f"event_{len(self.events) + 1}"
            event = {
                'id': event_id,
                'title': event_data.get('title', 'New Event'),
                'date': event_data.get('date', datetime.now().strftime('%Y-%m-%d')),
                'time': event_data.get('time', '10:00'),
                'duration': event_data.get('duration', 60),
                'created_at': datetime.now().isoformat()
            }

            self.events.append(event)

            return AgentResponse(
                agent_name="CalendarAgent",
                response=f"✅ Successfully created event: '{event['title']}' on {event['date']} at {event['time']}",
                type="calendar",
                metadata={
                    "action": "event_created",
                    "event": event,
                    "show_calendar": True
                },
                suggested_actions=["View my calendar", "Create another event", "Set reminder"]
            )
        else:
            return AgentResponse(
                agent_name="CalendarAgent",
                response="I'd be happy to help you schedule an event! Please provide more details like:\n\n• What event would you like to schedule?\n• When would you like it?\n• How long should it be?",
                type="calendar",
                metadata={"action": "request_details"},
                requires_follow_up=True,
                suggested_actions=["Schedule meeting with John tomorrow 3 PM", "Book dentist appointment next week"]
            )

    async def list_events(self, request: AgentRequest) -> AgentResponse:
        if not self.events:
            return AgentResponse(
                agent_name="CalendarAgent",
                response="📅 You don't have any scheduled events yet. Would you like to create one?",
                type="calendar",
                metadata={"action": "empty_calendar"},
                suggested_actions=["Schedule a meeting", "Add personal event", "Set reminder"]
            )

        # Format events for display
        events_text = "📅 Your upcoming events:\n\n"
        for event in self.events[-5:]:  # Show last 5 events
            events_text += f"• **{event['title']}**\n  {event['date']} at {event['time']}\n\n"

        return AgentResponse(
            agent_name="CalendarAgent",
            response=events_text,
            type="calendar",
            metadata={
                "action": "events_listed",
                "events": self.events[-5:],
                "show_calendar": True
            },
            suggested_actions=["Create new event", "Modify event", "Check availability"]
        )

    async def check_availability(self, request: AgentResponse) -> AgentResponse:
        # Simple availability check
        today = datetime.now()
        available_slots = []

        # Generate some available time slots
        for i in range(1, 8):  # Next 7 days
            date = (today + timedelta(days=i)).strftime('%Y-%m-%d')
            available_slots.extend([
                f"{date} at 9:00 AM",
                f"{date} at 2:00 PM",
                f"{date} at 4:00 PM"
            ])

        response_text = "🕒 You have availability on:\n\n"
        for slot in available_slots[:6]:  # Show first 6 slots
            response_text += f"• {slot}\n"

        return AgentResponse(
            agent_name="CalendarAgent",
            response=response_text,
            type="calendar",
            metadata={
                "action": "availability_check",
                "available_slots": available_slots[:6]
            },
            suggested_actions=["Schedule meeting for [time]", "Check next week", "Block time slot"]
        )

    async def general_calendar_help(self, request: AgentRequest) -> AgentResponse:
        return AgentResponse(
            agent_name="CalendarAgent",
            response="📅 I can help you manage your calendar! I can:\n\n• **Schedule events** - 'Schedule meeting with John tomorrow 3 PM'\n• **View your calendar** - 'What's my schedule today?'\n• **Check availability** - 'When am I free this week?'\n• **Set reminders** - 'Remind me about the presentation'\n\nWhat would you like to do?",
            type="calendar",
            metadata={"action": "help"},
            suggested_actions=["Schedule a meeting", "View my calendar", "Check my availability"]
        )

    def extract_event_data(self, message: str) -> Optional[Dict]:
        """Extract event details from natural language"""
        event_data = {}

        # Extract common event titles
        meeting_patterns = [
            r'meeting with (\w+)',
            r'call with (\w+)',
            r'(\w+) appointment',
            r'schedule (\w+)',
        ]

        for pattern in meeting_patterns:
            match = re.search(pattern, message)
            if match:
                event_data['title'] = f"Meeting with {match.group(1).title()}" if 'meeting' in pattern else f"{match.group(1).title()} Appointment"
                break

        # Extract time patterns
        time_patterns = [
            r'(\d{1,2}):(\d{2})\s*(am|pm)',
            r'(\d{1,2})\s*(am|pm)',
            r'at (\d{1,2})',
        ]

        for pattern in time_patterns:
            match = re.search(pattern, message)
            if match:
                if 'am' in pattern or 'pm' in pattern:
                    event_data['time'] = match.group(0)
                else:
                    event_data['time'] = f"{match.group(1)}:00"
                break

        # Extract date patterns
        date_patterns = [
            r'tomorrow',
            r'next week',
            r'monday|tuesday|wednesday|thursday|friday|saturday|sunday',
        ]

        for pattern in date_patterns:
            if re.search(pattern, message):
                if pattern == 'tomorrow':
                    event_data['date'] = (datetime.now() + timedelta(days=1)).strftime('%Y-%m-%d')
                elif pattern == 'next week':
                    event_data['date'] = (datetime.now() + timedelta(days=7)).strftime('%Y-%m-%d')
                break

        return event_data if event_data else None

# Update the orchestrator to use enhanced calendar agent
class SimpleOrchestrator:
    def __init__(self):
        self.calendar_agent = EnhancedCalendarAgent()
        self.agents = {
            'chat': 'ChatAgent',
            'calendar': 'CalendarAgent',
            'email': 'EmailAgent',
        }

    # ... existing methods ...

    async def handle_calendar(self, request: AgentRequest) -> AgentResponse:
        """Enhanced calendar handling"""
        return await self.calendar_agent.process(request)
