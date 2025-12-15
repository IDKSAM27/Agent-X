import sys
import os
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from fastapi import FastAPI, Request, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from datetime import datetime
from typing import Dict, Any, Optional, List
import logging
import uvicorn
import firebase_admin
import asyncio
import shutil
from firebase_admin import credentials, auth as firebase_auth
from fastapi import HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from starlette.requests import ClientDisconnect

from services.llm_service import LLMService
from dotenv import load_dotenv
from database.operations import (
    save_user_name, get_user_name, get_user_profession_from_db,
    save_task, get_user_tasks,
    save_event, get_all_events,
    save_conversation, get_conversation_history, get_all_conversations,
    update_task_completion_in_db, update_task_in_db, delete_task_from_db,
    save_enhanced_event, update_event_in_db, delete_event_from_db,
    ensure_user_exists, delete_all_user_data, get_user_data_status,
    get_latest_conversation,
    create_chat_session, get_user_chat_sessions, update_chat_session_title,
    delete_chat_session, get_chat_messages
)
from memory_manager import memory_manager
from routes.news_router import router as news_router
from services.news_scheduler import news_scheduler
from services.smart_news_service import SmartNewsService
from services.llm_service import LLMService

# Load env variables
load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Agent X API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create uploads directory if it doesn't exist
UPLOAD_DIR = "uploads"
if not os.path.exists(UPLOAD_DIR):
    os.makedirs(UPLOAD_DIR)

# Mount static files
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")

# Include router for news support
app.include_router(news_router)

# Absolute DB path for reliability

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
DEVELOPMENT_MODE = False # Set to False in production

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


@app.post("/api/upload/image")
async def upload_image(file: UploadFile = File(...), current_user: dict = Depends(get_current_user)):
    """Upload an image and return its URL"""
    try:
        firebase_uid = current_user["firebase_uid"]
        
        # Create a unique filename
        timestamp = int(datetime.now().timestamp())
        file_extension = file.filename.split(".")[-1] if "." in file.filename else "jpg"
        filename = f"{firebase_uid}_{timestamp}.{file_extension}"
        file_path = os.path.join(UPLOAD_DIR, filename)
        
        # Save the file
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
        # Construct the full URL (assuming the app knows the base URL)
        # We return the relative path, the frontend can prepend the base URL
        # Or we can return the full URL if we know the host
        
        # For now, return the relative path which is served by StaticFiles
        image_url = f"/uploads/{filename}"
        
        logger.info(f"✅ Image uploaded for {firebase_uid}: {filename}")
        
        return {
            "status": "success",
            "url": image_url,
            "filename": filename
        }
    except Exception as e:
        logger.error(f"❌ Error uploading image: {e}")
        return {"status": "error", "message": str(e)}


class AgentRequest(BaseModel):
    message: str
    user_id: str
    context: Dict[str, Any]
    context: Dict[str, Any]
    timestamp: str
    session_id: Optional[int] = None # Added session_id

class AgentResponse(BaseModel):
    agent_name: str
    response: str
    type: str
    metadata: Dict[str, Any]
    requires_follow_up: bool = False
    suggested_actions: Optional[List[str]] = None
    session_id: Optional[int] = None # Added session_id

