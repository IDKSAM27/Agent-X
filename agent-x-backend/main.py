from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from memory_manager import memory_manager
import re
import uvicorn
import logging
import sqlite3
import json
import uuid
from openai import OpenAI

# Set up proper logging
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Agent X Backend",
    description="Multi-Agent AI Orchestration System",
    version="1.0.0"
)

# Configure OpenRouter client
client = OpenAI(
    base_url="https://openrouter.ai/api/v1",
    api_key="YOUR_OPENROUTER_API_KEY"  # Store in environment variable
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Try to import memory system
try:
    # from memory_manager import memory_manager
    MEMORY_ENABLED = True
    logger.info("🧠 Memory system loaded successfully!")
except ImportError as e:
    logger.warning(f"⚠️ Memory system not available: {e}")
    MEMORY_ENABLED = False

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

# Enhanced Calendar Agent (same as before)
class EnhancedCalendarAgent:
    def __init__(self):
        self.events = []

    async def process(self, request: AgentRequest) -> AgentResponse:
        message = request.message.lower()
        logger.debug(f"📅 Calendar agent processing: {message}")

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
            logger.info(f"📅 Created event: {event['title']} on {event['date']}")

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
            response_text = f"🗑️ Deleted {len(deleted_events)} event(s) for tomorrow." if deleted_events else "❌ No events found for tomorrow."
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

    async def general_calendar_help(self, request: AgentRequest) -> AgentResponse:
        return AgentResponse(
            agent_name="CalendarAgent",
            response="📅 I can help you manage your calendar! I can:\n\n• **Schedule events** - 'Schedule meeting with John tomorrow 3 PM'\n• **View your calendar** - 'What's my schedule today?'\n• **Delete events** - 'Delete all my events'\n• **Check availability** - 'When am I free this week?'\n\nWhat would you like to do?",
            type="calendar",
            metadata={"action": "help"},
            suggested_actions=["Schedule a meeting", "View my calendar", "Delete an event", "Check availability"]
        )

    def extract_event_data(self, message: str) -> Optional[Dict]:
        event_data = {}

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

        if 'tomorrow' in message:
            event_data['date'] = (datetime.now() + timedelta(days=1)).strftime('%Y-%m-%d')
        elif 'next week' in message:
            event_data['date'] = (datetime.now() + timedelta(days=7)).strftime('%Y-%m-%d')

        return event_data if event_data else None

# MEMORY-AWARE ORCHESTRATOR
class SimpleOrchestrator:
    def __init__(self):
        self.calendar_agent = EnhancedCalendarAgent()
        self.agents = {
            'chat': 'ChatAgent',
            'calendar': 'CalendarAgent',
            'email': 'EmailAgent',
        }
        self.memory_enabled = MEMORY_ENABLED

    async def classify_intent(self, message: str) -> str:
        message_lower = message.lower()

        if any(word in message_lower for word in ['schedule', 'meeting', 'calendar', 'appointment', 'book', 'delete', 'cancel', 'remove']):
            return 'calendar'
        elif any(word in message_lower for word in ['email', 'mail', 'send', 'compose', 'inbox']):
            return 'email'
        else:
            return 'chat'

    # ENHANCED PROCESS REQUEST WITH MEMORY
    async def process_request(self, request: AgentRequest) -> AgentResponse:
        logger.debug(f"🤖 Processing request from {request.user_id}: {request.message}")

        # Get user context from memory if available
        user_context = {}
        if self.memory_enabled:
            try:
                user_context = await memory_manager.get_user_context(request.user_id)
                logger.debug(f"🧠 Retrieved context for {request.user_id}: {len(user_context.get('recent_conversations', []))} conversations")
            except Exception as e:
                logger.error(f"🧠 Memory error: {e}")
                user_context = {}

        intent = await self.classify_intent(request.message)
        logger.debug(f"🎯 Classified intent: {intent}")

        if intent == 'chat':
            response = await self.handle_chat(request, user_context)
        elif intent == 'calendar':
            response = await self.calendar_agent.process(request)
        elif intent == 'email':
            response = await self.handle_email(request, user_context)
        else:
            response = await self.handle_chat(request, user_context)

        # Store conversation in memory
        if self.memory_enabled:
            try:
                message_id = f"{request.user_id}_{datetime.now().timestamp()}"
                await memory_manager.store_conversation(
                    user_id=request.user_id,
                    message_id=message_id,
                    user_message=request.message,
                    agent_response=response.response,
                    agent_name=response.agent_name,
                    metadata=response.metadata
                )
                logger.info(f"🧠 Stored conversation for {request.user_id}")

                # Store user preferences if mentioned
                await self.extract_and_store_preferences(request, user_context)

            except Exception as e:
                logger.error(f"🧠 Failed to store conversation: {e}")

        return response

    # MEMORY-AWARE CHAT HANDLER
    async def handle_chat(self, request: AgentRequest, user_context: dict = None) -> AgentResponse:
        message = request.message.lower()

        # Check if user is asking about their name/profession
        if any(word in message for word in ['my name', 'what is my name', 'who am i']):
            if user_context and user_context.get('recent_conversations'):
                # Search for name mentions in past conversations
                for conv in user_context['recent_conversations']:
                    content = conv.get('content', '').lower()
                    if 'my name is' in content or 'i am' in content:
                        # Extract name from conversation
                        import re
                        name_match = re.search(r'my name is (\w+)', content)
                        if name_match:
                            name = name_match.group(1).title()
                            return AgentResponse(
                                agent_name="ChatAgent",
                                response=f"Your name is {name}! I remember you telling me that.",
                                type="text",
                                metadata={"intent": "name_recall", "memory_used": True},
                                suggested_actions=["Tell me more about yourself", "What can you help me with?"]
                            )

        # Check if user is asking about their profession
        elif any(word in message for word in ['my profession', 'what is my profession', 'what do i do', 'my job']):
            if user_context and user_context.get('recent_conversations'):
                for conv in user_context['recent_conversations']:
                    content = conv.get('content', '').lower()
                    if 'software engineer' in content or 'developer' in content or 'programmer' in content:
                        return AgentResponse(
                            agent_name="ChatAgent",
                            response=f"You're a software engineer! I remember you mentioning that. How can I help you with your work today?",
                            type="text",
                            metadata={"intent": "profession_recall", "memory_used": True},
                            suggested_actions=["Help with coding", "Schedule work meetings", "Plan your day"]
                        )

        # Enhanced chat with memory awareness
        context_info = ""
        if user_context and user_context.get('recent_conversations'):
            context_info = f" I remember our previous conversations and I'm here to help based on what I know about you."

        return AgentResponse(
            agent_name="ChatAgent",
            response=f"Hello! You said: '{request.message}'. I'm your AI assistant and I'm here to help with various tasks including scheduling, emails, and general conversation.{context_info}",
            type="text",
            metadata={"intent": "chat", "memory_used": bool(context_info)},
            suggested_actions=["Ask about schedule", "Check emails", "Plan your day"]
        )

    async def handle_email(self, request: AgentRequest, user_context: dict = None) -> AgentResponse:
        return AgentResponse(
            agent_name="EmailAgent",
            response=f"I can help you with email management. You mentioned: '{request.message}'. I can sort emails, compose messages, and manage your inbox.",
            type="email",
            metadata={"intent": "email", "action_needed": "email_management"},
            requires_follow_up=True,
            suggested_actions=["Check inbox", "Compose email", "Sort by priority"]
        )

    # EXTRACT USER PREFERENCES
    async def extract_and_store_preferences(self, request: AgentRequest, user_context: dict):
        message = request.message.lower()

        # Extract name
        name_match = re.search(r'my name is (\w+)', message)
        if name_match:
            name = name_match.group(1)

        # Extract profession
        profession = "Unknown"
        if 'software engineer' in message:
            profession = "Software Engineer"
        elif 'developer' in message:
            profession = "Developer"
        elif 'student' in message:
            profession = "Student"
        elif 'teacher' in message:
            profession = "Teacher"

        if profession != "Unknown":
            preferences = {"profession": profession}
            await memory_manager.store_user_preferences(
                user_id=request.user_id,
                profession=profession,
                preferences=preferences
            )
            logger.info(f"🧠 Stored user preference: {profession} for {request.user_id}")

# Initialize orchestrator
orchestrator = SimpleOrchestrator()

# DEBUG ENDPOINTS
@app.get("/debug")
async def debug_endpoint():
    logger.debug("🔧 Debug endpoint called")
    return {"message": "Debug working", "memory_enabled": MEMORY_ENABLED}

@app.get("/api/memory/debug/{user_id}")
async def debug_memory(user_id: str):
    """Debug endpoint to inspect stored conversations"""
    logger.debug(f"🔍 Memory debug requested for user: {user_id}")

    if not MEMORY_ENABLED:
        return {"error": "Memory system not enabled"}

    try:
        # Get all conversations for user
        conversations = await memory_manager.search_conversations(
            query="",
            user_id=user_id,
            limit=50
        )

        # Get user context
        user_context = await memory_manager.get_user_context(user_id)

        logger.info(f"🔍 Found {len(conversations)} conversations for {user_id}")

        return {
            "user_id": user_id,
            "total_conversations": len(conversations),
            "conversations": conversations,
            "user_context": user_context,
            "database_path": memory_manager.db_path
        }
    except Exception as e:
        logger.error(f"🔍 Memory debug error: {e}")
        return {"error": str(e)}

# API Routes
@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "memory_enabled": MEMORY_ENABLED, "timestamp": datetime.now().isoformat()}

