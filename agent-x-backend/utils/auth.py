import firebase_admin
from firebase_admin import auth, credentials
from fastapi import HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import os
import logging

logger = logging.getLogger(__name__)

# Initialize Firebase Admin SDK (if not already done)
if not firebase_admin._apps:
    # Adjust path to your service account file
    cred_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "firebase-service-account.json")
    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

security = HTTPBearer()

async def verify_firebase_token(credentials: HTTPAuthorizationCredentials = Depends(security)) -> dict:
    """Verify Firebase token and return user info"""
    try:
        token = credentials.credentials
        decoded_token = auth.verify_id_token(token)
        logger.info(f"✅ Token verified for user: {decoded_token.get('email')}")
        return decoded_token
    except Exception as e:
        logger.error(f"❌ Token verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid authentication token")
