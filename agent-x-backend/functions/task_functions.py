from typing import Dict, Any
from datetime import datetime
import json
import logging
from functions.base import BaseFunctionExecutor
from database.operations import save_task, get_user_tasks

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
            status_text = {
                "pending": "📋 You don't have any pending tasks! Great job staying on top of things.",
                "completed": "📋 No completed tasks yet. Start checking some off!",
                "all": "📋 No tasks yet. Create your first task to get started!"
            }.get(status, "📋 No tasks found.")

            return self._success_response(
                status_text,
                {"tasks": [], "count": 0}
            )

        # ✅ Fixed unpacking to match database schema
        formatted_tasks = []
        task_summaries = []

        for task in tasks:
            # Unpack all 9 columns returned by get_user_tasks
            (task_id, title, description, priority, category, due_date,
             is_completed, progress, created_at) = task

            # Parse tags safely
            try:
                tags = []  # Default to empty since we don't store tags yet
            except Exception:
                tags = []

            formatted_tasks.append({
                "id": task_id,
                "title": title,
                "description": description,
                "priority": priority,
                "category": category,
                "due_date": due_date,
                "is_completed": bool(is_completed),
                "progress": float(progress) if progress else 0.0,
                "tags": tags,
                "created_at": created_at,
            })

            # Create summary for natural response
            priority_emoji = "🔥" if priority == "high" else "⚡" if priority == "medium" else "📝"
            status_emoji = "✅" if is_completed else "📋"
            due_text = f" (due {due_date})" if due_date else ""

            task_summaries.append(f"{status_emoji} {priority_emoji} **{title}**{due_text}")

        # Create natural response message
        total_tasks = len(tasks)
        completed_count = sum(1 for task in formatted_tasks if task["is_completed"])
        pending_count = total_tasks - completed_count

        if status == "pending":
            message_header = f"📋 **Your Pending Tasks ({pending_count} total):**"
        elif status == "completed":
            message_header = f"✅ **Your Completed Tasks ({completed_count} total):**"
        else:
            message_header = f"📋 **All Your Tasks ({total_tasks} total):**\n*{completed_count} completed, {pending_count} pending*"

        detailed_message = f"{message_header}\n\n" + "\n".join(task_summaries)

        return self._success_response(
            detailed_message,
            {
                "tasks": formatted_tasks,
                "count": total_tasks,
                "completed": completed_count,
                "pending": pending_count
            }
        )
