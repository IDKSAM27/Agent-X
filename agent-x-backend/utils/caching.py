import json
import asyncio
from typing import Any, Optional
from datetime import datetime, timedelta
try:
    import redis.asyncio as redis
    REDIS_AVAILABLE = True
except ImportError:
    REDIS_AVAILABLE = False

try:
    import diskcache
    DISKCACHE_AVAILABLE = True
except ImportError:
    DISKCACHE_AVAILABLE = False

class CacheManager:
    def __init__(self, ttl_hours: int = 2, use_redis: bool = True):
        self.ttl_seconds = ttl_hours * 3600
        self.use_redis = use_redis and REDIS_AVAILABLE

        if self.use_redis:
            try:
                self.redis_client = redis.Redis(
                    host='localhost',
                    port=6379,
                    decode_responses=True
                )
            except:
                self.use_redis = False

        if not self.use_redis and DISKCACHE_AVAILABLE:
            self.disk_cache = diskcache.Cache('news_cache')
        else:
            self.memory_cache = {}

    async def get(self, key: str) -> Optional[Any]:
        """Get cached value"""
        try:
            if self.use_redis:
                value = await self.redis_client.get(key)
                return json.loads(value) if value else None
            elif hasattr(self, 'disk_cache'):
                return self.disk_cache.get(key)
            else:
                entry = self.memory_cache.get(key)
                if entry and entry['expires'] > datetime.now():
                    return entry['value']
                elif entry:
                    del self.memory_cache[key]
                return None
        except Exception as e:
            print(f"Cache get error: {e}")
            return None

    async def set(self, key: str, value: Any) -> bool:
        """Set cached value"""
        try:
            if self.use_redis:
                await self.redis_client.setex(
                    key,
                    self.ttl_seconds,
                    json.dumps(value, default=str)
                )
            elif hasattr(self, 'disk_cache'):
                self.disk_cache.set(key, value, expire=self.ttl_seconds)
            else:
                self.memory_cache[key] = {
                    'value': value,
                    'expires': datetime.now() + timedelta(seconds=self.ttl_seconds)
                }
            return True
        except Exception as e:
            print(f"Cache set error: {e}")
            return False
