from typing import Dict, List

class FunctionRegistry:
    """Registry for available functions (Open/Closed: Easy to extend without modifying)"""

    def __init__(self):
        self.functions = {}
        self._register_default_functions()

    def register_function(self, name: str, definition: Dict):
        """Register a new function"""
        self.functions[name] = definition

    def get_all_functions(self) -> List[Dict]:
        """Get all registered functions"""
        return list(self.functions.values())

    def get_function(self, name: str) -> Dict:
        """Get specific function definition"""
        return self.functions.get(name, {})

    def _register_default_functions(self):
        """Register default Agent X functions"""

        # Task Management Functions
        self.register_function("create_task", {
            "type": "function",
            "function": {
                "name": "create_task",
                "description": "Create a new task for the user",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "title": {
                            "type": "string",
                            "description": "The task title or description"
                        },
                        "priority": {
                            "type": "string",
                            "enum": ["low", "medium", "high"],
                            "description": "Task priority level",
                            "default": "medium"
                        },
                        "due_date": {
                            "type": "string",
                            "description": "Due date in YYYY-MM-DD format (optional)"
                        }
                    },
                    "required": ["title"]
                }
            }
        })

        self.register_function("get_tasks", {
            "type": "function",
            "function": {
                "name": "get_tasks",
                "description": "Get user's tasks",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "status": {
                            "type": "string",
                            "enum": ["pending", "completed", "all"],
                            "description": "Filter tasks by status",
                            "default": "pending"
                        }
                    }
                }
            }
        })

        # Calendar Functions
        self.register_function("create_event", {
            "type": "function",
            "function": {
                "name": "create_event",
                "description": "Create a calendar event",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string", "description": "Event title"},
                        "date": {"type": "string", "description": "Event date in YYYY-MM-DD format"},
                        "time": {"type": "string", "description": "Event time in HH:MM format", "default": "10:00"}
                    },
                    "required": ["title", "date"]
                }
            }
        })

        self.register_function("get_events", {
            "type": "function",
            "function": {
                "name": "get_events",
                "description": "Get user's calendar events and schedule",
                "parameters": {
                    "type": "object",
                    "properties": {}
                }
            }
        })

        # Memory/User Functions
        self.register_function("save_user_info", {
            "type": "function",
            "function": {
                "name": "save_user_info",
                "description": "Save user information like name",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string", "description": "User's name"},
                        "info_type": {"type": "string", "description": "Type of information", "default": "name"}
                    },
                    "required": ["name"]
                }
            }
        })

        self.register_function("get_user_info", {
            "type": "function",
            "function": {
                "name": "get_user_info",
                "description": "Get user's saved information like name",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "info_type": {"type": "string", "description": "Type of information to retrieve", "default": "name"}
                    }
                }
            }
        })
