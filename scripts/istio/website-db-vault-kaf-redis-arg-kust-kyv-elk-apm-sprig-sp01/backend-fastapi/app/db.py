import os
from sqlalchemy import create_engine, Column, Integer, String, Numeric, Date, Boolean, DateTime, func
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@postgres-clusterip:5432/davtro",
)

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()


class Apartment(Base):
    __tablename__ = "apartments"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    description = Column(String)
    price_per_night = Column(Numeric(10, 2), nullable=False)


class Booking(Base):
    __tablename__ = "bookings"
    id = Column(Integer, primary_key=True)
    apartment_id = Column(Integer, nullable=False)
    date_from = Column(Date, nullable=False)
    date_to = Column(Date, nullable=False)
    guest_name = Column(String, nullable=False)
    guest_email = Column(String, nullable=False)
    marketing_consent = Column(Boolean, default=False)
    status = Column(String, default="pending")
    invoice_sent = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())


def init_db():
    Base.metadata.create_all(bind=engine)
    session = SessionLocal()
    if session.query(Apartment).count() == 0:
        session.add_all([
            Apartment(name="Apartament Centrum", description="2 pokoje, blisko rynku", price_per_night=250),
            Apartment(name="Apartament Panoramiczny", description="Widok na miasto", price_per_night=320),
            Apartment(name="Studio Kompakt", description="Idealne dla pary", price_per_night=180),
        ])
        session.commit()
    session.close()
