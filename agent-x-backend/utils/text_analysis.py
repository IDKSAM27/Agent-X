import re
from typing import List, Dict
try:
    import nltk
    from nltk.corpus import stopwords
    from nltk.tokenize import word_tokenize, sent_tokenize
    NLTK_AVAILABLE = True
except ImportError:
    NLTK_AVAILABLE = False

class TextAnalyzer:
    def __init__(self):
        self.stop_words = set()
        if NLTK_AVAILABLE:
            try:
                self.stop_words = set(stopwords.words('english'))
            except:
                pass

    def generate_summary(self, text: str, max_length: int = 200) -> str:
        """Generate a summary of the text"""
        if not text or len(text) <= max_length:
            return text

        # Simple extractive summarization
        sentences = self._split_sentences(text)
        if not sentences:
            return text[:max_length] + "..."

        # Score sentences (simple approach)
        scored_sentences = []
        for i, sentence in enumerate(sentences):
            score = self._score_sentence(sentence, i == 0)  # First sentence bonus
            scored_sentences.append((score, sentence))

        # Sort by score and take best sentences
        scored_sentences.sort(reverse=True)

        summary = ""
        for score, sentence in scored_sentences:
            if len(summary) + len(sentence) <= max_length:
                summary += sentence + " "
            else:
                break

        return summary.strip() or text[:max_length] + "..."

    def _split_sentences(self, text: str) -> List[str]:
        """Split text into sentences"""
        if NLTK_AVAILABLE:
            try:
                return sent_tokenize(text)
            except:
                pass

        # Fallback: simple sentence splitting
        sentences = re.split(r'[.!?]+', text)
        return [s.strip() for s in sentences if s.strip()]

    def _score_sentence(self, sentence: str, is_first: bool = False) -> float:
        """Score a sentence for importance"""
        score = 0.0

        # Length bonus (not too short, not too long)
        length = len(sentence.split())
        if 8 <= length <= 25:
            score += 0.3

        # First sentence bonus
        if is_first:
            score += 0.2

        # Keyword indicators
        important_words = ['important', 'significant', 'major', 'key', 'essential']
        for word in important_words:
            if word in sentence.lower():
                score += 0.1

        return score
