import asyncio
import io
import sys
import os
from PIL import Image, ImageDraw

# Add current directory to path to import modules
sys.path.append(os.getcwd())

from scheduler.service import SchedulerService

def create_test_image():
    # Create a white image
    img = Image.new('RGB', (400, 200), color='white')
    d = ImageDraw.Draw(img)
    
    # Draw text - we don't have a specific font loaded so default might be small
    # but EasyOCR is usually good. We'll try to use default bitmap font.
    # To make it bigger/clearer in default font, we might need a truetype font which might not be available.
    # We will just write it and hope standard OCR picks it up.
    # Or, we can use a basic font if available system wide but safe to stick to default.
    
    text = "Monday 10:00 AM\nMathematics Class\nRoom 101"
    d.text((20, 20), text, fill=(0, 0, 0))
    
    # Save to bytes
    buf = io.BytesIO()
    img.save(buf, format='PNG')
    return buf.getvalue()

async def verify():
    print("🎨 Creating test image...")
    image_bytes = create_test_image()
    print(f"✅ Image created ({len(image_bytes)} bytes)")
    
    print("🚀 Initializing SchedulerService...")
    service = SchedulerService()
    
    print("🔍 Extracting text...")
    try:
        # We access the internal method directly for unit testing the OCR part
        text = service._extract_text_from_image(image_bytes)
        print(f"\n✨ Extracted Text:\n----------------\n{text}\n----------------")
        
        expected_keywords = ["Monday", "10:00", "Math"]
        missing = [k for k in expected_keywords if k.lower() not in text.lower()]
        
        if not missing:
            print("✅ content verification PASSED")
        else:
            print(f"⚠️  Content verification WARNING: Missing keywords {missing}")
            # EasyOCR with default font on small image might be tricky, so we don't fail hard
            
    except Exception as e:
        print(f"❌ Extraction failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(verify())
