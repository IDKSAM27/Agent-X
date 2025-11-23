import json
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

from sentence_transformers import SentenceTransformer
from chromadb import PersistentClient  # New import
from database.operations import (
    save_conversation, 
    store_user_preferences, 
    get_user_preferences, 
    store_agent_context, 
    get_agent_context
)

class MemoryManager:
    def __init__(self):
        self.embedding_model = SentenceTransformer('all-MiniLM-L6-v2')

        # Use new PersistentClient instead of deprecated Settings
        self.chroma_client = PersistentClient(path="./chroma_db")

        # Create collections
        self.conversations = self.chroma_client.get_or_create_collection("conversations")
        self.user_preferences = self.chroma_client.get_or_create_collection("user_preferences")
        self.agent_context = self.chroma_client.get_or_create_collection("agent_context")

    async def store_conversation(
            self,
            user_id: str,
            message_id: str,
            user_message: str,
            agent_response: str,
            agent_name: str,
            metadata: Dict[str, Any] = None
    ):
        """Store conversation with vector embeddings for semantic search"""

        print(f"🧠 [MEMORY] Storing conversation for user {user_id}: '{user_message[:50]}...'")

        # Store in PostgreSQL
        try:
            save_conversation(
                firebase_uid=user_id,
                user_message=user_message,
                assistant_response=agent_response,
                agent_name=agent_name,
                intent=metadata.get("intent") if metadata else None,
                message_id=message_id,
                metadata=metadata
            )
            print(f"🧠 [MEMORY] ✅ Conversation stored in PostgreSQL database")
        except Exception as e:
            print(f"🧠 [MEMORY] ❌ Error storing in PostgreSQL: {e}")

        # Create embeddings and store in ChromaDB
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
            print(f"🧠 [MEMORY] ✅ Vector embedding stored in ChromaDB")
        except Exception as e:
            print(f"🧠 [MEMORY] ❌ Error storing in ChromaDB: {e}")

    async def search_conversations(
            self,
            query: str,
            user_id: str,
            limit: int = 5
    ) -> List[Dict[str, Any]]:
        """Search past conversations using semantic similarity"""

        print(f"🧠 [MEMORY] Searching conversations for user {user_id} with query: '{query}'")

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

            print(f"🧠 [MEMORY] Found {len(conversations)} relevant conversations")
            return conversations
        except Exception as e:
            print(f"🧠 [MEMORY] ❌ Error searching conversations: {e}")
            return []

    async def store_user_preferences(self, user_id: str, profession: str, preferences: Dict[str, Any]):
        """Store user preferences and patterns"""
        
        # Store in PostgreSQL
        store_user_preferences(user_id, profession, preferences)

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

        # Get user preferences from PostgreSQL
        prefs = get_user_preferences(user_id)
        
        # We need profession too, which is stored in User model. 
        # get_user_preferences returns the dict stored in preferences column.
        # But we also need profession. 
        # Let's check get_user_preferences implementation again.
        # It returns json.loads(user.preferences). It doesn't return profession.
        # I should update get_user_preferences to return profession as well or use get_user_profile_by_uuid.
        # Wait, get_user_profile_by_uuid returns profession.
        
        from database.operations import get_user_profile_by_uuid
        profile = get_user_profile_by_uuid(user_id)

        return {
            "user_id": user_id,
            "recent_conversations": recent_conversations,
            "preferences": prefs,
            "profession": profile.get("profession", "Unknown")
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
        expires_at = (datetime.now() + timedelta(hours=expires_hours)).isoformat()
        store_agent_context(user_id, agent_name, context_type, context_data, expires_at)

    async def get_agent_context(self, user_id: str, context_type: str = None) -> List[Dict[str, Any]]:
        """Get shared context from other agents"""
        return get_agent_context(user_id, context_type)

# Global memory manager instance
memory_manager = MemoryManager()
