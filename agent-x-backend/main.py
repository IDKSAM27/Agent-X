from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
import re
import uvicorn

app = FastAPI(
    title="Agent X Backend",
    description="Multi-Agent AI Orchestration System",
    version="1.0.0"
)

# CORS middleware for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure properly for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pydantic models
class AgentRequest(BaseModel):
    message: str
    user_id: str
    context: Dict[str, Any]
    timestamp: str

class AgentResponse(BaseModel):
    agent_name: str
    response: str
    type: str
    metadata: Dict[str, Any] = {}
    requires_follow_up: bool = False
    suggested_actions: Optional[List[str]] = None

# Complete Enhanced Calendar Agent with all methods
class EnhancedCalendarAgent:
    def __init__(self):
        self.events = []  # In-memory storage for demo

    async def process(self, request: AgentRequest) -> AgentResponse:
        message = request.message.lower()

        # Parse different calendar intents including deletion
        if any(word in message for word in ['schedule', 'book', 'create', 'add']):
            return await self.create_event(request)
        elif any(word in message for word in ['delete', 'cancel', 'remove', 'clear']):
            return await self.delete_event(request)
        elif any(word in message for word in ['show', 'list', 'view', 'what']):
            return await self.list_events(request)
        elif any(word in message for word in ['free', 'available', 'busy']):
            return await self.check_availability(request)
        else:
            return await self.general_calendar_help(request)

    # CREATE EVENT METHOD
    async def create_event(self, request: AgentRequest) -> AgentResponse:
        message = request.message.lower()
        event_data = self.extract_event_data(message)

        if event_data:
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

    # LIST EVENTS METHOD
    async def list_events(self, request: AgentRequest) -> AgentResponse:
        if not self.events:
            return AgentResponse(
                agent_name="CalendarAgent",
                response="📅 You don't have any scheduled events yet. Would you like to create one?",
                type="calendar",
                metadata={"action": "empty_calendar"},
                suggested_actions=["Schedule a meeting", "Add personal event", "Set reminder"]
            )

        events_text = "📅 Your upcoming events:\n\n"
        for event in self.events[-5:]:
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

    # CHECK AVAILABILITY METHOD
    async def check_availability(self, request: AgentRequest) -> AgentResponse:
        today = datetime.now()
        available_slots = []

        for i in range(1, 8):
            date = (today + timedelta(days=i)).strftime('%Y-%m-%d')
            available_slots.extend([
                f"{date} at 9:00 AM",
                f"{date} at 2:00 PM",
                f"{date} at 4:00 PM"
            ])

        response_text = "🕒 You have availability on:\n\n"
        for slot in available_slots[:6]:
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

    # DELETE EVENT METHOD (NEW)
    async def delete_event(self, request: AgentRequest) -> AgentResponse:
        message = request.message.lower()

        if not self.events:
            return AgentResponse(
                agent_name="CalendarAgent",
                response="📅 You don't have any events to delete. Your calendar is already empty!",
                type="calendar",
                metadata={"action": "no_events_to_delete"},
                suggested_actions=["Schedule a meeting", "View calendar", "Check availability"]
            )

        deleted_events = []

        # Simple deletion patterns
        if 'all' in message or 'everything' in message:
            deleted_events = self.events.copy()
            self.events.clear()
            response_text = f"🗑️ Deleted all {len(deleted_events)} events from your calendar."

        elif 'tomorrow' in message:
            tomorrow = (datetime.now() + timedelta(days=1)).strftime('%Y-%m-%d')
            events_to_delete = [event for event in self.events if event['date'] == tomorrow]

            for event in events_to_delete:
                self.events.remove(event)
                deleted_events.append(event)

            if deleted_events:
                response_text = f"🗑️ Deleted {len(deleted_events)} event(s) for tomorrow:\n\n"
                for event in deleted_events:
                    response_text += f"• {event['title']} at {event['time']}\n"
            else:
                response_text = "❌ No events found for tomorrow to delete."

        elif 'today' in message:
            today = datetime.now().strftime('%Y-%m-%d')
            events_to_delete = [event for event in self.events if event['date'] == today]

            for event in events_to_delete:
                self.events.remove(event)
                deleted_events.append(event)

            if deleted_events:
                response_text = f"🗑️ Deleted {len(deleted_events)} event(s) for today:\n\n"
                for event in deleted_events:
                    response_text += f"• {event['title']} at {event['time']}\n"
            else:
                response_text = "❌ No events found for today to delete."
        else:
            response_text = "❓ What would you like to delete? You can say:\n\n• 'Delete all events'\n• 'Cancel tomorrow's meetings'\n• 'Delete today's appointments'"

        return AgentResponse(
            agent_name="CalendarAgent",
            response=response_text,
            type="calendar",
            metadata={
                "action": "events_deleted" if deleted_events else "delete_failed",
                "deleted_events": deleted_events,
                "remaining_events": len(self.events),
                "show_calendar": True
            },
            suggested_actions=["View remaining events", "Schedule new event"] if deleted_events else ["View my calendar", "Schedule a meeting"]
        )

    # GENERAL HELP METHOD
    async def general_calendar_help(self, request: AgentRequest) -> AgentResponse:
        return AgentResponse(
            agent_name="CalendarAgent",
            response="📅 I can help you manage your calendar! I can:\n\n• **Schedule events** - 'Schedule meeting with John tomorrow 3 PM'\n• **View your calendar** - 'What's my schedule today?'\n• **Delete events** - 'Delete all my events' or 'Cancel tomorrow's meetings'\n• **Check availability** - 'When am I free this week?'\n• **Set reminders** - 'Remind me about the presentation'\n\nWhat would you like to do?",
            type="calendar",
            metadata={"action": "help"},
            suggested_actions=["Schedule a meeting", "View my calendar", "Delete an event", "Check availability"]
        )

    # EVENT DATA EXTRACTION METHOD
    def extract_event_data(self, message: str) -> Optional[Dict]:
        event_data = {}

        # Extract event titles
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
        if 'tomorrow' in message:
            event_data['date'] = (datetime.now() + timedelta(days=1)).strftime('%Y-%m-%d')
        elif 'next week' in message:
            event_data['date'] = (datetime.now() + timedelta(days=7)).strftime('%Y-%m-%d')

        return event_data if event_data else None

