# Firebase Setup Guide for Agent-X

> Complete guide for contributors to set up Firebase for development (I basically wrote a whole f*ing Firebase tutorial)

## Table of Contents

1. Prerequisites
2. Creating Firebase Project
3. Configuring Authentication
4. Setting Up Android App
5. Configuring Flutter
6. Backend Service Account Setup
7. Environment Variables
8. Verification
9. Troubleshooting

## Prerequisites

### Before starting, ensure you have:

- `Google account`
- `Flutter SDK installed (3.0+)`
- `Android Studio or Xcode installed`
- `Node.js and npm installed (for Firebase CLI)`
- `Git repository cloned`

## Creating Firebase Project

### Step 1: Create New Project

1. Go to Firebase Console
2. Click "Add project" or "Create a project"
3. Enter project name: agent-x (or your preferred name)
4. Enable Google Analytics (Optional but recommended)
    - Select or create Analytics account
5. Click "Create project"
6. Wait for project creation (takes 30-60 seconds)
7. Click "Continue" when ready

## Configuring Authentication

### Step 2: Enable Authentication Methods

1. In Firebase Console, select your project
2. Navigate to Build → Authentication
3. Click "Get started"
4. Go to "Sign-in method" tab

#### Enable Email/Password:

1. Click on "Email/Password"
2. Toggle "Enable"
3. Leave "Email link" disabled (optional feature)
4. Click "Save"

#### Enable Google Sign-In:

1. Click on "Google"
2. Toggle "Enable"
3. Enter Project support email (your email)
4. Click "Save"

### Step 3: Add Authorized Domains (Optional for Production)

1. In Authentication → Settings → Authorized domains
2. By default, localhost is authorized for development
3. For production, add your domain (e.g., agent-x.app)

## Setting Up Android App
### Step 4: Register Android App

1. In Firebase Console, click the ⚙️ (Settings) icon → Project settings
2. Scroll to "Your apps" section
3. Click the Android icon to add Android app

#### Fill in App Details:

#### Package Name:

```text
com.yourcompany.agent_x
```

>⚠️ Important: Find your actual package name in android/app/build.gradle:

```text
defaultConfig {
    applicationId "com.yourcompany.agent_x"  // ← This is your package name
}
```

#### App nickname (optional):

```text
Agent-X Android
```

#### Debug signing certificate SHA-1:

> Required for Google Sign-In to work

#### Get your SHA-1 fingerprint:

```bash
# Navigate to android folder
cd android

# Run signing report
./gradlew signingReport

# For Windows:
gradlew.bat signingReport
```

Copy the SHA-1 value from the output (looks like `AA:BB:CC:...`) and paste it in Firebase.

#### Example output:

```text
Variant: debug
Config: debug
Store: ~/.android/debug.keystore
Alias: AndroidDebugKey
MD5: 1A:2B:3C:...
SHA1: AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD  ← Copy this
SHA-256: ...
```

4. Click "Register app"

### Step 5: Download google-services.json

1. After registering, Firebase will prompt you to download google-services.json
2. Click "Download google-services.json"
3. Move the downloaded file to:

    ```text
    Agent-X/android/app/google-services.json
    ```

#### Expected file structure:

```graphql
Agent-X/
└── android/
    └── app/
        └── google-services.json  
```

4. Verify the file is in the correct location - this is critical!

### Step 6: Update Android Build Files

Firebase should have already added the necessary plugins, but verify:

File: ```android/build.gradle``` (Project-level)

```text
buildscript {
    dependencies {
        // Add this line (should already be there)
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

File: `android/app/build.gradle` (App-level)

```text
// Add this at the BOTTOM of the file
apply plugin: 'com.google.gms.google-services'
```

## Configuring Flutter
### Step 7: Install FlutterFire CLI

```bash
# Install FlutterFire CLI globally
dart pub global activate flutterfire_cli

# Verify installation
flutterfire --version
```

### Step 8: Configure Firebase in Flutter

```bash
# Navigate to project root
cd Agent-X

# Run FlutterFire configuration
flutterfire configure
```

#### The CLI will:

1. Ask you to select your Firebase project → Choose agent-x
2. Ask which platforms to configure → Select Android (and iOS if needed)
3. Auto-generate lib/firebase_options.dart

#### Expected output:

```text
✔ Firebase project selected: agent-x
✔ Registered Android app: com.yourcompany.agent_x
✔ Firebase configuration file lib/firebase_options.dart generated successfully
```

### Step 9: Verify firebase_options.dart

Check that `lib/firebase_options.dart` was created:

```dart
// lib/firebase_options.dart (auto-generated)
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    // Contains your Firebase configuration
    return android; // or ios, web, etc.
  }
  
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIza...',
    appId: '1:123...',
    messagingSenderId: '123...',
    projectId: 'agent-x',
    // ... more config
  );
}
```

### Step 10: Initialize Firebase in Flutter (done already!)

File: `lib/main.dart`

```dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const MyApp());
}
```

## Backend Service Account Setup
### Step 11: Generate Service Account Key

1. In Firebase Console → Project Settings (⚙️ icon)
2. Go to "Service accounts" tab
3. Click "Generate new private key"
4. Confirm by clicking "Generate key"
5. A JSON file will download (e.g., agent-x-1a2b3c.json)

### Step 12: Move Service Account File

1. Rename the downloaded file to:

    ```text
    firebase-service-account.json
    ```

2. Move it to:

    ```text
    Agent-X/agent-x-backend/firebase-service-account.json
    ```

#### Expected backend structure:

```graphql
Agent-X/
└── agent-x-backend/
    ├── main.py
    ├── requirements.txt
    └── firebase-service-account.json  
