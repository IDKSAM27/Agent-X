from typing import Dict, List, Any
import logging
from llm.base import BaseLLMClient
from llm.gemini_client import GeminiClient
from llm.function_registry import FunctionRegistry
from functions.task_functions import TaskFunctions
from functions.calendar_functions import CalendarFunctions
from functions.memory_functions import MemoryFunctions
from functions.news_functions import NewsFunctions

logger = logging.getLogger(__name__)

class LLMService:
    """Main LLM orchestration service (Dependency Inversion: Depends on abstractions)"""

    def __init__(self, gemini_api_key: str):
        # Dependency injection - can easily swap LLM providers
        self.primary_llm: BaseLLMClient = GeminiClient(gemini_api_key)
        self.function_registry = FunctionRegistry()

        # Initialize function executors
        self.task_functions = TaskFunctions()
        self.calendar_functions = CalendarFunctions()
        self.memory_functions = MemoryFunctions()
        self.news_functions = NewsFunctions()

        logger.info("✅ LLM Service initialized")

    async def process_message(self, firebase_uid: str, message: str, context: str, profession: str) -> Dict[str, Any]:
        """Process user message with LLM and function calling"""
        try:
            # Build system prompt with context
            system_prompt = self._build_system_prompt(profession, context)

            # Prepare messages
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": message}
            ]

            # Get available functions
            functions = self.function_registry.get_all_functions()
            logger.info(f"📋 Available functions: {[f['function']['name'] for f in functions]}")

            # Generate LLM response
            llm_response = await self.primary_llm.generate_response(messages, functions)
            logger.info(f"🔧 LLM wanted to call {len(llm_response.function_calls)} functions")

            # Handle function calls if any
            if llm_response.function_calls:
                final_response, executed_functions = await self._execute_functions(
                    firebase_uid,
                    llm_response.function_calls,
                    messages
                )

                # NEW: Build navigation metadata based on executed functions
                navigation_metadata = self._build_navigation_metadata(executed_functions)
            else:
                final_response = llm_response.content
                navigation_metadata = {}

            return {
                "agent_name": "LLMAgent",
                "response": final_response,
                "type": "text",
                "metadata": {
                    "llm_provider": "gemini",
                    "function_calls_made": len(llm_response.function_calls),
                    **llm_response.metadata,
                    **navigation_metadata  # Include navigation metadata
                },
                "suggested_actions": self._generate_suggestions(message),
                "requires_follow_up": False
            }

        except Exception as e:
            logger.error(f"❌ LLM Service error: {e}")
            return self._fallback_response(str(e))

    def _build_navigation_metadata(self, executed_functions: List[Dict]) -> Dict[str, Any]:
        """Build navigation metadata based on executed functions"""
        metadata = {}

        for func_data in executed_functions:
            function_name = func_data["name"]
            result_data = func_data["result"]

            # Calendar functions
            if function_name == "create_event" and result_data.get("success"):
                event_data = result_data.get("data", {})
                metadata.update({
                    "type": "calendar",
                    "action": "event_created",
                    "show_action_button": True,
                    "event_id": event_data.get("event_id"),
                    "event_title": event_data.get("title"),
                    "event_date": event_data.get("date"), # Add event date
                })

            elif function_name == "get_events" and result_data.get("success"):
                metadata.update({
                    "type": "calendar",
                    "action": "events_listed",
                    "show_action_button": True,
                    "event_count": len(result_data.get("data", {}).get("events", []))
                })

            # Task functions
            elif function_name == "create_task" and result_data.get("success"):
                metadata.update({
                    "type": "task",
                    "action": "task_created",
                    "show_action_button": True,
                    "task_id": result_data.get("data", {}).get("task_id"),
                    "task_title": result_data.get("data", {}).get("title"),
                })
            elif function_name == "get_tasks" and result_data.get("success"):
                metadata.update({
                    "type": "task",
                    "action": "tasks_listed",
                    "show_action_button": True,
                    "task_count": len(result_data.get("data", {}).get("tasks", []))
                })

        return metadata

    def _build_system_prompt(self, profession: str, context: str) -> str:
        """Build system prompt with user context"""
        base_prompt = f"""You are Agent X, an AI assistant specifically designed to help {profession}s.

Available functions:
- save_user_info: Save user's name and information  
- get_user_info: Retrieve user's saved name and information
- create_task: Create new tasks with title and priority
- get_tasks: Show user's current tasks
- create_event: Schedule calendar events 
- get_events: Show user's calendar and schedule
- get_recent_news: Get recent news relevant to their profession
- get_news_insights: Get news insights and trends for their field

IMPORTANT: When users ask about:
- "What's happening" or "news" or "updates" → Use get_recent_news
- "Trends" or "insights" or "industry updates" → Use get_news_insights  
- Multiple requests → Call ALL relevant functions in sequence

    {context}

Be conversational and helpful. Reference their profession when relevant."""

        return base_prompt



    async def _execute_functions(self, firebase_uid: str, function_calls: List[Dict], messages: List[Dict]) -> tuple[str, List[Dict]]:
        """Execute function calls and generate final response"""
        function_results = []
        executed_functions = []

        logger.info(f"🔧 Executing {len(function_calls)} function calls")

        for func_call in function_calls:
            name = func_call["name"]
            arguments = func_call["arguments"]

            logger.info(f"🔧 Executing function: {name} with args: {arguments}")

            try:
                if name in ["create_task", "get_tasks"]:
                    result = await self.task_functions.execute(name, firebase_uid, arguments)
                elif name in ["create_event", "get_events"]:
                    result = await self.calendar_functions.execute(name, firebase_uid, arguments)
                elif name in ["save_user_info", "get_user_info"]:
                    result = await self.memory_functions.execute(name, firebase_uid, arguments)
                elif name in ["get_recent_news", "get_news_insights"]:  # ADD THIS LINE
                    result = await self.news_functions.execute(name, firebase_uid, arguments)  # ADD THIS LINE
                else:
                    result = {"error": f"Unknown function: {name}"}

                function_results.append({"function": name, "result": result})

                if result.get("success"):
                    executed_functions.append({"name": name, "result": result})

                logger.info(f"✅ Function {name} executed: {result}")

            except Exception as func_error:
                logger.error(f"❌ Error executing function {name}: {func_error}")
                function_results.append({"function": name, "result": {"error": str(func_error)}})

        # Generate natural response with LLM based on function results
        response = await self._generate_natural_response(function_results, messages)

        return response, executed_functions  # ✅ Return both response and executed functions


    async def _generate_natural_response(self, function_results: List[Dict], original_messages: List[Dict]) -> str:
        """Generate a natural response based on function execution results"""

        successful_messages = []
        error_messages = []

        # NEW: Track executed functions for metadata
        executed_functions = []

        # Extract the actual messages from successful function calls
        for func_result in function_results:
            function_name = func_result["function"]
            result_data = func_result["result"]

            if result_data.get("success", False):
                # NEW: Track successful function execution
                executed_functions.append({
                    "name": function_name,
                    "result": result_data
                })

                # Use the actual message from the function, not a generic one
                function_message = result_data.get("message", "")
                if function_message:
                    successful_messages.append(function_message)
                else:
                    # Fallback for functions without messages
                    successful_messages.append(f"✅ {function_name} completed successfully")
            else:
                # Handle errors
                error_msg = result_data.get("error", "Unknown error occurred")
                error_messages.append(f"❌ Error with {function_name}: {error_msg}")

        # Combine all messages
        all_messages = successful_messages + error_messages

        if not all_messages:
            return "I completed the requested action."

        if len(all_messages) == 1:
            # Single function - return the message directly
            return all_messages[0]

        # Multiple functions - combine messages nicely
        combined_message = "\n\n".join(all_messages)

        # For multiple successful actions, add a brief intro
        if len(successful_messages) > 1 and not error_messages:
            return f"I've completed multiple actions for you:\n\n{combined_message}"

        return combined_message


    def _generate_suggestions(self, message: str) -> List[str]:
        """Generate contextual suggestions based on message"""
        message_lower = message.lower()

        if "task" in message_lower:
            return ["View my tasks", "Create another task", "Set task priority"]
        elif "calendar" in message_lower or "event" in message_lower:
            return ["Create new event", "View my calendar", "Set reminder"]
        elif "name" in message_lower:
            return ["Update my profile", "Show my information", "Create a task"]
        else:
            return ["Create a task", "Show my calendar", "Ask me anything"]

    def _fallback_response(self, error: str) -> Dict[str, Any]:
        """Fallback response when LLM fails"""
        return {
            "agent_name": "FallbackAgent",
            "response": "I'm having trouble processing your request right now. Please try again or ask something simpler.",
            "type": "text",
            "metadata": {"error": error, "fallback": True},
            "suggested_actions": ["Try again", "Ask a simple question"],
            "requires_follow_up": False
        }