# ORCHESTRATOR WITH ENHANCED CALENDAR AGENT
class SimpleOrchestrator:
    def __init__(self):
        self.calendar_agent = EnhancedCalendarAgent()
        self.agents = {
            'chat': 'ChatAgent',
            'calendar': 'CalendarAgent',
            'email': 'EmailAgent',
        }

    async def classify_intent(self, message: str) -> str:
        message_lower = message.lower()

        if any(word in message_lower for word in ['schedule', 'meeting', 'calendar', 'appointment', 'book', 'delete', 'cancel', 'remove']):
            return 'calendar'
        elif any(word in message_lower for word in ['email', 'mail', 'send', 'compose', 'inbox']):
            return 'email'
        else:
            return 'chat'

    async def process_request(self, request: AgentRequest) -> AgentResponse:
        intent = await self.classify_intent(request.message)

        if intent == 'chat':
            return await self.handle_chat(request)
        elif intent == 'calendar':
            return await self.calendar_agent.process(request)
        elif intent == 'email':
            return await self.handle_email(request)
        else:
            return await self.handle_chat(request)

    async def handle_chat(self, request: AgentRequest) -> AgentResponse:
        return AgentResponse(
            agent_name="ChatAgent",
            response=f"Hello! You said: '{request.message}'. I'm your AI assistant and I'm here to help with various tasks including scheduling, emails, and general conversation.",
            type="text",
            metadata={"intent": "chat"},
            suggested_actions=["Ask about schedule", "Check emails", "Plan your day"]
        )

    async def handle_email(self, request: AgentRequest) -> AgentResponse:
        return AgentResponse(
            agent_name="EmailAgent",
            response=f"I can help you with email management. You mentioned: '{request.message}'. I can sort emails, compose messages, and manage your inbox.",
            type="email",
            metadata={"intent": "email", "action_needed": "email_management"},
            requires_follow_up=True,
            suggested_actions=["Check inbox", "Compose email", "Sort by priority"]
        )

# Initialize orchestrator
orchestrator = SimpleOrchestrator()

# API Routes
@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.post("/api/agents/process", response_model=AgentResponse)
async def process_agent_request(request: AgentRequest):
    try:
        response = await orchestrator.process_request(request)
        return response
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/agents")
async def get_agents():
    return {
        "agents": list(orchestrator.agents.keys()),
        "total": len(orchestrator.agents)
    }

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