@app.post("/api/agents/process")
async def process_agent(request: Request, current_user: dict = Depends(get_current_user)):
    try:
        data = await request.json()
        message = data.get("message", "")
        firebase_uid = current_user["firebase_uid"]
        session_id = data.get("session_id")

        # Create session if not provided
        if not session_id:
            session_id = create_chat_session(firebase_uid, title=message[:30] + "..." if len(message) > 30 else message)
            logger.info(f"🆕 Created new session {session_id} for {firebase_uid}")

        # Fix: Get profession from context data sent by Flutter
        context_data = data.get("context", {})
        profession = context_data.get("profession", current_user.get("profession", "Professional"))

        logger.info(f"🤖 Processing: '{message}' from Firebase user {firebase_uid} (profession: {profession})")

        # Ensure user exists in local database
        ensure_user_exists(
            firebase_uid=current_user["firebase_uid"],
            email=current_user.get("email", ""),
            name=current_user.get("name", ""),
            profession=current_user.get("profession", "")
        )

        # Get conversation context
        # TODO: Get context specific to this session? For now, keep global context or switch to session context
        # Switching to session context makes more sense for "multiple chats"
        if session_id:
             session_messages = get_chat_messages(session_id, firebase_uid)
             # Convert to format expected by build_context_string
             recent_conversations = []
             for msg in session_messages[-5:]: # Last 5 messages
                 recent_conversations.append((msg['user_message'], msg['assistant_response'], msg['agent_name'], msg['intent'], msg['timestamp']))
        else:
             recent_conversations = get_conversation_history(firebase_uid, limit=3)
        
        context_string = build_context_string(recent_conversations)

        # Try LLM first, fallback to rule-based
        gemini_api_key = os.getenv("GEMINI_API_KEY")

        if gemini_api_key:
            try:
                logger.info("🧠 Using LLM processing")
                # Create LLM service instance
                llm_service = LLMService(gemini_api_key)

                response_data = await llm_service.process_message(
                    firebase_uid=firebase_uid,
                    message=message,
                    context=context_string,
                    profession=profession
                )
                intent = "llm_processed"

            except Exception as e:
                logger.error(f"❌ LLM processing failed, using fallback: {e}")
                response_data = await _fallback_rule_based_processing(message, firebase_uid, profession, context_string)
                intent = "fallback_processed"
        else:
            logger.info("🔧 Using rule-based processing (no API key)")
            response_data = await _fallback_rule_based_processing(message, firebase_uid, profession, context_string)
            intent = "rule_based"

        # Save conversation
        save_conversation(
            firebase_uid=firebase_uid,
            user_message=message,
            assistant_response=response_data["response"],
            agent_name=response_data["agent_name"],
            intent=intent,
            session_id=session_id
        )

        logger.info(f"💾 Saved conversation for Firebase UID {firebase_uid}")

        # Add session_id to response
        response_data["session_id"] = session_id
        return response_data

    except ClientDisconnect:
        # Handle client disconnect gracefully
        logger.warning(f"⚠️ Client disconnected during processing for user {firebase_uid}")
        # Still try to save the conversation if we have the data
        return {"error": "Client disconnected"}

    except Exception as e:
        logger.error(f"❌ Unexpected error in process_agent: {e}")
        return {
            "agent_name": "ErrorAgent",
            "response": "I encountered an error processing your request. Please try again.",
            "type": "text",
            "metadata": {"error": str(e)},
            "suggested_actions": ["Try again", "Ask a simpler question"],
            "requires_follow_up": False
        }


async def _fallback_rule_based_processing(message: str, firebase_uid: str, profession: str, context: str):
    """Your existing rule-based processing as fallback"""
    message_lower = message.lower()

    # Your existing intent detection logic (keep exactly as is)
    if any(phrase in message_lower for phrase in ["my name is", "call me", "i am"]):
        return handle_name_storage(message, firebase_uid, profession, context)
    elif any(phrase in message_lower for phrase in ["what is my name", "who am i", "what am i called"]):
        return handle_name_query(message, firebase_uid, context)
    elif any(word in message_lower for word in ["export", "download", "save", "backup"]):
        return handle_export(message, firebase_uid, context)
    elif any(word in message_lower for word in ["create task", "add task", "task to", "new task"]):
        return handle_task_creation(message, firebase_uid, profession, context)
    elif any(word in message_lower for word in ["list tasks", "show tasks", "view tasks", "my tasks"]):
        return handle_task_list(message, firebase_uid, context)
    elif any(word in message_lower for word in ["complete task", "finish task", "done task"]):
        return handle_task_completion(message, firebase_uid, context)
    elif any(word in message_lower for word in ["schedule", "meeting", "add event", "create event"]):
        return await handle_calendar_create(message, firebase_uid, context)
    elif any(word in message_lower for word in ["list events", "show events", "view events", "my calendar", "show my calendar", "show calendar", "show me calendar"]):
        return await handle_calendar_list(firebase_uid, context)
    elif any(word in message_lower for word in ["calendar", "event"]):
        return handle_calendar_help(context)
    else:
        return handle_general(message, firebase_uid, profession, context)



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

async def handle_calendar_create(message: str, user_id: str, context: str = ""):
    # Simple logic: any schedule/create gets a 'Meeting' on today at 10:00
    today_str = datetime.now().strftime("%Y-%m-%d")
    start_time = f"{today_str}T10:00:00"
    
    # save_event signature: firebase_uid, title, description, start_time, end_time, category, priority, location
    event_id = save_event(user_id, "Meeting", "Scheduled via chat", start_time)

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



