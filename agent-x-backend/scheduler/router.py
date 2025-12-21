from fastapi import APIRouter, Depends, File, UploadFile, HTTPException, Body
from typing import List, Optional
from .models import ScheduleCreate, ScheduleResponse, ParseRequest
from .service import SchedulerService
from .db import create_schedule, get_user_schedules, get_schedule_by_id, delete_schedule
from dependencies import get_current_user

router = APIRouter(prefix="/api/scheduler", tags=["scheduler"])

scheduler_service = SchedulerService()

@router.post("/parse")
async def parse_schedule(
    file: Optional[UploadFile] = File(None),
    text: Optional[str] = Body(None),
    current_user: dict = Depends(get_current_user)
):
    """Parse a schedule from Image/PDF or Text"""
    try:
        if file:
            content = await file.read()
            mime_type = file.content_type
            result = await scheduler_service.parse_schedule_from_image(content, mime_type)
            return {"status": "success", "data": result}
        elif text:
            result = await scheduler_service.parse_schedule_from_text(text)
            return {"status": "success", "data": result}
        else:
            raise HTTPException(status_code=400, detail="Must provide either file or text")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/schedules", response_model=ScheduleResponse)
async def create_new_schedule(
    schedule_data: ScheduleCreate,
    current_user: dict = Depends(get_current_user)
):
    """Create a new schedule"""
    try:
        uid = current_user["firebase_uid"]
        new_schedule = create_schedule(uid, schedule_data)
        return new_schedule
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/schedules")
async def list_schedules(current_user: dict = Depends(get_current_user)):
    """List user schedules"""
    try:
        uid = current_user["firebase_uid"]
        schedules = get_user_schedules(uid)
        return {"status": "success", "schedules": schedules}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/schedules/{schedule_id}")
async def get_schedule(schedule_id: int, current_user: dict = Depends(get_current_user)):
    try:
        schedule = get_schedule_by_id(schedule_id)
        if not schedule:
            raise HTTPException(status_code=404, detail="Schedule not found")
        return {"status": "success", "schedule": schedule}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/schedules/{schedule_id}")
async def remove_schedule(schedule_id: int, current_user: dict = Depends(get_current_user)):
    try:
        uid = current_user["firebase_uid"]
        success = delete_schedule(schedule_id, uid)
        if not success:
            raise HTTPException(status_code=404, detail="Schedule not found")
        return {"status": "success", "message": "Schedule deleted"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
