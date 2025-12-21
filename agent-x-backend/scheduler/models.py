from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class ScheduleItem(BaseModel):
    day: str
    start_time: str
    end_time: str
    subject: str
    type: str = "class" # class, internship, lab, etc.
    location: Optional[str] = None

class ScheduleCreate(BaseModel):
    name: str
    type: str # 'academic', 'work', 'other'
    items: List[ScheduleItem]

class ScheduleResponse(BaseModel):
    id: int
    firebase_uid: str
    name: str
    type: str
    items: List[ScheduleItem]
    created_at: str

class ParseRequest(BaseModel):
    text: Optional[str] = None
    # Files are handled via Form/UploadFile, so this might not be used directly if uploading file
