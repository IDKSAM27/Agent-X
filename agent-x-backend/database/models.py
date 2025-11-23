from sqlalchemy import Column, Integer, String, Boolean, Float, Text
from .connection import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    firebase_uid = Column(String, unique=True, nullable=False, index=True)
    display_name = Column(String, nullable=True)
    profession = Column(String, nullable=True)
    email = Column(String, nullable=True)
    email_verified = Column(Boolean, default=False)
    created_at = Column(String, nullable=False)
    last_login = Column(String, nullable=True)
    preferences = Column(Text, nullable=True)

class Task(Base):
    __tablename__ = "tasks"

    id = Column(Integer, primary_key=True, index=True)
    firebase_uid = Column(String, nullable=False, index=True)
    title = Column(String, nullable=False)
    description = Column(Text, default="")
    priority = Column(String, default="medium")
    category = Column(String, default="general")
    due_date = Column(String, nullable=True)
    is_completed = Column(Boolean, default=False)
    progress = Column(Float, default=0.0)
    tags = Column(Text, default="[]")
    created_at = Column(String, nullable=False)
    updated_at = Column(String, nullable=False)

class Event(Base):
    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    firebase_uid = Column(String, nullable=False, index=True)
    title = Column(String, nullable=False)
    description = Column(Text, default="")
    start_time = Column(String, nullable=False)
    end_time = Column(String, nullable=True)
    category = Column(String, default="general")
    priority = Column(String, default="medium")
    location = Column(String, nullable=True)
    created_at = Column(String, nullable=False)
    updated_at = Column(String, nullable=False)

class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(Integer, primary_key=True, index=True)
    firebase_uid = Column(String, nullable=False, index=True)
    message_id = Column(String, unique=True, nullable=True)
    user_message = Column(Text, nullable=False)
    assistant_response = Column(Text, nullable=False)
    agent_name = Column(String, nullable=False)
    intent = Column(String, nullable=True)
    conversation_metadata = Column(Text, nullable=True)
    timestamp = Column(String, nullable=False)

class AgentContext(Base):
    __tablename__ = "agent_context"

    id = Column(Integer, primary_key=True, index=True)
    firebase_uid = Column(String, nullable=False, index=True)
    agent_name = Column(String, nullable=False)
    context_type = Column(String, nullable=True)
    context_data = Column(Text, nullable=True)
    created_at = Column(String, nullable=False)
    expires_at = Column(String, nullable=True)
