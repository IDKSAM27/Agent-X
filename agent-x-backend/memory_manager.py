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
        self.notes = self.chroma_client.get_or_create_collection("notes")

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

    async def get_user_context(self, user_id: str, query: str = None) -> Dict[str, Any]:
        """Get comprehensive user context for agents"""

        # Get recent conversations
        recent_conversations = await self.search_conversations(
            query="recent conversation context" if not query else query,
            user_id=user_id,
            limit=5
        )
        
        # Get relevant notes if query is provided
        relevant_notes = []
        if query:
            relevant_notes = await self.search_notes(user_id, query, limit=3)

        # Get user preferences from PostgreSQL
        prefs = get_user_preferences(user_id)
        
        from database.operations import get_user_profile_by_uuid
        profile = get_user_profile_by_uuid(user_id)

        return {
            "user_id": user_id,
            "recent_conversations": recent_conversations,
            "relevant_notes": relevant_notes,
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

    # --- Notes / Knowledge Base Methods ---

    async def add_note(self, user_id: str, title: str, content: str, category: str = "general") -> str:
        """Add a note to the knowledge base"""
        note_id = f"note_{datetime.now().timestamp()}"
        timestamp = datetime.now().isoformat()
        
        # Combine title and content for embedding
        full_text = f"Title: {title}\nContent: {content}"
        embedding = self.embedding_model.encode([full_text])[0].tolist()
        
        # We'll use the 'agent_context' collection for now or create a new one if we could
        # But since we initialized collections in __init__, let's add 'notes' there first.
        # Wait, I can't easily modify __init__ with this tool if I'm appending here.
        # I should have modified __init__ first or use a separate tool call.
        # Let's assume I'll modify __init__ in the next step or use a multi-replace.
        # Actually, I can use get_or_create_collection here dynamically if I want, 
        # but it's better practice to have it in __init__.
        # For now, let's use a new collection 'notes' which I will add to __init__ in a separate call.
        
        self.notes.add(
            documents=[full_text],
            embeddings=[embedding],
            metadatas=[{
                "user_id": user_id,
                "title": title,
                "category": category,
                "timestamp": timestamp,
                "type": "note"
            }],
            ids=[note_id]
        )
        return note_id

    async def get_notes(self, user_id: str, limit: int = 20) -> List[Dict[str, Any]]:
        """Get all notes for a user"""
        try:
            # ChromaDB doesn't have a simple "get all" without IDs, so we query with a dummy embedding or metadata
            # A workaround is to get by metadata
            results = self.notes.get(
                where={"user_id": user_id},
                limit=limit
            )
            
            notes = []
            if results['ids']:
                for i in range(len(results['ids'])):
                    notes.append({
                        "id": results['ids'][i],
                        "content": results['documents'][i],
                        "metadata": results['metadatas'][i]
                    })
            # Sort by timestamp desc
            notes.sort(key=lambda x: x['metadata']['timestamp'], reverse=True)
            return notes
        except Exception as e:
            print(f"Error getting notes: {e}")
            return []

    async def delete_note(self, user_id: str, note_id: str) -> bool:
        """Delete a note"""
        try:
            # Verify ownership
            result = self.notes.get(ids=[note_id], where={"user_id": user_id})
            if not result['ids']:
                return False
                
            self.notes.delete(ids=[note_id])
            return True
        except Exception as e:
            print(f"Error deleting note: {e}")
            return False

    async def search_notes(self, user_id: str, query: str, limit: int = 3) -> List[str]:
        """Search notes for RAG context"""
        try:
            query_embedding = self.embedding_model.encode([query])[0].tolist()
            results = self.notes.query(
                query_embeddings=[query_embedding],
                n_results=limit,
                where={"user_id": user_id}
            )
            
            found_notes = []
            if results['documents'] and results['documents'][0]:
                found_notes = results['documents'][0]
                
            return found_notes
        except Exception as e:
            print(f"Error searching notes: {e}")
            return []

# Global memory manager instance
memory_manager = MemoryManager()
