from fastapi import HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from firebase_admin import auth as firebase_auth
from database.operations import get_user_profession_from_db
import logging
import os
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

# Security dependency
security = HTTPBearer()

# TODO: TEMPORARY: Add development mode bypass
DEVELOPMENT_MODE = False # Set to False in production

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer())):
    """Dependency to get current authenticated Firebase user with debug info"""

    # TEMPORARY: Development mode bypass
    if DEVELOPMENT_MODE:
        logger.warning("🚧 DEVELOPMENT MODE: Bypassing Firebase Auth")
        return {
            "user_id": "dev_user_123",
            "firebase_uid": "dev_user_123",
            "email": "dev@test.com",
            "email_verified": True,
            "name": "Dev User",
            "profession": "Developer"
        }

    try:
        logger.info(f"🔍 Attempting to verify Firebase token")
        logger.info(f"🔍 Token length: {len(credentials.credentials)}")
        logger.info(f"🔍 Token preview: {credentials.credentials[:50]}...")

        # Verify the Firebase ID token
        decoded_token = firebase_auth.verify_id_token(credentials.credentials)
        logger.info(f"✅ Token verified for user: {decoded_token.get('email')}")

        # Extract user info from token
        user_data = {
            "user_id": decoded_token['uid'],
            "firebase_uid": decoded_token['uid'],
            "email": decoded_token.get('email'),
            "email_verified": decoded_token.get('email_verified', False),
            "name": decoded_token.get('name'),
            "picture": decoded_token.get('picture'),
        }

        # Get additional user data
        profession = get_user_profession_from_db(user_data['firebase_uid'])
        user_data['profession'] = profession

        return user_data

    except firebase_auth.InvalidIdTokenError as e:
        logger.error(f"❌ Invalid Firebase ID token: {e}")
        raise HTTPException(status_code=401, detail=f"Invalid Firebase ID token: {str(e)}")
    except firebase_auth.ExpiredIdTokenError as e:
        logger.error(f"❌ Expired Firebase ID token: {e}")
        raise HTTPException(status_code=401, detail=f"Expired Firebase ID token: {str(e)}")
    except Exception as e:
        logger.error(f"❌ User verification failed: {e}")
        raise HTTPException(status_code=401, detail=f"Authentication failed: {str(e)}")