@app.post("/api/clear_memory")
async def clear_memory_endpoint(request: Request, current_user: dict = Depends(get_current_user)):
    firebase_uid = current_user["firebase_uid"]

    try:
        result = delete_all_user_data(firebase_uid)
        return {
            "status": "success",
            "message": "All data cleared successfully",
            "deleted_counts": result
        }
    except Exception as e:
        logger.error(f"❌ Clear memory error: {str(e)}")
        return {"status": "error", "message": str(e)}

# TODO: Migrate this to sqlalchemy
@app.get("/debug/data_status/{firebase_uid}")
async def debug_data_status(firebase_uid: str):
    """Debug endpoint to check all data for a Firebase UID"""
    try:
        return get_user_data_status(firebase_uid)
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


# Conversation memory endpoints
# TODO: Change this to sqlalchemy.
@app.get("/api/memory/debug/{firebase_uid}")
async def debug_memory_status(firebase_uid: str):
    """Debug endpoint to check memory status"""
    try:
        return get_latest_conversation(firebase_uid)
    except Exception as e:
        return {"error": str(e)}

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


# --- Chat Session Endpoints ---

@app.get("/api/chats")
async def get_chats(current_user: dict = Depends(get_current_user)):
    """Get all chat sessions for the user"""
    try:
        firebase_uid = current_user["firebase_uid"]
        sessions = get_user_chat_sessions(firebase_uid)
        return {"status": "success", "sessions": sessions}
    except Exception as e:
        logger.error(f"❌ Error getting chats: {e}")
        return {"status": "error", "message": str(e)}

@app.post("/api/chats")
async def create_chat(request: dict, current_user: dict = Depends(get_current_user)):
    """Create a new chat session"""
    try:
        firebase_uid = current_user["firebase_uid"]
        title = request.get("title", "New Chat")
        session_id = create_chat_session(firebase_uid, title)
        return {"status": "success", "session_id": session_id, "title": title}
    except Exception as e:
        logger.error(f"❌ Error creating chat: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/api/chats/{session_id}/messages")
async def get_chat_history(session_id: int, current_user: dict = Depends(get_current_user)):
    """Get messages for a specific chat session"""
    try:
        firebase_uid = current_user["firebase_uid"]
        messages = get_chat_messages(session_id, firebase_uid)
        return {"status": "success", "messages": messages}
    except Exception as e:
        logger.error(f"❌ Error getting chat messages: {e}")
        return {"status": "error", "message": str(e)}

@app.delete("/api/chats/{session_id}")
async def delete_chat(session_id: int, current_user: dict = Depends(get_current_user)):
    """Delete a chat session"""
    try:
        firebase_uid = current_user["firebase_uid"]
        success = delete_chat_session(session_id, firebase_uid)
        if success:
            return {"status": "success", "message": "Chat deleted"}
        else:
            return {"status": "error", "message": "Chat not found or could not be deleted"}
    except Exception as e:
        logger.error(f"❌ Error deleting chat: {e}")
        return {"status": "error", "message": str(e)}

@app.patch("/api/chats/{session_id}")
async def update_chat(session_id: int, request: dict, current_user: dict = Depends(get_current_user)):
    """Update chat session (e.g. title)"""
    try:
        firebase_uid = current_user["firebase_uid"]
        title = request.get("title")
        if not title:
             return {"status": "error", "message": "Title required"}
             
        success = update_chat_session_title(session_id, title, firebase_uid)
        if success:
            return {"status": "success", "message": "Chat updated"}
        else:
            return {"status": "error", "message": "Chat not found or could not be updated"}
    except Exception as e:
        logger.error(f"❌ Error updating chat: {e}")
        return {"status": "error", "message": str(e)}


@app.get("/api/tasks")
async def get_tasks(current_user: dict = Depends(get_current_user)):
    """Get user's tasks"""
    try:
        firebase_uid = current_user["firebase_uid"]

        # Get tasks from database
        tasks = get_user_tasks(firebase_uid, status="all")

        # Format tasks for frontend
        formatted_tasks = []
        for task in tasks:
            task_id, title, description, priority, category, due_date, is_completed, progress, created_at = task

            formatted_tasks.append({
                "id": task_id,
                "title": title,
                "description": description,
                "priority": priority,
                "category": category,
                "due_date": due_date,
                "is_completed": is_completed,
                "progress": progress,
                "tags": "[]",  # Default empty tags
                "created_at": created_at
            })

        logger.info(f"📋 API: Retrieved {len(formatted_tasks)} tasks for {firebase_uid}")

        return {
            "success": True,
            "tasks": formatted_tasks,
            "count": len(formatted_tasks)
        }

    except Exception as e:
        logger.error(f"❌ Error getting tasks via API: {e}")
        return {
            "success": False,
            "tasks": [],
            "count": 0,
            "error": str(e)
        }

