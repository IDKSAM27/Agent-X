from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Dict, Any, Optional, List
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

# Simple agent orchestrator
class SimpleOrchestrator:
    def __init__(self):
        self.agents = {
            'chat': 'ChatAgent',
            'calendar': 'CalendarAgent',
            'email': 'EmailAgent',
        }

    async def classify_intent(self, message: str) -> str:
        """Simple intent classification - will be enhanced with AI"""
        message_lower = message.lower()

        # Calendar intents
        if any(word in message_lower for word in ['schedule', 'meeting', 'calendar', 'appointment', 'book']):
            return 'calendar'

        # Email intents
        elif any(word in message_lower for word in ['email', 'mail', 'send', 'compose', 'inbox']):
            return 'email'

        # Default to chat
        else:
            return 'chat'

    async def process_request(self, request: AgentRequest) -> AgentResponse:
        intent = await self.classify_intent(request.message)

        if intent == 'chat':
            return await self.handle_chat(request)
        elif intent == 'calendar':
            return await self.handle_calendar(request)
        elif intent == 'email':
            return await self.handle_email(request)
        else:
            return await self.handle_chat(request)

    async def handle_chat(self, request: AgentRequest) -> AgentResponse:
        """Enhanced chat handling - will integrate with OpenAI later"""
        return AgentResponse(
            agent_name="ChatAgent",
            response=f"Hello! You said: '{request.message}'. I'm your AI assistant and I'm here to help with various tasks including scheduling, emails, and general conversation.",
            type="text",
            metadata={"intent": "chat"},
            suggested_actions=["Ask me about your schedule", "Check your emails", "Plan your day"]
        )

    async def handle_calendar(self, request: AgentRequest) -> AgentResponse:
        return AgentResponse(
            agent_name="CalendarAgent",
            response=f"I detected you want help with scheduling. You said: '{request.message}'. I can help you manage your calendar, schedule meetings, and set reminders.",
            type="calendar",
            metadata={"intent": "calendar", "action_needed": "schedule"},
            requires_follow_up=True,
            suggested_actions=["View my calendar", "Schedule a meeting", "Set a reminder"]
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
