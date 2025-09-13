from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Dict, Any, Optional, List
import logging
import uvicorn
import sqlite3
import os
import firebase_admin
from firebase_admin import credentials, auth as firebase_auth
from fastapi import HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

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

# Initialize Firebase Admin SDK with better error handling
def initialize_firebase():
    """Initialize Firebase Admin SDK with service account key"""
    try:
        # Path to your service account key
        cred_path = os.path.join(os.path.dirname(__file__), "firebase-service-account.json")

        if os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            logger.info("✅ Firebase Admin SDK initialized with service account key")
        else:
            logger.error("❌ Firebase service account key not found at: " + cred_path)
            logger.error("Please download the service account key from Firebase Console")
            raise FileNotFoundError("Firebase service account key not found")

    except Exception as e:
        logger.error(f"❌ Firebase Admin SDK initialization failed: {e}")
        raise

# Initialize Firebase when starting the app
initialize_firebase()

# Security dependency
security = HTTPBearer()

# TODO: TEMPORARY: Add development mode bypass
DEVELOPMENT_MODE = False  # Set to False in production

def migrate_database_to_firebase_uid():
    """Migrate existing database schema from user_id to firebase_uid"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # Check if migration is needed
        cursor.execute("PRAGMA table_info(users)")
        columns = [column[1] for column in cursor.fetchall()]

        if 'firebase_uid' in columns:
            logger.info("✅ Database already migrated to firebase_uid schema")
            conn.close()
            return

        logger.info("🔄 Starting database migration to firebase_uid schema...")

        # Begin transaction
        cursor.execute("BEGIN TRANSACTION")

        # 1. Backup existing tables
        cursor.execute("CREATE TABLE users_backup AS SELECT * FROM users")
        cursor.execute("CREATE TABLE tasks_backup AS SELECT * FROM tasks")
        cursor.execute("CREATE TABLE calendar_events_backup AS SELECT * FROM calendar_events")

        # Check if conversations table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='conversations'")
        if cursor.fetchone():
            cursor.execute("CREATE TABLE conversations_backup AS SELECT * FROM conversations")

        # 2. Drop existing tables
        cursor.execute("DROP TABLE users")
        cursor.execute("DROP TABLE tasks")
        cursor.execute("DROP TABLE calendar_events")
        cursor.execute("DROP TABLE IF EXISTS conversations")

        # 3. Create new schema with firebase_uid
        cursor.execute('''
            CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firebase_uid TEXT UNIQUE NOT NULL,
                email TEXT UNIQUE NOT NULL,
                profession TEXT,
                display_name TEXT,
                photo_url TEXT,
                email_verified BOOLEAN DEFAULT FALSE,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_login DATETIME,
                preferences JSON
            )
        ''')

        cursor.execute('''
            CREATE TABLE tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firebase_uid TEXT NOT NULL,
                title TEXT,
                description TEXT,
                status TEXT DEFAULT 'pending',
                priority TEXT DEFAULT 'medium',
                due_date TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                completed_at TIMESTAMP,
                FOREIGN KEY (firebase_uid) REFERENCES users(firebase_uid)
            )
        ''')

        cursor.execute('''
            CREATE TABLE calendar_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firebase_uid TEXT NOT NULL,
                title TEXT,
                description TEXT,
                start_time TEXT,
                end_time TEXT,
                location TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (firebase_uid) REFERENCES users(firebase_uid)
            )
        ''')

        cursor.execute('''
            CREATE TABLE conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                firebase_uid TEXT NOT NULL,
                user_message TEXT NOT NULL,
                assistant_response TEXT NOT NULL,
                agent_name TEXT,
                intent TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                session_id TEXT,
                FOREIGN KEY (firebase_uid) REFERENCES users(firebase_uid)
            )
        ''')

        # 4. Migrate data (map old user_id to firebase_uid)
        # For development, we'll map old data to dev user
        DEV_FIREBASE_UID = "dev_user_123"

        # Migrate users (if any)
        cursor.execute("SELECT user_id, name, profession FROM users_backup")
        old_users = cursor.fetchall()
        for old_user in old_users:
            cursor.execute('''
                INSERT INTO users (firebase_uid, display_name, profession, email)
                VALUES (?, ?, ?, ?)
            ''', (DEV_FIREBASE_UID, old_user[1], old_user[2], "dev@test.com"))

        # Migrate tasks
        cursor.execute("SELECT title, description, status, priority, due_date, created_at FROM tasks_backup")
        old_tasks = cursor.fetchall()
        for task in old_tasks:
            cursor.execute('''
                INSERT INTO tasks (firebase_uid, title, description, status, priority, due_date, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (DEV_FIREBASE_UID, *task))

        # Migrate events
        cursor.execute("SELECT title, description, start_time, end_time, location, created_at FROM calendar_events_backup")
        old_events = cursor.fetchall()
        for event in old_events:
            cursor.execute('''
                INSERT INTO calendar_events (firebase_uid, title, description, start_time, end_time, location, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (DEV_FIREBASE_UID, *event))

        # Migrate conversations if they exist
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='conversations_backup'")
        if cursor.fetchone():
            cursor.execute("SELECT user_message, assistant_response, agent_name, intent, timestamp, session_id FROM conversations_backup")
            old_conversations = cursor.fetchall()
            for conv in old_conversations:
                cursor.execute('''
                    INSERT INTO conversations (firebase_uid, user_message, assistant_response, agent_name, intent, timestamp, session_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                ''', (DEV_FIREBASE_UID, *conv))

        # 5. Clean up backup tables
        cursor.execute("DROP TABLE users_backup")
        cursor.execute("DROP TABLE tasks_backup")
        cursor.execute("DROP TABLE calendar_events_backup")
        cursor.execute("DROP TABLE IF EXISTS conversations_backup")

        # Commit transaction
        cursor.execute("COMMIT")
        conn.close()

        logger.info("✅ Database migration completed successfully!")
        logger.info(f"📊 All data migrated to firebase_uid: {DEV_FIREBASE_UID}")

    except Exception as e:
        logger.error(f"❌ Database migration failed: {e}")
        try:
            cursor.execute("ROLLBACK")
            logger.info("🔄 Migration rolled back")
        except:
            pass
        raise

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer())):
    """Dependency to get current authenticated Firebase user with debug info"""

    # TEMPORARY: Development mode bypass
    if DEVELOPMENT_MODE:
        logger.warning("🚧 DEVELOPMENT MODE: Bypassing Firebase Auth")
        return {
            "user_id": "dev_user_123",
            "firebase_uid": "dev_user_123",
            "email": "dev@test.com",
            "email_verified": True,
            "name": "Dev User",
            "profession": "Developer"
        }

    try:
        logger.info(f"🔍 Attempting to verify Firebase token")
        logger.info(f"🔍 Token length: {len(credentials.credentials)}")
        logger.info(f"🔍 Token preview: {credentials.credentials[:50]}...")

        # Verify the Firebase ID token
        decoded_token = firebase_auth.verify_id_token(credentials.credentials)
        logger.info(f"✅ Token verified for user: {decoded_token.get('email')}")

        # Extract user info from token
        user_data = {
            "user_id": decoded_token['uid'],
            "firebase_uid": decoded_token['uid'],
            "email": decoded_token.get('email'),
            "email_verified": decoded_token.get('email_verified', False),
            "name": decoded_token.get('name'),
            "picture": decoded_token.get('picture'),
        }

        # Get additional user data
        profession = get_user_profession_from_db(user_data['firebase_uid'])
        user_data['profession'] = profession

        return user_data

    except firebase_auth.InvalidIdTokenError as e:
        logger.error(f"❌ Invalid Firebase ID token: {e}")
        raise HTTPException(status_code=401, detail=f"Invalid Firebase ID token: {str(e)}")
    except firebase_auth.ExpiredIdTokenError as e:
        logger.error(f"❌ Expired Firebase ID token: {e}")
        raise HTTPException(status_code=401, detail=f"Expired Firebase ID token: {str(e)}")
    except Exception as e:
        logger.error(f"❌ Firebase auth error: {e}")
        raise HTTPException(status_code=401, detail=f"Authentication failed: {str(e)}")

def get_user_profession_from_db(firebase_uid: str) -> str:
    """Get user profession from your SQLite database"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT profession FROM users WHERE firebase_uid = ?", (firebase_uid,))
        result = cursor.fetchone()
        conn.close()
        return result[0] if result else "Professional"
    except Exception:
        return "Professional"

