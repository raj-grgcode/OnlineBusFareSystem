from pydantic import BaseModel
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Form
from fastapi.responses import HTMLResponse
import json
import math
import uuid as uuid_lib
import hmac
import hashlib
import base64
import uuid
import httpx
import os
from sqlalchemy import create_engine, Column, Integer, String, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

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


# Creates the users table in Postgres if it doesn't already exist
Base.metadata.create_all(bind=engine)
import random
import smtplib
from email.mime.text import MIMEText
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

GMAIL_ADDRESS = os.environ.get("GMAIL_ADDRESS")
GMAIL_APP_PASSWORD = os.environ.get("GMAIL_APP_PASSWORD")

# temporary in-memory OTP storage: email -> {"otp": "123456", "name":..., "phone":..., "password_hash":...}
pending_signups: dict[str, dict] = {}


def send_otp_email(to_email: str, otp: str):
    msg = MIMEText(f"Your BusAm verification code is: {otp}")
    msg["Subject"] = "BusAm - Verify your email"
    msg["From"] = GMAIL_ADDRESS
    msg["To"] = to_email

    with smtplib.SMTP_SSL("smtp.gmail.com", 465) as server:
        server.login(GMAIL_ADDRESS, GMAIL_APP_PASSWORD)
        server.sendmail(GMAIL_ADDRESS, to_email, msg.as_string())

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
    """
    The driver's phone connects here ONCE, then keeps sending
    new locations (+ route_id) over this same open connection.
    """
    global driver_online
    await websocket.accept()
    driver_online = True
    print("Driver connected")

    try:
        while True:
            data = await websocket.receive_text()
            location = json.loads(data)  # {"lat": ..., "lng": ..., "route_id": ...}

            latest_location["lat"] = location.get("lat")
            latest_location["lng"] = location.get("lng")
            latest_location["route_id"] = location.get("route_id")
            print(f"Received location: {latest_location}")

            # Push this new location to every connected passenger
            payload = json.dumps({**latest_location, "driver_online": True})
            for passenger in connected_passengers:
                await passenger.send_text(payload)

    except WebSocketDisconnect:
        driver_online = False
        latest_location["route_id"] = None
        print("Driver disconnected")

        # Let passengers know the bus went offline
        payload = json.dumps({"lat": None, "lng": None, "route_id": None, "driver_online": False})
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

    # Send whatever the last known state was immediately
    await websocket.send_text(json.dumps({**latest_location, "driver_online": driver_online}))

    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        connected_passengers.remove(websocket)
        print("Passenger disconnected")



# ---- Wallet + Trip tracking (in-memory, no DB yet) ----
# Since there's no login system yet, each phone gets a random device_id
# on first launch (generated client-side), and that's used as the "user"

wallets: dict[str, float] = {}          # device_id -> balance
open_trips: dict[str, dict] = {}        # device_id -> {route_id, board_lat, board_lng}
pending_exits: dict[str, dict] = {}     # device_id -> {distance_km, fare, company}

# ---- Ride passes (flat-rate bundles, NPR 20/ride, scoped per company) ----
ride_passes: dict[str, dict[str, int]] = {}   # device_id -> {company: rides_remaining}
PRICE_PER_RIDE = 20

# Which company each route belongs to — a pass only works on that company's buses
ROUTE_COMPANY = {
    "mayuri_jamal": "Mayuri",
    "mayuri_baudha": "Mayuri",
    "sajha_koteshwor": "Sajha",
}


def haversine_km(lat1, lng1, lat2, lng2) -> float:
    """Straight-line distance between two GPS points, in kilometers."""
    R = 6371  # Earth radius in km
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)

    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c


