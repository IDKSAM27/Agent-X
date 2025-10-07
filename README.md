<div align="center">
   <img src="assets/icons/app_icon-modified.png" alt="Agent-X Logo" width="180"/>
</div>

<h1 align="center">Agent-X : AI-Powered Personal Assistant</h1>

<div align="center">

  <a href="https://github.com/IDKSAM27/Agent-X">
    <img src="https://img.shields.io/badge/status-in%20development-yellow" alt="Development Status">
  </a>
    <a href="https://flutter.dev">
    <img src="https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter" alt="Flutter Version">
  </a>
  <a href="https://www.python.org">
    <img src="https://img.shields.io/badge/Python-3.11+-3776AB?logo=python&logoColor=white" alt="Python Version">
  </a>
  <a href="https://github.com/IDKSAM27/Agent-X/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="License">
  </a>

</div>

<p align="center">
 Agent-X is a smart personal assistant mobile app that helps you manage tasks, schedule events, and stay informed—all through natural conversations. Just tell Agent-X what you need, and it handles the rest.
  <br/>
  <br/>
  ·
  <a href="https://github.com/IDKSAM27/Agent-X/issues">Report a Bug</a>
  ·
  <a href="https://github.com/IDKSAM27/Agent-X/issues">Request a Feature</a>
</p>

>An intelligent productivity companion that understands you, powered by AI.

## Key Highlights:

-  **AI-Powered Chat** - Natural language task and calendar creation
-  **Smart Calendar** - Intelligent event scheduling with categories
-  **Task Management** - Priority-based task organization
-  **Personalized News** - Context-aware news based on your profession
-  **Secure Auth** - Firebase authentication with Google Sign-In

## Features
### Implemented:
- **AI Chat Interface** - Powered by Google Gemini 2.5 Flash with function calling
- **Task Management** - Create, edit, delete tasks with categories and priorities
- **Calendar System** - Event scheduling with categories (work, personal, meeting, etc.)
- **News Feed** - Multi-source RSS aggregation with relevance scoring
- **User Profiles** - Profession-based personalization

### In Progress:
- Backend database migration (SQLite → PostgreSQL)
- Cloud deployment (Backend hosting)
- Advanced AI features (smarter context awareness)
- Google Calendar sync
- Task reminders and notifications

### Planned:
- Voice input for hands-free operation
- Multi-language support
- Dark mode enhancements
- Productivity analytics dashboard

## Tech Stack
### Frontend

- [Flutter (Dart)](https://flutter.dev/) - Cross-platform mobile framework
- [Material Design 3](https://m3.material.io/) - Modern, adaptive UI
- [firebase_auth](https://firebase.google.com/docs/auth) - User authentication
- [dio](https://pub.dev/packages/dio) - HTTP client for API calls
- [flutter_markdown](https://pub.dev/documentation/flutter_markdown/latest/) - Rich text rendering

### Backend

- [Python 3.11+](https://www.python.org/) - Core language
- [FastAPI](https://fastapi.tiangolo.com/) - High-performance API framework
- [SQLite](https://sqlite.org/) - Local database (migrating to PostgreSQL)
- [Google Gemini AI](https://ai.google.dev/) - LLM with function calling
- [Firebase Admin](https://firebase.google.com/docs/admin/setup) - Token verification

### AI & Integration

- [Gemini 2.5 Flash](https://ai.google.dev/) - Natural language understanding
- [RSS Feeds](https://rss.app/en/) - Multi-source news aggregation
- [ChromaDB](https://pypi.org/project/chromadb/) - Vector storage for memory (planned)


## Installation

### [Firebase Setup Instruction](https://github.com/IDKSAM27/Agent-X/blob/main/FIREBASE_SETUP.md) (Go through the instructions for Firebase setup)

### Prerequisites

- `Flutter SDK (>=3.0.0)`
- `Python 3.11+`
- `Firebase project with Auth enabled`
- `Google Gemini API key`

### Backend Setup

```bash
# Clone repository
git clone https://github.com/IDKSAM27/Agent-X.git
cd Agent-X/agent-x-backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run backend
uvicorn main:app --reload --host 0.0.0.0 --port 8000
# Or just
python main.py
```

### Frontend Setup

```bash
cd Agent-X/lib

# Install Flutter dependencies
flutter pub get

# Update API config (lib/core/config/api_config.dart)
# Set baseUrl to your backend URL

# Run app
flutter run
```

### Agent-X/lib/.env
```bash
FIREBASE_PROJECT_ID=
FIREBASE_API_KEY=
```

### Agent-X/agent-x-backend/.env
```bash
GEMINI_API_KEY=
FIREBASE_SERVICE_ACCOUNT_KEY=./firebase-service-account.json
```
> [Firebase setup instructions (required!)](https://github.com/IDKSAM27/Agent-X/blob/main/FIREBASE_SETUP.md)

### Flutter Files required

```graphql
Agent-X/
├── android/
│   └── app/
│       └── google-services.json          # Android Firebase config
├── ios/
│   └── Runner/
│       └── GoogleService-Info.plist      # iOS Firebase config 
├── lib/
│   └── firebase_options.dart             # Auto-generated Flutter config
└── backend/
    └── firebase-adminsdk.json            # Backend service account (KEEP SECURE!)

```


## Quick Start

- **Sign Up** - Create account with email or Google
- **Set Profession** - Tell Agent-X what you do in the sign up page itself or in case of Google sign in, Profession page (e.g., "Student", "Developer", "Teacher")

- **Start Chatting** - Try: "What's happening in my field?" or "Create a task to study math tomorrow at 3 PM"

- **Explore Features** - Check out Calendar, Tasks, and News tabs

## Contributing

> Agent-X is a work-in-progress project. Contributions, suggestions, and feedback are welcome!

#### How to contribute:

- Fork the [repository](https://github.com/IDKSAM27/Agent-X)
- Create a feature branch (git checkout -b feature/AmazingFeature)
- Commit changes (git commit -m 'Add AmazingFeature')
- Push to branch (git push origin feature/AmazingFeature)
- Open a Pull Request

## Development Notes
#### Known Issues

- News loading can be slow on first request (caching improves subsequent loads)
- Profession data syncs between Firebase and SQLite (migration planned)
- Some edge cases in calendar time parsing

## License

> This project is licensed under the MIT License - see the [LICENSE](https://github.com/IDKSAM27/Agent-X/blob/main/LICENSE) file for details.

## Author

#### Sampreet Patil

- GitHub: `@IDKSAM27`
- Email: `sampreetpatil270@gmail.com`