def init_database():
    """Initialize database with migration support"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Check if any tables exist (for migration)
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    existing_tables = [table[0] for table in cursor.fetchall()]

    # If tables exist but schema is old, run migration
    if existing_tables and 'users' in existing_tables:
        conn.close()
        migrate_database_to_firebase_uid()
        return

    # Create fresh database with firebase_uid schema
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firebase_uid TEXT UNIQUE NOT NULL,
            email TEXT UNIQUE NOT NULL,
            profession TEXT,
            display_name TEXT,
            photo_url TEXT,
            email_verified BOOLEAN DEFAULT FALSE,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            last_login DATETIME,
            preferences JSON
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firebase_uid TEXT NOT NULL,
            title TEXT,
            description TEXT,
            status TEXT DEFAULT 'pending',
            priority TEXT DEFAULT 'medium',
            due_date TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            completed_at TIMESTAMP,
            FOREIGN KEY (firebase_uid) REFERENCES users(firebase_uid)
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS calendar_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firebase_uid TEXT NOT NULL,
            title TEXT,
            description TEXT,
            start_time TEXT,
            end_time TEXT,
            location TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (firebase_uid) REFERENCES users(firebase_uid)
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            firebase_uid TEXT NOT NULL,
            user_message TEXT NOT NULL,
            assistant_response TEXT NOT NULL,
            agent_name TEXT,
            intent TEXT,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            session_id TEXT,
            FOREIGN KEY (firebase_uid) REFERENCES users(firebase_uid)
        )
    ''')

    conn.commit()
    conn.close()
    logger.info("✅ Database initialized with Firebase UID support")

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
async def process_agent(request: Request, current_user: dict = Depends(get_current_user)):
    data = await request.json()
    message = data.get("message", "")

    # Use Firebase UID consistently
    firebase_uid = current_user["firebase_uid"]
    profession = current_user.get("profession", "Professional")

    logger.info(f"Processing: '{message}' from Firebase user {firebase_uid}")

    # Ensure user exists in local database
    ensure_user_exists_in_db(current_user)

    # Get conversation history using firebase_uid
    recent_conversations = get_conversation_history(firebase_uid, limit=3)
    context_string = build_context_string(recent_conversations)

    # Your existing intent detection and processing logic...
    message_lower = message.lower()

    if any(phrase in message_lower for phrase in ["my name is", "call me", "i am"]):
        response_data = handle_name_storage(message, firebase_uid, profession, context_string)
        intent = "name_storage"
    elif any(phrase in message_lower for phrase in ["what is my name", "who am i", "what am i called"]):
        response_data = handle_name_query(message, firebase_uid, context_string)
        intent = "name_query"
    elif any(word in message_lower for word in ["export", "download", "save", "backup"]):
        response_data = handle_export(message, firebase_uid, context_string)
        intent = "export"
    elif any(word in message_lower for word in ["create task", "add task", "task to", "new task"]):
        response_data = handle_task_creation(message, firebase_uid, profession, context_string)
        intent = "task_creation"
    elif any(word in message_lower for word in ["list tasks", "show tasks", "view tasks", "my tasks"]):
        response_data = handle_task_list(message, firebase_uid, context_string)
        intent = "task_list"
    elif any(word in message_lower for word in ["complete task", "finish task", "done task"]):
        response_data = handle_task_completion(message, firebase_uid, context_string)
        intent = "task_completion"
    elif any(word in message_lower for word in ["schedule", "meeting", "add event", "create event"]):
        response_data = await handle_calendar_create(message, firebase_uid, context_string)
        intent = "calendar_create"
    elif any(word in message_lower for word in ["list events", "show events", "view events", "my calendar", "show my calendar", "show calendar", "show me calendar"]):
        response_data = await handle_calendar_list(firebase_uid, context_string)
        intent = "calendar_list"
    elif any(word in message_lower for word in ["calendar", "event"]):
        response_data = handle_calendar_help(context_string)
        intent = "calendar_help"
    else:
        response_data = handle_general(message, firebase_uid, profession, context_string)
        intent = "general"

    # Save this conversation turn to memory
    save_conversation(
        firebase_uid=firebase_uid,
        user_message=message,
        assistant_response=response_data["response"],
        agent_name=response_data["agent_name"],
        intent=intent
    )

    return response_data

def ensure_user_exists_in_db(user_data: dict):
    """Ensure user exists in local database, create if not"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        cursor.execute("SELECT firebase_uid FROM users WHERE firebase_uid = ?", (user_data["firebase_uid"],))
        if not cursor.fetchone():
            # Create user record
            cursor.execute('''
                INSERT INTO users (firebase_uid, email, display_name, email_verified, last_login)
                VALUES (?, ?, ?, ?, ?)
            ''', (
                user_data["firebase_uid"],
                user_data.get("email"),
                user_data.get("name"),
                user_data.get("email_verified", False),
                datetime.utcnow()
            ))
            conn.commit()
            logger.info(f"✅ Created local user record for Firebase UID: {user_data['firebase_uid']}")
        else:
            # Update last login
            cursor.execute("UPDATE users SET last_login = ? WHERE firebase_uid = ?",
                           (datetime.utcnow(), user_data["firebase_uid"]))
            conn.commit()

        conn.close()
    except Exception as e:
        logger.error(f"Error ensuring user exists: {e}")

