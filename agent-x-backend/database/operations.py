from sqlalchemy.orm import Session
from sqlalchemy import text, case
from .connection import SessionLocal
from .models import User, Task, Event, Conversation
import logging
from datetime import datetime
from contextlib import contextmanager

logger = logging.getLogger(__name__)

@contextmanager
def get_session():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def save_user_name(firebase_uid: str, name: str, profession: str):
    with get_session() as db:
        try:
            user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
            if user:
                user.display_name = name
                user.profession = profession
            else:
                user = User(
                    firebase_uid=firebase_uid,
                    display_name=name,
                    profession=profession,
                    email=f"{firebase_uid}@placeholder.com",
                    email_verified=True,
                    created_at=datetime.now().isoformat()
                )
                db.add(user)
            db.commit()
            logger.info(f"✅ Saved name: {name} for Firebase UID {firebase_uid}")
        except Exception as e:
            logger.error(f"❌ Error saving user name: {e}")
            db.rollback()
            raise

def get_user_name(firebase_uid: str) -> str:
    with get_session() as db:
        user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
        name = user.display_name if user else ""
        logger.info(f"📋 Retrieved name: {name} for Firebase UID {firebase_uid}")
        return name

def get_user_profession_from_db(firebase_uid: str) -> str:
    with get_session() as db:
        try:
            user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
            return user.profession if user and user.profession else "Professional"
        except Exception:
            return "Professional"

# --- TASKS

def save_task(firebase_uid: str, title: str, description: str = "", priority: str = "medium",
              category: str = "general", due_date: str = None) -> int:
    with get_session() as db:
        now = datetime.now().isoformat()
        task = Task(
            firebase_uid=firebase_uid,
            title=title,
            description=description,
            priority=priority,
            category=category,
            due_date=due_date,
            is_completed=False,
            progress=0.0,
            tags='[]',
            created_at=now,
            updated_at=now
        )
        db.add(task)
        db.commit()
        db.refresh(task)
        return task.id

def get_user_tasks(firebase_uid: str, status: str = "pending"):
    with get_session() as db:
        try:
            query = db.query(Task).filter(Task.firebase_uid == firebase_uid)
            
            if status == "pending":
                query = query.filter(Task.is_completed == False)
                # Custom sorting for priority: high=1, medium=2, low=3
                priority_order = case(
                    (Task.priority == 'high', 1),
                    (Task.priority == 'medium', 2),
                    (Task.priority == 'low', 3),
                    else_=4
                )
                query = query.order_by(priority_order, Task.due_date.asc())
                
            elif status == "completed":
                query = query.filter(Task.is_completed == True).order_by(Task.updated_at.desc())
            else:
                query = query.order_by(Task.is_completed.asc(), Task.due_date.asc())

            tasks = query.all()
            result = []
            for t in tasks:
                result.append((t.id, t.title, t.description, t.priority, t.category, t.due_date, t.is_completed, t.progress, t.created_at))
            
            logger.info(f"📋 Retrieved {len(result)} {status} tasks for Firebase UID {firebase_uid}")
            return result

        except Exception as e:
            logger.error(f"❌ Error getting tasks: {e}")
            return []

# --- CALENDAR EVENTS

def save_event(firebase_uid: str, title: str, description: str = "", start_time: str = "", end_time: str = None, category: str = "general", priority: str = "medium", location: str = None):
    with get_session() as db:
        try:
            now = datetime.now().isoformat()
            event = Event(
                firebase_uid=firebase_uid,
                title=title,
                description=description,
                start_time=start_time,
                end_time=end_time,
                category=category,
                priority=priority,
                location=location,
                created_at=now,
                updated_at=now
            )
            db.add(event)
            db.commit()
            db.refresh(event)
            logger.info(f"✅ Saved event: {title} for Firebase UID {firebase_uid}")
            return event.id
        except Exception as e:
            logger.error(f"❌ Error saving event: {e}")
            db.rollback()
            raise

def get_all_events(firebase_uid: str):
    with get_session() as db:
        try:
            events = db.query(Event).filter(Event.firebase_uid == firebase_uid).order_by(Event.start_time.asc()).all()
            result = []
            for e in events:
                result.append((e.id, e.title, e.description, e.start_time, e.end_time, e.category, e.priority, e.location, e.created_at))
            
            logger.info(f"📅 Retrieved {len(result)} events for Firebase UID {firebase_uid}")
            return result
        except Exception as e:
            logger.error(f"❌ Error getting events: {e}")
            return []

