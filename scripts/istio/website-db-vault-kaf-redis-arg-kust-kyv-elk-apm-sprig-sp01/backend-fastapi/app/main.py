from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import List, Optional
import asyncpg
import redis.asyncio as aioredis
import json
import os
from datetime import datetime, date
from kafka import KafkaProducer
import uvicorn
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI(title="DavTro Rentals API", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)

DB_HOST = os.getenv("DB_HOST", "postgres-db")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "davtro_rentals")
DB_USER = os.getenv("DB_USER", "davtro")
DB_PASS = os.getenv("DB_PASSWORD", "changeme")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "kafka-kraft:9092")

db_pool = None
redis_pool = None
kafka_producer = None

class BookingCreate(BaseModel):
    property_id: int
    guest_name: str
    email: EmailStr
    phone: Optional[str] = None
    guests: int = 1
    check_in: date
    check_out: date
    total_price: float

class BookingResponse(BaseModel):
    id: str
    property_id: int
    property_name: str
    guest_name: str
    email: str
    check_in: str
    check_out: str
    total_price: float
    status: str
    created_at: str

@app.on_event("startup")
async def startup():
    global db_pool, redis_pool, kafka_producer
    db_pool = await asyncpg.create_pool(host=DB_HOST, port=DB_PORT, database=DB_NAME, user=DB_USER, password=DB_PASS, min_size=5, max_size=20)
    redis_pool = aioredis.from_url(f"redis://{REDIS_HOST}:{REDIS_PORT}", decode_responses=True)
    kafka_producer = KafkaProducer(bootstrap_servers=KAFKA_BOOTSTRAP, value_serializer=lambda v: json.dumps(v).encode('utf-8'))
    await init_db()

@app.on_event("shutdown")
async def shutdown():
    if db_pool: await db_pool.close()
    if redis_pool: await redis_pool.close()
    if kafka_producer: kafka_producer.close()

async def init_db():
    async with db_pool.acquire() as conn:
        await conn.execute('CREATE TABLE IF NOT EXISTS properties (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL, location VARCHAR(100), price DECIMAL(10,2), guests INT DEFAULT 2, description TEXT, amenities JSONB DEFAULT \'[]\', created_at TIMESTAMP DEFAULT NOW())')
        await conn.execute('CREATE TABLE IF NOT EXISTS bookings (id VARCHAR(50) PRIMARY KEY, property_id INT REFERENCES properties(id), guest_name VARCHAR(255), email VARCHAR(255), phone VARCHAR(50), guests INT, check_in DATE, check_out DATE, nights INT, total_price DECIMAL(10,2), status VARCHAR(50) DEFAULT \'confirmed\', pipeline VARCHAR(100) DEFAULT \'Redis -> Kafka -> PostgreSQL\', created_at TIMESTAMP DEFAULT NOW())')
        count = await conn.fetchval("SELECT COUNT(*) FROM properties")
        if count == 0:
            await conn.execute("""INSERT INTO properties (id, name, location, price, guests, description, amenities) VALUES
                (1, 'Apartament Premium - Warszawa', 'warsaw', 450, 4, 'Luksusowy apartament w centrum', '["WiFi","Klimatyzacja","Balkon","Parking"]'),
                (2, 'Studio Modern - Krakow', 'krakow', 320, 2, 'Stylowe studio obok Rynku', '["WiFi","Smart TV","Kuchnia"]'),
                (3, 'Villa nad Morzem - Gdansk', 'gdansk', 680, 6, 'Willa 200m od plazy', '["WiFi","Ogrodek","Grill","Parking"]'),
                (4, 'Loft Industrial - Wroclaw', 'wroclaw', 280, 3, 'Industrialny loft', '["WiFi","Projektor","Klimatyzacja"]'),
                (5, 'Penthouse View - Warszawa', 'warsaw', 850, 4, 'Ekskluzywny penthouse', '["WiFi","Basen","Silownia","Concierge"]'),
                (6, 'Apartament Royal - Krakow', 'krakow', 390, 4, 'Elegancki apartament w Kazimierzu', '["WiFi","Klimatyzacja","Balkon"]')
                ON CONFLICT DO NOTHING""")

@app.get("/api/health")
async def health():
    redis_ok = await redis_pool.ping()
    async with db_pool.acquire() as conn:
        db_ok = await conn.fetchval("SELECT 1")
    return {"status": "healthy", "database": db_ok == 1, "redis": redis_ok, "kafka": kafka_producer is not None}

@app.get("/api/properties")
async def get_properties():
    cache_key = "properties:all"
    cached = await redis_pool.get(cache_key)
    if cached: return json.loads(cached)
    async with db_pool.acquire() as conn:
        rows = await conn.fetch("SELECT * FROM properties ORDER BY id")
    properties = [{"id": r["id"], "name": r["name"], "location": r["location"], "price": float(r["price"]), "guests": r["guests"], "description": r["description"], "amenities": json.loads(r["amenities"])} for r in rows]
    await redis_pool.setex(cache_key, 300, json.dumps(properties))
    return properties

@app.post("/api/bookings")
async def create_booking(booking: BookingCreate, background_tasks: BackgroundTasks):
    booking_id = f"BK-{datetime.now().strftime('%Y%m%d%H%M%S')}-{booking.property_id}"
    nights = (booking.check_out - booking.check_in).days
    cache_key = f"booking:{booking_id}"
    booking_data = booking.dict()
    booking_data.update({"id": booking_id, "nights": nights, "status": "pending"})
    await redis_pool.setex(cache_key, 3600, json.dumps(booking_data))
    kafka_producer.send("bookings-created", {"event": "booking_created", "booking_id": booking_id, "property_id": booking.property_id, "guest_name": booking.guest_name, "email": booking.email, "phone": booking.phone, "check_in": str(booking.check_in), "check_out": str(booking.check_out), "nights": nights, "total_price": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    kafka_producer.send("email-invoices", {"event": "invoice_request", "booking_id": booking_id, "email": booking.email, "guest_name": booking.guest_name, "total_price": float(booking.total_price), "property_id": booking.property_id, "check_in": str(booking.check_in), "check_out": str(booking.check_out)})
    kafka_producer.send("marketing-actions", {"event": "new_booking", "property_id": booking.property_id, "guest_email": booking.email, "guest_name": booking.guest_name, "booking_value": float(booking.total_price), "timestamp": datetime.now().isoformat()})
    kafka_producer.flush()
    return BookingResponse(id=booking_id, property_id=booking.property_id, property_name="", guest_name=booking.guest_name, email=booking.email, check_in=str(booking.check_in), check_out=str(booking.check_out), total_price=booking.total_price, status="pending", created_at=datetime.now().isoformat())

@app.get("/api/bookings")
async def get_bookings():
    async with db_pool.acquire() as conn:
        rows = await conn.fetch("SELECT b.*, p.name as property_name FROM bookings b JOIN properties p ON b.property_id = p.id ORDER BY b.created_at DESC")
    return [BookingResponse(id=r["id"], property_id=r["property_id"], property_name=r["property_name"], guest_name=r["guest_name"], email=r["email"], check_in=str(r["check_in"]), check_out=str(r["check_out"]), total_price=float(r["total_price"]), status=r["status"], created_at=str(r["created_at"])) for r in rows]

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