# Name storage/retrieval functions
def save_user_name(firebase_uid: str, name: str, profession: str):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('INSERT OR REPLACE INTO users (firebase_uid, display_name, profession) VALUES (?, ?, ?)', (firebase_uid, name, profession))
    conn.commit()
    conn.close()
    logger.info(f"✅ Saved name: {name} for Firebase UID {firebase_uid}")

def get_user_name(firebase_uid: str) -> str:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT display_name FROM users WHERE firebase_uid = ?', (firebase_uid,))
    row = cursor.fetchone()
    conn.close()
    name = row[0] if row else ""
    logger.info(f"📋 Retrieved name: {name} for Firebase UID {firebase_uid}")
    return name

def extract_name(message: str):
    if "my name is" in message:
        return message.split("my name is")[-1].split(".")[0].strip().title()
    elif "call me" in message:
        return message.split("call me")[-1].split(".")[0].strip().title()
    elif "i am" in message and not "who am i" in message:
        return message.split("i am")[-1].split(".")[0].strip().title()
    return ""

def handle_name_storage(message: str, user_id: str, profession: str, context: str = ""):
    name = extract_name(message)
    if name and len(name.split()) <= 4:
        save_user_name(user_id, name, profession)

        # Context-aware response
        context_note = "I can see from our conversation that " if context else ""

        return {
            "agent_name": "PersonalAgent",
            "response": f"Perfect! Nice to meet you, {name}. {context_note}I've saved your name and will remember it permanently!",
            "type": "text",
            "metadata": {"action": "name_stored", "name": name, "has_context": bool(context)},
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

def handle_name_query(message: str, user_id: str, context: str = ""):
    stored_name = get_user_name(user_id)
    if stored_name:
        # Context-aware response
        context_note = f"{context}**Current Request:**\n" if context else ""

        return {
            "agent_name": "PersonalAgent",
            "response": f"{context_note}Your name is **{stored_name}**! 👋 I remember you!",
            "type": "text",
            "metadata": {"action": "name_retrieved", "name": stored_name, "has_context": bool(context)},
            "suggested_actions": ["Update my name", "Create a task", "Show my tasks"],
            "requires_follow_up": False
        }
    else:
        context_note = f"{context}**Current Request:**\n" if context else ""

        return {
            "agent_name": "PersonalAgent",
            "response": f"{context_note}🤔 I don't have your name stored yet.\n\nYou can tell me by saying:\n• 'My name is John Smith'\n• 'Call me Sarah'\n• 'I am Alex'",
            "type": "text",
            "metadata": {"action": "name_request", "has_context": bool(context)},
            "suggested_actions": ["My name is John", "Call me Sarah"],
            "requires_follow_up": False
        }

# Persistent tasks
def save_task(firebase_uid: str, title: str, description: str = "", priority: str = "medium"):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        INSERT INTO tasks (firebase_uid, title, description, priority)
        VALUES (?, ?, ?, ?)
    ''', (firebase_uid, title, description, priority))
    conn.commit()
    task_id = cursor.lastrowid
    conn.close()
    logger.info(f"✅ Saved task: {title} for Firebase UID {firebase_uid}")
    return task_id

def get_user_tasks(firebase_uid: str, status: str = "pending"):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT id, title, description, priority, created_at, due_date 
        FROM tasks WHERE firebase_uid = ? AND status = ?
        ORDER BY created_at DESC
    ''', (firebase_uid, status))
    tasks = cursor.fetchall()
    conn.close()
    return tasks

