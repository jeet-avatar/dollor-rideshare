"""
WebSocket Server for Real-Time Updates
Dollor.ai Matchmaking Platform

Provides real-time updates for:
- Order status changes
- Driver location tracking
- Ride status updates
- Chat messages
"""

from fastapi import WebSocket, WebSocketDisconnect
from typing import Dict, Set, Optional, Any
from datetime import datetime
import json
import asyncio
import logging
import threading
import os
from jose import jwt, JWTError

logger = logging.getLogger(__name__)

# Connection caps — prevent DoS via unbounded WebSocket connections
MAX_CONNECTIONS_PER_CLIENT = 3
MAX_TOTAL_CONNECTIONS = 10000

# Redis pub/sub for cross-worker broadcast
try:
    from cache import redis_client, REDIS_AVAILABLE
except ImportError:
    redis_client = None
    REDIS_AVAILABLE = False


class ConnectionManager:
    """
    Manages WebSocket connections for real-time updates.

    Connection Types:
    - customer:{customer_id} - Customer tracking their orders/rides
    - driver:{driver_id} - Driver receiving order assignments and updates
    - restaurant:{vendor_id} - Restaurant receiving new orders
    - order:{order_id} - Anyone tracking a specific order
    - ride:{ride_id} - Anyone tracking a specific ride
    """

    def __init__(self):
        # Active WebSocket connections by client_id
        self.active_connections: Dict[str, WebSocket] = {}

        # Subscription groups (topic -> set of client_ids)
        self.subscriptions: Dict[str, Set[str]] = {}

        # Client metadata (client_id -> metadata dict)
        self.client_metadata: Dict[str, Dict[str, Any]] = {}

        # Rate limiting (client_id -> last message timestamps)
        self.rate_limits: Dict[str, list] = {}

    async def connect(self, websocket: WebSocket, client_id: str, metadata: Optional[Dict] = None):
        """Accept a new WebSocket connection."""
        # Global cap — reject when server is at capacity
        if len(self.active_connections) >= MAX_TOTAL_CONNECTIONS:
            await websocket.close(code=1008, reason="Server at capacity")
            logger.warning(f"WebSocket rejected (global cap): {client_id}")
            return

        # Per-client cap — count connections sharing the same entity prefix
        # client_id format: "customer:123" or "driver:456" or "order:789"
        base_id = ":".join(client_id.split(":")[:2]) if ":" in client_id else client_id
        existing_count = sum(
            1 for cid in self.active_connections
            if (":".join(cid.split(":")[:2]) if ":" in cid else cid) == base_id
        )
        if existing_count >= MAX_CONNECTIONS_PER_CLIENT:
            await websocket.close(code=1008, reason="Too many connections from this client")
            logger.warning(f"WebSocket rejected (per-client cap {existing_count}): {client_id}")
            return

        await websocket.accept()
        self.active_connections[client_id] = websocket
        self.client_metadata[client_id] = metadata or {}
        self.rate_limits[client_id] = []

        logger.info(f"WebSocket connected: {client_id}")

        # Send connection confirmation
        await self.send_personal_message({
            "type": "connected",
            "client_id": client_id,
            "timestamp": datetime.utcnow().isoformat()
        }, client_id)

    def disconnect(self, client_id: str):
        """Handle WebSocket disconnection."""
        if client_id in self.active_connections:
            del self.active_connections[client_id]

        if client_id in self.client_metadata:
            del self.client_metadata[client_id]

        if client_id in self.rate_limits:
            del self.rate_limits[client_id]

        # Remove from all subscriptions
        for topic in list(self.subscriptions.keys()):
            if client_id in self.subscriptions[topic]:
                self.subscriptions[topic].remove(client_id)
                if not self.subscriptions[topic]:
                    del self.subscriptions[topic]

        logger.info(f"WebSocket disconnected: {client_id}")

    async def subscribe(self, client_id: str, topic: str):
        """Subscribe a client to a topic."""
        if topic not in self.subscriptions:
            self.subscriptions[topic] = set()
        self.subscriptions[topic].add(client_id)

        logger.info(f"Client {client_id} subscribed to {topic}")

        await self.send_personal_message({
            "type": "subscribed",
            "topic": topic,
            "timestamp": datetime.utcnow().isoformat()
        }, client_id)

    async def unsubscribe(self, client_id: str, topic: str):
        """Unsubscribe a client from a topic."""
        if topic in self.subscriptions and client_id in self.subscriptions[topic]:
            self.subscriptions[topic].remove(client_id)
            if not self.subscriptions[topic]:
                del self.subscriptions[topic]

        logger.info(f"Client {client_id} unsubscribed from {topic}")

        await self.send_personal_message({
            "type": "unsubscribed",
            "topic": topic,
            "timestamp": datetime.utcnow().isoformat()
        }, client_id)

    async def send_personal_message(self, message: dict, client_id: str):
        """Send a message to a specific client."""
        if client_id in self.active_connections:
            try:
                await self.active_connections[client_id].send_json(message)
            except Exception as e:
                logger.error(f"Error sending to {client_id}: {e}")
                self.disconnect(client_id)

    async def broadcast_to_topic(self, message: dict, topic: str):
        """Broadcast a message to all subscribers of a topic.
        If Redis is available, also publish so other workers receive it."""
        message["topic"] = topic
        message["timestamp"] = datetime.utcnow().isoformat()

        # Publish to Redis for cross-worker delivery
        if REDIS_AVAILABLE and redis_client and not message.get("_from_redis"):
            try:
                redis_client.publish(f"ws:{topic}", json.dumps(message, default=str))
            except Exception as e:
                logger.warning(f"Redis publish failed for {topic}: {e}")

        # Deliver to local subscribers
        await self._deliver_local(message, topic)

    async def _deliver_local(self, message: dict, topic: str):
        """Deliver a message to subscribers connected to THIS worker."""
        if topic not in self.subscriptions:
            return

        disconnected = []
        for client_id in self.subscriptions[topic]:
            if client_id in self.active_connections:
                try:
                    msg = {k: v for k, v in message.items() if k != "_from_redis"}
                    await self.active_connections[client_id].send_json(msg)
                except Exception as e:
                    logger.error(f"Error broadcasting to {client_id}: {e}")
                    disconnected.append(client_id)

        for client_id in disconnected:
            self.disconnect(client_id)

    async def broadcast_to_all(self, message: dict):
        """Broadcast a message to all connected clients."""
        message["timestamp"] = datetime.utcnow().isoformat()

        disconnected = []
        for client_id, websocket in self.active_connections.items():
            try:
                await websocket.send_json(message)
            except Exception as e:
                logger.error(f"Error broadcasting to {client_id}: {e}")
                disconnected.append(client_id)

        for client_id in disconnected:
            self.disconnect(client_id)

    def get_topic_subscribers(self, topic: str) -> Set[str]:
        """Get all subscribers for a topic."""
        return self.subscriptions.get(topic, set())

    def get_client_subscriptions(self, client_id: str) -> list:
        """Get all topics a client is subscribed to."""
        return [topic for topic, subs in self.subscriptions.items() if client_id in subs]

    def get_connection_count(self) -> int:
        """Get total number of active connections."""
        return len(self.active_connections)

    def is_rate_limited(self, client_id: str, max_messages: int = 60, window_seconds: int = 60) -> bool:
        """Check if a client is rate limited."""
        now = datetime.utcnow().timestamp()

        if client_id not in self.rate_limits:
            self.rate_limits[client_id] = []

        # Remove old timestamps outside window
        self.rate_limits[client_id] = [
            ts for ts in self.rate_limits[client_id]
            if now - ts < window_seconds
        ]

        # Check if over limit
        if len(self.rate_limits[client_id]) >= max_messages:
            return True

        # Add current timestamp
        self.rate_limits[client_id].append(now)
        return False


