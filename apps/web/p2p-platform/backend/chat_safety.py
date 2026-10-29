"""Chat report and block (App Store Guideline 1.2: user-generated content safeguards).

Reports are stored in ``chat_reports`` and emailed to support@dollor.ai (best-effort, after the response).
A block hides the blocked user's chat messages from the blocker and stops messages in both directions.
It never touches rides, payments or safety flows, and system/admin messages are never hidden.
"""
import logging
from datetime import datetime, timedelta
from typing import Literal, Optional

from fastapi import APIRouter, BackgroundTasks, Body, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from auth_utils import require_admin, require_any_auth
from database import get_db
from models import ChatReport, Customer, Driver, RideChatMessage, RideRequest, UserBlock

logger = logging.getLogger(__name__)

router = APIRouter()

REPORT_REASONS = ("harassment", "inappropriate", "spam", "safety", "other")
MAX_REPORTS_PER_HOUR = 10
CANNOT_MESSAGE_DETAIL = "You cannot message this user"


class ChatReportRequest(BaseModel):
    ride_request_id: int
    message_id: Optional[int] = None
    reason: Literal["harassment", "inappropriate", "spam", "safety", "other"]
    details: Optional[str] = Field(default=None, max_length=1000)


class BlockRequest(BaseModel):
    blocked_user_type: Literal["customer", "driver"]
    blocked_user_id: int


def caller_identity(auth: dict) -> tuple:
    """(user_type, user_id) of a rider or driver token; admins and other roles are rejected."""
    if auth.get("role") == "driver" and auth.get("driver_id"):
        return "driver", auth["driver_id"]
    if auth.get("customer_id"):
        return "customer", auth["customer_id"]
    if auth.get("driver_id"):
        return "driver", auth["driver_id"]
    raise HTTPException(status_code=403, detail="Only riders and drivers can use this feature")


def ride_parties(ride: RideRequest) -> dict:
    return {"customer": ride.customer_id, "driver": ride.matched_driver_id}


def other_party(ride: RideRequest, my_type: str) -> tuple:
    other_type = "driver" if my_type == "customer" else "customer"
    return other_type, ride_parties(ride)[other_type]


def is_blocked(db: Session, blocker: tuple, blocked: tuple) -> bool:
    return db.query(UserBlock.id).filter(
        UserBlock.blocker_type == blocker[0], UserBlock.blocker_id == blocker[1],
        UserBlock.blocked_type == blocked[0], UserBlock.blocked_id == blocked[1],
    ).first() is not None


def blocked_senders(db: Session, blocker: tuple) -> set:
    rows = db.query(UserBlock.blocked_type, UserBlock.blocked_id).filter(
        UserBlock.blocker_type == blocker[0], UserBlock.blocker_id == blocker[1]).all()
    return {(t, i) for t, i in rows}


def assert_can_message(db: Session, ride: RideRequest, sender_type: str) -> None:
    """403 when either party has blocked the other. Admin sends are never checked."""
    sender = (sender_type, ride_parties(ride)[sender_type])
    recipient = other_party(ride, sender_type)
    if recipient[1] is None:
        return
    if is_blocked(db, recipient, sender) or is_blocked(db, sender, recipient):
        raise HTTPException(status_code=403, detail=CANNOT_MESSAGE_DETAIL)


def _notify_support_of_report(report_id: int, details: dict) -> None:
    try:
        from email_service import notify_support
        notify_support(f"Chat report #{report_id}", details)
    except Exception as exc:  # best-effort: a mail failure must never affect the report
        logger.error("chat report %s: support email failed: %s", report_id, exc)


