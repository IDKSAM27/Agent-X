import re
from datetime import datetime, timedelta
from typing import Dict, Optional

class EventDetector:
    def __init__(self):
        self.location_keywords = [
            'bangalore', 'mumbai', 'delhi', 'pune', 'hyderabad', 'chennai',
            'kolkata', 'ahmedabad', 'india', 'karnataka', 'maharashtra'
        ]

        self.event_keywords = [
            'conference', 'meetup', 'workshop', 'seminar', 'event', 'summit',
            'symposium', 'webinar', 'training', 'course'
        ]

    def detect_event(self, text: str) -> Dict[str, any]:
        """Detect event-related information in text"""
        text_lower = text.lower()

        result = {
            'is_local_event': False,
            'is_urgent': False,
            'event_date': None,
            'location': None,
            'deadline': None
        }

        # Check for event keywords
        has_event_keyword = any(keyword in text_lower for keyword in self.event_keywords)

        # Check for location keywords
        location_found = None
        for location in self.location_keywords:
            if location in text_lower:
                location_found = location
                break

        if has_event_keyword and location_found:
            result['is_local_event'] = True
            result['location'] = location_found

        # Simple date detection (dd/mm/yyyy or similar patterns)
        date_patterns = [
            r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b',
            r'\b(\d{4})[/-](\d{1,2})[/-](\d{1,2})\b',
            r'\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\s+(\d{4})\b'
        ]

        for pattern in date_patterns:
            match = re.search(pattern, text_lower)
            if match:
                try:
                    if 'jan' in pattern:  # Month name pattern
                        day = int(match.group(1))
                        month_str = match.group(2)
                        year = int(match.group(3))
                        month_map = {
                            'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
                            'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
                        }
                        month = month_map.get(month_str, 1)
                        result['event_date'] = datetime(year, month, day)
                    else:  # Numeric date pattern
                        parts = [int(x) for x in match.groups()]
                        if len(parts) == 3:
                            # Try different date formats
                            if parts[2] > 31:  # yyyy/mm/dd format
                                result['event_date'] = datetime(parts[0], parts[1], parts[2])
                            else:  # dd/mm/yyyy format
                                result['event_date'] = datetime(parts[2], parts[1], parts[0])

                    # Check if urgent (within 7 days)
                    if result['event_date']:
                        days_until = (result['event_date'] - datetime.now()).days
                        if 0 <= days_until <= 7:
                            result['is_urgent'] = True

                    break
                except (ValueError, TypeError):
                    continue

        # Detect registration deadlines
        deadline_patterns = [
            r'deadline[:\s]+(\d{1,2})[/-](\d{1,2})[/-](\d{4})',
            r'register\s+by[:\s]+(\d{1,2})[/-](\d{1,2})[/-](\d{4})',
            r'last\s+date[:\s]+(\d{1,2})[/-](\d{1,2})[/-](\d{4})'
        ]

        for pattern in deadline_patterns:
            match = re.search(pattern, text_lower)
            if match:
                try:
                    day, month, year = map(int, match.groups())
                    result['deadline'] = datetime(year, month, day)
                    break
                except (ValueError, TypeError):
                    continue

        return result
