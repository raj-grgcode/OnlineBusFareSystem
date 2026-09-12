from pydantic import BaseModel
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Form
from fastapi.responses import HTMLResponse
from datetime import date
import json
import math
import uuid as uuid_lib
import base64
import uuid
import httpx
import os
import random
import time
from sqlalchemy import create_engine, Column, Integer, String, Boolean, Float
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from passlib.context import CryptContext

DATABASE_URL = os.environ.get("DATABASE_URL")

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    phone = Column(String, nullable=False)
    email = Column(String, unique=True, nullable=False, index=True)
    password_hash = Column(String, nullable=False)
    is_verified = Column(Boolean, default=False)


class Wallet(Base):
    __tablename__ = "wallets"
    device_id = Column(String, primary_key=True, index=True)
    balance = Column(Float, default=0.0)


class RidePass(Base):
    __tablename__ = "ride_passes"
    id = Column(Integer, primary_key=True, index=True)
    device_id = Column(String, index=True, nullable=False)
    company = Column(String, nullable=False)
    rides_remaining = Column(Integer, default=0)


class StudentVerification(Base):
    __tablename__ = "student_verifications"
    device_id = Column(String, primary_key=True, index=True)
    status = Column(String, default="pending")  # pending / approved / rejected
    expiry_date = Column(String, nullable=True)
    image_base64 = Column(String, nullable=True)


# Creates all tables (users, wallets, ride_passes, student_verifications) if they don't exist
Base.metadata.create_all(bind=engine)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

GMAIL_ADDRESS = os.environ.get("GMAIL_ADDRESS")

# temporary in-memory OTP storage: email -> {"otp": "123456", "name":..., "phone":..., "password_hash":...}
pending_signups: dict[str, dict] = {}


def send_otp_email(to_email: str, otp: str):
    BREVO_API_KEY = os.environ.get("BREVO_API_KEY")

    response = httpx.post(
        "https://api.brevo.com/v3/smtp/email",
        headers={
            "api-key": BREVO_API_KEY,
            "Content-Type": "application/json",
        },
        json={
            "sender": {"name": "BusAm", "email": "rajbackup12345@gmail.com"},
            "to": [{"email": to_email}],
            "subject": "BusAm - Verify your email",
            "textContent": f"Your BusAm verification code is: {otp}",
        },
    )
    response.raise_for_status()


def haversine_km(lat1, lng1, lat2, lng2) -> float:
    """Straight-line distance between two GPS points, in kilometers."""
    R = 6371
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)

    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


# Speed tracking state
previous_location = {"lat": None, "lng": None, "time": None}
current_speed_kmh = 0.0
speed_samples = []  # recent speed readings, for smoothing
MAX_SPEED_SAMPLES = 20  # ~20 samples at 3-sec intervals ≈ 60 sec rolling window
MIN_MOVEMENT_SPEED_KMH = 0.5  # readings below this are treated as "stopped", not counted in the average

app = FastAPI()

# Every passenger currently connected and listening for updates
connected_passengers: list[WebSocket] = []

# The most recent location + route the driver sent — so a passenger
# who connects late still sees where the bus currently is
latest_location = {"lat": None, "lng": None, "route_id": None}

# Whether a driver is currently connected/broadcasting
driver_online = False


@app.websocket("/ws/driver")
async def driver_socket(websocket: WebSocket):
    global driver_online
    await websocket.accept()
    driver_online = True
    print("Driver connected")

    try:
        while True:
            data = await websocket.receive_text()
            location = json.loads(data)

            new_lat = location.get("lat")
            new_lng = location.get("lng")
            now = time.time()

            # ---- Speed calculation ----
            global current_speed_kmh
            if (
                previous_location["lat"] is not None
                and previous_location["time"] is not None
                and new_lat is not None
            ):
                time_elapsed = now - previous_location["time"]
                if time_elapsed > 0.5:  # avoid divide-by-zero / noise on very fast repeats
                    dist = haversine_km(
                        previous_location["lat"], previous_location["lng"], new_lat, new_lng
                    )
                    instantaneous_speed = (dist / time_elapsed) * 3600  # km/h

                    # only count genuine movement in the rolling average —
                    # this stops brief red-light/stop-sign pauses from dragging
                    # the average toward 0 every single time
                    if instantaneous_speed >= MIN_MOVEMENT_SPEED_KMH:
                        speed_samples.append(instantaneous_speed)
                        if len(speed_samples) > MAX_SPEED_SAMPLES:
                            speed_samples.pop(0)

                    current_speed_kmh = (
                        sum(speed_samples) / len(speed_samples) if speed_samples else 0.0
                    )

            previous_location["lat"] = new_lat
            previous_location["lng"] = new_lng
            previous_location["time"] = now

            latest_location["lat"] = new_lat
            latest_location["lng"] = new_lng
            latest_location["route_id"] = location.get("route_id")
            print(f"Received location: {latest_location}, speed: {current_speed_kmh:.1f} km/h")

            payload = json.dumps({
                **latest_location,
                "driver_online": True,
                "speed_kmh": round(current_speed_kmh, 1),
            })
            for passenger in connected_passengers:
                await passenger.send_text(payload)

    except WebSocketDisconnect:
        driver_online = False
        latest_location["route_id"] = None
        previous_location["lat"] = None
        previous_location["lng"] = None
        previous_location["time"] = None
        speed_samples.clear()
        current_speed_kmh = 0.0
        print("Driver disconnected")

        payload = json.dumps({
            "lat": None, "lng": None, "route_id": None,
            "driver_online": False, "speed_kmh": 0.0,
        })
        for passenger in connected_passengers:
            await passenger.send_text(payload)