# Global connection manager instance
manager = ConnectionManager()


# ===================== REDIS PUB/SUB LISTENER =====================

# Captured by the main thread's event loop so the subscriber thread can schedule coroutines
_main_event_loop: asyncio.AbstractEventLoop = None


def capture_event_loop():
    """Call from an async context (e.g. FastAPI lifespan/startup) to capture the running loop."""
    global _main_event_loop
    _main_event_loop = asyncio.get_running_loop()
    logger.info(f"Captured event loop for Redis subscriber: {_main_event_loop}")


def _start_redis_subscriber():
    """Background thread that subscribes to Redis pub/sub and delivers to local WebSocket clients.
    Reconnects automatically on Redis disconnect with exponential backoff."""
    if not REDIS_AVAILABLE or not redis_client:
        logger.info("Redis not available, skipping pub/sub subscriber")
        return

    import time as _time

    def _listener():
        import redis as redis_lib
        import os
        backoff = 1

        while True:
            try:
                sub_client = redis_lib.Redis.from_url(
                    os.environ["REDIS_URL"],  # present whenever REDIS_AVAILABLE is True
                    decode_responses=True,
                    socket_connect_timeout=5,
                    socket_timeout=None,  # blocking subscribe
                )
                pubsub = sub_client.pubsub()
                pubsub.psubscribe("ws:*")
                logger.info("Redis pub/sub subscriber connected")
                backoff = 1  # reset on successful connect

                for raw_message in pubsub.listen():
                    if raw_message["type"] != "pmessage":
                        continue
                    try:
                        topic = raw_message["channel"].removeprefix("ws:")
                        data = json.loads(raw_message["data"])
                        data["_from_redis"] = True
                        # Use captured event loop (set by capture_event_loop)
                        loop = _main_event_loop
                        if loop and not loop.is_closed():
                            asyncio.run_coroutine_threadsafe(
                                manager._deliver_local(data, topic), loop
                            )
                    except Exception as e:
                        logger.warning(f"Redis subscriber message error: {e}")
            except Exception as e:
                logger.error(f"Redis subscriber disconnected: {e}, reconnecting in {backoff}s")
                _time.sleep(backoff)
                backoff = min(backoff * 2, 30)  # cap at 30s

    t = threading.Thread(target=_listener, daemon=True, name="redis-ws-subscriber")
    t.start()

