from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base

# 1. The SQLite URL (This creates a file named 'velo.db' in your backend folder)
SQLALCHEMY_DATABASE_URL = "sqlite:///./velo.db"

# 2. Create Engine (The 'check_same_thread' argument is strictly required for SQLite in FastAPI)
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)

# 3. Setup Session and Base
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# 4. Dependency function to get the DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()