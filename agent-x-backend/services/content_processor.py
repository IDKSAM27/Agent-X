import re
from typing import List, Dict, Optional
from datetime import datetime
import logging

from models.news_models import (
    RawArticle,
    ProcessedArticle,
    NewsCategory,
    NewsAction,
    ActionType,
    UserProfile,
)

logger = logging.getLogger(__name__)

class ContentProcessor:
    """Processes raw news articles into enriched, personalized content."""

    def __init__(self):
        # Initialize any NLP tools or resources here
        # You can add nltk or spacy initialization if required
        pass

    async def process_articles(self, raw_articles: List[RawArticle], user_profile: UserProfile) -> List[ProcessedArticle]:
        """Process a list of raw articles considering user profile and returns processed articles."""
        processed_articles = []

        for raw in raw_articles:
            try:
                processed = await self._process_single_article(raw, user_profile)
                if processed and self._meets_quality_threshold(processed):
                    processed_articles.append(processed)
            except Exception as e:
                logger.error(f"Error processing article '{raw.title}': {e}")

        # Sort articles by combined score (weighted)
        processed_articles.sort(
            key=lambda a: a.relevance_score * 0.6 + a.quality_score * 0.4,
            reverse=True
        )
        # Limit to top 100 for performance
        return processed_articles[:100]

    async def _process_single_article(self, raw: RawArticle, user_profile: UserProfile) -> Optional[ProcessedArticle]:
        # Combine text fields to analyze
        content_text = " ".join(filter(None, [raw.title, raw.description, raw.content or ""]))

        # Clean and summarize content, can leverage NLP here
        summary = self._generate_summary(raw.description or raw.content or "")

        # Extract keywords e.g. via simple frequency or NLP-based extraction
        keywords = self._extract_keywords(content_text)

        # Determine category
        category = self._classify_category(content_text, keywords, user_profile.profession)

        # Detect event details in text, dates and locations
        event_info = self._detect_event_info(content_text)

        # Calculate relevance to user
        relevance_score = self._calculate_relevance_score(content_text, keywords, user_profile)

        # Determine quality (length, source, freshness)
        quality_score = self._calculate_quality_score(raw, content_text)

        # Generate possible actions user can take
        actions = self._generate_actions(content_text, event_info, category)

        processed = ProcessedArticle(
            id="",
            title=raw.title,
            description=raw.description,
            summary=summary,
            url=raw.url,
            image_url=raw.image_url,
            published_at=raw.published_at,
            source=raw.source,
            category=category,
            relevance_score=relevance_score,
            quality_score=quality_score,
            engagement_score=0.0,  # for future
            tags=keywords,  # reuse as simple tags
            keywords=keywords,
            is_local_event=event_info.get("is_local", False),
            is_urgent=event_info.get("is_urgent", False),
            event_date=event_info.get("date"),
            event_location=event_info.get("location"),
            event_deadline=event_info.get("deadline"),
            available_actions=actions,
        )
        return processed

    def _generate_summary(self, text: str, max_length: int = 150) -> str:
        """Generates a simple summary, limiting length and preserving sentences."""
        if not text:
            return ""

        # Strip HTML tags, use regex or any utility function if you have
        plain_text = re.sub(r'<.*?>', '', text)

        if len(plain_text) <= max_length:
            return plain_text

        # Try to cut off at sentence boundary
        sentences = re.split(r'(?<=[.!?]) +', plain_text)
        summary = ""
        for sentence in sentences:
            if len(summary) + len(sentence) <= max_length:
                summary += sentence + " "
            else:
                break

        return summary.strip()

    def _extract_keywords(self, text: str) -> List[str]:
        """Extracts keywords from text - basic implementation."""
        text = text.lower()
        words = re.findall(r'\b\w{4,}\b', text)  # Words with 4+ letters
        stopwords = set([
            "the", "this", "that", "with", "from", "your", "have",
            "will", "about", "into", "some", "been", "they", "their",
            "them", "which", "more", "these", "than", "when", "what",
        ])

        filtered = [w for w in words if w not in stopwords]

        # Frequency count
        freq = {}
        for word in filtered:
            freq[word] = freq.get(word, 0) + 1

        # Return top 10 keywords
        sorted_keys = sorted(freq.items(), key=lambda x: x[1], reverse=True)
        return [word for word, count in sorted_keys[:10]]

    def _classify_category(self, text: str, keywords: List[str], profession: str) -> NewsCategory:
        """Simple rule based classification."""
        text = text.lower()

        event_keywords = {"conference", "meetup", "workshop", "seminar", "event", "summit"}
        if any(word in text for word in event_keywords):
            return NewsCategory.LOCAL_EVENTS

        career_keywords = {"job", "career", "vacancy", "hiring", "opportunity"}
        if any(word in text for word in career_keywords):
            return NewsCategory.CAREER_OPPORTUNITIES

        education_keywords = {"course", "training", "learning", "education", "certification"}
        if any(word in text for word in education_keywords):
            return NewsCategory.EDUCATION

        tech_keywords = {"technology", "software", "hardware", "innovation", "ai", "machine learning"}
        if any(word in text for word in tech_keywords):
            return NewsCategory.TECHNOLOGY

        if profession.lower() in text:
            return NewsCategory.PROFESSIONAL_DEV

        productivity_keywords = {"productivity", "efficiency", "tool", "method", "technique"}
        if any(word in text for word in productivity_keywords):
            return NewsCategory.PRODUCTIVITY

        return NewsCategory.INDUSTRY_TRENDS

    def _detect_event_info(self, text: str) -> Dict[str, Optional[any]]:
        """Detects event-related information: date, location, urgency."""
        # Basic date detection via regex (can be enhanced)
        from datetime import datetime, timedelta

        result = {
            "is_local": False,
            "is_urgent": False,
            "date": None,
            "location": None,
            "deadline": None
        }

        # Simple date pattern matching dd/mm/yyyy or similar
        date_match = re.search(r'(\b\d{1,2}[/-]\d{1,2}[/-]\d{4}\b)', text)
        if date_match:
            try:
                dt = datetime.strptime(date_match.group(1), "%d/%m/%Y")
                result["date"] = dt
                if dt <= datetime.now() + timedelta(days=7):
                    result["is_urgent"] = True
            except Exception:
                pass

        # Check for location keywords (simplified)
        locations = ["india", "bangalore", "mumbai", "delhi", "karnataka", "belagavi"]
        if any(loc in text.lower() for loc in locations):
            result["is_local"] = True
            result["location"] = next(filter(lambda l: l in text.lower(), locations), None)

        # Detect deadlines
        deadline_match = re.search(r'deadline[: ]+(\d{1,2}[/-]\d{1,2}[/-]\d{4})', text, re.I)
        if deadline_match:
            try:
                result["deadline"] = datetime.strptime(deadline_match.group(1), "%d/%m/%Y")
            except Exception:
                pass

        return result

    def _calculate_relevance_score(self, text: str, keywords: List[str], profile: UserProfile) -> float:
        """Calculate relevance of article content to user profile."""
        score = 0.0
        text_lc = text.lower()

        # Profession match
        if profile.profession.lower() in text_lc:
            score += 0.3

        # Location match
        if profile.location.lower() in text_lc:
            score += 0.2

        # Interests match
        interests_score = sum(1 for i in profile.interests if i.lower() in text_lc)
        score += min(interests_score * 0.05, 0.25)

        # Keywords in profession list (simplify for demo)
        prof_keywords = {
            "teacher": ["education", "learning", "student"],
            "engineer": ["technology", "software", "development"],
            "student": ["scholarship", "degree", "exam"],
            "developer": ["programming", "coding", "framework"],
        }
        if profile.profession.lower() in prof_keywords:
            prof_keys = prof_keywords[profile.profession.lower()]
            key_matches = sum(1 for k in keywords if k in prof_keys)
            score += min(key_matches * 0.05, 0.25)

        return min(score, 1.0)

    def _calculate_quality_score(self, raw: RawArticle, text: str) -> float:
        """Estimate article quality (length, source, freshness)"""
        score = 0.5
        length = len(text)
        if length > 500:
            score += 0.1
        elif length > 1000:
            score += 0.15

        # Known reputable sources boost
        reputable_sources = {"bbc", "reuters", "the hindu", "times of india", "techcrunch"}
        if any(src in raw.source.lower() for src in reputable_sources):
            score += 0.2

        age_hours = (datetime.now() - raw.published_at).total_seconds() / 3600
        if age_hours < 24:
            score += 0.1
        elif age_hours < 72:
            score += 0.05

        # Check for image availability
        if raw.image_url:
            score += 0.1

        return min(score, 1.0)

    def _generate_actions(self, text: str, event_info: Dict, category: NewsCategory) -> List[NewsAction]:
        """Determine actionable items user can take."""
        actions = []

        # Add calendar event action
        if event_info.get("is_local", False):
            actions.append(NewsAction(
                type=ActionType.ADD_TO_CALENDAR,
                label="Add to Calendar",
                icon="calendar_today",
                color="#2196F3",
                metadata={"date": event_info.get("date")}
            ))

        # Add task action for learning content
        if "course" in text.lower() or "tutorial" in text.lower() or "learning" in text.lower():
            actions.append(NewsAction(
                type=ActionType.CREATE_TASK,
                label="Create Learning Task",
                icon="task_alt",
                color="#4CAF50",
                metadata={"type": "learning"}
            ))

        # Add reminders for deadlines
        if event_info.get("deadline"):
            actions.append(NewsAction(
                type=ActionType.SET_REMINDER,
                label="Set Reminder",
                icon="notifications",
                color="#FF9800",
                metadata={"deadline": event_info["deadline"]}
            ))

        # Career related follow-ups
        if any(word in text.lower() for word in ["job", "career", "hiring", "apply"]):
            actions.append(NewsAction(
                type=ActionType.CREATE_TASK,
                label="Create Career Task",
                icon="work",
                color="#9C27B0",
                metadata={"type": "career"}
            ))

        return actions[:3]  # Limit to max 3 actions

    def _meets_quality_threshold(self, article: ProcessedArticle) -> bool:
        """Check if article passes quality filter."""
        if article.quality_score < 0.3:
            return False
        if len(article.title) < 10 or len(article.description) < 20:
            return False
        spam_indicators = ["click here", "buy now", "free trial", "subscribe now", "limited time"]
        text = f"{article.title} {article.description}".lower()
        if any(s in text for s in spam_indicators):
            return False
        return True
