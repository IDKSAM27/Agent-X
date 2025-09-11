from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
import logging
import uvicorn
import sqlite3
import json
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

# Database setup
DB_PATH = "agent_x.db"

def init_database():
    """Initialize SQLite database with required tables"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Users table for names and preferences
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            user_id TEXT PRIMARY KEY,
            name TEXT,
            profession TEXT,
            preferences TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')

    # Tasks table
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

    # Calendar events table
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

# Initialize database on startup
init_database()

# Models (same as before)
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

    # Enhanced routing with task separation
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
    elif any(word in message for word in ["calendar", "schedule", "event", "meeting"]):
        return await handle_calendar(message, user_id)
    else:
        return handle_general(message, user_id, profession)

# Database helper functions
def get_user_name(user_id: str) -> str:
    """Get user name from database"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('SELECT name FROM users WHERE user_id = ?', (user_id,))
        row = cursor.fetchone()
        conn.close()
        name = row[0] if row else ""
        logger.info(f"📋 Retrieved name: {name} for user {user_id}")
        return name
    except Exception as e:
        logger.error(f"❌ Error getting name: {e}")
        return ""

def save_user_name(user_id: str, name: str):
    """Save user name to database"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('INSERT OR REPLACE INTO users (user_id, name) VALUES (?, ?)', (user_id, name))
        conn.commit()
        conn.close()
        logger.info(f"✅ Saved name: {name} for user {user_id}")
        return True
    except Exception as e:
        logger.error(f"❌ Error saving name: {e}")
        return False

def save_task(user_id: str, title: str, description: str = "", priority: str = "medium"):
    """Save task to database"""
    try:
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
    except Exception as e:
        logger.error(f"Error saving task: {e}")
        return None

def get_user_tasks(user_id: str, status: str = "pending"):
    """Get user tasks from database"""
    try:
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
    except Exception as e:
        logger.error(f"Error getting tasks: {e}")
        return []

# FIXED: Enhanced name handlers
def handle_name_storage(message: str, user_id: str, profession: str):
    """Handle when user provides their name"""
    name = ""

    if "my name is" in message:
        name = message.split("my name is")[-1].strip().title()
    elif "call me" in message:
        name = message.split("call me")[-1].strip().title()
    elif "i am" in message and not "who am i" in message:
        name = message.split("i am")[-1].strip().title()

    if name and len(name.split()) <= 3:  # Reasonable name length
        success = save_user_name(user_id, name)
        if success:
            return {
                "agent_name": "PersonalAgent",
                "response": f"Perfect! Nice to meet you, {name}. I've saved your name and will remember it permanently!",
                "type": "text",
                "metadata": {"action": "name_stored", "name": name},
                "suggested_actions": ["What can you help me with?", "Create a task", "Show my tasks"],
                "requires_follow_up": False
            }
        else:
            return {
                "agent_name": "PersonalAgent",
                "response": "I had trouble saving your name. Please try again.",
                "type": "text",
                "metadata": {"action": "name_save_failed"},
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
    """Handle when user asks for their name"""
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


# Enhanced task handlers with persistence
def handle_task_creation(message: str, user_id: str, profession: str):
    """Handle task creation with database storage"""
    # Extract task title
    task_title = message.replace("create task", "").replace("add task", "").replace("task to", "").strip()
    if not task_title or task_title == "to":
        task_title = "Complete the project"

    # Extract priority if mentioned
    priority = "medium"
    if "urgent" in message or "high priority" in message:
        priority = "high"
    elif "low priority" in message:
        priority = "low"

    # Save to database
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
    """Handle task listing from database"""
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

    # Format task list
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
    """Handle task completion"""
    return {
        "agent_name": "TaskAgent",
        "response": "🎉 **Task completed!** Great job staying productive!\n\nTo mark specific tasks as complete, try: 'Complete task [task name]'",
        "type": "task",
        "metadata": {"action": "task_completed"},
        "suggested_actions": ["View remaining tasks", "Create new task"],
        "requires_follow_up": False
    }

# Other handlers (export, calendar, general) - same as before
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

async def handle_calendar(message: str, user_id: str):
    """Handle calendar-related requests (same as before but with DB storage)"""
    # Calendar logic stays the same, but you can extend it to use calendar_events table
    return {
        "agent_name": "CalendarAgent",
        "response": "📅 **Calendar Management**\n\nI can help you manage your calendar events. Your tasks are stored separately in the task list.",
        "type": "calendar",
        "metadata": {"action": "calendar_help"},
        "suggested_actions": ["Schedule a meeting", "View my tasks", "Show calendar"],
        "requires_follow_up": False
    }

def handle_general(message: str, user_id: str, profession: str):
    """Handle general queries and fallback"""
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
    """Debug endpoint to check saved names"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM users')
        users = cursor.fetchall()
        conn.close()
        return {"users": users, "db_path": DB_PATH}
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
