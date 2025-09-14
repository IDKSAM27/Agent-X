import sqlite3
import os
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "agent_x.db")

# --- USER / PROFILE
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

def save_task(firebase_uid: str, title: str, description: str = "", priority: str = "medium"):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        '''INSERT INTO tasks (firebase_uid, title, description, priority)
           VALUES (?, ?, ?, ?)''',
        (firebase_uid, title, description, priority))
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

# --- CALENDAR EVENTS

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

# --- CONVERSATIONS

def save_conversation(firebase_uid: str, user_message: str, assistant_response: str, agent_name: str, intent: str):
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