_start_redis_subscriber()


# ===================== EVENT BROADCASTING FUNCTIONS =====================

async def broadcast_order_status(order_id: int, status: str, details: dict = None):
    """Broadcast order status update to all interested parties."""
    message = {
        "type": "order_status_update",
        "order_id": order_id,
        "status": status,
        "details": details or {}
    }

    # Broadcast to order-specific topic
    await manager.broadcast_to_topic(message, f"order:{order_id}")

    # Also broadcast to customer if details include customer_id
    if details and details.get("customer_id"):
        await manager.broadcast_to_topic(message, f"customer:{details['customer_id']}")

    # Broadcast to restaurant if details include vendor_id
    if details and details.get("vendor_id"):
        await manager.broadcast_to_topic(message, f"restaurant:{details['vendor_id']}")

    # Broadcast to driver if details include driver_id
    if details and details.get("driver_id"):
        await manager.broadcast_to_topic(message, f"driver:{details['driver_id']}")


async def broadcast_driver_location(driver_id: int, latitude: float, longitude: float,
                                     heading: float = None, speed: float = None):
    """Broadcast driver location update."""
    message = {
        "type": "driver_location_update",
        "driver_id": driver_id,
        "latitude": latitude,
        "longitude": longitude,
        "heading": heading,
        "speed": speed
    }

    # Broadcast to driver-specific topic (for order tracking)
    await manager.broadcast_to_topic(message, f"driver:{driver_id}")


async def broadcast_ride_status(ride_id: str, status: str, details: dict = None):
    """Broadcast ride status update."""
    message = {
        "type": "ride_status_update",
        "ride_id": ride_id,
        "status": status,
        "details": details or {}
    }

    await manager.broadcast_to_topic(message, f"ride:{ride_id}")

    if details and details.get("customer_id"):
        await manager.broadcast_to_topic(message, f"customer:{details['customer_id']}")

    if details and details.get("driver_id"):
        await manager.broadcast_to_topic(message, f"driver:{details['driver_id']}")