# --- CONVERSATIONS

def save_conversation(firebase_uid: str, user_message: str, assistant_response: str, agent_name: str, intent: str = None):
    with get_session() as db:
        try:
            conv = Conversation(
                firebase_uid=firebase_uid,
                user_message=user_message,
                assistant_response=assistant_response,
                agent_name=agent_name,
                intent=intent,
                timestamp=datetime.now().isoformat()
            )
            db.add(conv)
            db.commit()
            logger.info(f"💾 Saved conversation: {intent} for Firebase UID {firebase_uid}")
        except Exception as e:
            logger.error(f"❌ Error saving conversation: {e}")
            db.rollback()
            raise

def get_conversation_history(firebase_uid: str, limit: int = 5):
    with get_session() as db:
        conversations = db.query(Conversation).filter(Conversation.firebase_uid == firebase_uid).order_by(Conversation.timestamp.desc()).limit(limit).all()
        result = []
        for c in conversations:
            result.append((c.user_message, c.assistant_response, c.agent_name, c.intent, c.timestamp))
        logger.info(f"📜 Retrieved {len(result)} conversations for Firebase UID {firebase_uid}")
        return result

def get_all_conversations(firebase_uid: str):
    with get_session() as db:
        conversations = db.query(Conversation).filter(Conversation.firebase_uid == firebase_uid).order_by(Conversation.timestamp.desc()).all()
        result = []
        for c in conversations:
            result.append((c.id, c.user_message, c.assistant_response, c.agent_name, c.intent, c.timestamp, None))
        return result

def update_task_completion_in_db(firebase_uid: str, task_id: int, completed: bool) -> bool:
    with get_session() as db:
        try:
            task = db.query(Task).filter(Task.id == task_id, Task.firebase_uid == firebase_uid).first()
            if task:
                task.is_completed = completed
                task.progress = 1.0 if completed else 0.0
                task.updated_at = datetime.now().isoformat()
                db.commit()
                logger.info(f"✅ Updated task {task_id} completion: {completed}")
                return True
            else:
                logger.warning(f"⚠️ No task found with id {task_id} for user {firebase_uid}")
                return False
        except Exception as e:
            logger.error(f"❌ Error updating task completion in DB: {e}")
            db.rollback()
            return False

def update_task_in_db(firebase_uid: str, task_id: int, title: str, description: str, priority: str, category: str, due_date: str = None) -> bool:
    with get_session() as db:
        try:
            task = db.query(Task).filter(Task.id == task_id, Task.firebase_uid == firebase_uid).first()
            if task:
                task.title = title
                task.description = description
                task.priority = priority
                task.category = category
                task.due_date = due_date
                task.updated_at = datetime.now().isoformat()
                db.commit()
                return True
            return False
        except Exception as e:
            logger.error(f"❌ Error updating task in DB: {e}")
            db.rollback()
            return False

def delete_task_from_db(firebase_uid: str, task_id: int) -> bool:
    with get_session() as db:
        try:
            task = db.query(Task).filter(Task.id == task_id, Task.firebase_uid == firebase_uid).first()
            if task:
                db.delete(task)
                db.commit()
                return True
            return False
        except Exception as e:
            logger.error(f"❌ Error deleting task: {e}")
            db.rollback()
            return False

def save_enhanced_event(firebase_uid: str, title: str, description: str, start_time: str,
                        end_time: str = None, category: str = "general", priority: str = "medium",
                        location: str = None) -> int:
    return save_event(firebase_uid, title, description, start_time, end_time, category, priority, location)

def update_event_in_db(firebase_uid: str, event_id: int, title: str, description: str,
                       start_time: str, end_time: str = None, category: str = "general",
                       priority: str = "medium", location: str = None) -> bool:
    with get_session() as db:
        try:
            event = db.query(Event).filter(Event.id == event_id, Event.firebase_uid == firebase_uid).first()
            if event:
                event.title = title
                event.description = description
                event.start_time = start_time
                event.end_time = end_time
                event.category = category
                event.priority = priority
                event.location = location
                event.updated_at = datetime.now().isoformat()
                db.commit()
                return True
            return False
        except Exception as e:
            db.rollback()
            raise e

