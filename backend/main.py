from fastapi import FastAPI, WebSocket, WebSocketDisconnect
import json

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