async def broadcast_chat_message(conversation_id: str, sender_id: str,
                                  sender_type: str, message_text: str):
    """Broadcast a chat message."""
    message = {
        "type": "chat_message",
        "conversation_id": conversation_id,
        "sender_id": sender_id,
        "sender_type": sender_type,
        "message": message_text
    }
    await manager.broadcast_to_topic(message, f"chat:{conversation_id}")


async def broadcast_eta_update(order_id: int = None, ride_id: str = None,
                                eta_minutes: int = None, eta_timestamp: str = None):
    """Broadcast ETA update for an order or ride."""
    message = {
        "type": "eta_update",
        "eta_minutes": eta_minutes,
        "eta_timestamp": eta_timestamp
    }

    if order_id:
        message["order_id"] = order_id
        await manager.broadcast_to_topic(message, f"order:{order_id}")

    if ride_id:
        message["ride_id"] = ride_id
        await manager.broadcast_to_topic(message, f"ride:{ride_id}")


# ===================== BID/MATCHMAKING BROADCAST FUNCTIONS =====================

async def broadcast_new_ride_request(ride_request_data: dict, driver_ids: list = None):
    """
    Broadcast a new ride request to nearby drivers for bidding.
    If driver_ids is None, broadcasts to all drivers.
    """
    message = {
        "type": "new_ride_request",
        "ride_request": ride_request_data
    }

    if driver_ids:
        # Send to specific drivers
        for driver_id in driver_ids:
            await manager.broadcast_to_topic(message, f"driver:{driver_id}")
    else:
        # Broadcast to all drivers (they'll filter by distance on their end)
        # Create a topic for ride requests
        await manager.broadcast_to_topic(message, "ride_requests")


async def broadcast_new_bid(ride_request_id: int, customer_id: int, bid_data: dict):
    """Notify customer of a new bid on their ride request."""
    message = {
        "type": "new_bid",
        "ride_request_id": ride_request_id,
        "bid": bid_data
    }

    # Send to the customer
    await manager.broadcast_to_topic(message, f"customer:{customer_id}")

    # Also broadcast to the ride request topic
    await manager.broadcast_to_topic(message, f"ride_request:{ride_request_id}")


async def broadcast_bid_response(driver_id: int, bid_id: int, action: str, details: dict = None):
    """
    Notify driver of customer's response to their bid.
    Actions: accepted, rejected, countered
    """
    message = {
        "type": "bid_response",
        "bid_id": bid_id,
        "action": action,
        "details": details or {}
    }

    await manager.broadcast_to_topic(message, f"driver:{driver_id}")


async def broadcast_ride_matched(ride_request_id: int, customer_id: int,
                                  driver_id: int, match_details: dict):
    """Notify both parties when a ride is successfully matched."""
    message = {
        "type": "ride_matched",
        "ride_request_id": ride_request_id,
        "match_details": match_details
    }

    # Notify customer
    await manager.broadcast_to_topic(message, f"customer:{customer_id}")

    # Notify matched driver
    await manager.broadcast_to_topic(message, f"driver:{driver_id}")

    # Broadcast to ride request topic (other drivers will know to stop bidding)
    await manager.broadcast_to_topic({
        "type": "ride_request_closed",
        "ride_request_id": ride_request_id,
        "reason": "matched"
    }, f"ride_request:{ride_request_id}")


async def broadcast_ride_request_cancelled(ride_request_id: int, bidder_driver_ids: list = None):
    """Notify drivers that a ride request was cancelled."""
    message = {
        "type": "ride_request_cancelled",
        "ride_request_id": ride_request_id
    }

    # Notify specific drivers who had bids
    if bidder_driver_ids:
        for driver_id in bidder_driver_ids:
            await manager.broadcast_to_topic(message, f"driver:{driver_id}")

    # Also broadcast to the ride request topic
    await manager.broadcast_to_topic(message, f"ride_request:{ride_request_id}")


async def broadcast_bid_update(ride_request_id: int, customer_id: int, bid_data: dict):
    """Notify customer that a driver updated their bid."""
    message = {
        "type": "bid_updated",
        "ride_request_id": ride_request_id,
        "bid": bid_data
    }

    await manager.broadcast_to_topic(message, f"customer:{customer_id}")
    await manager.broadcast_to_topic(message, f"ride_request:{ride_request_id}")


