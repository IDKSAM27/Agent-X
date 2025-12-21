from sqlalchemy.orm import Session, joinedload
from database.connection import SessionLocal, engine
from .db_models import Schedule, ScheduleItem, Base
from .models import ScheduleCreate
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

def init_scheduler_db():
    Base.metadata.create_all(bind=engine)
    logger.info("✅ Scheduler tables created/verified")

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def create_schedule(firebase_uid: str, schedule_data: ScheduleCreate) -> Schedule:
    db = SessionLocal()
    try:
        now = datetime.now().isoformat()
        db_schedule = Schedule(
            firebase_uid=firebase_uid,
            name=schedule_data.name,
            type=schedule_data.type,
            created_at=now
        )
        db.add(db_schedule)
        db.commit()
        db.refresh(db_schedule)

        for item in schedule_data.items:
            db_item = ScheduleItem(
                schedule_id=db_schedule.id,
                day=item.day,
                start_time=item.start_time,
                end_time=item.end_time,
                subject=item.subject,
                type=item.type,
                location=item.location
            )
            db.add(db_item)
        
        db.commit()
        db.refresh(db_schedule)
        
        # Force load items to avoid DetachedInstanceError
        _ = db_schedule.items
        
        logger.info(f"✅ Created schedule {db_schedule.id} for {firebase_uid}")
        return db_schedule
    except Exception as e:
        logger.error(f"❌ Error creating schedule: {e}")
        db.rollback()
        raise e
    finally:
        db.close()

def get_user_schedules(firebase_uid: str):
    db = SessionLocal()
    try:
        schedules = db.query(Schedule).options(joinedload(Schedule.items)).filter(Schedule.firebase_uid == firebase_uid).all()
        return schedules
    finally:
        db.close()

def get_schedule_by_id(schedule_id: int):
    db = SessionLocal()
    try:
        schedule = db.query(Schedule).options(joinedload(Schedule.items)).filter(Schedule.id == schedule_id).first()
        return schedule
    finally:
        db.close()

def delete_schedule(schedule_id: int, firebase_uid: str) -> bool:
    db = SessionLocal()
    try:
        schedule = db.query(Schedule).filter(Schedule.id == schedule_id, Schedule.firebase_uid == firebase_uid).first()
        if schedule:
            db.delete(schedule)
            db.commit()
            return True
        return False
    finally:
        db.close()