@app.get("/api/events")
async def get_events(current_user: dict = Depends(get_current_user)):
    """Get user's calendar events"""
    try:
        firebase_uid = current_user["firebase_uid"]
        events = get_all_events(firebase_uid)

        # Format for frontend
        formatted_events = []
        for event in events:
            event_id, title, description, start_time, end_time, category, priority, location, created_at = event
            formatted_events.append({
                "id": event_id,
                "title": title,
                "description": description,
                "start_time": start_time,
                "end_time": end_time,
                "category": category,
                "priority": priority,
                "location": location,
                "created_at": created_at,
            })

        logger.info(f"📅 API: Retrieved {len(formatted_events)} events for {firebase_uid}")
        return {"success": True, "events": formatted_events, "count": len(formatted_events)}

    except Exception as e:
        logger.error(f"❌ Error getting events via API: {e}")
        return {"success": False, "events": [], "count": 0, "error": str(e)}

@app.get("/api/briefing")
async def get_daily_briefing(
    force_refresh: bool = False,
    current_user: dict = Depends(get_current_user)
):
    """Get a daily briefing summary"""
    try:
        firebase_uid = current_user["firebase_uid"]
        profession = current_user.get("profession", "Professional")
        
        # 1. Get today's events
        events = get_all_events(firebase_uid)
        today_str = datetime.now().strftime("%Y-%m-%d")
        todays_events = [e for e in events if e[3].startswith(today_str)]
        
        # 2. Get high priority tasks
        tasks = get_user_tasks(firebase_uid, status="pending")
        priority_tasks = [t for t in tasks if t[3] == "high"]
        
        # 3. Get news
        news_service = SmartNewsService()
        # Use fast context for chat which gives a good summary
        news_context = await news_service.get_news_context_for_chat_fast(
            profession, 
            "US", 
            force_refresh=force_refresh
        )
        
        # 4. Generate Summary with LLM
        gemini_api_key = os.getenv("GEMINI_API_KEY")
        if not gemini_api_key:
            return {"status": "error", "message": "LLM not configured"}
            
        # Determine greeting
        current_hour = datetime.now().hour
        if 5 <= current_hour < 12:
            greeting = "Good morning"
        elif 12 <= current_hour < 17:
            greeting = "Good afternoon"
        elif 17 <= current_hour < 22:
            greeting = "Good evening"
        else:
            greeting = "Hello"

        llm_service = LLMService(gemini_api_key)
        
        prompt = f"""
        You are Agent X, an intelligent personal assistant for a {profession}.
        Current Date: {today_str}
        Current Time: {datetime.now().strftime("%H:%M")}

        Your goal is to generate a high-quality, actionable daily briefing. Do not just list items; analyze them.

        USER'S SCHEDULE FOR TODAY:
        {todays_events if todays_events else "No events scheduled."}

        TOP PRIORITY TASKS:
        {priority_tasks if priority_tasks else "No high priority tasks."}

        RELEVANT NEWS CONTEXT:
        {news_context}

        INSTRUCTIONS:
        1. Synthesize the information. If a news item correlates with a task or event (e.g., industry news relevant to a meeting), explicitly make that connection.
        2. Prioritize what's truly important. If the schedule is empty, focus on deep work or news insights.
        3. Be professional yet conversational and energetic.
        4. Start with "{greeting}!".
        5. Provide a clear outlook for the day (or evening/tomorrow if it's late).

        Format the response as a cohesive spoken paragraph suitable for reading aloud. Avoid robotic listing.
        """
        
        # We use a direct generation here instead of the full agent process
        # Assuming LLMService has a method for raw generation or we use the client directly
        # Since LLMService.process_message is complex, let's use the internal client if accessible or add a method
        # For now, let's try to use the gemini client directly if possible, or add a helper in LLMService.
        # Looking at LLMService, it uses self.llm_client.generate_content
        
        # Use simple_chat method which is available in GeminiClient
        from llm.gemini_client import GeminiClient
        client = GeminiClient(gemini_api_key)
        response_text = await client.simple_chat(prompt, max_tokens=1000)
        
        return {
            "status": "success",
            "summary": response_text,
            "data": {
                "events_count": len(todays_events),
                "tasks_count": len(priority_tasks),
                "date": today_str
            }
        }

    except Exception as e:
        logger.error(f"❌ Error generating briefing: {e}")
        return {"status": "error", "message": str(e)}

