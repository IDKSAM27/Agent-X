import sqlite3
import os
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "agent_x.db")

# --- USER / PROFILE
def migrate_database_schema():
    """Migrate database to latest schema with new columns"""
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    try:
        cursor = conn.cursor()

        # ✅ Check and add missing columns to tasks table
        cursor.execute("PRAGMA table_info(tasks)")
        existing_columns = [column[1] for column in cursor.fetchall()]

        if 'category' not in existing_columns:
            cursor.execute("ALTER TABLE tasks ADD COLUMN category TEXT DEFAULT 'general'")
            logger.info("✅ Added 'category' column to tasks table")

        if 'progress' not in existing_columns:
            cursor.execute("ALTER TABLE tasks ADD COLUMN progress REAL DEFAULT 0.0")
            logger.info("✅ Added 'progress' column to tasks table")

        if 'tags' not in existing_columns:
            cursor.execute("ALTER TABLE tasks ADD COLUMN tags TEXT DEFAULT '[]'")
            logger.info("✅ Added 'tags' column to tasks table")

        if 'is_completed' not in existing_columns:
            cursor.execute("ALTER TABLE tasks ADD COLUMN is_completed INTEGER DEFAULT 0")
            logger.info("✅ Added 'is_completed' column to tasks table")

        # ✅ Check and add missing columns to events table (if it exists)
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='events'")
        if cursor.fetchone():
            cursor.execute("PRAGMA table_info(events)")
            existing_event_columns = [column[1] for column in cursor.fetchall()]

            if 'category' not in existing_event_columns:
                cursor.execute("ALTER TABLE events ADD COLUMN category TEXT DEFAULT 'general'")
                logger.info("✅ Added 'category' column to events table")

            if 'priority' not in existing_event_columns:
                cursor.execute("ALTER TABLE events ADD COLUMN priority TEXT DEFAULT 'medium'")
                logger.info("✅ Added 'priority' column to events table")

            if 'location' not in existing_event_columns:
                cursor.execute("ALTER TABLE events ADD COLUMN location TEXT")
                logger.info("✅ Added 'location' column to events table")

        conn.commit()
        logger.info("✅ Database schema migration completed successfully")

    except Exception as e:
        logger.error(f"❌ Database migration error: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()


def save_user_name(firebase_uid: str, name: str, profession: str):
    conn = sqlite3.connect(DB_PATH, timeout=10.0)  # ✅ Add timeout
    try:
        cursor = conn.cursor()

        # Fix: Update existing user instead of inserting new record
        cursor.execute('''
            UPDATE users SET display_name = ?, profession = ? 
            WHERE firebase_uid = ?
        ''', (name, profession, firebase_uid))

        # If no rows were updated, the user doesn't exist yet
        if cursor.rowcount == 0:
            cursor.execute('''
                INSERT INTO users (firebase_uid, display_name, profession, email, email_verified)
                VALUES (?, ?, ?, ?, ?)
            ''', (firebase_uid, name, profession, f"{firebase_uid}@placeholder.com", True))

        conn.commit()
        logger.info(f"✅ Saved name: {name} for Firebase UID {firebase_uid}")

    except Exception as e:
        logger.error(f"❌ Error saving user name: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()


def get_user_name(firebase_uid: str) -> str:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('SELECT display_name FROM users WHERE firebase_uid = ?', (firebase_uid,))
    row = cursor.fetchone()
    conn.close()
    name = row[0] if row else ""
    logger.info(f"📋 Retrieved name: {name} for Firebase UID {firebase_uid}")
    return name

def get_user_profession_from_db(firebase_uid: str) -> str:
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT profession FROM users WHERE firebase_uid = ?", (firebase_uid,))
        result = cursor.fetchone()
        conn.close()
        return result[0] if result else "Professional"
    except Exception:
        return "Professional"

# --- TASKS

def save_task(firebase_uid: str, title: str, description: str = "", priority: str = "medium", category: str = "general", due_date: str = None):
    """Save a task"""
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    try:
        cursor = conn.cursor()
        now = datetime.now().isoformat()

        cursor.execute('''
            INSERT INTO tasks (firebase_uid, title, description, priority, category, due_date, is_completed, progress, tags, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (firebase_uid, title, description, priority, category, due_date, 0, 0.0, '[]', now, now))

        task_id = cursor.lastrowid
        conn.commit()

        logger.info(f"✅ Saved task: {title} for Firebase UID {firebase_uid}")
        return task_id

    except Exception as e:
        logger.error(f"❌ Error saving task: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()

def get_user_tasks(firebase_uid: str, status: str = "pending"):
    """Get user tasks by status"""
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    try:
        cursor = conn.cursor()

        if status == "pending":
            cursor.execute('''
                SELECT id, title, description, priority, category, due_date, is_completed, progress, created_at
                FROM tasks 
                WHERE firebase_uid = ? AND is_completed = 0
                ORDER BY 
                    CASE priority 
                        WHEN 'high' THEN 1 
                        WHEN 'medium' THEN 2 
                        WHEN 'low' THEN 3 
                    END,
                    due_date ASC
            ''', (firebase_uid,))
        elif status == "completed":
            cursor.execute('''
                SELECT id, title, description, priority, category, due_date, is_completed, progress, created_at
                FROM tasks 
                WHERE firebase_uid = ? AND is_completed = 1
                ORDER BY updated_at DESC
            ''', (firebase_uid,))
        else:  # all
            cursor.execute('''
                SELECT id, title, description, priority, category, due_date, is_completed, progress, created_at
                FROM tasks 
                WHERE firebase_uid = ? 
                ORDER BY is_completed ASC, due_date ASC
            ''', (firebase_uid,))

        tasks = cursor.fetchall()
        logger.info(f"📋 Retrieved {len(tasks)} {status} tasks for Firebase UID {firebase_uid}")
        return tasks

    except Exception as e:
        logger.error(f"❌ Error getting tasks: {e}")
        return []
    finally:
        conn.close()

# --- CALENDAR EVENTS

def save_event(firebase_uid: str, title: str, description: str = "", start_time: str = "", end_time: str = None, category: str = "general", priority: str = "medium", location: str = None):
    """Save a calendar event"""
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    try:
        cursor = conn.cursor()
        now = datetime.now().isoformat()

        cursor.execute('''
            INSERT INTO events (firebase_uid, title, description, start_time, end_time, category, priority, location, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (firebase_uid, title, description, start_time, end_time, category, priority, location, now, now))

        event_id = cursor.lastrowid
        conn.commit()

        logger.info(f"✅ Saved event: {title} for Firebase UID {firebase_uid}")
        return event_id

    except Exception as e:
        logger.error(f"❌ Error saving event: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()

def get_all_events(firebase_uid: str):
    """Get all events for a user"""
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    try:
        cursor = conn.cursor()
        cursor.execute('''
            SELECT id, title, description, start_time, end_time, category, priority, location, created_at
            FROM events 
            WHERE firebase_uid = ? 
            ORDER BY start_time ASC
        ''', (firebase_uid,))

        events = cursor.fetchall()
        logger.info(f"📅 Retrieved {len(events)} events for Firebase UID {firebase_uid}")
        return events

    except Exception as e:
        logger.error(f"❌ Error getting events: {e}")
        return []
    finally:
        conn.close()

# --- CONVERSATIONS

def save_conversation(firebase_uid: str, user_message: str, assistant_response: str, agent_name: str, intent: str = None):
    """Save conversation to database"""
    conn = sqlite3.connect(DB_PATH, timeout=10.0)
    try:
        cursor = conn.cursor()

        # Simple insert without session_id
        cursor.execute('''
            INSERT INTO conversations (firebase_uid, user_message, assistant_response, agent_name, intent, timestamp)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (firebase_uid, user_message, assistant_response, agent_name, intent, datetime.now().isoformat()))

        conn.commit()
        logger.info(f"💾 Saved conversation: {intent} for Firebase UID {firebase_uid}")

    except Exception as e:
        logger.error(f"❌ Error saving conversation: {e}")
        conn.rollback()
        raise
    finally:
        conn.close()


def get_conversation_history(firebase_uid: str, limit: int = 5):
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
