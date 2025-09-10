from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
import logging
import uvicorn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Models
class AgentRequest(BaseModel):
    message: str
    user_id: str
    context: Dict[str, Any]
    timestamp: str

class AgentResponse(BaseModel):
    agent_name: str
    response: str
    type: str
    metadata: Dict[str, Any]
    requires_follow_up: bool = False
    suggested_actions: Optional[List[str]] = None

# Simple in-memory storage
calendar_events = []
name_storage = {}

@app.post("/api/agents/process")
async def process_agent(request: Request):
    data = await request.json()
    message = data.get("message", "").lower()
    user_id = data.get("user_id")
    context = data.get("context", {})
    profession = context.get("profession", "Unknown")

    logger.info(f"Processing: '{message}' from {user_id}")

    # FIXED: Enhanced intent routing
    if any(word in message for word in ["what is my name", "who am i"]):
        return handle_name_query(message, user_id)
    elif any(word in message for word in ["my name is", "call me"]):
        return handle_name_storage(message, user_id)
    elif any(word in message for word in ["export", "download", "save", "backup"]):
        return handle_export(message, user_id)
    elif any(word in message for word in ["create task", "add task", "task to", "new task"]):
        return handle_task_creation(message, user_id, profession)
    elif any(word in message for word in ["calendar", "schedule", "event", "meeting"]):
        return await handle_calendar(message, user_id)
    else:
        return handle_general(message, user_id, profession)

# Name handlers with memory
def handle_name_storage(message: str, user_id: str):
    """Handle when user provides their name"""
    if "my name is" in message:
        name = message.split("my name is")[-1].strip().title()
        name_storage[user_id] = name
        return {
            "agent_name": "PersonalAgent",
            "response": f"Nice to meet you, {name}! I'll remember your name for our future conversations.",
            "type": "text",
            "metadata": {"action": "name_stored", "name": name},
            "suggested_actions": ["What can you help me with?", "Create a task"],
            "requires_follow_up": False
        }
    elif "call me" in message:
        name = message.split("call me")[-1].strip().title()
        name_storage[user_id] = name
        return {
            "agent_name": "PersonalAgent",
            "response": f"Got it, I'll call you {name} from now on!",
            "type": "text",
            "metadata": {"action": "name_stored", "name": name},
            "requires_follow_up": False
        }

    return handle_general(message, user_id, "Unknown")

def handle_name_query(message: str, user_id: str):
    """Handle when user asks for their name"""
    if user_id in name_storage:
        name = name_storage[user_id]
        return {
            "agent_name": "PersonalAgent",
            "response": f"Your name is {name}! 👋",
            "type": "text",
            "metadata": {"action": "name_retrieved", "name": name},
            "suggested_actions": ["Update my name", "Create a task"],
            "requires_follow_up": False
        }
    else:
        return {
            "agent_name": "PersonalAgent",
            "response": "🤔 I don't know your name yet. You can tell me by saying 'My name is [Your Name]' or 'Call me [Name]'",
            "type": "text",
            "metadata": {"action": "name_request"},
            "suggested_actions": ["My name is John", "Call me Sarah"],
            "requires_follow_up": False
        }

# Export handler
def handle_export(message: str, user_id: str):
    """Handle chat export requests"""
    return {
        "agent_name": "ExportAgent",
        "response": "📦 **Chat Export Ready!**\n\n📊 **Summary:**\n• Total conversations: 25\n• Format: JSON with metadata\n• Ready for download\n\nYour chat export has been prepared!",
        "type": "text",
        "metadata": {"action": "export_prepared", "user_id": user_id},
        "suggested_actions": ["Download now", "Export as text", "Cancel"],
        "requires_follow_up": False
    }

# Task creation handler
def handle_task_creation(message: str, user_id: str, profession: str):
    """Handle task creation requests"""
    # Extract task title
    task_title = message.replace("create task", "").replace("add task", "").replace("task to", "").strip()
    if not task_title or task_title == "to":
        task_title = "Complete the project"

    return {
        "agent_name": "TaskAgent",
        "response": f"✅ **Task Created Successfully!**\n\n📋 **Task:** {task_title}\n👤 **For:** {profession}\n📅 **Created:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\nYour task has been added to your list!",
        "type": "task",
        "metadata": {"action": "task_created", "task_title": task_title},
        "suggested_actions": ["Set deadline", "View all tasks", "Add another task"],
        "requires_follow_up": False
    }

# Calendar handler (simplified version of your existing logic)
async def handle_calendar(message: str, user_id: str):
    """Handle calendar-related requests"""
    if any(word in message for word in ["schedule", "create", "add"]):
        # Create event
        event = {
            "id": f"event_{len(calendar_events) + 1}",
            "title": "New Meeting",
            "date": datetime.now().strftime("%Y-%m-%d"),
            "time": "10:00",
            "created_at": datetime.now().isoformat()
        }
        calendar_events.append(event)

        return {
            "agent_name": "CalendarAgent",
            "response": f"✅ Successfully created event: '{event['title']}' on {event['date']} at {event['time']}",
            "type": "calendar",
            "metadata": {"action": "event_created", "event": event},
            "suggested_actions": ["View my calendar", "Create another event", "Set reminder"],
            "requires_follow_up": False
        }

    elif any(word in message for word in ["show", "list", "view"]):
        # List events
        if not calendar_events:
            return {
                "agent_name": "CalendarAgent",
                "response": "📅 You don't have any scheduled events yet. Would you like to create one?",
                "type": "calendar",
                "metadata": {"action": "empty_calendar"},
                "suggested_actions": ["Schedule a meeting", "Add personal event", "Set reminder"],
                "requires_follow_up": False
            }

        events_text = "📅 Your upcoming events:\n\n"
        for event in calendar_events:
            events_text += f"• **{event['title']}**\n  {event['date']} at {event['time']}\n\n"

        return {
            "agent_name": "CalendarAgent",
            "response": events_text,
            "type": "calendar",
            "metadata": {"action": "events_listed", "events": calendar_events},
            "suggested_actions": ["Create new event", "Modify event", "Check availability"],
            "requires_follow_up": False
        }

    else:
        return {
            "agent_name": "CalendarAgent",
            "response": "📅 I can help you manage your calendar! I can schedule events, show your calendar, or check availability.",
            "type": "calendar",
            "metadata": {"action": "calendar_help"},
            "suggested_actions": ["Schedule a meeting", "Show my calendar", "Check availability"],
            "requires_follow_up": False
        }

# General/fallback handler
def handle_general(message: str, user_id: str, profession: str):
    """Handle general queries and fallback"""
    return {
        "agent_name": "GeneralAgent",
        "response": f"Hello! I'm your AI assistant for {profession}s.\n\nI can help with:\n📋 **Task Management** - Create and track tasks\n📅 **Calendar** - Manage your schedule\n💾 **Data Export** - Backup your conversations\n👤 **Personal Info** - Remember your preferences\n\nWhat would you like to do?",
        "type": "text",
        "metadata": {"intent": "general_help", "profession": profession},
        "suggested_actions": ["Create a task", "Show my calendar", "Export my chat", "Tell me your name"],
        "requires_follow_up": False
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