@app.post("/api/tasks/{task_id}/complete")
async def update_task_completion(
        task_id: int,
        request: dict,  # Accept JSON body
        current_user: dict = Depends(get_current_user)
):
    """Update task completion status"""
    try:
        firebase_uid = current_user["firebase_uid"]
        completed = request.get("completed", False)

        # Update in database
        success = update_task_completion_in_db(firebase_uid, task_id, completed)

        if success:
            logger.info(f"✅ Updated task {task_id} completion to {completed} for {firebase_uid}")
            return {
                "success": True,
                "message": f"Task {'completed' if completed else 'reopened'} successfully"
            }
        else:
            logger.warning(f"⚠️ Task {task_id} not found or not updated for {firebase_uid}")
            return {
                "success": False,
                "message": "Task not found or could not be updated"
            }

    except Exception as e:
        logger.error(f"❌ Error updating task completion: {e}")
        return {
            "success": False,
            "message": str(e)
        }

@app.put("/api/tasks/{task_id}")
async def update_task(
        task_id: int,
        request: dict,
        current_user: dict = Depends(get_current_user)
):
    """Update a task"""
    try:
        firebase_uid = current_user["firebase_uid"]

        # Extract update fields
        title = request.get("title", "").strip()
        description = request.get("description", "")
        priority = request.get("priority", "medium")
        category = request.get("category", "general")
        due_date = request.get("due_date")

        if not title:
            return {"success": False, "message": "Task title is required"}

        # Update in database
        success = update_task_in_db(firebase_uid, task_id, title, description, priority, category, due_date)

        if success:
            return {"success": True, "message": "Task updated successfully"}
        else:
            return {"success": False, "message": "Task not found or could not be updated"}

    except Exception as e:
        logger.error(f"❌ Error updating task: {e}")
        return {"success": False, "message": str(e)}

@app.delete("/api/tasks/{task_id}")
async def delete_task(task_id: int, current_user: dict = Depends(get_current_user)):
    """Delete a task"""
    try:
        firebase_uid = current_user["firebase_uid"]
        success = delete_task_from_db(firebase_uid, task_id)

        if success:
            return {"success": True, "message": "Task deleted successfully"}
        else:
            return {"success": False, "message": "Task not found"}

    except Exception as e:
        logger.error(f"❌ Error deleting task: {e}")
        return {"success": False, "message": str(e)}

@app.post("/api/tasks")
async def create_task(request: dict, current_user: dict = Depends(get_current_user)):
    """Create a new task"""
    try:
        firebase_uid = current_user["firebase_uid"]

        # Extract task data
        title = request.get("title", "").strip()
        description = request.get("description", "")
        priority = request.get("priority", "medium")
        category = request.get("category", "general")
        due_date = request.get("due_date")

        if not title:
            return {"success": False, "message": "Task title is required"}

        # Save to database
        task_id = save_task(firebase_uid, title, description, priority, category, due_date)

        logger.info(f"📋 Created task {task_id} for {firebase_uid}: {title}")

        return {
            "success": True,
            "message": "Task created successfully",
            "task_id": task_id
        }

    except Exception as e:
        logger.error(f"❌ Error creating task: {e}")
        return {"success": False, "message": str(e)}

# Calendar CRUD endpoints
@app.post("/api/events")
async def create_event(request: dict, current_user: dict = Depends(get_current_user)):
    """Create a new calendar event"""
    try:
        firebase_uid = current_user["firebase_uid"]

        # Extract event data
        title = request.get("title", "").strip()
        description = request.get("description", "")
        start_time = request.get("start_time")  # Expected format: "2025-09-18 10:00:00"
        end_time = request.get("end_time")
        category = request.get("category", "general")
        priority = request.get("priority", "medium")
        location = request.get("location")

        if not title or not start_time:
            return {"success": False, "message": "Title and start time are required"}

        # Save to database using existing save_event function (we'll enhance it)
        event_id = save_enhanced_event(
            firebase_uid, title, description, start_time, end_time,
            category, priority, location
        )

        logger.info(f"📅 Created event {event_id} for {firebase_uid}: {title}")

        return {
            "success": True,
            "message": "Event created successfully",
            "event_id": event_id
        }

    except Exception as e:
        logger.error(f"❌ Error creating event: {e}")
        return {"success": False, "message": str(e)}