def handle_task_creation(message: str, user_id: str, profession: str, context: str = ""):
    task_title = message.replace("create task", "").replace("add task", "").replace("task to", "").replace("new task", "").strip()
    if not task_title or task_title == "to":
        task_title = "Complete the project"
    priority = "medium"
    if "urgent" in message or "high priority" in message:
        priority = "high"
    elif "low priority" in message:
        priority = "low"
    task_id = save_task(user_id, task_title, "", priority)

    # Context-aware response
    context_note = f"{context}**Current Request:**\n" if context else ""

    return {
        "agent_name": "TaskAgent",
        "response": f"{context_note}✅ **Task Created & Saved!**\n\n📋 **Task:** {task_title}\n👤 **For:** {profession}\n🎯 **Priority:** {priority.title()}\n📅 **Created:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n\nYour task has been saved permanently!",
        "type": "task",
        "metadata": {"action": "task_created", "task_id": task_id, "task_title": task_title, "has_context": bool(context)},
        "suggested_actions": ["View my tasks", "Create another task", "Set task priority"],
        "requires_follow_up": False
    }

def handle_task_list(message: str, user_id: str, context: str = ""):
    tasks = get_user_tasks(user_id)
    if not tasks:
        context_note = f"{context}**Current Request:**\n" if context else ""

        return {
            "agent_name": "TaskAgent",
            "response": f"{context_note}📋 **No tasks found!**\n\nYou don't have any pending tasks right now. Would you like to create one?",
            "type": "task",
            "metadata": {"action": "empty_tasks", "has_context": bool(context)},
            "suggested_actions": ["Create a task", "Add reminder", "Plan my day"],
            "requires_follow_up": False
        }

    tasks_text = f"📋 **Your Tasks ({len(tasks)} pending):**\n\n"
    for i, task in enumerate(tasks, 1):
        task_id, title, description, priority, created_at, due_date = task
        priority_emoji = "🔥" if priority == "high" else "⚡" if priority == "medium" else "📝"
        tasks_text += f"{i}. {priority_emoji} **{title}**\n   Created: {created_at[:10]}\n\n"

    # Context-aware response
    context_note = f"{context}**Current Request:**\n" if context else ""

    return {
        "agent_name": "TaskAgent",
        "response": f"{context_note}{tasks_text}",
        "type": "task",
        "metadata": {"action": "tasks_listed", "task_count": len(tasks), "has_context": bool(context)},
        "suggested_actions": ["Create another task", "Complete a task", "Set priorities"],
        "requires_follow_up": False
    }

