from typing import Dict, Any
from .base import BaseFunctionExecutor
from ..database.operations import save_user_name, get_user_name
import logging

logger = logging.getLogger(__name__)

class MemoryFunctions(BaseFunctionExecutor):
    """Handle memory/user info related function calls"""

    async def execute(self, function_name: str, firebase_uid: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Execute memory function"""
        try:
            if function_name == "save_user_info":
                return await self._save_user_info(firebase_uid, arguments)
            else:
                return self._error_response(f"Unknown memory function: {function_name}")

        except Exception as e:
            logger.error(f"❌ Memory function error: {e}")
            return self._error_response(str(e))

    async def _save_user_info(self, firebase_uid: str, args: Dict[str, Any]) -> Dict[str, Any]:
        """Save user information"""
        name = args.get("name", "").strip()
        info_type = args.get("info_type", "name")

        if not name:
            return self._error_response("Name is required")

        if info_type == "name":
            save_user_name(firebase_uid, name, "Professional")

            logger.info(f"✅ LLM saved user name: {name} for {firebase_uid}")

            return self._success_response(
                f"I've saved your name as {name}",
                {
                    "name": name,
                    "info_type": info_type
                }
            )

        return self._error_response(f"Unsupported info type: {info_type}")
