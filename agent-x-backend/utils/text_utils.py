import re
from bs4 import BeautifulSoup
from typing import List, Optional

def clean_html(text: str) -> str:
    """Remove HTML tags and clean text"""
    if not text:
        return ""

    # Parse HTML
    soup = BeautifulSoup(text, 'html.parser')

    # Remove scripts and styles
    for script in soup(["script", "style"]):
        script.decompose()

    # Get text and clean it
    text = soup.get_text()

    # Clean whitespace
    text = re.sub(r'\s+', ' ', text)
    text = text.strip()

    return text

def extract_text(content: str, max_length: int = 500) -> str:
    """Extract and limit text content"""
    cleaned = clean_html(content)
    if len(cleaned) <= max_length:
        return cleaned

    # Find last complete sentence within limit
    truncated = cleaned[:max_length]
    last_period = truncated.rfind('.')

    if last_period > max_length * 0.7:  # If we found a good breaking point
        return truncated[:last_period + 1]

    return truncated.rstrip() + "..."

def extract_image_urls(content: str) -> List[str]:
    """Extract image URLs from HTML content"""
    soup = BeautifulSoup(content, 'html.parser')
    images = soup.find_all('img')

    urls = []
    for img in images:
        src = img.get('src') or img.get('data-src')
        if src and src.startswith(('http', 'https')):
            urls.append(src)

    return urls
