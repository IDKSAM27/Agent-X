from abc import ABC, abstractmethod
from typing import Dict, Any

class BaseFunctionExecutor(ABC):
    """Abstract base class for function executors"""

    @abstractmethod
    async def execute(self, function_name: str, firebase_uid: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Execute a function with given arguments"""
        pass

    def _success_response(self, message: str, data: Dict = None) -> Dict[str, Any]:
        """Standard success response"""
        return {
            "success": True,
            "message": message,
            "data": data or {}
        }

    def _error_response(self, error: str) -> Dict[str, Any]:
        """Standard error response"""
        return {
            "success": False,
            "error": error
        }