@app.websocket("/ws/passenger")
async def passenger_socket(websocket: WebSocket):
    """
    The passenger's phone connects here ONCE, then just listens.
    """
    await websocket.accept()
    connected_passengers.append(websocket)
    print("Passenger connected")

    await websocket.send_text(json.dumps({
        **latest_location,
        "driver_online": driver_online,
        "speed_kmh": round(current_speed_kmh, 1),
    }))

    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        connected_passengers.remove(websocket)
        print("Passenger disconnected")


# ---- Trip tracking (still in-memory - transient by nature) ----
open_trips: dict[str, dict] = {}        # device_id -> {route_id, board_lat, board_lng}
pending_exits: dict[str, dict] = {}     # device_id -> {distance_km, fare, company}

PRICE_PER_RIDE = 20

# Which company each route belongs to — a pass only works on that company's buses
ROUTE_COMPANY = {
    "mayuri_jamal": "Mayuri",
    "mayuri_baudha": "Mayuri",
    "sajha_koteshwor": "Sajha",
}


def calculate_fare(distance_km: float) -> float:
    """Tiered fare based on distance. Used for wallet payment."""
    if distance_km <= 15:
        return 30.0
    elif distance_km <= 30:
        return 50.0
    elif distance_km <= 45:
        return 70.0
    else:
        return 90.0


class QrScanRequest(BaseModel):
    device_id: str
    route_id: str
    lat: float
    lng: float


@app.post("/qr/scan")
async def qr_scan(req: QrScanRequest):
    """
    Called every time a passenger scans the bus QR.
    First scan = board. Second scan = calculates trip details and
    returns payment OPTIONS (wallet vs pass) without deducting anything yet —
    the app then calls /qr/confirm_exit with the passenger's choice.
    """
    existing_trip = open_trips.get(req.device_id)

    if existing_trip is None:
        open_trips[req.device_id] = {
            "route_id": req.route_id,
            "board_lat": req.lat,
            "board_lng": req.lng,
        }
        return {
            "event": "boarded",
            "message": "Trip started. Scan again when you get off.",
        }

    else:
        distance = haversine_km(
            existing_trip["board_lat"], existing_trip["board_lng"], req.lat, req.lng
        )
        fare = calculate_fare(distance)
        company = ROUTE_COMPANY.get(existing_trip["route_id"])

        db = SessionLocal()
        wallet = db.query(Wallet).filter(Wallet.device_id == req.device_id).first()
        ride_pass = (
            db.query(RidePass)
            .filter(RidePass.device_id == req.device_id, RidePass.company == company)
            .first()
        ) if company else None
        db.close()

        wallet_balance = wallet.balance if wallet else 0.0
        rides_remaining = ride_pass.rides_remaining if ride_pass else 0

        pending_exits[req.device_id] = {
            "distance_km": round(distance, 2),
            "fare": fare,
            "company": company,
        }
        del open_trips[req.device_id]

        return {
            "event": "exit_pending",
            "distance_km": round(distance, 2),
            "wallet_fare": fare,
            "wallet_balance": wallet_balance,
            "company": company,
            "pass_rides_remaining": rides_remaining,
            "pass_available": rides_remaining > 0,
        }


class ConfirmExitRequest(BaseModel):
    device_id: str
    method: str  # "wallet" or "pass"


