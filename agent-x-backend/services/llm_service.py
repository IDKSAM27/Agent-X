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

            # Generate LLM response
            llm_response = await self.primary_llm.generate_response(messages, functions)

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
        base_prompt = f"""You are Agent X, an AI assistant specifically designed to help {profession}s. You are helpful, professional, and knowledgeable about {profession}-related work.

You can help with:
- Creating and managing tasks (homework, lesson plans, grading, etc.)
- Managing calendar events (classes, meetings, appointments)
- Remembering user information and preferences
- Answering questions related to {profession} work and responsibilities

When users ask you to perform actions (create tasks, schedule events, etc.), use the provided functions.
Always be conversational, helpful, and reference their profession when relevant.

{context}

Remember to be context-aware and reference previous conversations when relevant. Speak naturally as if you understand their profession and daily challenges."""

        return base_prompt


    async def _execute_functions(self, firebase_uid: str, function_calls: List[Dict], messages: List[Dict]) -> str:
        """Execute function calls and generate final response"""
        function_results = []

        logger.info(f"🔧 Executing {len(function_calls)} function calls")

        for func_call in function_calls:
            name = func_call["name"]
            arguments = func_call["arguments"]

            logger.info(f"🔧 Executing function: {name} with args: {arguments}")

            # Execute function based on name
            try:
                if name in ["create_task"]:
                    result = await self.task_functions.execute(name, firebase_uid, arguments)
                elif name in ["get_tasks"]:
                    result = await self.task_functions.execute(name, firebase_uid, arguments)
                elif name in ["create_event"]:
                    result = await self.calendar_functions.execute(name, firebase_uid, arguments)
                elif name in ["get_events"]:
                    result = await self.calendar_functions.execute(name, firebase_uid, arguments)
                elif name in ["save_user_info"]:
                    result = await self.memory_functions.execute(name, firebase_uid, arguments)
                else:
                    result = {"error": f"Unknown function: {name}"}
                    logger.warning(f"⚠️ Unknown function called: {name}")

                function_results.append({"function": name, "result": result})
                logger.info(f"✅ Function {name} executed: {result}")

            except Exception as func_error:
                logger.error(f"❌ Error executing function {name}: {func_error}")
                function_results.append({"function": name, "result": {"error": str(func_error)}})

        # Generate final response based on function results
        successful_results = [r for r in function_results if r["result"].get("success", False)]

        if successful_results:
            # Create a natural response based on successful function executions
            result_messages = []
            for result in successful_results:
                if result["result"].get("success"):
                    result_messages.append(result["result"]["message"])

            if result_messages:
                final_response = "\n".join(result_messages)
                logger.info(f"✅ Function execution successful: {final_response}")
                return final_response

        # Fallback if no successful results
        error_messages = [r["result"].get("error", "Unknown error") for r in function_results if "error" in r["result"]]
        if error_messages:
            logger.error(f"❌ Function execution failed: {error_messages}")
            return f"I encountered an error: {'; '.join(error_messages)}"

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