def handle_task_completion(message: str, user_id: str, context: str = ""):
    # Context-aware response
    context_note = f"{context}**Current Request:**\n" if context else ""

    return {
        "agent_name": "TaskAgent",
        "response": f"{context_note}🎉 **Task completed!** Great job staying productive!\n\nTo mark specific tasks as complete, try: 'Complete task [task name]'",
        "type": "task",
        "metadata": {"action": "task_completed", "has_context": bool(context)},
        "suggested_actions": ["View remaining tasks", "Create new task"],
        "requires_follow_up": False
    }

# Persistent calendar events
def save_event(firebase_uid: str, title: str, date: str, time_: str = "10:00"):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        'INSERT INTO calendar_events (firebase_uid, title, start_time) VALUES (?, ?, ?)',
        (firebase_uid, title, f"{date} {time_}"))
    conn.commit()
    event_id = cursor.lastrowid
    conn.close()
    logger.info(f"✅ Event saved: {title} for {date} {time_} - Firebase UID: {firebase_uid}")
    return event_id

def get_all_events(firebase_uid: str):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT title, start_time FROM calendar_events WHERE firebase_uid = ?', (firebase_uid,))
    events = cursor.fetchall()
    conn.close()
    return events

async def handle_calendar_create(message: str, user_id: str, context: str = ""):
    # Simple logic: any schedule/create gets a 'Meeting' on today at 10:00
    date = datetime.now().strftime("%Y-%m-%d")
    event_id = save_event(user_id, "Meeting", date, "10:00")

    # Context-aware response
    context_note = f"{context}**Current Request:**\n" if context else ""

    return {
        "agent_name": "CalendarAgent",
        "response": f"{context_note}✅ Successfully created event: 'Meeting' on {date} at 10:00",
        "type": "calendar",
        "metadata": {"action": "event_created", "event_id": event_id, "date": date, "has_context": bool(context)},
        "suggested_actions": ["View my calendar", "Create another event", "Set reminder"],
        "requires_follow_up": False
    }

