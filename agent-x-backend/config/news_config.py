from typing import List
from models.news_models import NewsSource, NewsCategory

# Define configured news sources for the app
NEWS_SOURCES_CONFIG = {
    'rss': [
        # Global Technology and Innovation
        NewsSource(
            name="TechCrunch",
            url="https://techcrunch.com/feed/",
            type="rss",
            categories=[NewsCategory.TECHNOLOGY, NewsCategory.INDUSTRY_TRENDS],
            priority=3,
            is_active=True,
            region="global",
        ),

        NewsSource(
            name="The Verge",
            url="https://www.theverge.com/rss/index.xml",
            type="rss",
            categories=[NewsCategory.TECHNOLOGY],
            priority=2,
            is_active=True,
            region="global",
        ),

        # Education and Professional Growth
        NewsSource(
            name="EdSurge",
            url="https://edsurge.com/feed/",
            type="rss",
            categories=[NewsCategory.EDUCATION, NewsCategory.PROFESSIONAL_DEV],
            priority=3,
            is_active=True,
            region="global",
            profession="teacher",
        ),

        NewsSource(
            name="Harvard Business Review",
            url="https://hbr.org/feed",
            type="rss",
            categories=[NewsCategory.PROFESSIONAL_DEV, NewsCategory.PRODUCTIVITY],
            priority=2,
            is_active=True
        ),

        # Indian Local News & Events
        NewsSource(
            name="The Hindu",
            url="https://www.thehindu.com/news/national/feeder/default.rss",
            type="rss",
            categories=[NewsCategory.LOCAL_EVENTS, NewsCategory.INDUSTRY_TRENDS],
            priority=3,
            is_active=True,
            region="india",
        ),

        NewsSource(
            name="Times of India",
            url="https://timesofindia.indiatimes.com/rssfeeds/-2128936835.cms",
            type="rss",
            categories=[NewsCategory.TECHNOLOGY, NewsCategory.LOCAL_EVENTS],
            priority=3,
            is_active=True,
            region="india",
        ),

        # Free Online Learning Sources
        NewsSource(
            name="Coursera Blog",
            url="https://blog.coursera.org/feed/",
            type="rss",
            categories=[NewsCategory.EDUCATION, NewsCategory.CAREER_OPPORTUNITIES],
            priority=2,
            is_active=True
        ),

        # More sources can be added here with same structure
    ],

    # Any API-based sources can be configured here, for example:
    'api': [
        # Google News RSS can be added as a special source
    ],

    # Scrapers if any can be added here as well
}

# Keywords for professions to improve filtering and personalization
PROFESSION_KEYWORDS = {
    'teacher': [
        'education', 'teaching', 'classroom', 'student', 'pedagogy', 'curriculum',
        'edtech', 'assessment', 'learning', 'online courses', 'student engagement'
    ],
    'engineer': [
        'software', 'engineering', 'development', 'devops', 'machine learning',
        'automation', 'coding', 'programming', 'cloud', 'system design'
    ],
    'student': [
        'scholarship', 'internship', 'exam', 'degree', 'online courses', 'study',
        'research', 'college', 'career'
    ],
    'developer': [
        'javascript', 'flutter', 'dart', 'api', 'unix', 'rust', 'open source',
        'frontend', 'backend', 'database', 'microservices'
    ],
    # Add more professions as needed
}

# Geographic regions and cities for location-based filtering (India focused)
INDIA_REGIONS = [
    'karnataka', 'maharashtra', 'tamil nadu', 'haryana', 'delhi', 'gujarat',
    'kerala', 'punjab', 'odisha', 'west bengal', 'uttar pradesh', 'rajasthan'
]

INDIA_CITIES = [
    'bangalore', 'mumbai', 'chennai', 'delhi', 'hyderabad', 'pune', 'kolkata',
    'ahmedabad', 'jaipur', 'ludhiana', 'surat', 'nagpur', 'indore', 'thane', 'bhopal'
]

# Other configurations like cache ttl, max fetches per source etc can also be added here
CACHE_TTL_HOURS = 2
MAX_ARTICLES_PER_CATEGORY = 20