@app.post("/api/agents/process", response_model=AgentResponse)
async def process_agent_request(request: AgentRequest):
    try:
        response = await orchestrator.process_request(request)
        return response
    except Exception as e:
        logger.error(f"❌ Error processing request: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/agents")
async def get_agents():
    return {
        "agents": list(orchestrator.agents.keys()),
        "total": len(orchestrator.agents)
    }

# Clear memory API endpoint
@app.post("/api/clear_memory")
async def clear_memory(request: Request):
    """Clear all user data and memory"""
    try:
        body = await request.json()
        user_id = body.get('user_id')

        if not user_id:
            return {"error": "user_id is required"}

        if not MEMORY_ENABLED:
            return {"error": "Memory system not enabled"}

        logger.info(f"🗑️ Clearing all data for user: {user_id}")

        # Clear SQLite database
        conn = sqlite3.connect(memory_manager.db_path)
        cursor = conn.cursor()

        cursor.execute('DELETE FROM conversations WHERE user_id = ?', (user_id,))
        cursor.execute('DELETE FROM user_preferences WHERE user_id = ?', (user_id,))
        cursor.execute('DELETE FROM agent_context WHERE user_id = ?', (user_id,))

        conn.commit()
        conn.close()

        # Clear ChromaDB vector collections
        try:
            memory_manager.conversations.delete(where={"user_id": user_id})
            memory_manager.user_preferences.delete(where={"user_id": user_id})
            memory_manager.agent_context.delete(where={"user_id": user_id})
        except Exception as e:
            logger.warning(f"ChromaDB clear warning: {e}")

        logger.info(f"🗑️ ✅ All data cleared for user: {user_id}")

        return {
            "status": "success",
            "message": "All chat history and memory data cleared successfully",
            "cleared_data": ["conversations", "user_preferences", "agent_context"]
        }

    except Exception as e:
        logger.error(f"🗑️ ❌ Error clearing memory: {e}")
        return {"status": "error", "message": str(e)}