def calculate_fare(distance_km: float) -> float:
    """Tiered fare based on distance. Used for wallet payment."""
    if distance_km <= 15:
        return 30.0
    elif distance_km <= 30:
        return 50.0
    elif distance_km <= 45:
        return 70.0
    else:
        return 90.0  # fallback for longer trips


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
        # ---- BOARDING ----
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
        # ---- EXIT: calculate, but don't deduct yet ----
        distance = haversine_km(
            existing_trip["board_lat"], existing_trip["board_lng"], req.lat, req.lng
        )
        fare = calculate_fare(distance)
        company = ROUTE_COMPANY.get(existing_trip["route_id"])
        rides_remaining = ride_passes.get(req.device_id, {}).get(company, 0) if company else 0

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
            "wallet_balance": wallets.get(req.device_id, 0.0),
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
        company_passes = ride_passes.setdefault(req.device_id, {})
        remaining = company_passes.get(company, 0)
        if remaining <= 0:
            return {"success": False, "message": "No pass rides remaining"}
        company_passes[company] = remaining - 1
        del pending_exits[req.device_id]
        return {
            "success": True,
            "method": "pass",
            "distance_km": distance,
            "rides_remaining": company_passes[company],
            "message": f"Trip complete using pass. {company_passes[company]} rides left.",
        }
    else:
        balance = wallets.get(req.device_id, 0.0)
        if balance < fare:
            return {"success": False, "message": "Insufficient wallet balance. Please load money."}
        wallets[req.device_id] = balance - fare
        del pending_exits[req.device_id]
        return {
            "success": True,
            "method": "wallet",
            "distance_km": distance,
            "fare": fare,
            "balance": wallets[req.device_id],
            "message": f"Trip complete. NPR {fare} deducted from wallet.",
        }


@app.get("/wallet/{device_id}")
async def get_wallet(device_id: str):
    return {"balance": wallets.get(device_id, 0.0)}


class LoadMoneyRequest(BaseModel):
    device_id: str
    amount: float


@app.post("/wallet/load")
async def load_wallet(req: LoadMoneyRequest):
    """
    Manually add money to wallet - stand-in until real eSewa payment
    verification is wired in later.
    """
    wallets[req.device_id] = wallets.get(req.device_id, 0.0) + req.amount
    return {"balance": wallets[req.device_id]}


# ---- Ride pass endpoints (per-company passes) ----

class BuyPassRequest(BaseModel):
    device_id: str
    company: str
    rides: int


@app.post("/pass/buy")
async def buy_pass(req: BuyPassRequest):
    """
    Buys a bundle of `rides` ride-credits for a specific company,
    at NPR 20/ride, deducted from wallet. Only usable on that company's buses.
    """
    if req.rides <= 0:
        return {"success": False, "message": "Invalid ride count"}

    cost = req.rides * PRICE_PER_RIDE
    balance = wallets.get(req.device_id, 0.0)

    if balance < cost:
        return {
            "success": False,
            "message": "Insufficient wallet balance",
            "wallet_balance": balance,
            "cost": cost,
        }

    wallets[req.device_id] = balance - cost
    company_passes = ride_passes.setdefault(req.device_id, {})
    company_passes[req.company] = company_passes.get(req.company, 0) + req.rides

    return {
        "success": True,
        "message": f"Pass purchased: {req.rides} rides for {req.company}",
        "rides_remaining": company_passes[req.company],
        "wallet_balance": wallets[req.device_id],
    }


@app.get("/pass/{device_id}")
async def get_passes(device_id: str):
    return {"passes": ride_passes.get(device_id, {})}


# ---- eSewa payment integration (UAT/sandbox — kept for reference, not currently used) ----

ESEWA_SECRET_KEY = "8gBm/:&EnhH.1/q"
ESEWA_PRODUCT_CODE = "EPAYTEST"
ESEWA_FORM_URL = "https://rc-epay.esewa.com.np/api/epay/main/v2/form"
ESEWA_STATUS_URL = "https://rc.esewa.com.np/api/epay/transaction/status/"

BASE_URL = "https://busam.onrender.com"  # your deployed backend

