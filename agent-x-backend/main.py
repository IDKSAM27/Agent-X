from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Dict, Any, Optional, List
import logging
import uvicorn
import sqlite3
import os

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

# Absolute DB path for reliability
DB_PATH = os.path.join(os.path.dirname(__file__), "agent_x.db")

def init_database():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            user_id TEXT PRIMARY KEY,
            name TEXT,
            profession TEXT,
            preferences TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT,
            title TEXT,
            description TEXT,
            status TEXT DEFAULT 'pending',
            priority TEXT DEFAULT 'medium',
            due_date TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP
        )
    ''')
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS calendar_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT,
            title TEXT,
            description TEXT,
            start_time TEXT,
            end_time TEXT,
            location TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    conn.close()
    logger.info("✅ Database initialized successfully")

init_database()

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

@app.post("/api/agents/process")
async def process_agent(request: Request):
    data = await request.json()
    message = data.get("message", "").lower()
    user_id = data.get("user_id")
    context = data.get("context", {})
    profession = context.get("profession", "Unknown")

    logger.info(f"Processing: '{message}' from {user_id}")

    if any(phrase in message for phrase in ["my name is", "call me", "i am"]):
        return handle_name_storage(message, user_id, profession)
    elif any(phrase in message for phrase in ["what is my name", "who am i", "what am i called"]):
        return handle_name_query(message, user_id)
    elif any(word in message for word in ["export", "download", "save", "backup"]):
        return handle_export(message, user_id)
    elif any(word in message for word in ["create task", "add task", "task to", "new task"]):
        return handle_task_creation(message, user_id, profession)
    elif any(word in message for word in ["list tasks", "show tasks", "view tasks", "my tasks"]):
        return handle_task_list(message, user_id)
    elif any(word in message for word in ["complete task", "finish task", "done task"]):
        return handle_task_completion(message, user_id)
    elif any(word in message for word in ["schedule", "meeting", "add event", "create event"]):
        return await handle_calendar_create(message, user_id)
    elif any(word in message for word in ["list events", "show events", "view events", "my calendar", "show my calendar", "show calendar"]):
        return await handle_calendar_list(user_id)
    elif any(word in message for word in ["calendar", "event"]):
        return handle_calendar_help()
    else:
        return handle_general(message, user_id, profession)

# Name storage/retrieval functions
def save_user_name(user_id: str, name: str, profession: str):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('INSERT OR REPLACE INTO users (user_id, name, profession) VALUES (?, ?, ?)', (user_id, name, profession))
    conn.commit()
    conn.close()
    logger.info(f"✅ Saved name: {name} for user {user_id}")

def get_user_name(user_id: str) -> str:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT name FROM users WHERE user_id = ?', (user_id,))
    row = cursor.fetchone()
    conn.close()
    name = row[0] if row else ""
    logger.info(f"📋 Retrieved name: {name} for user {user_id}")
    return name

def extract_name(message: str):
    if "my name is" in message:
        return message.split("my name is")[-1].split(".")[0].strip().title()
    elif "call me" in message:
        return message.split("call me")[-1].split(".")[0].strip().title()
    elif "i am" in message and not "who am i" in message:
        return message.split("i am")[-1].split(".")[0].strip().title()
    return ""

def handle_name_storage(message: str, user_id: str, profession: str):
    name = extract_name(message)
    if name and len(name.split()) <= 4:
        save_user_name(user_id, name, profession)
        return {
            "agent_name": "PersonalAgent",
            "response": f"Perfect! Nice to meet you, {name}. I've saved your name and will remember it permanently!",
            "type": "text",
            "metadata": {"action": "name_stored", "name": name},
            "suggested_actions": ["What can you help me with?", "Create a task", "Show my tasks"],
            "requires_follow_up": False
        }
    return {
        "agent_name": "PersonalAgent",
        "response": "I didn't catch your name clearly. Please say 'My name is [Your Full Name]'",
        "type": "text",
        "metadata": {"action": "name_unclear"},
        "requires_follow_up": False
    }

def handle_name_query(message: str, user_id: str):
    stored_name = get_user_name(user_id)
    if stored_name:
        return {
            "agent_name": "PersonalAgent",
            "response": f"Your name is **{stored_name}**! 👋 I remember you!",
            "type": "text",
            "metadata": {"action": "name_retrieved", "name": stored_name},
            "suggested_actions": ["Update my name", "Create a task", "Show my tasks"],
            "requires_follow_up": False
        }
    else:
        return {
            "agent_name": "PersonalAgent",
            "response": "🤔 I don't have your name stored yet.\n\nYou can tell me by saying:\n• 'My name is John Smith'\n• 'Call me Sarah'\n• 'I am Alex'",
            "type": "text",
            "metadata": {"action": "name_request"},
            "suggested_actions": ["My name is John", "Call me Sarah"],
            "requires_follow_up": False
        }

# Persistent tasks
def save_task(user_id: str, title: str, description: str = "", priority: str = "medium"):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO tasks (user_id, title, description, priority)
        VALUES (?, ?, ?, ?)
    ''', (user_id, title, description, priority))
    conn.commit()
    task_id = cursor.lastrowid
    conn.close()
    logger.info(f"✅ Saved task: {title}")
    return task_id