@app.post("/qr/confirm_exit")
async def confirm_exit(req: ConfirmExitRequest):
    pending = pending_exits.get(req.device_id)
    if pending is None:
        return {"success": False, "message": "No pending trip to confirm"}

    company = pending["company"]
    fare = pending["fare"]
    distance = pending["distance_km"]

    if req.method == "pass":
        db = SessionLocal()
        ride_pass = (
            db.query(RidePass)
            .filter(RidePass.device_id == req.device_id, RidePass.company == company)
            .first()
        )
        if not ride_pass or ride_pass.rides_remaining <= 0:
            db.close()
            return {"success": False, "message": "No pass rides remaining"}

        ride_pass.rides_remaining -= 1
        db.commit()
        remaining = ride_pass.rides_remaining
        db.close()

        del pending_exits[req.device_id]
        return {
            "success": True,
            "method": "pass",
            "distance_km": distance,
            "rides_remaining": remaining,
            "message": f"Trip complete using pass. {remaining} rides left.",
        }
    else:
        db = SessionLocal()
        wallet = db.query(Wallet).filter(Wallet.device_id == req.device_id).first()
        balance = wallet.balance if wallet else 0.0

        if balance < fare:
            db.close()
            return {"success": False, "message": "Insufficient wallet balance. Please load money."}

        if wallet:
            wallet.balance -= fare
        else:
            wallet = Wallet(device_id=req.device_id, balance=-fare)
            db.add(wallet)
        db.commit()
        new_balance = wallet.balance
        db.close()

        del pending_exits[req.device_id]
        return {
            "success": True,
            "method": "wallet",
            "distance_km": distance,
            "fare": fare,
            "balance": new_balance,
            "message": f"Trip complete. NPR {fare} deducted from wallet.",
        }


@app.get("/wallet/{device_id}")
async def get_wallet(device_id: str):
    db = SessionLocal()
    wallet = db.query(Wallet).filter(Wallet.device_id == device_id).first()
    db.close()
    return {"balance": wallet.balance if wallet else 0.0}


class LoadMoneyRequest(BaseModel):
    device_id: str
    amount: float


@app.post("/wallet/load")
async def load_wallet(req: LoadMoneyRequest):
    db = SessionLocal()
    wallet = db.query(Wallet).filter(Wallet.device_id == req.device_id).first()
    if wallet:
        wallet.balance += req.amount
    else:
        wallet = Wallet(device_id=req.device_id, balance=req.amount)
        db.add(wallet)
    db.commit()
    balance = wallet.balance
    db.close()
    return {"balance": balance}


# ---- Ride pass endpoints (per-company passes) ----

class BuyPassRequest(BaseModel):
    device_id: str
    company: str
    rides: int


@app.post("/pass/buy")
async def buy_pass(req: BuyPassRequest):
    if req.rides <= 0:
        return {"success": False, "message": "Invalid ride count"}

    cost = req.rides * PRICE_PER_RIDE
    db = SessionLocal()

    wallet = db.query(Wallet).filter(Wallet.device_id == req.device_id).first()
    balance = wallet.balance if wallet else 0.0

    if balance < cost:
        db.close()
        return {
            "success": False,
            "message": "Insufficient wallet balance",
            "wallet_balance": balance,
            "cost": cost,
        }

    if wallet:
        wallet.balance -= cost
    else:
        wallet = Wallet(device_id=req.device_id, balance=-cost)
        db.add(wallet)

    existing_pass = (
        db.query(RidePass)
        .filter(RidePass.device_id == req.device_id, RidePass.company == req.company)
        .first()
    )
    if existing_pass:
        existing_pass.rides_remaining += req.rides
        rides_remaining = existing_pass.rides_remaining
    else:
        new_pass = RidePass(device_id=req.device_id, company=req.company, rides_remaining=req.rides)
        db.add(new_pass)
        rides_remaining = req.rides

    db.commit()
    new_balance = wallet.balance
    db.close()

    return {
        "success": True,
        "message": f"Pass purchased: {req.rides} rides for {req.company}",
        "rides_remaining": rides_remaining,
        "wallet_balance": new_balance,
    }


@app.get("/pass/{device_id}")
async def get_passes(device_id: str):
    db = SessionLocal()
    passes = db.query(RidePass).filter(RidePass.device_id == device_id).all()
    db.close()
    return {"passes": {p.company: p.rides_remaining for p in passes}}



BASE_URL = "https://busam.onrender.com"
# ---- Khalti payment integration (KPG-2 Web Checkout, sandbox) ----

KHALTI_SECRET_KEY = os.environ.get("KHALTI_SECRET_KEY")
KHALTI_INITIATE_URL = "https://dev.khalti.com/api/v2/epayment/initiate/"
KHALTI_LOOKUP_URL = "https://dev.khalti.com/api/v2/epayment/lookup/"

