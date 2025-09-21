import asyncio
import sys

async def test_imports():
    """Test that all required modules can be imported"""
    try:
        import feedparser
        print("✅ feedparser imported successfully")

        import aiohttp
        print("✅ aiohttp imported successfully")

        from bs4 import BeautifulSoup
        print("✅ BeautifulSoup imported successfully")

        import nltk
        print("✅ NLTK imported successfully")

        # Test NLTK data
        from nltk.corpus import stopwords
        stopwords.words('english')[:5]
        print("✅ NLTK data available")

        print("\n🎉 All dependencies are properly installed!")
        return True

    except ImportError as e:
        print(f"❌ Missing dependency: {e}")
        return False
    except Exception as e:
        print(f"⚠️  Setup issue: {e}")
        print("💡 You may need to run: python -c \"import nltk; nltk.download('punkt'); nltk.download('stopwords')\"")
        return False

if __name__ == "__main__":
    asyncio.run(test_imports())
