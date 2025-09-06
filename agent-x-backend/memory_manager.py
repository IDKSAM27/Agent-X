import sqlite3
import json
import numpy as np
from sentence_transformers import SentenceTransformer
from datetime import datetime, timedelta 
from typing import List, Dict, Any, Optional
import chromadb
from chromadb.config import Settings

class MemoryManager:
    def __init__(self, db_path: str = "agent_memory.db"):
        self.db_path = db_path
        self.embedding_model = SentenceTransformer('all-MiniLM-L6-v2')

        # Initialize ChromaDB for vector storage
        self.chroma_client = chromadb.Client(Settings(
            chroma_db_impl="duckdb+parquet",
            persist_directory="./chroma_db"
        ))

        # Create collections
        self.conversations = self._get_or_create_collection("conversations")
        self.user_preferences = self._get_or_create_collection("user_preferences")
        self.agent_context = self._get_or_create_collection("agent_context")

        self._init_sqlite_db()

    def _get_or_create_collection(self, name: str):
        try:
            return self.chroma_client.get_collection(name)
        except:
            return self.chroma_client.create_collection(name)

    def _init_sqlite_db(self):
        """Initialize SQLite for structured data"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Conversations table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                message_id TEXT UNIQUE,
                user_message TEXT,
                agent_response TEXT,
                agent_name TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                metadata TEXT
            )
        ''')

        # User preferences table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS user_preferences (
                user_id TEXT PRIMARY KEY,
                profession TEXT,
                preferences TEXT,
                last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Agent context table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS agent_context (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                agent_name TEXT NOT NULL,
                context_type TEXT,
                context_data TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                expires_at DATETIME
            )
        ''')

        conn.commit()
        conn.close()

    async def store_conversation(self, user_id, message_id, user_message, agent_response, agent_name, metadata=None):
        """Store conversation with vector embeddings for semantic search"""

        print(f"[MEMORY] Storing conversation for user {user_id}: '{user_message[:50]}...'")

        # Store in SQLite
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT OR REPLACE INTO conversations 
            (user_id, message_id, user_message, agent_response, agent_name, metadata)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (user_id, message_id, user_message, agent_response, agent_name, json.dumps(metadata or {})))

        conn.commit()
        conn.close()

        print(f"[MEMORY] Conversation stored in SQLite database")

        # Store in ChromaDB
        try:
            combined_text = f"User: {user_message} Agent: {agent_response}"
            embedding = self.embedding_model.encode([combined_text])[0].tolist()

            self.conversations.add(
                documents=[combined_text],
                embeddings=[embedding],
                metadatas=[{
                    "user_id": user_id,
                    "message_id": message_id,
                    "agent_name": agent_name,
                    "timestamp": datetime.now().isoformat(),
                    **(metadata or {})
                }],
                ids=[message_id]
            )
            print(f"[MEMORY] Vector embedding stored in ChromaDB")
        except Exception as e:
            print(f"[MEMORY] ❌ Error storing in ChromaDB: {e}")

    async def search_conversations(self, query, user_id, limit=5):
        """Search past conversations using semantic similarity"""

        print(f"[MEMORY] Searching conversations for user {user_id} with query: '{query}'")

        try:
            query_embedding = self.embedding_model.encode([query])[0].tolist()

            results = self.conversations.query(
                query_embeddings=[query_embedding],
                n_results=limit,
                where={"user_id": user_id}
            )

            conversations = []
            if results['ids'] and results['ids'][0]:
                for i in range(len(results['ids'][0])):
                    conversations.append({
                        "message_id": results['ids'][0][i],
                        "content": results['documents'][0][i],
                        "similarity": results['distances'][0][i] if 'distances' in results else 0,
                        "metadata": results['metadatas'][0][i]
                    })

            print(f"[MEMORY] Found {len(conversations)} relevant conversations")
            return conversations
        except Exception as e:
            print(f"[MEMORY] ❌ Error searching conversations: {e}")
            return []

    async def store_user_preferences(self, user_id: str, profession: str, preferences: Dict[str, Any]):
        """Store user preferences and patterns"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT OR REPLACE INTO user_preferences (user_id, profession, preferences)
            VALUES (?, ?, ?)
        ''', (user_id, profession, json.dumps(preferences)))

        conn.commit()
        conn.close()

        # Store in vector DB for semantic matching
        preferences_text = f"User profession: {profession}. Preferences: {json.dumps(preferences)}"
        embedding = self.embedding_model.encode([preferences_text])[0].tolist()

        try:
            self.user_preferences.add(
                documents=[preferences_text],
                embeddings=[embedding],
                metadatas=[{"user_id": user_id, "profession": profession}],
                ids=[user_id]
            )
        except:
            # Update if exists
            try:
                self.user_preferences.delete(ids=[user_id])
                self.user_preferences.add(
                    documents=[preferences_text],
                    embeddings=[embedding],
                    metadatas=[{"user_id": user_id, "profession": profession}],
                    ids=[user_id]
                )
            except Exception as e:
                print(f"Error storing user preferences: {e}")

    async def get_user_context(self, user_id: str) -> Dict[str, Any]:
        """Get comprehensive user context for agents"""

        # Get recent conversations
        recent_conversations = await self.search_conversations(
            query="recent conversation context",
            user_id=user_id,
            limit=10
        )

        # Get user preferences
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('SELECT * FROM user_preferences WHERE user_id = ?', (user_id,))
        prefs = cursor.fetchone()
        conn.close()

        return {
            "user_id": user_id,
            "recent_conversations": recent_conversations,
            "preferences": json.loads(prefs[2]) if prefs and len(prefs) > 2 else {},
            "profession": prefs[1] if prefs and len(prefs) > 1 else "Unknown"
        }

    async def store_agent_context(
            self,
            user_id: str,
            agent_name: str,
            context_type: str,
            context_data: Dict[str, Any],
            expires_hours: int = 24
    ):
        """Store agent-specific context that other agents can access"""

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        expires_at = datetime.now() + timedelta(hours=expires_hours)  # Fixed timedelta usage

        cursor.execute('''
            INSERT INTO agent_context (user_id, agent_name, context_type, context_data, expires_at)
            VALUES (?, ?, ?, ?, ?)
        ''', (user_id, agent_name, context_type, json.dumps(context_data), expires_at))

        conn.commit()
        conn.close()

    async def get_agent_context(self, user_id: str, context_type: str = None) -> List[Dict[str, Any]]:
        """Get shared context from other agents"""

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        if context_type:
            cursor.execute('''
                SELECT * FROM agent_context 
                WHERE user_id = ? AND context_type = ? AND expires_at > CURRENT_TIMESTAMP
            ''', (user_id, context_type))
        else:
            cursor.execute('''
                SELECT * FROM agent_context 
                WHERE user_id = ? AND expires_at > CURRENT_TIMESTAMP
            ''', (user_id,))

        contexts = cursor.fetchall()
        conn.close()

        return [
            {
                "agent_name": ctx[2],
                "context_type": ctx[3],
                "context_data": json.loads(ctx[4]) if ctx[4] else {},
                "created_at": ctx[5]
            }
            for ctx in contexts
        ]

# Global memory manager instance
memory_manager = MemoryManager()
