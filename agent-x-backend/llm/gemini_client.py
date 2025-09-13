import google.generativeai as genai
from typing import Dict, List, Optional
import json
import logging
from .base import BaseLLMClient, LLMResponse

logger = logging.getLogger(__name__)

class GeminiClient(BaseLLMClient):
    """Gemini API client implementation (Single Responsibility: Handle Gemini API only)"""

    def __init__(self, api_key: str):
        self.api_key = api_key
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel(
            "gemini-2.5-flash",
            generation_config=genai.GenerationConfig(
                temperature=0.7,
                max_output_tokens=1000,
            )
        )
        logger.info("✅ Gemini client initialized")

    async def generate_response(self, messages: List[Dict], functions: List[Dict]) -> LLMResponse:
        """Generate response with function calling"""
        try:
            # Convert function definitions to Gemini format
            tools = self._convert_functions_to_tools(functions)

            # Build conversation context
            conversation_text = self._build_conversation_text(messages)

            # Generate response
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
            return response.text
        except Exception as e:
            logger.error(f"❌ Gemini simple chat error: {e}")
            return "I'm having trouble processing your request. Please try again."

    def is_available(self) -> bool:
        """Check if Gemini is available"""
        try:
            # Simple test generation
            test_response = self.model.generate_content("Test")
            return bool(test_response.text)
        except:
            return False

    def _convert_functions_to_tools(self, functions: List[Dict]) -> List:
        """Convert OpenAI-style function definitions to Gemini tools"""
        tools = []
        for func in functions:
            tool = genai.protos.Tool(
                function_declarations=[
                    genai.protos.FunctionDeclaration(
                        name=func["function"]["name"],
                        description=func["function"]["description"],
                        parameters=genai.protos.Schema(
                            type=genai.protos.Type.OBJECT,
                            properties={
                                name: genai.protos.Schema(
                                    type=getattr(genai.protos.Type, prop.get("type", "STRING").upper()),
                                    description=prop.get("description", "")
                                )
                                for name, prop in func["function"]["parameters"]["properties"].items()
                            },
                            required=func["function"]["parameters"].get("required", [])
                        )
                    )
                ]
            )
            tools.append(tool)
        return tools

    def _build_conversation_text(self, messages: List[Dict]) -> str:
        """Build conversation text from messages"""
        conversation_parts = []
        for msg in messages:
            role = msg["role"]
            content = msg["content"]
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
            # Check for function calls
            function_calls = []
            if hasattr(response, 'candidates') and response.candidates:
                candidate = response.candidates[0]
                if hasattr(candidate, 'content') and candidate.content.parts:
                    for part in candidate.content.parts:
                        if hasattr(part, 'function_call'):
                            function_calls.append({
                                "name": part.function_call.name,
                                "arguments": dict(part.function_call.args)
                            })

            content = response.text if hasattr(response, 'text') else "No response generated"

            return LLMResponse(
                content=content,
                function_calls=function_calls,
                metadata={"model": "gemini-2.5-flash", "provider": "google"}
            )

        except Exception as e:
            logger.error(f"❌ Error parsing Gemini response: {e}")
            return LLMResponse(
                content="I encountered an error processing your request.",
                function_calls=[],
                metadata={"error": str(e)}
            )