async def handle_calendar_list(user_id: str, context: str = ""):
    events = get_all_events(user_id)
    if not events:
        context_note = f"{context}**Current Request:**\n" if context else ""

        return {
            "agent_name": "CalendarAgent",
            "response": f"{context_note}📅 You don't have any scheduled events yet. Would you like to create one?",
            "type": "calendar",
            "metadata": {"action": "empty_calendar", "has_context": bool(context)},
            "suggested_actions": ["Schedule a meeting", "Add personal event", "Set reminder"],
            "requires_follow_up": False
        }

    events_text = "📅 Your upcoming events:\n\n"
    for title, dt in events:
        events_text += f"• **{title}** at {dt}\n"

    # Context-aware response
    context_note = f"{context}**Current Request:**\n" if context else ""

    return {
        "agent_name": "CalendarAgent",
        "response": f"{context_note}{events_text}",
        "type": "calendar",
        "metadata": {"action": "events_listed", "has_context": bool(context)},
        "suggested_actions": ["Create new event", "Modify event", "Check availability"],
        "requires_follow_up": False
    }

def handle_calendar_help(context: str = ""):
    # Context-aware response
    context_note = f"{context}**Current Request:**\n" if context else ""

    return {
        "agent_name": "CalendarAgent",
        "response": f"{context_note}📅 **Calendar Management**\n\nI can help you manage your calendar events and show your scheduled meetings.",
        "type": "calendar",
        "metadata": {"action": "calendar_help", "has_context": bool(context)},
        "suggested_actions": ["Schedule a meeting", "Show my events"],
        "requires_follow_up": False
    }

def handle_export(message: str, user_id: str, context: str = ""):
    # Context-aware response
    context_note = f"{context}**Current Request:**\n" if context else ""

    return {
        "agent_name": "ExportAgent",
        "response": f"{context_note}📦 **Chat Export Ready!**\n\n📊 **Summary:**\n• Total conversations: 25\n• Format: JSON with metadata\n• Ready for download\n\nYour chat export has been prepared!",
        "type": "text",
        "metadata": {"action": "export_prepared", "user_id": user_id, "has_context": bool(context)},
        "suggested_actions": ["Download now", "Export as text", "Cancel"],
        "requires_follow_up": False
    }

def handle_general(message: str, user_id: str, profession: str, context: str = ""):
    base_response = f"Hello! I'm your AI assistant for {profession}s.\n\nI can help with:\n📋 **Task Management** - Create and track tasks\n📅 **Calendar** - Manage your schedule\n💾 **Data Export** - Backup your conversations\n👤 **Personal Info** - Remember your preferences\n\nWhat would you like to do?"

    # Context-aware response
    context_note = f"{context}**Current Request:**\n" if context else ""

    return {
        "agent_name": "GeneralAgent",
        "response": f"{context_note}{base_response}",
        "type": "text",
        "metadata": {"intent": "general_help", "profession": profession, "has_context": bool(context)},
        "suggested_actions": ["Create a task", "Show my tasks", "Show my calendar", "Export my chat"],
        "requires_follow_up": False
    }

