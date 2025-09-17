from typing import Dict, List, Any
import logging
from llm.base import BaseLLMClient
from llm.gemini_client import GeminiClient
from llm.function_registry import FunctionRegistry
from functions.task_functions import TaskFunctions
from functions.calendar_functions import CalendarFunctions
from functions.memory_functions import MemoryFunctions

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
                final_response = await self._execute_functions(
                    firebase_uid,
                    llm_response.function_calls,
                    messages
                )
            else:
                final_response = llm_response.content

            return {
                "agent_name": "LLMAgent",
                "response": final_response,
                "type": "text",
                "metadata": {
                    "llm_provider": "gemini",
                    "function_calls_made": len(llm_response.function_calls),
                    **llm_response.metadata
                },
                "suggested_actions": self._generate_suggestions(message),
                "requires_follow_up": False
            }

        except Exception as e:
            logger.error(f"❌ LLM Service error: {e}")
            return self._fallback_response(str(e))

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

IMPORTANT: When users make multiple requests in one message, call ALL the relevant functions in sequence. For example:
- "My name is Sam, create a task to grade assignments, and show me my calendar" should call:
  1. save_user_info (for the name)
  2. create_task (for the grading task) 
  3. get_events (to show calendar)

Always execute ALL requested actions, not just the first one.

{context}

Be conversational and helpful. Reference their profession when relevant."""

        return base_prompt


    async def _execute_functions(self, firebase_uid: str, function_calls: List[Dict], messages: List[Dict]) -> str:
        """Execute function calls and generate final response"""
        function_results = []

        logger.info(f"🔧 Executing {len(function_calls)} function calls")

        # In the _execute_functions method, add this debug logging:
        for func_call in function_calls:
            name = func_call["name"]
            arguments = func_call["arguments"]

            logger.info(f"🔧 Executing function: {name} with args: {arguments}")

            # Add this debug line:
            logger.info(f"🔍 Function name '{name}' - checking routing...")

            # Execute function based on name
            try:
                if name in ["create_task", "get_tasks"]:
                    logger.info(f"🔍 Routing {name} to task_functions")
                    result = await self.task_functions.execute(name, firebase_uid, arguments)
                elif name in ["create_event", "get_events"]:
                    logger.info(f"🔍 Routing {name} to calendar_functions")
                    result = await self.calendar_functions.execute(name, firebase_uid, arguments)
                elif name in ["save_user_info", "get_user_info"]:
                    logger.info(f"🔍 Routing {name} to memory_functions")
                    result = await self.memory_functions.execute(name, firebase_uid, arguments)
                else:
                    result = {"error": f"Unknown function: {name}"}
                    logger.warning(f"⚠️ Unknown function called: {name}")

                function_results.append({"function": name, "result": result})
                logger.info(f"✅ Function {name} executed: {result}")

            except Exception as func_error:
                logger.error(f"❌ Error executing function {name}: {func_error}")
                function_results.append({"function": name, "result": {"error": str(func_error)}})

        # Generate natural response with LLM based on function results
        return await self._generate_natural_response(function_results, messages)

    async def _generate_natural_response(self, function_results: List[Dict], original_messages: List[Dict]) -> str:
        """Generate a natural response based on function execution results"""

        successful_messages = []
        error_messages = []

        # Extract the actual messages from successful function calls
        for func_result in function_results:
            function_name = func_result["function"]
            result_data = func_result["result"]

            if result_data.get("success", False):
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
