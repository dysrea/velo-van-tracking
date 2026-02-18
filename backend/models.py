from sqlalchemy import Column, String, Integer, Float, Boolean, JSON
from database import Base
import uuid

def generate_uuid():
    return str(uuid.uuid4())

class User(Base):
    __tablename__ = "users"
    id = Column(String, primary_key=True, default=generate_uuid)
    email = Column(String, unique=True, index=True)
    
    # MATCHING main.py: We use 'hashed_password' now
    hashed_password = Column(String) 
    
    role = Column(String) 
    
    # THE MISSING FIELD:
    agency_name = Column(String, nullable=True) 
    
    status = Column(String, default="pending")

class Van(Base):
    __tablename__ = "vans"
    id = Column(String, primary_key=True, default=generate_uuid)
    van_number = Column(String)
    capacity = Column(Integer)
    agency_id = Column(String)
    assigned_driver_id = Column(String, nullable=True)
    status = Column(String, default="pending")
    track_always = Column(Boolean, default=False)
    current_lat = Column(Float, default=18.5204)
    current_lng = Column(Float, default=73.8567)
    start_lat = Column(Float, default=18.5204)
    start_lng = Column(Float, default=73.8567)

class Driver(Base):
    __tablename__ = "drivers"
    id = Column(String, primary_key=True, default=generate_uuid)
    name = Column(String)
    email = Column(String, unique=True)
    password = Column(String)
    agency_id = Column(String)
    assigned_van_id = Column(String, nullable=True)
    status = Column(String, default="pending")

class Student(Base):
    __tablename__ = "students"
    id = Column(String, primary_key=True, default=generate_uuid)
    name = Column(String)
    home_lat = Column(Float)
    home_lng = Column(Float)
    school_lat = Column(Float, default=0.0)
    school_lng = Column(Float, default=0.0)
    agency_id = Column(String)
    assigned_van_id = Column(String, nullable=True)
    schedule = Column(String)
    status = Column(String, default="approved")

class Route(Base):
    __tablename__ = "routes"
    id = Column(String, primary_key=True, default=generate_uuid)
    agency_id = Column(String)
    van_id = Column(String)
    driver_id = Column(String, nullable=True)
    trip_type = Column(String)
    stops = Column(JSON) 
    student_ids = Column(JSON)