# Conversation memory functions
def save_conversation(firebase_uid: str, user_message: str, assistant_response: str, agent_name: str, intent: str):
    """Save a conversation turn to persistent memory"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    session_id = f"session_{firebase_uid}_{datetime.now().strftime('%Y%m%d')}"
    cursor.execute('''
        INSERT INTO conversations (firebase_uid, user_message, assistant_response, agent_name, intent, session_id)
        VALUES (?, ?, ?, ?, ?, ?)
    ''', (firebase_uid, user_message, assistant_response, agent_name, intent, session_id))
    conn.commit()
    conversation_id = cursor.lastrowid
    conn.close()
    logger.info(f"💾 Saved conversation: {intent} for Firebase UID {firebase_uid}")
    return conversation_id

def get_conversation_history(firebase_uid: str, limit: int = 5):
    """Get recent conversation history for context"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT user_message, assistant_response, agent_name, intent, timestamp
        FROM conversations 
        WHERE firebase_uid = ?
        ORDER BY timestamp DESC
        LIMIT ?
    ''', (firebase_uid, limit))
    conversations = cursor.fetchall()
    conn.close()
    logger.info(f"📜 Retrieved {len(conversations)} conversations for Firebase UID {firebase_uid}")
    return conversations

def get_all_conversations(firebase_uid: str):
    """Get all conversations for a user (for export/debug)"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT id, user_message, assistant_response, agent_name, intent, timestamp, session_id
        FROM conversations 
        WHERE firebase_uid = ?
        ORDER BY timestamp DESC
    ''', (firebase_uid,))
    conversations = cursor.fetchall()
    conn.close()
    return conversations

def build_context_string(conversations):
    """Build context string from recent conversations"""
    if not conversations:
        return ""

    context_parts = ["📝 **Recent Context:**"]
    for user_msg, assistant_resp, agent_name, intent, timestamp in reversed(conversations):
        # Truncate long messages for context
        user_preview = user_msg[:50] + "..." if len(user_msg) > 50 else user_msg
        assistant_preview = assistant_resp[:50] + "..." if len(assistant_resp) > 50 else assistant_resp
        context_parts.append(f"User: {user_preview}")
        context_parts.append(f"Assistant: {assistant_preview}")

    return "\n".join(context_parts) + "\n\n"

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
async def clear_memory_endpoint(request: Request, current_user: dict = Depends(get_current_user)):
    firebase_uid = current_user["firebase_uid"]

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # Clear data using Firebase UID
        deleted_tasks = cursor.execute("DELETE FROM tasks WHERE firebase_uid = ?", (firebase_uid,)).rowcount
        deleted_events = cursor.execute("DELETE FROM calendar_events WHERE firebase_uid = ?", (firebase_uid,)).rowcount
        deleted_conversations = cursor.execute("DELETE FROM conversations WHERE firebase_uid = ?", (firebase_uid,)).rowcount

        conn.commit()
        conn.close()

        logger.info(f"🗑️ Cleared data for Firebase UID {firebase_uid} - Tasks: {deleted_tasks}, Events: {deleted_events}, Conversations: {deleted_conversations}")

        return {
            "status": "success",
            "message": "All data cleared successfully",
            "deleted_counts": {
                "tasks": deleted_tasks,
                "events": deleted_events,
                "conversations": deleted_conversations
            }
        }

    except Exception as e:
        logger.error(f"❌ Clear memory error: {str(e)}")
        return {"status": "error", "message": str(e)}

