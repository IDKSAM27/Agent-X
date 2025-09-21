import re
from typing import List, Dict, Set

class KeywordExtractor:
    def __init__(self):
        self.stop_words = {
            'the', 'this', 'that', 'with', 'from', 'your', 'have', 'will',
            'about', 'into', 'some', 'been', 'they', 'their', 'them', 'which',
            'more', 'these', 'than', 'when', 'what', 'could', 'said', 'each',
            'make', 'most', 'over', 'said', 'some', 'very', 'what', 'know'
        }

    def extract_keywords(self, text: str, max_keywords: int = 10) -> List[str]:
        """Extract keywords from text using simple frequency analysis"""
        if not text:
            return []

        # Clean and tokenize
        text_lower = text.lower()
        words = re.findall(r'\b[a-zA-Z]{3,}\b', text_lower)

        # Filter stop words
        filtered_words = [word for word in words if word not in self.stop_words]

        # Count frequency
        word_freq = {}
        for word in filtered_words:
            word_freq[word] = word_freq.get(word, 0) + 1

        # Sort by frequency and return top keywords
        sorted_words = sorted(word_freq.items(), key=lambda x: x[1], reverse=True)
        return [word for word, freq in sorted_words[:max_keywords]]