def delete_event_from_db(firebase_uid: str, event_id: int) -> bool:
    with get_session() as db:
        try:
            event = db.query(Event).filter(Event.id == event_id, Event.firebase_uid == firebase_uid).first()
            if event:
                db.delete(event)
                db.commit()
                return True
            return False
        except Exception as e:
            db.rollback()
            raise e

def get_user_profile_by_uuid(firebase_uid: str) -> dict:
    with get_session() as db:
        user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
        if user:
            return {
                "display_name": user.display_name,
                "profession": user.profession,
                "email": user.email
            }
        else:
            return {}

def ensure_user_exists(firebase_uid: str, email: str, name: str = None, profession: str = None):
    with get_session() as db:
        try:
            user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
            now = datetime.now().isoformat()
            if user:
                user.last_login = now
            else:
                user = User(
                    firebase_uid=firebase_uid,
                    display_name=name,
                    profession=profession,
                    email=email,
                    email_verified=False,
                    created_at=now,
                    last_login=now
                )
                db.add(user)
            db.commit()
            logger.info(f"✅ Ensured user exists: {firebase_uid}")
        except Exception as e:
            logger.error(f"❌ Error ensuring user exists: {e}")
            db.rollback()

def delete_all_user_data(firebase_uid: str) -> dict:
    with get_session() as db:
        try:
            # Delete tasks
            tasks_deleted = db.query(Task).filter(Task.firebase_uid == firebase_uid).delete()
            
            # Delete events
            events_deleted = db.query(Event).filter(Event.firebase_uid == firebase_uid).delete()
            
            # Delete conversations
            convs_deleted = db.query(Conversation).filter(Conversation.firebase_uid == firebase_uid).delete()
            
            db.commit()
            
            logger.info(f"🗑️ Cleared data for {firebase_uid}: {tasks_deleted} tasks, {events_deleted} events, {convs_deleted} conversations")
            
            return {
                "tasks": tasks_deleted,
                "events": events_deleted,
                "conversations": convs_deleted
            }
        except Exception as e:
            logger.error(f"❌ Error clearing user data: {e}")
            db.rollback()
            raise e

def get_user_data_status(firebase_uid: str) -> dict:
    with get_session() as db:
        try:
            user_count = db.query(User).filter(User.firebase_uid == firebase_uid).count()
            task_count = db.query(Task).filter(Task.firebase_uid == firebase_uid).count()
            event_count = db.query(Event).filter(Event.firebase_uid == firebase_uid).count()
            conv_count = db.query(Conversation).filter(Conversation.firebase_uid == firebase_uid).count()
            
            user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
            user_name = user.display_name if user else None
            
            sample_tasks = db.query(Task.title).filter(Task.firebase_uid == firebase_uid).limit(3).all()
            sample_events = db.query(Event.title).filter(Event.firebase_uid == firebase_uid).limit(3).all()
            
            return {
                "firebase_uid": firebase_uid,
                "counts": {
                    "users": user_count,
                    "tasks": task_count,
                    "events": event_count,
                    "conversations": conv_count
                },
                "samples": {
                    "user_name": user_name,
                    "tasks": [t[0] for t in sample_tasks],
                    "events": [e[0] for e in sample_events]
                },
                "db_type": "postgresql"
            }
        except Exception as e:
            logger.error(f"❌ Error getting data status: {e}")
            return {"error": str(e)}

def get_latest_conversation(firebase_uid: str):
    with get_session() as db:
        try:
            count = db.query(Conversation).filter(Conversation.firebase_uid == firebase_uid).count()
            latest = db.query(Conversation).filter(Conversation.firebase_uid == firebase_uid).order_by(Conversation.timestamp.desc()).first()
            
            return {
                "firebase_uid": firebase_uid,
                "total_conversations": count,
                "latest_conversation": latest.timestamp if latest else None,
                "latest_intent": latest.intent if latest else None,
                "memory_status": "active" if count > 0 else "empty"
            }
        except Exception as e:
            logger.error(f"❌ Error getting latest conversation: {e}")
            return {"error": str(e)}