async def broadcast_bid_withdrawn(ride_request_id: int, customer_id: int, bid_id: int, driver_id: int):
    """Notify customer that a driver withdrew their bid."""
    message = {
        "type": "bid_withdrawn",
        "ride_request_id": ride_request_id,
        "bid_id": bid_id,
        "driver_id": driver_id
    }

    await manager.broadcast_to_topic(message, f"customer:{customer_id}")
    await manager.broadcast_to_topic(message, f"ride_request:{ride_request_id}")


async def broadcast_counter_offer_response(customer_id: int, ride_request_id: int,
                                            bid_id: int, action: str, new_price: float = None):
    """
    Notify customer when driver responds to their counter-offer.
    Actions: accepted, rejected
    """
    message = {
        "type": "counter_offer_response",
        "ride_request_id": ride_request_id,
        "bid_id": bid_id,
        "action": action,
        "new_price": new_price
    }

    await manager.broadcast_to_topic(message, f"customer:{customer_id}")


# ===================== WEBSOCKET MESSAGE HANDLER =====================

async def handle_websocket_message(websocket: WebSocket, client_id: str, data: dict):
    """Handle incoming WebSocket messages from clients."""

    message_type = data.get("type")

    if message_type == "subscribe":
        topic = data.get("topic")
        if topic:
            await manager.subscribe(client_id, topic)

    elif message_type == "unsubscribe":
        topic = data.get("topic")
        if topic:
            await manager.unsubscribe(client_id, topic)

    elif message_type == "ping":
        await manager.send_personal_message({"type": "pong"}, client_id)

    elif message_type == "driver_location":
        # Driver is updating their location
        latitude = data.get("latitude")
        longitude = data.get("longitude")
        heading = data.get("heading")
        speed = data.get("speed")
        driver_id = data.get("driver_id")

        if latitude and longitude and driver_id:
            await broadcast_driver_location(driver_id, latitude, longitude, heading, speed)

    elif message_type == "chat":
        # Chat message
        conversation_id = data.get("conversation_id")
        message_text = data.get("message")
        sender_type = data.get("sender_type", "unknown")

        if conversation_id and message_text:
            await broadcast_chat_message(conversation_id, client_id, sender_type, message_text)

    elif message_type == "typing":
        # Typing indicator
        order_id = data.get("order_id")
        sender_type = data.get("sender_type")
        is_typing = data.get("is_typing", False)
        recipient_id = data.get("recipient_id")

        if order_id and sender_type and recipient_id:
            recipient_type = "customer" if sender_type == "driver" else "driver"
            await manager.send_personal_message({
                "type": "typing_indicator",
                "order_id": order_id,
                "sender_type": sender_type,
                "is_typing": is_typing
            }, f"{recipient_type}_{recipient_id}")

    elif message_type == "mark_read":
        # Mark messages as read notification
        order_id = data.get("order_id")
        reader_type = data.get("reader_type")
        recipient_id = data.get("recipient_id")

        if order_id and reader_type and recipient_id:
            sender_type = "driver" if reader_type == "customer" else "customer"
            await manager.send_personal_message({
                "type": "read_receipt",
                "order_id": order_id,
                "reader_type": reader_type,
                "read_at": datetime.utcnow().isoformat()
            }, f"{sender_type}_{recipient_id}")

    elif message_type == "get_subscriptions":
        subscriptions = manager.get_client_subscriptions(client_id)
        await manager.send_personal_message({
            "type": "subscriptions",
            "topics": subscriptions
        }, client_id)

    else:
        await manager.send_personal_message({
            "type": "error",
            "message": f"Unknown message type: {message_type}"
        }, client_id)


# ===================== FASTAPI WEBSOCKET ENDPOINT =====================

