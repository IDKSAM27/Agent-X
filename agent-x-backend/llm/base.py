from abc import ABC, abstractmethod
from typing import Dict, List, Any, Optional

class LLMResponse:
    """Data class for LLM responses"""
    def __init__(self, content: str, function_calls: Optional[List[Dict]] = None, metadata: Optional[Dict] = None):
        self.content = content
        self.function_calls = function_calls or []
        self.metadata = metadata or {}

class BaseLLMClient(ABC):
    """Abstract base class for LLM clients (Interface Segregation Principle)"""

    @abstractmethod
    async def generate_response(self, messages: List[Dict], functions: List[Dict]) -> LLMResponse:
        """Generate response with function calling support"""
        pass

    @abstractmethod
    async def simple_chat(self, message: str, context: str = "") -> str:
        """Simple chat without function calling"""
        pass

    @abstractmethod
    def is_available(self) -> bool:
        """Check if the LLM service is available"""
        pass
