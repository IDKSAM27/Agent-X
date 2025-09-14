from typing import Dict, Any
from datetime import datetime
from .base import BaseFunctionExecutor
from ..database.operations import save_task, get_user_tasks
import logging

logger = logging.getLogger(__name__)

class TaskFunctions(BaseFunctionExecutor):
    """Handle task-related function calls"""

    async def execute(self, function_name: str, firebase_uid: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Execute task function"""
        try:
            if function_name == "create_task":
                return await self._create_task(firebase_uid, arguments)
            elif function_name == "get_tasks":
                return await self._get_tasks(firebase_uid, arguments)
            else:
                return self._error_response(f"Unknown task function: {function_name}")

        except Exception as e:
            logger.error(f"❌ Task function error: {e}")
            return self._error_response(str(e))

    async def _create_task(self, firebase_uid: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new task"""
        title = args.get("title", "").strip()
        if not title:
            return self._error_response("Task title is required")

        priority = args.get("priority", "medium")
        due_date = args.get("due_date")

        task_id = save_task(
            firebase_uid=firebase_uid,
            title=title,
            description="",
            priority=priority
        )

        logger.info(f"✅ LLM created task: {title} for {firebase_uid}")

        return self._success_response(
            f"Task '{title}' created with {priority} priority",
            {
                "task_id": task_id,
                "title": title,
                "priority": priority,
                "due_date": due_date,
                "created_at": datetime.now().isoformat()
            }
        )

    async def _get_tasks(self, firebase_uid: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Get user tasks"""
        status = args.get("status", "pending")

        tasks = get_user_tasks(firebase_uid, status)

        if not tasks:
            return self._success_response(
                "No tasks found",
                {"tasks": [], "count": 0}
            )

        formatted_tasks = []
        for task in tasks:
            task_id, title, description, priority, created_at, due_date = task
            formatted_tasks.append({
                "id": task_id,
                "title": title,
                "priority": priority,
                "created_at": created_at,
                "due_date": due_date
            })

        return self._success_response(
            f"Found {len(tasks)} tasks",
            {
                "tasks": formatted_tasks,
                "count": len(tasks)
            }
        )
