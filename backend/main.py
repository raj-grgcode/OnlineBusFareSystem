from pydantic import BaseModel
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
import json
import math
import uuid as uuid_lib
import hmac
import hashlib
import base64
import uuid
import httpx

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
open_trips: dict[str, dict] = {}        # device_id -> {route_id, board_lat, board_lng, board_time}


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
    """Tiered fare based on distance."""
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
    First scan = board, second scan (while a trip is open) = exit + fare deduction.
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
        # ---- EXIT ----
        distance = haversine_km(
            existing_trip["board_lat"], existing_trip["board_lng"], req.lat, req.lng
        )
        fare = calculate_fare(distance)

        balance = wallets.get(req.device_id, 0.0)
        if balance < fare:
            # Not enough balance - trip stays open? Or force clear it.
            # For demo purposes, clear the trip either way but flag insufficient funds.
            del open_trips[req.device_id]
            return {
                "event": "exit",
                "distance_km": round(distance, 2),
                "fare": fare,
                "success": False,
                "message": "Insufficient balance. Please load money.",
                "balance": balance,
            }

        wallets[req.device_id] = balance - fare
        del open_trips[req.device_id]

        return {
            "event": "exit",
            "distance_km": round(distance, 2),
            "fare": fare,
            "success": True,
            "message": f"Trip complete. NPR {fare} deducted.",
            "balance": wallets[req.device_id],
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


# ---- eSewa payment integration (UAT/sandbox — safe for testing) ----

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