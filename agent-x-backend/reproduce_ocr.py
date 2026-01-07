import asyncio
import io
import sys
import os
from PIL import Image

# Add current directory to path to import modules
sys.path.append(os.getcwd())

from scheduler.service import SchedulerService

IMAGE_PATH = "/home/sam/.gemini/antigravity/brain/27a68c3d-6dd9-4498-b1dc-ed554c51a98b/uploaded_image_1766333520801.png"

async def test_specific_image():
    print(f"🚀 Testing OCR on user image: {IMAGE_PATH}")
    
    if not os.path.exists(IMAGE_PATH):
        print(f"❌ Image not found at {IMAGE_PATH}")
        return

    try:
        with open(IMAGE_PATH, "rb") as f:
            image_bytes = f.read()
            
        service = SchedulerService()
        print("🔍 Extracting text...")
        text = service._extract_text_from_image(image_bytes)
        
        print("\n✨ Extracted Text Preview (first 500 chars):")
        print("-" * 40)
        print(text[:500])
        print("-" * 40)
        
        # Initialize Pillow image from bytes
        original_img = Image.open(io.BytesIO(image_bytes))
        
        rotations = [90, 180, 270] # 0 is already done
        
        for angle in rotations:
            print(f"\n🔄 Trying {angle}-degree rotation...")
            # expand=True ensures the image isn't cropped
            rotated_img = original_img.rotate(-angle, expand=True)
            
            # Convert to bytes
            buf = io.BytesIO()
            rotated_img.save(buf, format='PNG')
            rotated_bytes = buf.getvalue()
            
            text_rotated = service._extract_text_from_image(rotated_bytes)
            print(f"\n✨ Extracted Text (Rotated {angle}):")
            print("-" * 40)
            print(text_rotated[:500])
            print("-" * 40)
        
    except Exception as e:
        print(f"❌ Verification failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(test_specific_image())