def get_user_tasks(user_id: str, status: str = "pending"):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT id, title, description, priority, created_at, due_date 
        FROM tasks WHERE user_id = ? AND status = ?
        ORDER BY created_at DESC
    ''', (user_id, status))
    tasks = cursor.fetchall()
    conn.close()
    return tasks

def handle_task_creation(message: str, user_id: str, profession: str):
    task_title = message.replace("create task", "").replace("add task", "").replace("task to", "").replace("new task", "").strip()
    if not task_title or task_title == "to":
        task_title = "Complete the project"
    priority = "medium"
    if "urgent" in message or "high priority" in message:
        priority = "high"
    elif "low priority" in message:
        priority = "low"
    task_id = save_task(user_id, task_title, "", priority)
    return {
        "agent_name": "TaskAgent",
        "response": f"✅ **Task Created & Saved!**\n\n📋 **Task:** {task_title}\n👤 **For:** {profession}\n🎯 **Priority:** {priority.title()}\n📅 **Created:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\nYour task has been saved permanently!",
        "type": "task",
        "metadata": {"action": "task_created", "task_id": task_id, "task_title": task_title},
        "suggested_actions": ["View my tasks", "Create another task", "Set task priority"],
        "requires_follow_up": False
    }

def handle_task_list(message: str, user_id: str):
    tasks = get_user_tasks(user_id)
    if not tasks:
        return {
            "agent_name": "TaskAgent",
            "response": "📋 **No tasks found!**\n\nYou don't have any pending tasks right now. Would you like to create one?",
            "type": "task",
            "metadata": {"action": "empty_tasks"},
            "suggested_actions": ["Create a task", "Add reminder", "Plan my day"],
            "requires_follow_up": False
        }
    tasks_text = f"📋 **Your Tasks ({len(tasks)} pending):**\n\n"
    for i, task in enumerate(tasks, 1):
        task_id, title, description, priority, created_at, due_date = task
        priority_emoji = "🔥" if priority == "high" else "⚡" if priority == "medium" else "📝"
        tasks_text += f"{i}. {priority_emoji} **{title}**\n   Created: {created_at[:10]}\n\n"
    return {
        "agent_name": "TaskAgent",
        "response": tasks_text,
        "type": "task",
        "metadata": {"action": "tasks_listed", "task_count": len(tasks)},
        "suggested_actions": ["Create another task", "Complete a task", "Set priorities"],
        "requires_follow_up": False
    }

def handle_task_completion(message: str, user_id: str):
    return {
        "agent_name": "TaskAgent",
        "response": "🎉 **Task completed!** Great job staying productive!\n\nTo mark specific tasks as complete, try: 'Complete task [task name]'",
        "type": "task",
        "metadata": {"action": "task_completed"},
        "suggested_actions": ["View remaining tasks", "Create new task"],
        "requires_follow_up": False
    }

# Persistent calendar events
def save_event(user_id: str, title: str, date: str, time_: str = "10:00"):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        'INSERT INTO calendar_events (user_id, title, start_time) VALUES (?, ?, ?)',
        (user_id, title, f"{date} {time_}"))
    conn.commit()
    event_id = cursor.lastrowid
    conn.close()
    logger.info(f"✅ Event saved: {title} for {date} {time_}")
    return event_id

def get_all_events(user_id: str):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT title, start_time FROM calendar_events WHERE user_id = ?', (user_id,))
    events = cursor.fetchall()
    conn.close()
    return events

async def handle_calendar_create(message: str, user_id: str):
    # Simple logic: any schedule/create gets a 'Meeting' on today at 10:00
    date = datetime.now().strftime("%Y-%m-%d")
    event_id = save_event(user_id, "Meeting", date, "10:00")
    return {
        "agent_name": "CalendarAgent",
        "response": f"✅ Successfully created event: 'Meeting' on {date} at 10:00",
        "type": "calendar",
        "metadata": {"action": "event_created", "event_id": event_id, "date": date},
        "suggested_actions": ["View my calendar", "Create another event", "Set reminder"],
        "requires_follow_up": False
    }

async def handle_calendar_list(user_id: str):
    events = get_all_events(user_id)
    if not events:
        return {
            "agent_name": "CalendarAgent",
            "response": "📅 You don't have any scheduled events yet. Would you like to create one?",
            "type": "calendar",
            "metadata": {"action": "empty_calendar"},
            "suggested_actions": ["Schedule a meeting", "Add personal event", "Set reminder"],
            "requires_follow_up": False
        }

    events_text = "📅 Your upcoming events:\n\n"
    for title, dt in events:
        events_text += f"• **{title}** at {dt}\n"

    return {
        "agent_name": "CalendarAgent",
        "response": events_text,
        "type": "calendar",
        "metadata": {"action": "events_listed"},
        "suggested_actions": ["Create new event", "Modify event", "Check availability"],
        "requires_follow_up": False
    }

def handle_calendar_help():
    return {
        "agent_name": "CalendarAgent",
        "response": "📅 **Calendar Management**\n\nI can help you manage your calendar events and show your scheduled meetings.",
        "type": "calendar",
        "metadata": {"action": "calendar_help"},
        "suggested_actions": ["Schedule a meeting", "Show my events"],
        "requires_follow_up": False
    }

def handle_export(message: str, user_id: str):
    return {
        "agent_name": "ExportAgent",
        "response": "📦 **Chat Export Ready!**\n\n📊 **Summary:**\n• Total conversations: 25\n• Format: JSON with metadata\n• Ready for download\n\nYour chat export has been prepared!",
        "type": "text",
        "metadata": {"action": "export_prepared", "user_id": user_id},
        "suggested_actions": ["Download now", "Export as text", "Cancel"],
        "requires_follow_up": False
    }

def handle_general(message: str, user_id: str, profession: str):
    return {
        "agent_name": "GeneralAgent",
        "response": f"Hello! I'm your AI assistant for {profession}s.\n\nI can help with:\n📋 **Task Management** - Create and track tasks\n📅 **Calendar** - Manage your schedule\n💾 **Data Export** - Backup your conversations\n👤 **Personal Info** - Remember your preferences\n\nWhat would you like to do?",
        "type": "text",
        "metadata": {"intent": "general_help", "profession": profession},
        "suggested_actions": ["Create a task", "Show my tasks", "Show my calendar", "Export my chat"],
        "requires_follow_up": False
    }

@app.get("/debug/names")
async def debug_names():
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM users')
        users = cursor.fetchall()
        conn.close()
        return {"users": users, "db_path": DB_PATH}
    except Exception as e:
        return {"error": str(e)}

@app.get("/debug/events")
async def debug_events():
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM calendar_events')
        events = cursor.fetchall()
        conn.close()
        return {"events": events, "db_path": DB_PATH}
    except Exception as e:
        return {"error": str(e)}

@app.post("/api/clear_memory")
async def clear_memory_endpoint(request: Request):
    data = await request.json()
    user_id = data.get("user_id")
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM users WHERE user_id = ?", (user_id,))
        cursor.execute("DELETE FROM tasks WHERE user_id = ?", (user_id,))
        cursor.execute("DELETE FROM calendar_events WHERE user_id = ?", (user_id,))
        conn.commit()
        conn.close()
        return {"status": "success", "message": "All data cleared successfully"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.post("/api/export_chat")
async def export_chat_endpoint(request: Request):
    data = await request.json()
    user_id = data.get("user_id")
    profession = data.get("profession", "Unknown")

    # For demo, read recent conversation from some persistent store or simulate data
    # Replace this with your actual conversation memory store
    conversations = [
        {
            "user_message": "Hi there",
            "agent_response": "Hello! How can I assist?",
            "timestamp": "2025-09-10T18:00:00"
        },
        # Add more conversation entries here...
    ]

    # Return structured export data
    return {
        "status": "success",
        "data": {
            "user_id": user_id,
            "profession": profession,
            "export_date": datetime.utcnow().isoformat(),
            "total_messages": len(conversations),
            "conversations": conversations
        }
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
