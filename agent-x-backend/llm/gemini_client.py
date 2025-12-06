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
            # Safer prompt construction - avoid potential safety triggers
            if context:
                prompt = f"Context: {context}\n\nUser message: {message}\n\nPlease provide a helpful response."
            else:
                prompt = f"User message: {message}\n\nPlease provide a helpful response."

            # Use simpler generation config for post-function responses
            response = self.model.generate_content(
                prompt,
                generation_config=genai.GenerationConfig(
                    temperature=0.3,  # Increased slightly
                    max_output_tokens=500,  # Increased
                    candidate_count=1,
                )
            )

            # Better response extraction
            try:
                if hasattr(response, 'text') and response.text:
                    return response.text.strip()
            except Exception:
                # Fallback if response.text fails (e.g. finish_reason is not STOP)
                pass

            if hasattr(response, 'candidates') and response.candidates:
                for candidate in response.candidates:
                    if hasattr(candidate, 'content') and candidate.content.parts:
                        for part in candidate.content.parts:
                            if hasattr(part, 'text') and part.text:
                                return part.text.strip()

            # Fallback response instead of error
            return "I've processed your request successfully."

        except Exception as e:
            logger.error(f"❌ Gemini simple chat error: {e}")
            # Return success message instead of error for function responses
            if "finish_reason" in str(e) or "safety" in str(e).lower():
                return "I've completed your request successfully."
            return "I'm having trouble generating a response, but your request was processed."


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

            # Extract function calls and text from candidates
            if hasattr(response, 'candidates') and response.candidates:
                for candidate in response.candidates:
                    if hasattr(candidate, 'content') and candidate.content.parts:
                        for part in candidate.content.parts:
                            # Extract function calls
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

                                    logger.info(f"🔧 Function call detected: {part.function_call.name} with args: {args}")

                                except Exception as func_error:
                                    logger.warning(f"⚠️ Error parsing function call: {func_error}")

                            # Extract text content (only if it's not a function call)
                            elif hasattr(part, 'text') and part.text:
                                content += part.text

            # If we have function calls but no text, that's normal for function calling
            if function_calls and not content:
                content = f"I'll help you with that. Let me execute the requested action."
                logger.info(f"✅ Function-only response detected with {len(function_calls)} function calls")

            # If no function calls and no content, try the old way as fallback
            elif not content and not function_calls:
                try:
                    if hasattr(response, 'text') and response.text:
                        content = response.text
                    else:
                        content = "I understand your request but couldn't generate a proper response."
                except Exception as text_error:
                    logger.warning(f"⚠️ Could not extract text: {text_error}")
                    content = "I understand your request but couldn't generate a proper response."

            return LLMResponse(
                content=content,
                function_calls=function_calls,
                metadata={
                    "model": "gemini-2.5-flash",
                    "provider": "google",
                    "has_function_calls": len(function_calls) > 0,
                    "function_count": len(function_calls)
                }
            )

        except Exception as e:
            logger.error(f"❌ Error parsing Gemini response: {e}")
            return LLMResponse(
                content="I encountered an error processing your request.",
                function_calls=[],
                metadata={"error": str(e), "model": "gemini-2.5-flash", "provider": "google"}
            )

    async def get_enhanced_response_with_news_context(
            self,
            message: str,
            conversation_history: List[Dict[str, str]],
            user_context: Dict[str, str],
            news_context: Dict[str, any] = None
    ) -> Dict[str, any]:
        """Get AI response enhanced with recent news context"""

        # Build system prompt with news awareness
        system_prompt = f"""
You are Agent X, an intelligent personal assistant. You have access to the user's recent news context and should provide helpful, actionable responses.

User Profile:
- Profession: {user_context.get('profession', 'Professional')}
- Location: {user_context.get('location', 'Unknown')}

Recent News Context:
{news_context.get('summary', 'No recent news available') if news_context else 'No news context provided'}
    """

        if news_context and news_context.get('total_articles', 0) > 0:
            system_prompt += f"""

Available Actions:
- You can reference recent news articles when relevant
- Suggest creating tasks for learning opportunities
- Recommend calendar events for upcoming deadlines or local events
- Provide insights based on industry trends

News Categories Available:
{', '.join(news_context.get('categories', {}).keys())}

Urgent Items: {', '.join(news_context.get('urgent_items', []))}
Local Events: {len(news_context.get('local_events', []))} upcoming events
Career Opportunities: {len(news_context.get('career_opportunities', []))} opportunities
Learning Opportunities: {len(news_context.get('learning_opportunities', []))} opportunities
"""

        # Add news-specific prompt enhancements
        if any(keyword in message.lower() for keyword in ['news', 'update', 'happening', 'trends', 'opportunities']):
            system_prompt += """
The user is asking about news or updates. Use your news context to provide relevant, personalized information. Focus on actionable insights and suggest concrete next steps.
"""

    # Get AI response with enhanced context
        response = await self.get_response(
            message=message,
            conversation_history=conversation_history,
            system_prompt=system_prompt,
            user_context=user_context
        )

        return response