@router.post("/api/chat/report")
def report_chat(
    body: ChatReportRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    auth: dict = Depends(require_any_auth),
):
    from main_new import _require_ride_chat_participant

    role = _require_ride_chat_participant(db, body.ride_request_id, auth)
    if role == "admin":
        raise HTTPException(status_code=403, detail="Only riders and drivers can report chat")
    ride = db.query(RideRequest).filter(RideRequest.id == body.ride_request_id).first()
    reporter = (role, ride_parties(ride)[role])

    since = datetime.utcnow() - timedelta(hours=1)
    recent = db.query(ChatReport).filter(
        ChatReport.reporter_type == reporter[0], ChatReport.reporter_id == reporter[1],
        ChatReport.created_at >= since).count()
    if recent >= MAX_REPORTS_PER_HOUR:
        raise HTTPException(status_code=429, detail="Too many reports. Please try again later.",
                            headers={"Retry-After": "3600"})

    reported = other_party(ride, role)
    if body.message_id is not None:
        message = db.query(RideChatMessage).filter(
            RideChatMessage.id == body.message_id, RideChatMessage.ride_request_id == ride.id).first()
        if not message:
            raise HTTPException(status_code=404, detail="Message not found in this ride")
        if (message.sender_type, message.sender_id) == reporter:
            raise HTTPException(status_code=400, detail="You cannot report your own message")
        reported = (message.sender_type, message.sender_id)
    if reported[1] is None:
        raise HTTPException(status_code=400, detail="There is no other participant to report")

    report = ChatReport(
        reporter_type=reporter[0], reporter_id=reporter[1], reported_type=reported[0], reported_id=reported[1],
        ride_request_id=ride.id, message_id=body.message_id, reason=body.reason,
        details=(body.details or "").strip() or None, status="open")
    db.add(report)
    db.commit()
    db.refresh(report)
    logger.warning("chat report %s: %s %s reported %s %s (ride %s, message %s, reason %s)",
                   report.id, reporter[0], reporter[1], reported[0], reported[1], ride.id, body.message_id, body.reason)
    background_tasks.add_task(_notify_support_of_report, report.id, {
        "Report ID": report.id, "Reason": report.reason,
        "Reporter": f"{reporter[0]} #{reporter[1]}", "Reported": f"{reported[0]} #{reported[1]}",
        "Ride request ID": ride.id, "Message ID": body.message_id or "-",
        "Details": report.details or "-",
    })
    return {"success": True, "report_id": report.id}


def _block_target_exists(db: Session, user_type: str, user_id: int) -> bool:
    model = Customer if user_type == "customer" else Driver
    return db.query(model.id).filter(model.id == user_id).first() is not None


@router.post("/api/chat/block")
def block_user(body: BlockRequest, db: Session = Depends(get_db), auth: dict = Depends(require_any_auth)):
    me = caller_identity(auth)
    target = (body.blocked_user_type, body.blocked_user_id)
    if target == me:
        raise HTTPException(status_code=400, detail="You cannot block yourself")
    if not _block_target_exists(db, *target):
        raise HTTPException(status_code=404, detail="User not found")
    if not is_blocked(db, me, target):
        db.add(UserBlock(blocker_type=me[0], blocker_id=me[1], blocked_type=target[0], blocked_id=target[1]))
        db.commit()
    return {"success": True}


@router.delete("/api/chat/block")
def unblock_user(
    body: Optional[BlockRequest] = Body(default=None),
    blocked_user_type: Optional[Literal["customer", "driver"]] = Query(default=None),
    blocked_user_id: Optional[int] = Query(default=None),
    db: Session = Depends(get_db),
    auth: dict = Depends(require_any_auth),
):
    me = caller_identity(auth)
    if body is not None:
        target = (body.blocked_user_type, body.blocked_user_id)
    elif blocked_user_type and blocked_user_id is not None:
        target = (blocked_user_type, blocked_user_id)
    else:
        raise HTTPException(status_code=422, detail="blocked_user_type and blocked_user_id are required")
    db.query(UserBlock).filter(
        UserBlock.blocker_type == me[0], UserBlock.blocker_id == me[1],
        UserBlock.blocked_type == target[0], UserBlock.blocked_id == target[1],
    ).delete(synchronize_session=False)
    db.commit()
    return {"success": True}


@router.get("/api/chat/blocks")
def list_blocks(db: Session = Depends(get_db), auth: dict = Depends(require_any_auth)):
    me = caller_identity(auth)
    rows = db.query(UserBlock).filter(
        UserBlock.blocker_type == me[0], UserBlock.blocker_id == me[1]).order_by(UserBlock.created_at.desc()).all()
    return {"blocks": [
        {"blocked_user_type": r.blocked_type, "blocked_user_id": r.blocked_id,
         "created_at": r.created_at.isoformat() if r.created_at else None}
        for r in rows]}


@router.get("/api/admin/chat-reports")
def admin_list_chat_reports(
    status: Optional[str] = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    db: Session = Depends(get_db),
    _admin=Depends(require_admin),
):
    query = db.query(ChatReport)
    if status:
        query = query.filter(ChatReport.status == status)
    reports = query.order_by(ChatReport.created_at.desc()).limit(limit).all()
    message_ids = [r.message_id for r in reports if r.message_id]
    messages = {m.id: m.message for m in db.query(RideChatMessage).filter(RideChatMessage.id.in_(message_ids)).all()} \
        if message_ids else {}
    return {"reports": [
        {"id": r.id, "reporter_type": r.reporter_type, "reporter_id": r.reporter_id,
         "reported_type": r.reported_type, "reported_id": r.reported_id,
         "ride_request_id": r.ride_request_id, "message_id": r.message_id,
         "message_text": messages.get(r.message_id), "reason": r.reason, "details": r.details,
         "status": r.status, "created_at": r.created_at.isoformat() if r.created_at else None}
        for r in reports], "total": len(reports)}
