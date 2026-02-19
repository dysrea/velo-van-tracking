from fastapi import FastAPI, HTTPException, Depends, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from typing import List, Optional
import json
import uuid
from sqlalchemy.orm import Session
from database import SessionLocal
import models
import auth

import models, auth
from database import engine, get_db

models.Base.metadata.create_all(bind=engine)
def seed_admin():
    db = SessionLocal()
    # Check if the admin already exists
    existing_admin = db.query(models.User).filter(models.User.role == "admin").first()
    
    if not existing_admin:
        print("No admin found. Auto-creating default admin...")
        # Create the admin user (Update the fields to match your actual User model)
        new_admin = models.User(
            agency_name="admin", 
            email="admin@velo.com",
            # Replace 'get_password_hash' with however you hash passwords in your code
            hashed_password=auth.get_password_hash("admin123"), 
            role="admin",
            status="approved" # Or whatever makes them active
        )
        db.add(new_admin)
        db.commit()
        print("Admin created: admin@velo.com / admin123")
    db.close()

# Run the function every time the server starts
seed_admin()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from pydantic import BaseModel

class UserSchema(BaseModel):
    email: str
    password: str
    role: str
    agency_name: Optional[str] = None

class VanSchema(BaseModel):
    van_number: str
    capacity: int
    agency_id: str
    start_lat: Optional[float] = 18.5204
    start_lng: Optional[float] = 73.8567

class DriverSchema(BaseModel):
    name: str
    email: str
    password: str
    agency_id: str
    assigned_van_id: Optional[str] = None

class StudentSchema(BaseModel):
    name: str
    home_lat: float
    home_lng: float
    school_lat: Optional[float] = 0.0
    school_lng: Optional[float] = 0.0
    agency_id: str
    schedule: str

class RouteSchema(BaseModel):
    agency_id: str
    van_id: str
    trip_type: str
    student_ids: List[str]

class AssignmentRequest(BaseModel):
    van_id: str
    driver_id: str

class DriverLogin(BaseModel):
    agency_email: str
    van_number: str
    password: str

class LocationUpdate(BaseModel):
    van_id: str
    lat: float
    lng: float
    status: str

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: str):
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except:
                pass

manager = ConnectionManager()

