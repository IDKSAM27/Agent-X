import google.generativeai as genai
from typing import Dict, List
import logging
from llm.base import BaseLLMClient, LLMResponse

logger = logging.getLogger(__name__)

class GeminiClient(BaseLLMClient):
    """Gemini API client implementation (Single Responsibility: Handle Gemini API only)"""

    def __init__(self, api_key: str):
        self.api_key = api_key
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel(
            "gemini-2.5-flash",
            generation_config=genai.GenerationConfig(
                temperature=0.3,  # Lower temperature = faster
                max_output_tokens=500,  # Fewer tokens = faster
                candidate_count=1,  # Single candidate = faster
            )
        )
        logger.info("✅ Gemini client initialized with optimized settings")


    async def generate_response(self, messages: List[Dict], functions: List[Dict]) -> LLMResponse:
        """Generate response with function calling"""
        try:
            # Convert function definitions to Gemini format (now using proper dict format)
            tools = self._convert_functions_to_tools(functions) if functions else None

            # Build conversation context
            conversation_text = self._build_conversation_text(messages)

            # Generate response with or without tools
            if tools:
                response = self.model.generate_content(
                    conversation_text,
                    tools=tools
                )
            else:
                response = self.model.generate_content(conversation_text)

            # Parse response
            return self._parse_response(response)

        except Exception as e:
            logger.error(f"❌ Gemini API error: {e}")
            raise Exception(f"Gemini API failed: {str(e)}")

    async def simple_chat(self, message: str, context: str = "") -> str:
        """Simple chat without function calling"""
        try:
            prompt = f"{context}\n\nUser: {message}" if context else message
            response = self.model.generate_content(prompt)
            return response.text if hasattr(response, 'text') else "No response generated"
        except Exception as e:
            logger.error(f"❌ Gemini simple chat error: {e}")
            return "I'm having trouble processing your request. Please try again."

    def is_available(self) -> bool:
        """Check if Gemini is available"""
        try:
            test_response = self.model.generate_content("Test")
            return bool(test_response.text if hasattr(test_response, 'text') else False)
        except:
            return False

    def _convert_functions_to_tools(self, functions: List[Dict]) -> List[Dict]:
        """Convert OpenAI-style function definitions to Gemini tools format"""
        if not functions:
            return []

        gemini_tools = []
        for func in functions:
            # Extract function definition
            func_def = func.get("function", {})

            # Convert to Gemini tool format (plain Python dict)
            gemini_tool = {
                "function_declarations": [
                    {
                        "name": func_def.get("name", ""),
                        "description": func_def.get("description", ""),
                        "parameters": self._convert_parameters(func_def.get("parameters", {}))
                    }
                ]
            }
            gemini_tools.append(gemini_tool)

        return gemini_tools

    def _convert_parameters(self, openai_params: Dict) -> Dict:
        """Convert OpenAI parameter format to Gemini parameter format"""
        if not openai_params:
            return {"type": "object", "properties": {}}

        # Convert properties
        properties = {}
        for param_name, param_def in openai_params.get("properties", {}).items():
            properties[param_name] = {
                "type": param_def.get("type", "string"),
                "description": param_def.get("description", "")
            }

            # Handle enum values
            if "enum" in param_def:
                properties[param_name]["enum"] = param_def["enum"]

        return {
            "type": "object",
            "properties": properties,
            "required": openai_params.get("required", [])
        }

    def _build_conversation_text(self, messages: List[Dict]) -> str:
        """Build conversation text from messages"""
        conversation_parts = []
        for msg in messages:
            role = msg.get("role", "")
            content = msg.get("content", "")

            if role == "system":
                conversation_parts.append(f"System: {content}")
            elif role == "user":
                conversation_parts.append(f"User: {content}")
            elif role == "assistant":
                conversation_parts.append(f"Assistant: {content}")

        return "\n".join(conversation_parts)

    def _parse_response(self, response) -> LLMResponse:
        """Parse Gemini response into standardized format"""
        try:
            function_calls = []
            content = ""

            # Extract text content
            if hasattr(response, 'text') and response.text:
                content = response.text
            elif hasattr(response, 'candidates') and response.candidates:
                # Try to extract text from candidates
                for candidate in response.candidates:
                    if hasattr(candidate, 'content') and candidate.content.parts:
                        for part in candidate.content.parts:
                            if hasattr(part, 'text') and part.text:
                                content += part.text

            # Extract function calls
            if hasattr(response, 'candidates') and response.candidates:
                for candidate in response.candidates:
                    if hasattr(candidate, 'content') and candidate.content.parts:
                        for part in candidate.content.parts:
                            if hasattr(part, 'function_call') and part.function_call:
                                try:
                                    # Parse function call arguments
                                    args = {}
                                    if hasattr(part.function_call, 'args'):
                                        for key, value in part.function_call.args.items():
                                            args[key] = value

                                    function_calls.append({
                                        "name": part.function_call.name,
                                        "arguments": args
                                    })
                                except Exception as func_error:
                                    logger.warning(f"⚠️ Error parsing function call: {func_error}")

            # Fallback content if none found
            if not content and not function_calls:
                content = "I understand your request but couldn't generate a proper response."

            return LLMResponse(
                content=content,
                function_calls=function_calls,
                metadata={
                    "model": "gemini-2.5-flash",
                    "provider": "google",
                    "has_function_calls": len(function_calls) > 0
                }
            )

        except Exception as e:
            logger.error(f"❌ Error parsing Gemini response: {e}")
            return LLMResponse(
                content="I encountered an error processing your request.",
                function_calls=[],
                metadata={"error": str(e), "model": "gemini-2.5-flash", "provider": "google"}
            )