# tracks transaction_uuid -> device_id, so /pay/success knows whose wallet to credit
pending_payments: dict[str, str] = {}


def generate_signature(total_amount: str, transaction_uuid: str, product_code: str) -> str:
    """
    eSewa requires HMAC-SHA256 signature over specific fields, in this exact order.
    """
    message = f"total_amount={total_amount},transaction_uuid={transaction_uuid},product_code={product_code}"
    hmac_obj = hmac.new(
        ESEWA_SECRET_KEY.encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256,
    )
    return base64.b64encode(hmac_obj.digest()).decode("utf-8")


@app.get("/pay/initiate")
async def initiate_payment(amount: float, device_id: str):
    """
    Called by the Flutter app before opening the WebView.
    Returns an HTML page with a pre-filled form that auto-submits
    to eSewa (ePay v2 flow expects an HTML form POST, not raw JSON).
    """
    transaction_uuid = str(uuid.uuid4())
    total_amount = str(amount)

    signature = generate_signature(total_amount, transaction_uuid, ESEWA_PRODUCT_CODE)

    # remember which device_id this transaction belongs to
    pending_payments[transaction_uuid] = device_id

    success_url = f"{BASE_URL}/pay/success"
    failure_url = f"{BASE_URL}/pay/failure"

    html = f"""
    <html>
    <body onload="document.forms[0].submit()">
      <form action="{ESEWA_FORM_URL}" method="POST">
        <input type="hidden" name="amount" value="{total_amount}">
        <input type="hidden" name="tax_amount" value="0">
        <input type="hidden" name="total_amount" value="{total_amount}">
        <input type="hidden" name="transaction_uuid" value="{transaction_uuid}">
        <input type="hidden" name="product_code" value="{ESEWA_PRODUCT_CODE}">
        <input type="hidden" name="product_service_charge" value="0">
        <input type="hidden" name="product_delivery_charge" value="0">
        <input type="hidden" name="success_url" value="{success_url}">
        <input type="hidden" name="failure_url" value="{failure_url}">
        <input type="hidden" name="signed_field_names" value="total_amount,transaction_uuid,product_code">
        <input type="hidden" name="signature" value="{signature}">
      </form>
    </body>
    </html>
    """
    return HTMLResponse(content=html)


@app.get("/pay/success")
async def payment_success(data: str):
    """
    eSewa redirects here after payment, with a base64-encoded 'data' query param.
    We MUST verify with eSewa's server directly - never trust this redirect alone.
    """
    decoded = json.loads(base64.b64decode(data).decode("utf-8"))
    transaction_uuid = decoded.get("transaction_uuid")
    total_amount = decoded.get("total_amount")

    async with httpx.AsyncClient() as client:
        resp = await client.get(
            ESEWA_STATUS_URL,
            params={
                "product_code": ESEWA_PRODUCT_CODE,
                "total_amount": total_amount,
                "transaction_uuid": transaction_uuid,
            },
        )
        status_data = resp.json()

    if status_data.get("status") == "COMPLETE":
        device_id = pending_payments.pop(transaction_uuid, None)
        if device_id:
            wallets[device_id] = wallets.get(device_id, 0.0) + float(total_amount)
        return HTMLResponse("<h2>Payment verified! You can close this window.</h2>")
    else:
        return HTMLResponse(f"<h2>Payment not verified: {status_data}</h2>")


@app.get("/pay/failure")
async def payment_failure():
    return HTMLResponse("<h2>Payment failed or cancelled.</h2>")


# ---- Mock payment simulator (reliable stand-in for the demo) ----
# Simulates a real payment gateway flow (WebView -> confirm -> wallet credited)
# without depending on third-party sandbox infrastructure.

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
    wallets[device_id] = wallets.get(device_id, 0.0) + amount
    return HTMLResponse(
        f"<h2>Payment successful! NPR {amount} added.</h2>"
        f"<p>New balance: NPR {wallets[device_id]}</p>"
    )