@app.post("/register")
def register(user: UserSchema, db: Session = Depends(get_db)):
    # Check if exists
    existing_user = db.query(models.User).filter(models.User.email == user.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Email already exists")
    
    # Hash Password & Save
    hashed_pw = auth.get_password_hash(user.password)
    new_user = models.User(
        email=user.email, 
        hashed_password=hashed_pw, 
        role=user.role, 
        agency_name=user.agency_name,
        status="pending"
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return {"message": "Registration successful", "user": new_user}

@app.post("/login")
def login(user: UserSchema, db: Session = Depends(get_db)):
    # Agency/Admin Login
    found_user = db.query(models.User).filter(models.User.email == user.email).first()
    if found_user:
        if not auth.verify_password(user.password, found_user.hashed_password):
             raise HTTPException(status_code=400, detail="Invalid credentials")
        return found_user

    # Driver Login 
    found_driver = db.query(models.Driver).filter(models.Driver.email == user.email).first()
    if found_driver:
        if found_driver.password != user.password and not auth.verify_password(user.password, found_driver.password):
             raise HTTPException(status_code=400, detail="Invalid credentials")
        
        if found_driver.status != 'approved':
             raise HTTPException(status_code=400, detail="Driver account not approved yet")
             
        return {
            "id": found_driver.id,
            "email": found_driver.email,
            "role": "driver",
            "name": found_driver.name,
            "assigned_van_id": found_driver.assigned_van_id
        }

    raise HTTPException(status_code=400, detail="Invalid credentials")

@app.post("/login/driver")
def driver_login(creds: DriverLogin, db: Session = Depends(get_db)):
    # Find Agency
    agency = db.query(models.User).filter(models.User.email == creds.agency_email, models.User.role == 'agency').first()
    if not agency: raise HTTPException(status_code=404, detail="Agency not found")

    # Find Van
    van = db.query(models.Van).filter(models.Van.van_number == creds.van_number, models.Van.agency_id == agency.id).first()
    if not van: raise HTTPException(status_code=404, detail="Van number not found")
    
    # Check Driver Assignment
    if not van.assigned_driver_id: raise HTTPException(status_code=400, detail="No driver assigned to this van")
    
    # Find Driver
    driver = db.query(models.Driver).filter(models.Driver.id == van.assigned_driver_id).first()
    if not driver: raise HTTPException(status_code=404, detail="Driver profile missing")

    # Verify Password
    if driver.password != creds.password: raise HTTPException(status_code=400, detail="Invalid Password")
    if driver.status != 'approved': raise HTTPException(status_code=400, detail="Driver not approved")

    return {
        "id": driver.id,
        "name": driver.name,
        "role": "driver",
        "assigned_van_id": van.id,
        "agency_id": van.agency_id
    }

@app.post("/vans/add")
def add_van(van: VanSchema, db: Session = Depends(get_db)):
    new_van = models.Van(**van.dict(), status="pending")
    db.add(new_van)
    db.commit()
    return {"message": "Van added successfully"}

@app.get("/vans/{agency_id}")
def get_vans(agency_id: str, db: Session = Depends(get_db)):
    if agency_id == "super_admin":
        return db.query(models.Van).all()
    return db.query(models.Van).filter(models.Van.agency_id == agency_id).all()

@app.put("/vans/update/{van_id}")
def update_van(van_id: str, updated_van: VanSchema, db: Session = Depends(get_db)):
    van = db.query(models.Van).filter(models.Van.id == van_id).first()
    if not van: raise HTTPException(status_code=404, detail="Van not found")
    
    van.van_number = updated_van.van_number
    van.capacity = updated_van.capacity
    van.start_lat = updated_van.start_lat
    van.start_lng = updated_van.start_lng
    
    db.commit()
    return {"message": "Van updated"}

@app.delete("/vans/delete/{van_id}")
def delete_van(van_id: str, db: Session = Depends(get_db)):
    db.query(models.Van).filter(models.Van.id == van_id).delete()
    db.commit()
    return {"message": "Van deleted"}

@app.post("/drivers/add")
def add_driver(driver: DriverSchema, db: Session = Depends(get_db)):
    new_driver = models.Driver(**driver.dict(), status="pending")
    db.add(new_driver)
    db.commit()
    
    # Link Van if selected
    if new_driver.assigned_van_id:
        van = db.query(models.Van).filter(models.Van.id == new_driver.assigned_van_id).first()
        if van:
            van.assigned_driver_id = new_driver.id
            db.commit()
            
    return {"message": "Driver added"}

@app.get("/drivers/{agency_id}")
def get_drivers(agency_id: str, db: Session = Depends(get_db)):
    if agency_id == "super_admin":
        return db.query(models.Driver).all()
    return db.query(models.Driver).filter(models.Driver.agency_id == agency_id).all()

@app.put("/drivers/update/{driver_id}")
def update_driver(driver_id: str, updated_driver: DriverSchema, db: Session = Depends(get_db)):
    driver = db.query(models.Driver).filter(models.Driver.id == driver_id).first()
    if not driver: raise HTTPException(status_code=404, detail="Driver not found")
    
    driver.name = updated_driver.name
    driver.email = updated_driver.email
    driver.password = updated_driver.password
    db.commit()
    return {"message": "Driver updated"}

@app.delete("/drivers/delete/{driver_id}")
def delete_driver(driver_id: str, db: Session = Depends(get_db)):
    # Unlink van first
    van = db.query(models.Van).filter(models.Van.assigned_driver_id == driver_id).first()
    if van:
        van.assigned_driver_id = None
        
    db.query(models.Driver).filter(models.Driver.id == driver_id).delete()
    db.commit()
    return {"message": "Driver deleted"}

@app.post("/students/add")
def add_student(student: StudentSchema, db: Session = Depends(get_db)):
    new_student = models.Student(**student.dict(), status="approved")
    db.add(new_student)
    db.commit()
    return {"message": "Student added"}

@app.get("/students/{agency_id}")
def get_students(agency_id: str, db: Session = Depends(get_db)):
    if agency_id == "super_admin": return db.query(models.Student).all()
    return db.query(models.Student).filter(models.Student.agency_id == agency_id).all()

@app.put("/students/update/{student_id}")
def update_student(student_id: str, updated_student: StudentSchema, db: Session = Depends(get_db)):
    student = db.query(models.Student).filter(models.Student.id == student_id).first()
    if not student: raise HTTPException(status_code=404, detail="Student not found")
    
    for key, value in updated_student.dict().items():
        setattr(student, key, value)
    
    db.commit()
    return {"message": "Student updated"}

@app.delete("/students/delete/{student_id}")
def delete_student(student_id: str, db: Session = Depends(get_db)):
    db.query(models.Student).filter(models.Student.id == student_id).delete()
    db.commit()
    return {"message": "Student deleted"}

@app.get("/registrations")
def get_all_agencies(db: Session = Depends(get_db)):
    # Remove the "status == pending" check so it returns EVERYONE
    return db.query(models.User).filter(models.User.role == 'agency').all()

@app.post("/approve/{entity_type}/{id}")
def approve_entity(entity_type: str, id: str, db: Session = Depends(get_db)):
    if entity_type == "van":
        item = db.query(models.Van).filter(models.Van.id == id).first()
    elif entity_type == "driver":
        item = db.query(models.Driver).filter(models.Driver.id == id).first()
    elif entity_type == "users" or entity_type == "user": # Handle both
        item = db.query(models.User).filter(models.User.id == id).first()
    else:
        raise HTTPException(status_code=400, detail="Invalid entity type")
    
    if not item: raise HTTPException(status_code=404, detail="Item not found")
    item.status = 'approved'
    db.commit()
    return {"message": "Approved"}

@app.post("/vans/assign-driver")
def assign_driver(data: AssignmentRequest, db: Session = Depends(get_db)):
    van = db.query(models.Van).filter(models.Van.id == data.van_id).first()
    driver = db.query(models.Driver).filter(models.Driver.id == data.driver_id).first()
    
    if not van or not driver: raise HTTPException(status_code=404, detail="Not found")
    
    van.assigned_driver_id = driver.id
    driver.assigned_van_id = van.id
    db.commit()
    return {"message": "Assigned"}

@app.post("/routes/create")
def create_optimized_route(route_req: RouteSchema, db: Session = Depends(get_db)):
    # Fetch Van
    van = db.query(models.Van).filter(models.Van.id == route_req.van_id).first()
    if not van: raise HTTPException(status_code=404, detail="Van not found")
    if van.status != "approved": raise HTTPException(status_code=400, detail="Van must be approved")
    if not van.assigned_driver_id: raise HTTPException(status_code=400, detail="No Driver Assigned")

    # Fetch Students
    students = db.query(models.Student).filter(models.Student.id.in_(route_req.student_ids)).all()
    if not students: raise HTTPException(status_code=400, detail="No students selected")

    # Capacity Check
    if len(students) > van.capacity:
        raise HTTPException(status_code=400, detail=f"Over Capacity! ({len(students)} > {van.capacity})")

    # Sorting 
    optimized_stops = sorted(students, key=lambda s: (s.school_lat, s.school_lng))

    # Build Stops
    stops = []
    
    # Start Node
    stops.append({
        "type": "depot", "name": "START (DEPOT)", 
        "home_lat": van.start_lat, "home_lng": van.start_lng
    })
    
    # Students
    for s in optimized_stops:
        stops.append({
            "type": "student", "name": s.name, 
            "home_lat": s.home_lat, "home_lng": s.home_lng,
            "agency_id": s.agency_id # Marker for counting
        })
        
    # School (from first student)
    stops.append({
        "type": "school", "name": "SCHOOL", 
        "home_lat": students[0].school_lat, "home_lng": students[0].school_lng
    })

    # Save Route
    new_route = models.Route(
        agency_id=route_req.agency_id,
        van_id=route_req.van_id,
        driver_id=van.assigned_driver_id,
        trip_type=route_req.trip_type,
        stops=stops, 
        student_ids=route_req.student_ids
    )
    db.add(new_route)
    db.commit()
    return {"message": "Route Created Successfully"}

@app.get("/routes")
def get_routes(agency_id: Optional[str] = None, driver_id: Optional[str] = None, db: Session = Depends(get_db)):
    query = db.query(models.Route)
    if driver_id:
        query = query.filter(models.Route.driver_id == driver_id)
    if agency_id:
        query = query.filter(models.Route.agency_id == agency_id)
    return query.all()

@app.delete("/routes/delete/{route_id}")
def delete_route(route_id: str, db: Session = Depends(get_db)):
    db.query(models.Route).filter(models.Route.id == route_id).delete()
    db.commit()
    return {"message": "Route deleted"}

@app.post("/update-location")
async def update_location(data: LocationUpdate, db: Session = Depends(get_db)):
    # Update DB
    van = db.query(models.Van).filter(models.Van.id == data.van_id).first()
    if van:
        van.current_lat = data.lat
        van.current_lng = data.lng
        db.commit()
    
    # Broadcast to Dashboard Maps
    msg = json.dumps({
        "van_id": data.van_id, 
        "lat": data.lat, 
        "lng": data.lng,
        "status": data.status
    })
    await manager.broadcast(msg)
    
    return {"message": "Location updated"}

@app.post("/vans/toggle-tracking/{van_id}")
def toggle_tracking(van_id: str, db: Session = Depends(get_db)):
    van = db.query(models.Van).filter(models.Van.id == van_id).first()
    if not van: raise HTTPException(status_code=404, detail="Van not found")
    
    van.track_always = not van.track_always
    db.commit()
    return {"message": "Tracking Toggled", "track_always": van.track_always}

@app.websocket("/ws/location")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            await websocket.receive_text() # Keep alive
    except WebSocketDisconnect:
        manager.disconnect(websocket)