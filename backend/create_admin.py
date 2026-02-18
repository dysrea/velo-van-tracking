from database import SessionLocal
import models, auth

db = SessionLocal()

email = "admin@school.com"
password = "admin"

# Check if admin already exists
existing = db.query(models.User).filter(models.User.email == email).first()

if existing:
    print(f"Admin '{email}' already exists!")
else:
    # Hash the password
    hashed_pw = auth.get_password_hash(password)
    
    # Create the Admin User
    admin = models.User(
        email=email,
        hashed_password=hashed_pw, 
        role="admin",
        agency_name="Headquarters",
        status="approved"
    )
    
    db.add(admin)
    db.commit()
    print(f"SUCCESS: Created Admin ({email} / {password})")

db.close()