pending_khalti_payments: dict[str, str] = {}  # pidx -> device_id


@app.get("/khalti/initiate")
async def khalti_initiate(amount: float, device_id: str):
    purchase_order_id = str(uuid.uuid4())

    payload = {
        "return_url": f"{BASE_URL}/khalti/callback",
        "website_url": BASE_URL,
        "amount": int(amount * 100),  # Khalti expects paisa, not rupees
        "purchase_order_id": purchase_order_id,
        "purchase_order_name": "BusAm Wallet Load",
        "customer_info": {
            "name": "BusAm User",
            "email": "user@busam.app",
            "phone": "9800000000",
        },
    }

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            KHALTI_INITIATE_URL,
            json=payload,
            headers={
                "Authorization": f"key {KHALTI_SECRET_KEY}",
                "Content-Type": "application/json",
            },
        )
        data = resp.json()

    if "pidx" not in data:
        return {"success": False, "message": data}

    pending_khalti_payments[data["pidx"]] = device_id

    return {"success": True, "payment_url": data["payment_url"], "pidx": data["pidx"]}


@app.get("/khalti/callback")
async def khalti_callback(pidx: str):
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            KHALTI_LOOKUP_URL,
            json={"pidx": pidx},
            headers={
                "Authorization": f"key {KHALTI_SECRET_KEY}",
                "Content-Type": "application/json",
            },
        )
        lookup_data = resp.json()

    if lookup_data.get("status") == "Completed":
        device_id = pending_khalti_payments.pop(pidx, None)
        credited_amount = int(lookup_data.get("total_amount", 0)) / 100  # back to NPR

        if device_id:
            db = SessionLocal()
            wallet = db.query(Wallet).filter(Wallet.device_id == device_id).first()
            if wallet:
                wallet.balance += credited_amount
            else:
                wallet = Wallet(device_id=device_id, balance=credited_amount)
                db.add(wallet)
            db.commit()
            db.close()

        return HTMLResponse("<h2>Payment verified! You can close this window.</h2>")
    else:
        return HTMLResponse(f"<h2>Payment not verified: {lookup_data}</h2>")


# ---- Mock payment simulator (reliable stand-in for the demo) ----

@app.get("/pay/mock/initiate")
async def mock_pay_initiate(amount: float, device_id: str):
    html = f"""
    <html>
    <body style="font-family: sans-serif; text-align: center; padding: 40px;">
      <h2>Mock Payment Gateway</h2>
      <p>Amount: NPR {amount}</p>
      <p>This simulates a real payment confirmation screen.</p>
      <form action="/pay/mock/confirm" method="POST">
        <input type="hidden" name="device_id" value="{device_id}">
        <input type="hidden" name="amount" value="{amount}">
        <button type="submit" style="padding: 12px 24px; font-size: 16px; background: green; color: white; border: none; border-radius: 8px;">
          Confirm Payment
        </button>
      </form>
    </body>
    </html>
    """
    return HTMLResponse(content=html)


@app.post("/pay/mock/confirm")
async def mock_pay_confirm(device_id: str = Form(...), amount: float = Form(...)):
    db = SessionLocal()
    wallet = db.query(Wallet).filter(Wallet.device_id == device_id).first()
    if wallet:
        wallet.balance += amount
    else:
        wallet = Wallet(device_id=device_id, balance=amount)
        db.add(wallet)
    db.commit()
    new_balance = wallet.balance
    db.close()

    return HTMLResponse(
        f"<h2>Payment successful! NPR {amount} added.</h2>"
        f"<p>New balance: NPR {new_balance}</p>"
    )


# ---- Signup / OTP / Login ----

class SignupRequest(BaseModel):
    name: str
    phone: str
    email: str
    password: str


@app.post("/signup")
async def signup(req: SignupRequest):
    db = SessionLocal()
    existing = db.query(User).filter(User.email == req.email).first()
    db.close()

    if existing:
        return {"success": False, "message": "Email already registered"}

    otp = str(random.randint(100000, 999999))
    password_hash = pwd_context.hash(req.password)

    pending_signups[req.email] = {
        "otp": otp,
        "name": req.name,
        "phone": req.phone,
        "password_hash": password_hash,
    }

    try:
        send_otp_email(req.email, otp)
    except Exception as e:
        return {"success": False, "message": f"Failed to send OTP: {e}"}

    return {"success": True, "message": "OTP sent to your email"}


class VerifyOtpRequest(BaseModel):
    email: str
    otp: str


