import os
import json
import logging
import logging
import easyocr
import easyocr
import easyocr
import io
from PIL import Image, ImageFile, ImageOps
# Enable loading truncated images to handle potential network upload issues or minor corruption
ImageFile.LOAD_TRUNCATED_IMAGES = True

try:
    import cv2
    import numpy as np
except ImportError:
    pass
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
        self._reader = None # Lazy initialization for EasyOCR

    @property
    def reader(self):
        if self._reader is None:
            logger.info("Initializing EasyOCR reader...")
            self._reader = easyocr.Reader(['en'])
        return self._reader

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

    def _extract_text_from_image(self, file_data: bytes) -> str:
        """Extract text from image bytes using EasyOCR with auto-rotation"""
        try:
            logger.info(f"Received file_data of size: {len(file_data)} bytes")
            logger.info(f"First 20 bytes: {file_data[:20]}")
            
            # Use Pillow to decode image bytes
            try:
                original_image = Image.open(io.BytesIO(file_data))
                
                # Correct orientation based on EXIF data
                # This is critical for phone uploads which often have rotation metadata
                original_image = ImageOps.exif_transpose(original_image)
                
                # Convert to RGB to ensure consistency (e.g. if indexed color or RGBA)
                if original_image.mode != 'RGB':
                    original_image = original_image.convert('RGB')
                
            except Exception as pil_error:
                logger.error(f"Pillow decoding failed: {pil_error}")
                # Save failed bytes for inspection if really needed, but error message usually enough
                raise ValueError(f"Could not decode image bytes: {pil_error}")

            # Try extracting text with different rotations if needed
            # Priority: 0 (standard), 90 CCW (common landscape), 90 CW, 180
            # Note: PIL rotate argument is Counter-Clockwise
            rotations = [0, 90, 270, 180] 
            
            best_text = ""
            best_keyword_count = -1

            for angle in rotations:
                logger.info(f"Attempting OCR with rotation: {angle} degrees")
                
                if angle == 0:
                    img_to_process = original_image
                else:
                    img_to_process = original_image.rotate(angle, expand=True)

                img_np = np.array(img_to_process)
                result = self.reader.readtext(img_np, detail=0)
                text = " ".join(result)
                
                # Check quality
                keywords = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", 
                           "time", "table", "class", "room", "subject", "am", "pm", "schedule", "course", "sem"]
                text_lower = text.lower()
                keyword_count = sum(1 for k in keywords if k in text_lower)
                
                logger.info(f"Rotation {angle} extracted {len(text)} chars, keyword_count: {keyword_count}")
                logger.info(f"Sample: {text[:50]}...")

                if keyword_count > best_keyword_count:
                    best_keyword_count = keyword_count
                    best_text = text
                
                # If we found a good match, stop early to save time
                if keyword_count >= 3:
                     logger.info(f"✅ Found good text orientation at {angle} degrees")
                     return text

            if not best_text.strip():
                 raise ValueError("No text extracted from image (all rotations failed)")
            
            logger.info(f"Returning best text found (keywords={best_keyword_count})")
            return best_text
        except Exception as e:
            logger.error(f"EasyOCR extraction failed: {e}")
            raise Exception(f"OCR failed: {str(e)}")

    async def parse_schedule_from_image(self, file_data: bytes, mime_type: str) -> dict:
        if not self.client:
            raise Exception("Gemini API key not configured")

        try:
            # 1. Local OCR Extraction
            extracted_text = self._extract_text_from_image(file_data)
            
            if not extracted_text.strip():
                 raise ValueError("No text extracted from image")

            # 2. Parse using LLM with text prompt
            return await self.parse_schedule_from_text(extracted_text)
            
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