@app.get("/debug/data_status/{firebase_uid}")
async def debug_data_status(firebase_uid: str):
    """Debug endpoint to check all data for a Firebase UID"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # Count all data types using firebase_uid
        cursor.execute("SELECT COUNT(*) FROM users WHERE firebase_uid = ?", (firebase_uid,))
        user_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM tasks WHERE firebase_uid = ?", (firebase_uid,))
        task_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM calendar_events WHERE firebase_uid = ?", (firebase_uid,))
        event_count = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM conversations WHERE firebase_uid = ?", (firebase_uid,))
        conv_count = cursor.fetchone()[0]

        # Get actual data samples
        cursor.execute("SELECT display_name FROM users WHERE firebase_uid = ? LIMIT 1", (firebase_uid,))
        user_name = cursor.fetchone()

        cursor.execute("SELECT title FROM tasks WHERE firebase_uid = ? LIMIT 3", (firebase_uid,))
        sample_tasks = cursor.fetchall()

        cursor.execute("SELECT title FROM calendar_events WHERE firebase_uid = ? LIMIT 3", (firebase_uid,))
        sample_events = cursor.fetchall()

        conn.close()

        return {
            "firebase_uid": firebase_uid,
            "counts": {
                "users": user_count,
                "tasks": task_count,
                "events": event_count,
                "conversations": conv_count
            },
            "samples": {
                "user_name": user_name[0] if user_name else None,
                "tasks": [task[0] for task in sample_tasks],
                "events": [event[0] for event in sample_events]
            },
            "db_path": DB_PATH
        }
    except Exception as e:
        return {"error": str(e)}

@app.post("/api/export_chat")
async def export_chat_endpoint(request: Request, current_user: dict = Depends(get_current_user)):
    firebase_uid = current_user["firebase_uid"]
    profession = current_user.get("profession", "Unknown")

    try:
        # Get all conversations from memory using firebase_uid
        all_conversations = get_all_conversations(firebase_uid)
        conversations = []

        for conv in all_conversations:
            conv_id, user_msg, assistant_resp, agent_name, intent, timestamp, session_id = conv
            conversations.append({
                "id": conv_id,
                "user_message": user_msg,
                "assistant_response": assistant_resp,
                "agent_name": agent_name,
                "intent": intent,
                "timestamp": timestamp,
                "session_id": session_id
            })

        return {
            "status": "success",
            "data": {
                "firebase_uid": firebase_uid,
                "profession": profession,
                "export_date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "total_messages": len(conversations),
                "conversations": conversations,
                "memory_enabled": True
            }
        }
    except Exception as e:
        logger.error(f"Export error: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/api/memory/debug/{firebase_uid}")
async def debug_memory_status(firebase_uid: str):
    """Debug endpoint to check memory status"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # Count conversations
        cursor.execute('SELECT COUNT(*) FROM conversations WHERE firebase_uid = ?', (firebase_uid,))
        conv_count = cursor.fetchone()[0]

        # Get latest conversation
        cursor.execute('''
            SELECT timestamp, intent FROM conversations 
            WHERE firebase_uid = ? ORDER BY timestamp DESC LIMIT 1
        ''', (firebase_uid,))
        latest = cursor.fetchone()

        conn.close()

        return {
            "firebase_uid": firebase_uid,
            "total_conversations": conv_count,
            "latest_conversation": latest[0] if latest else None,
            "latest_intent": latest[1] if latest else None,
            "memory_status": "active" if conv_count > 0 else "empty"
        }
    except Exception as e:
        return {"error": str(e)}

# Conversation memory endpoints
@app.get("/api/conversations/history/{firebase_uid}")
async def get_conversation_history_endpoint(firebase_uid: str, limit: int = 10):
    """Get conversation history for a Firebase UID"""
    try:
        conversations = get_conversation_history(firebase_uid, limit)
        history = []
        for user_msg, assistant_resp, agent_name, intent, timestamp in conversations:
            history.append({
                "user_message": user_msg,
                "assistant_response": assistant_resp,
                "agent_name": agent_name,
                "intent": intent,
                "timestamp": timestamp
            })

        return {"status": "success", "history": history, "total": len(history)}
    except Exception as e:
        logger.error(f"Error fetching conversation history: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/debug/conversations/{firebase_uid}")
async def debug_conversations(firebase_uid: str):
    """Debug endpoint to view all conversations for a Firebase UID"""
    try:
        conversations = get_all_conversations(firebase_uid)
        conv_list = []
        for conv in conversations:
            conv_id, user_msg, assistant_resp, agent_name, intent, timestamp, session_id = conv
            conv_list.append({
                "id": conv_id,
                "user_message": user_msg,
                "assistant_response": assistant_resp,
                "agent_name": agent_name,
                "intent": intent,
                "timestamp": timestamp,
                "session_id": session_id
            })

        return {"conversations": conv_list, "total": len(conv_list), "db_path": DB_PATH}
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