@app.post("/verify-otp")
async def verify_otp(req: VerifyOtpRequest):
    pending = pending_signups.get(req.email)

    if not pending:
        return {"success": False, "message": "No pending signup for this email"}

    if pending["otp"] != req.otp:
        return {"success": False, "message": "Incorrect OTP"}

    db = SessionLocal()
    new_user = User(
        name=pending["name"],
        phone=pending["phone"],
        email=req.email,
        password_hash=pending["password_hash"],
        is_verified=True,
    )
    db.add(new_user)
    db.commit()
    db.close()

    del pending_signups[req.email]

    return {"success": True, "message": "Account created successfully"}


class LoginRequest(BaseModel):
    email: str
    password: str


@app.post("/login")
async def login(req: LoginRequest):
    db = SessionLocal()
    user = db.query(User).filter(User.email == req.email).first()
    db.close()

    if not user:
        return {"success": False, "message": "No account found with this email"}

    if not pwd_context.verify(req.password, user.password_hash):
        return {"success": False, "message": "Incorrect password"}

    return {
        "success": True,
        "message": "Login successful",
        "user": {
            "name": user.name,
            "phone": user.phone,
            "email": user.email,
        },
    }


# ---- Student ID verification ----

def is_student_verified(device_id: str) -> bool:
    db = SessionLocal()
    record = db.query(StudentVerification).filter(
        StudentVerification.device_id == device_id
    ).first()
    db.close()
    if not record or record.status != "approved" or not record.expiry_date:
        return False
    return date.fromisoformat(record.expiry_date) >= date.today()


class SubmitIdRequest(BaseModel):
    device_id: str
    image_base64: str


@app.post("/student-id/submit")
async def submit_student_id(req: SubmitIdRequest):
    db = SessionLocal()
    record = db.query(StudentVerification).filter(
        StudentVerification.device_id == req.device_id
    ).first()
    if record:
        record.status = "pending"
        record.image_base64 = req.image_base64
        record.expiry_date = None
    else:
        record = StudentVerification(
            device_id=req.device_id, status="pending", image_base64=req.image_base64
        )
        db.add(record)
    db.commit()
    db.close()
    return {"success": True, "message": "ID submitted, pending review."}


@app.get("/student-id/status/{device_id}")
async def get_student_id_status(device_id: str):
    db = SessionLocal()
    record = db.query(StudentVerification).filter(
        StudentVerification.device_id == device_id
    ).first()
    db.close()
    if not record:
        return {"status": "none"}
    verified = (
        record.status == "approved"
        and record.expiry_date
        and date.fromisoformat(record.expiry_date) >= date.today()
    )
    return {"status": record.status, "expiry_date": record.expiry_date, "verified": verified}


@app.get("/admin/student-id/pending")
async def list_pending_student_ids():
    db = SessionLocal()
    records = db.query(StudentVerification).filter(
        StudentVerification.status == "pending"
    ).all()
    db.close()
    return {
        "pending": {
            r.device_id: {"image_base64": r.image_base64} for r in records
        }
    }


class ApproveIdRequest(BaseModel):
    device_id: str
    expiry_date: str


@app.post("/admin/student-id/approve")
async def approve_student_id(req: ApproveIdRequest):
    db = SessionLocal()
    record = db.query(StudentVerification).filter(
        StudentVerification.device_id == req.device_id
    ).first()
    if not record:
        db.close()
        return {"success": False, "message": "No submission found"}
    record.status = "approved"
    record.expiry_date = req.expiry_date
    db.commit()
    db.close()
    return {"success": True, "message": "Approved"}


class RejectIdRequest(BaseModel):
    device_id: str


@app.post("/admin/student-id/reject")
async def reject_student_id(req: RejectIdRequest):
    db = SessionLocal()
    record = db.query(StudentVerification).filter(
        StudentVerification.device_id == req.device_id
    ).first()
    if not record:
        db.close()
        return {"success": False, "message": "No submission found"}
    record.status = "rejected"
    db.commit()
    db.close()
    return {"success": True, "message": "Rejected"}

@app.get("/admin/debug/all")
async def debug_all():
    db = SessionLocal()
    users = db.query(User).all()
    wallets = db.query(Wallet).all()
    passes = db.query(RidePass).all()
    db.close()
    return {
        "users": [{"name": u.name, "email": u.email, "phone": u.phone} for u in users],
        "wallets": [{"device_id": w.device_id, "balance": w.balance} for w in wallets],
        "ride_passes": [{"device_id": p.device_id, "company": p.company, "rides_remaining": p.rides_remaining} for p in passes],
    }