@app.put("/api/events/{event_id}")
async def update_event(
        event_id: int,
        request: dict,
        current_user: dict = Depends(get_current_user)
):
    """Update an existing calendar event"""
    try:
        firebase_uid = current_user["firebase_uid"]

        title = request.get("title", "").strip()
        description = request.get("description", "")
        start_time = request.get("start_time")
        end_time = request.get("end_time")
        category = request.get("category", "general")
        priority = request.get("priority", "medium")
        location = request.get("location")

        if not title or not start_time:
            return {"success": False, "message": "Title and start time are required"}

        # Update in database
        success = update_event_in_db(
            firebase_uid, event_id, title, description, start_time,
            end_time, category, priority, location
        )

        if success:
            logger.info(f"📅 Updated event {event_id} for {firebase_uid}")
            return {"success": True, "message": "Event updated successfully"}
        else:
            return {"success": False, "message": "Event not found or could not be updated"}

    except Exception as e:
        logger.error(f"❌ Error updating event: {e}")
        return {"success": False, "message": str(e)}

@app.delete("/api/events/{event_id}")
async def delete_event(event_id: int, current_user: dict = Depends(get_current_user)):
    """Delete a calendar event"""
    try:
        firebase_uid = current_user["firebase_uid"]
        success = delete_event_from_db(firebase_uid, event_id)

        if success:
            logger.info(f"📅 Deleted event {event_id} for {firebase_uid}")
            return {"success": True, "message": "Event deleted successfully"}
        else:
            return {"success": False, "message": "Event not found"}

    except Exception as e:
        logger.error(f"❌ Error deleting event: {e}")
        return {"success": False, "message": str(e)}

# News support endpoints
@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    logging.info("🚀 Agent X API starting up...")

    # Initialize NLTK data
    try:
        import nltk
        nltk.download('punkt', quiet=True)
        nltk.download('stopwords', quiet=True)
        logging.info("✅ NLTK data initialized")
    except Exception as e:
        logging.warning(f"⚠️ NLTK initialization failed: {e}")

    # Start background news updates
    #TODO: The scheduler is running every hour and consuming resources. For development, disabled it
    #asyncio.create_task(news_scheduler.start_background_updates())
    #logging.info("✅ News scheduler started")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    await news_scheduler.stop_background_updates()
    logging.info("🛑 Agent X API shutting down...")

@app.get("/")
async def root():
    return {
        "message": "Agent X API is running",
        "version": "1.0.0",
        "news_service": "active"
    }

@app.get("/debug/user_profile/{firebase_uid}")
async def debug_user_profile(firebase_uid: str):
    """Debug endpoint to check user profile"""
    try:
        from database.operations import get_user_profile_by_uuid
        profile = get_user_profile_by_uuid(firebase_uid)
        return {
            "firebase_uid": firebase_uid,
            "profile": profile,
            "profession": profile.get('profession') if profile else None
        }
    except Exception as e:
        return {"error": str(e)}

# --- Notes Endpoints ---

@app.post("/api/notes")
async def create_note(request: dict, current_user: dict = Depends(get_current_user)):
    """Create a new note"""
    try:
        firebase_uid = current_user["firebase_uid"]
        title = request.get("title", "Untitled Note")
        content = request.get("content", "")
        category = request.get("category", "general")
        
        if not content:
            return {"status": "error", "message": "Content is required"}
            
        note_id = await memory_manager.add_note(firebase_uid, title, content, category)
        return {"status": "success", "note_id": note_id}
    except Exception as e:
        logger.error(f"❌ Error creating note: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/api/notes")
async def get_notes(current_user: dict = Depends(get_current_user)):
    """Get all notes for the user"""
    try:
        firebase_uid = current_user["firebase_uid"]
        notes = await memory_manager.get_notes(firebase_uid)
        return {"status": "success", "notes": notes}
    except Exception as e:
        logger.error(f"❌ Error getting notes: {e}")
        return {"status": "error", "message": str(e)}

@app.delete("/api/notes/{note_id}")
async def delete_note(note_id: str, current_user: dict = Depends(get_current_user)):
    """Delete a note"""
    try:
        firebase_uid = current_user["firebase_uid"]
        success = await memory_manager.delete_note(firebase_uid, note_id)
        if success:
            return {"status": "success", "message": "Note deleted"}
        else:
            return {"status": "error", "message": "Note not found"}
    except Exception as e:
        logger.error(f"❌ Error deleting note: {e}")
        return {"status": "error", "message": str(e)}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