```

### Step 13: Initialize Firebase Admin in Backend (already done!)

File: `agent-x-backend/main.py`

```python
import firebase_admin
from firebase_admin import credentials, auth

# Initialize Firebase Admin SDK
cred = credentials.Certificate("firebase-service-account.json")
firebase_admin.initialize_app(cred)

print("Firebase Admin SDK initialized successfully!")
```

### Step 14: Secure the Service Account File

Add to `.gitignore` (already done)

> ⚠️ CRITICAL: NEVER commit service account files to Git!

## Environment Variables
### Step 15: Create Environment File 

File: `agent-x-backend/.env`

```text
GEMINI_API_KEY=
FIREBASE_SERVICE_ACCOUNT_KEY=./firebase-service-account.json
```

File: `lib/.env`

```text
FIREBASE_PROJECT_ID=
FIREBASE_API_KEY=
```

## Verification
### Step 16: Test Firebase Setup
#### Test Flutter Firebase:

```bash
# Run the app
flutter run

# You should see:
#  Firebase initialized successfully
#  No Firebase errors in console
```

#### Test Backend Firebase Admin:

```bash
# Navigate to backend
cd backend

# Activate virtual environment
source venv/bin/activate  # Linux/Mac
# OR
venv\Scripts\activate  # Windows

# Run backend
uvicorn main:app --reload

# Expected output:
# Firebase Admin SDK initialized successfully!
# INFO: Uvicorn running on http://127.0.0.1:8000
```

#### Test Authentication:

1. Run the Flutter app
2. Try signing up with email/password
3. Try signing in with Google
4. Check Firebase Console → Authentication → Users
5. Your test user should appear in the list 

#### Final File Structure Checklist

```graphql
Agent-X/
├── android/
│   └── app/
│       ├── build.gradle                      (contains google-services plugin)
│       └── google-services.json              (Firebase Android config)
├── lib/
│   ├── main.dart                             (Firebase initialized)
│   └── firebase_options.dart                 (Auto-generated config)
├── backend/
│   ├── main.py                               (Firebase Admin initialized)
│   ├── firebase-service-account.json         (Service account key)
│   └── .env                                  (Environment variables)
└── .gitignore                                (Sensitive files ignored)
```

## Troubleshooting
### Issue 1: "google-services.json missing"

#### Error:

```text
Could not find google-services.json
```

#### Solution:

1. Verify file is in android/app/google-services.json (not android/google-services.json)
2. Re-download from Firebase Console if needed
3. Clean and rebuild:

    ```bash
    flutter clean
    flutter pub get
    flutter run
    ```

### Issue 2: "SHA-1 fingerprint error" (Google Sign-In fails)

#### Error:

```text
Google Sign-In failed: DEVELOPER_ERROR
```

#### Solution:

1. Get your SHA-1 fingerprint:

    ```bash
    cd android && ./gradlew signingReport
    ```

2. Add it to Firebase Console → Project Settings → Your Android App → Add fingerprint
3. Wait 5 minutes for changes to propagate
4. Rebuild the app

### Issue 3: "Firebase Admin SDK initialization failed"

#### Error:

```python
ValueError: Could not load Firebase credentials
```

#### Solution:

1. Verify firebase-service-account.json exists in backend/ folder
2. Check file permissions (should be readable)
3. Verify JSON file is valid (open it, check for syntax errors)
4. Use absolute path in code:

    ```python
    import os
    cred_path = os.path.join(os.path.dirname(__file__), 'firebase-service-account.json')
    cred = credentials.Certificate(cred_path)
    ```

### Issue 4: "Firebase project not found"

#### Error:

```text
flutterfire configure: No Firebase projects found
```

#### Solution:

1. Login to Firebase CLI:

    ```bash
    firebase login
    ```
2. Verify you have access to the project in Firebase Console
3. Run flutterfire configure again

### Security Best Practices

1. Never commit sensitive files:
    - firebase-service-account.json
    - google-services.json
    - .env files
2. Use environment variables for API keys and credentials
3. Set up Firebase Security Rules (for Firestore, Storage, etc.)
4. Rotate service account keys periodically (every 90 days recommended)
5. Use separate Firebase projects for development/staging/production

### Need Help?

- Firebase Documentation: https://firebase.google.com/docs
- FlutterFire Documentation: https://firebase.flutter.dev
- Project Issues: [GitHub Issues](https://github.com/IDKSAM27/Agent-X/issues)
- Contact: sampreetpatil270@gmail.com

### Next Steps

After completing Firebase setup:

1. Test authentication (email + Google Sign-In)
2. Configure Firestore database (if needed)
3. Set up Firebase Storage (if needed)
4. Configure Cloud Messaging (for push notifications)
5. Deploy backend with proper credentials

> Congratulations! Firebase is now fully configured for Agent-X development!

>Last Updated: October 2025