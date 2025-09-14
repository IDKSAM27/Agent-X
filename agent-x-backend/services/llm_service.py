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

        # Build a detailed summary of what was executed
        results_summary = []

        for func_result in function_results:
            function_name = func_result["function"]
            result_data = func_result["result"]

            if result_data.get("success", False):
                if function_name == "create_task":
                    task_data = result_data.get("data", {})
                    results_summary.append(f"Created task: '{task_data.get('title', 'Unnamed Task')}' with {task_data.get('priority', 'medium')} priority")

                elif function_name == "get_tasks":
                    tasks = result_data.get("data", {}).get("tasks", [])
                    if tasks:
                        task_list = []
                        for i, task in enumerate(tasks, 1):
                            priority_emoji = "🔥" if task.get("priority") == "high" else "⚡" if task.get("priority") == "medium" else "📝"
                            task_list.append(f"{i}. {priority_emoji} {task.get('title', 'Unnamed Task')}")
                        results_summary.append(f"Your tasks:\n" + "\n".join(task_list))
                    else:
                        results_summary.append("You don't have any tasks yet.")

                elif function_name == "create_event":
                    event_data = result_data.get("data", {})
                    results_summary.append(f"Scheduled event: '{event_data.get('title', 'Unnamed Event')}' on {event_data.get('date')} at {event_data.get('time')}")

                elif function_name == "get_events":
                    events = result_data.get("data", {}).get("events", [])
                    if events:
                        event_list = []
                        for i, event in enumerate(events, 1):
                            event_list.append(f"{i}. 📅 {event.get('title', 'Unnamed Event')} at {event.get('datetime')}")
                        results_summary.append(f"Your upcoming events:\n" + "\n".join(event_list))
                    else:
                        results_summary.append("You don't have any scheduled events yet.")

                elif function_name == "save_user_info":
                    user_data = result_data.get("data", {})
                    results_summary.append(f"Saved your name as {user_data.get('name', 'Unknown')}")

                elif function_name == "get_user_info":
                    user_data = result_data.get("data", {})
                    user_name = user_data.get("name")
                    if user_name:
                        results_summary.append(f"Your name is {user_name}")
                    else:
                        results_summary.append("I don't have your name saved yet")

            else:
                # Handle errors
                error_msg = result_data.get("error", "Unknown error occurred")
                results_summary.append(f"Error with {function_name}: {error_msg}")

        # Create a natural prompt for the LLM to generate a conversational response
        if results_summary:
            results_text = "\n".join(results_summary)

            # For simple single-function responses, return directly
            if len(function_results) == 1 and function_results[0]["function"] == "get_user_info":
                return results_text

            # Use LLM to generate a natural, conversational response for complex cases
            natural_prompt = f"""Based on the following actions that were just completed:
    
    {results_text}
    
    Please provide a helpful, conversational response to the user. Be natural and friendly, and summarize what was accomplished. If showing lists of tasks or events, format them nicely with emojis and clear structure."""

            try:
                natural_response = await self.primary_llm.simple_chat(natural_prompt)
                logger.info(f"✅ Generated natural response: {natural_response[:100]}...")
                return natural_response
            except Exception as e:
                logger.error(f"❌ Failed to generate natural response: {e}")
                # Fallback to the results summary
                return results_text

        return "I completed the requested action."


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