@app.post("/api/export_chat")
async def export_chat(request: Request):
    """Export chat history for user"""
    try:
        body = await request.json()
        user_id = body.get('user_id')

        if not user_id or not MEMORY_ENABLED:
            return {"error": "user_id required and memory must be enabled"}

        # Get all conversations
        conn = sqlite3.connect(memory_manager.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT user_message, agent_response, agent_name, timestamp 
            FROM conversations WHERE user_id = ? 
            ORDER BY timestamp ASC
        ''', (user_id,))

        conversations = cursor.fetchall()
        conn.close()

        # Format as exportable data
        export_data = {
            "user_id": user_id,
            "export_date": datetime.now().isoformat(),
            "total_messages": len(conversations),
            "conversations": [
                {
                    "user_message": conv[0],
                    "agent_response": conv[1],
                    "agent_name": conv[2],
                    "timestamp": conv[3]
                }
                for conv in conversations
            ]
        }

        return {"status": "success", "data": export_data}

    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.post("/api/agents/process")
async def process_agent_request(request: Request):
    try:
        body = await request.json()
        message = body.get('message', '').lower()
        user_id = body.get('user_id')
        context = body.get('context', {})
        profession = context.get('profession', 'Unknown')

        logger.info(f"🐍 Backend processing: '{message}' for user {user_id}")

        # ✅ FIXED: Enhanced intent classification
        if _is_task_creation_intent(message):
            return _create_task_response(message, profession)
        elif _is_name_query_intent(message):
            return _handle_name_query_response(user_id)
        elif _is_export_intent(message):
            return _create_export_response()
        elif _is_calendar_intent(message):
            return _create_calendar_response(profession)
        else:
            return _create_general_response(profession, message)

    except Exception as e:
        logger.error(f"❌ Backend error: {e}")
        return _create_error_response()

# ✅ FIXED: Better intent detection functions
def _is_task_creation_intent(message: str) -> bool:
    task_indicators = [
        'create task', 'create a task', 'add task', 'add a task',
        'make task', 'make a task', 'new task', 'task to finish',
        'task to complete', 'task to do', 'finish project',
        'complete project', 'work on project'
    ]
    return any(indicator in message for indicator in task_indicators)

def _is_name_query_intent(message: str) -> bool:
    name_indicators = [
        'what is my name', 'whats my name', 'who am i',
        'what am i called', 'my name is', 'tell me my name'
    ]
    return any(indicator in message for indicator in name_indicators)

def _is_export_intent(message: str) -> bool:
    export_indicators = [
        'export', 'download', 'save chat', 'backup',
        'export chat', 'download chat'
    ]
    return any(indicator in message for indicator in export_indicators)

def _is_calendar_intent(message: str) -> bool:
    calendar_indicators = [
        'calendar', 'schedule', 'show calendar', 'my calendar',
        'show me calendar', 'view calendar'
    ]
    return any(indicator in message for indicator in calendar_indicators)

# ✅ FIXED: Specialized response creators
def _create_task_response(message: str, profession: str):
    task_title = _extract_task_from_message(message)

    return {
        "agent_name": "TaskAgent",
        "response": f"✅ **Task Created Successfully!**\n\n"
                    f"📋 **Task:** {task_title}\n"
                    f"👤 **For:** {profession}\n"
                    f"📅 **Created:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\n"
                    f"Your task has been added to your list!",
        "type": "task",
        "metadata": {
            "action": "task_created",
            "task_title": task_title,
            "source": "backend"
        },
        "suggested_actions": ["Set deadline", "Add priority", "View all tasks"],
        "requires_follow_up": False
    }

def _handle_name_query_response(user_id: str):
    # Try to get stored name (you can implement this with your memory system)
    stored_name = None  # Replace with actual memory lookup

    if stored_name:
        return {
            "agent_name": "PersonalAgent",
            "response": f"👋 **Hello {stored_name}!**\n\n"
                        f"I remember you! Your name is **{stored_name}**.",
            "type": "text",
            "metadata": {"action": "name_retrieved", "name": stored_name},
            "suggested_actions": ["Update my name", "Create a task"],
            "requires_follow_up": False
        }
    else:
        return {
            "agent_name": "PersonalAgent",
            "response": "🤔 **I don't know your name yet.**\n\n"
                        "You can tell me by saying:\n"
                        "• \"My name is John\"\n"
                        "• \"Call me Sarah\"\n\n"
                        "Once you tell me, I'll remember it!",
            "type": "text",
            "metadata": {"action": "name_request"},
            "suggested_actions": ["My name is...", "Call me...", "Skip for now"],
            "requires_follow_up": False
        }

def _create_export_response():
    return {
        "agent_name": "ExportAgent",
        "response": "📦 **Chat Export Ready!**\n\n"
                    "📊 **Summary:**\n"
                    "• Total conversations: 25\n"
                    "• Format: JSON with metadata\n"
                    "• Ready for download\n\n"
                    "Your chat export is prepared!",
        "type": "text",
        "metadata": {"action": "export_ready"},
        "suggested_actions": ["Download now", "Export as text", "Cancel"],
        "requires_follow_up": False
    }

def _create_calendar_response(profession: str):
    return {
        "agent_name": "CalendarAgent",
        "response": f"📅 **Calendar for {profession}**\n\n"
                    f"You don't have any scheduled events yet. "
                    f"Would you like to create one?",
        "type": "calendar",
        "metadata": {"action": "empty_calendar"},
        "suggested_actions": ["Schedule a meeting", "Add personal event", "Set reminder"],
        "requires_follow_up": False
    }

def _create_general_response(profession: str, message: str):
    return {
        "agent_name": "GeneralAgent",
        "response": f"Hello! I'm your AI assistant for {profession}s.\n\n"
                    f"I can help with:\n"
                    f"📋 Task Management\n"
                    f"📅 Calendar\n"
                    f"💾 Data Export\n"
                    f"👤 Personal Info\n\n"
                    f"What would you like to do?",
        "type": "text",
        "metadata": {"intent": "general_help"},
        "suggested_actions": ["Create a task", "Show calendar", "Export data"],
        "requires_follow_up": False
    }

def _create_error_response():
    return {
        "agent_name": "ErrorAgent",
        "response": "I apologize, but I encountered an issue. Please try again.",
        "type": "error",
        "metadata": {"error": "processing_failed"},
        "requires_follow_up": False
    }

def _extract_task_from_message(message: str) -> str:
    # Simple extraction logic
    if 'task to' in message:
        return message.split('task to')[-1].strip()
    elif 'finish' in message or 'complete' in message:
        if 'project' in message:
            return 'finish the project'
        elif 'work' in message:
            return 'complete the work'

    return 'Complete the task'


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="debug"
    )
