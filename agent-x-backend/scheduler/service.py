import os
import json
import logging
from llm.gemini_client import GeminiClient
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

class SchedulerService:
    def __init__(self):
        self.api_key = os.getenv("GEMINI_API_KEY")
        if not self.api_key:
            logger.warning("⚠️ GEMINI_API_KEY not found for SchedulerService")
        self.client = GeminiClient(self.api_key) if self.api_key else None

    def _clean_json_response(self, response_text: str) -> dict:
        """Helper to extract and parse JSON from LLM response with advanced repair"""
        try:
            logger.info(f"Raw LLM response (first 200 chars): {response_text[:200]}...")
            
            # 1. Try simple loads first
            try:
                return json.loads(response_text)
            except json.JSONDecodeError:
                pass

            text = response_text.strip()
            
            # 2. Extract code block
            if "```" in text:
                import re
                match = re.search(r"```(?:\w+)?\s*(.*?)s*```", text, re.DOTALL)
                if match:
                    text = match.group(1)
                else:
                    parts = text.split("```")
                    if len(parts) > 1:
                        content = parts[1]
                        if content.strip().startswith("json"):
                            content = content.strip()[4:]
                        text = content

            text = text.strip()
            
            # 3. Find the JSON object start
            start = text.find("{")
            if start == -1:
                start_arr = text.find("[")
                if start_arr != -1:
                     start = start_arr
                else:
                    raise ValueError("No JSON object found")
            
            text = text[start:]

            # 4. robust state-machine repair
            # Tracks: in_string, escape, stack
            stack = []
            in_string = False
            escape = False
            
            for i, char in enumerate(text):
                if in_string:
                    if char == '"' and not escape:
                        in_string = False
                    elif char == '\\' and not escape:
                        escape = True
                    else:
                        escape = False
                else:
                    if char == '"':
                        in_string = True
                    elif char == '{':
                        stack.append('}')
                    elif char == '[':
                        stack.append(']')
                    elif char == '}' or char == ']':
                        if stack:
                            if stack[-1] == char:
                                stack.pop()
            
            # Repair based on state
            if in_string:
                text += '"'
            
            while stack:
                text += stack.pop()
            
            # 5. Fix trailing commas (common LLM error) - regex needs to be careful not to touch strings
            # But since we just repaired syntax, maybe let's trust simple regex for now as it's rare to have ", }" inside a valid string context that matches this regex
            text = re.sub(r",\s*}", "}", text)
            text = re.sub(r",\s*]", "]", text)
            
            return json.loads(text)
            
        except Exception as e:
            logger.error(f"Failed to clean JSON: {response_text} ... Error: {e}")
            raise e

    async def parse_schedule_from_image(self, file_data: bytes, mime_type: str) -> dict:
        if not self.client:
            raise Exception("Gemini API key not configured")

        prompt = """
        Analyze this image. It is a user's timetable or schedule. 
        Extract all scheduled items accurately.
        
        Return ONLY a raw JSON object with the following structure:
        {
            "name": "Suggested Schedule Name",
            "type": "academic", 
            "items": [
                {
                    "day": "Monday",
                    "start_time": "10:00",
                    "end_time": "11:00",
                    "subject": "Mathematics",
                    "type": "class",
                    "location": "Room 101" 
                }
            ]
        }
        """

        try:
            response_text = await self.client.generate_content_with_media(prompt, file_data, mime_type)
            return self._clean_json_response(response_text)
        except Exception as e:
            logger.error(f"Error parsing schedule from image: {e}")
            raise Exception(f"Failed to parse schedule: {str(e)}")

    async def parse_schedule_from_text(self, text: str) -> dict:
        if not self.client:
            raise Exception("Gemini API key not configured")

        prompt = f"""
        Analyze this text describing a schedule. 
        Extract all scheduled items accurately.
        Text: "{text}"
        
        Return ONLY a raw JSON object with the following structure:
        {{
            "name": "Suggested Schedule Name",
            "type": "academic", 
            "items": [
                {{
                    "day": "Monday",
                    "start_time": "10:00",
                    "end_time": "11:00",
                    "subject": "Mathematics",
                    "type": "class",
                    "location": "Room 101"
                }}
            ]
        }}
        """

        try:
            # Using simple chat for text
            response_text = await self.client.simple_chat(prompt)
            return self._clean_json_response(response_text)
        except Exception as e:
            logger.error(f"Error parsing schedule from text: {e}")
            raise Exception(f"Failed to parse schedule: {str(e)}")
