from sqlalchemy import Column, Integer, String, Text, ForeignKey
from sqlalchemy.orm import relationship
from database.connection import Base

class Schedule(Base):
    __tablename__ = "schedules"

    id = Column(Integer, primary_key=True, index=True)
    firebase_uid = Column(String, nullable=False, index=True)
    name = Column(String, nullable=False)
    type = Column(String, default="academic") # academic, internship
    created_at = Column(String, nullable=False)
    
    items = relationship("ScheduleItem", back_populates="schedule", cascade="all, delete-orphan")

class ScheduleItem(Base):
    __tablename__ = "schedule_items"

    id = Column(Integer, primary_key=True, index=True)
    schedule_id = Column(Integer, ForeignKey("schedules.id"), nullable=False)
    day = Column(String, nullable=False)
    start_time = Column(String, nullable=False)
    end_time = Column(String, nullable=False)
    subject = Column(String, nullable=False)
    type = Column(String, default="class")
    location = Column(String, nullable=True)

    schedule = relationship("Schedule", back_populates="items")