def _verify_ws_token(token: str, client_id: str) -> bool:
    """Verify JWT token and check that client_id matches the token identity.

    Returns True if the token is valid AND the client_id matches the JWT claims.
    """
    secret_key = os.getenv("JWT_SECRET_KEY", "")
    if not secret_key:
        logger.error("JWT_SECRET_KEY not set -- rejecting WebSocket connection")
        return False

    try:
        payload = jwt.decode(token, secret_key, algorithms=["HS256"])
    except JWTError as e:
        logger.warning(f"WebSocket JWT decode failed: {e}")
        return False

    # Extract identity from JWT payload
    parts = client_id.split("_", 1)
    client_type = parts[0] if len(parts) > 0 else "unknown"
    entity_id_str = parts[1] if len(parts) > 1 else None

    if not entity_id_str:
        return False

    # Validate client_id matches JWT claims
    if client_type == "customer":
        jwt_customer_id = payload.get("customer_id")
        jwt_email = payload.get("sub")
        if jwt_customer_id and str(jwt_customer_id) == entity_id_str:
            return True
        # Fallback: look up customer by email and verify ID matches channel
        if jwt_email:
            try:
                from database import SessionLocal
                from models import Customer
                db = SessionLocal()
                try:
                    customer = db.query(Customer).filter(Customer.email == jwt_email).first()
                    if customer and str(customer.id) == entity_id_str:
                        return True
                finally:
                    db.close()
            except Exception as e:
                logger.warning(f"WebSocket email fallback DB lookup failed: {e}")
            return False
        return False

    elif client_type == "driver":
        jwt_driver_id = payload.get("driver_id")
        if jwt_driver_id and str(jwt_driver_id) == entity_id_str:
            return True
        return False

    elif client_type == "restaurant":
        jwt_vendor_id = payload.get("vendor_id")
        if jwt_vendor_id and str(jwt_vendor_id) == entity_id_str:
            return True
        return False

    elif client_type == "admin":
        jwt_role = payload.get("role", "")
        if jwt_role == "admin":
            return True
        return False

    return False


async def websocket_endpoint(websocket: WebSocket, client_id: str):
    """
    Main WebSocket endpoint handler.

    SECURITY: Requires a valid JWT token as a query parameter (?token=...).
    The token is verified and the client_id must match the JWT identity.

    Client ID format:
    - customer_{id} - Customer app connections
    - driver_{id} - Driver app connections
    - restaurant_{id} - Restaurant app connections
    - admin_{id} - Admin portal connections
    """

    # SECURITY: Verify JWT token before accepting connection
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4001, reason="Authentication required")
        return

    if not _verify_ws_token(token, client_id):
        await websocket.close(code=4003, reason="Invalid token or client_id mismatch")
        return

    # Extract client type and ID from client_id
    parts = client_id.split("_", 1)
    client_type = parts[0] if len(parts) > 0 else "unknown"
    entity_id = parts[1] if len(parts) > 1 else None

    metadata = {
        "client_type": client_type,
        "entity_id": entity_id,
        "connected_at": datetime.utcnow().isoformat()
    }

    await manager.connect(websocket, client_id, metadata)

    # Auto-subscribe to relevant topics based on client type
    if client_type == "customer" and entity_id:
        await manager.subscribe(client_id, f"customer:{entity_id}")
    elif client_type == "driver" and entity_id:
        await manager.subscribe(client_id, f"driver:{entity_id}")
    elif client_type == "restaurant" and entity_id:
        await manager.subscribe(client_id, f"restaurant:{entity_id}")

    try:
        while True:
            # Receive message from client
            data = await websocket.receive_json()

            # Rate limiting check
            if manager.is_rate_limited(client_id):
                await manager.send_personal_message({
                    "type": "error",
                    "message": "Rate limit exceeded. Please slow down."
                }, client_id)
                continue

            # Handle the message
            await handle_websocket_message(websocket, client_id, data)

    except WebSocketDisconnect:
        manager.disconnect(client_id)
    except Exception as e:
        logger.error(f"WebSocket error for {client_id}: {e}")
        manager.disconnect(client_id)


# ===================== HEALTH CHECK =====================

def get_websocket_stats() -> dict:
    """Get WebSocket server statistics."""
    return {
        "active_connections": manager.get_connection_count(),
        "subscription_topics": len(manager.subscriptions),
        "subscriptions": {topic: len(subs) for topic, subs in manager.subscriptions.items()}
    }
