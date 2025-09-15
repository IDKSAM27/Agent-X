from typing import Dict, Any
from datetime import datetime
from functions.base import BaseFunctionExecutor
from database.operations import save_task, get_user_tasks
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
        """Create a task"""
        title = args.get("title", "").strip()
        description = args.get("description", "")
        priority = args.get("priority", "medium")
        category = args.get("category", "general")
        due_date = args.get("due_date", None)

        if not title:
            return self._error_response("Task title is required")

        try:
            task_id = save_task(
                firebase_uid=firebase_uid,
                title=title,
                description=description,
                priority=priority,
                category=category,
                due_date=due_date
            )

            logger.info(f"✅ LLM created task: {title} for {firebase_uid}")

            due_text = f" (due {due_date})" if due_date else ""
            priority_emoji = "🔥" if priority == "high" else "⚡" if priority == "medium" else "📝"

            return self._success_response(
                f"✅ Created {priority} priority task: '{title}'{due_text}",
                {
                    "task_id": task_id,
                    "title": title,
                    "priority": priority,
                    "category": category,
                    "due_date": due_date,
                    "emoji": priority_emoji
                }
            )

        except Exception as e:
            logger.error(f"❌ Error creating task: {e}")
            return self._error_response(f"Failed to create task: {str(e)}")


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
