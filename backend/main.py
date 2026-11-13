import hashlib
import requests
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String, Float, Text, TIMESTAMP, ForeignKey, text
from sqlalchemy.orm import sessionmaker, declarative_base, Session

DATABASE_URL = "mysql+pymysql://root:@localhost:3306/asistencia_gps"

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

app = FastAPI(title="API Pase de Lista GPS")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(100), unique=True, nullable=False)
    password = Column(String(255), nullable=False)
    role = Column(String(20), default="student")

class Attendance(Base):
    __tablename__ = "attendance"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    address = Column(Text, nullable=False)
    created_at = Column(TIMESTAMP, server_default=text("CURRENT_TIMESTAMP"))

Base.metadata.create_all(bind=engine)

class RegisterModel(BaseModel):
    username: str
    password: str
    role: str = "student"

class LoginModel(BaseModel):
    username: str
    password: str

class AttendanceModel(BaseModel):
    user_id: int
    latitude: float
    longitude: float

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def md5_hash(password: str) -> str:
    return hashlib.md5(password.encode()).hexdigest()

def get_address_from_nominatim(lat: float, lon: float) -> str:
    url = f"https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}"
    headers = {"User-Agent": "FlutterAttendanceApp/1.0"}
    try:
        response = requests.get(url, headers=headers, timeout=10)
        if response.status_code == 200:
            data = response.json()
            return data.get("display_name", "Dirección no encontrada")
    except Exception:
        pass
    return f"Coordenadas: {lat}, {lon}"

@app.post("/register/")
def register(user: RegisterModel, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.username == user.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="El usuario ya existe")
    new_user = User(
        username=user.username,
        password=md5_hash(user.password),
        role=user.role
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return {"message": "Usuario registrado", "user_id": new_user.id}

@app.post("/login/")
def login(user: LoginModel, db: Session = Depends(get_db)):
    hashed = md5_hash(user.password)
    db_user = db.query(User).filter(
        User.username == user.username,
        User.password == hashed
    ).first()
    if not db_user:
        raise HTTPException(status_code=401, detail="Credenciales incorrectas")
    return {
        "message": "Login exitoso",
        "user_id": db_user.id,
        "username": db_user.username,
        "role": db_user.role
    }

@app.post("/attendance/")
def register_attendance(att: AttendanceModel, db: Session = Depends(get_db)):
    address = get_address_from_nominatim(att.latitude, att.longitude)
    new_record = Attendance(
        user_id=att.user_id,
        latitude=att.latitude,
        longitude=att.longitude,
        address=address
    )
    db.add(new_record)
    db.commit()
    db.refresh(new_record)
    return {
        "message": "Asistencia registrada",
        "id": new_record.id,
        "address": address,
        "latitude": att.latitude,
        "longitude": att.longitude
    }

@app.get("/attendance/")
def get_all_attendances(user_id: int = None, db: Session = Depends(get_db)):
    query = db.query(Attendance, User.username).join(User, Attendance.user_id == User.id)
    if user_id:
        query = query.filter(Attendance.user_id == user_id)
    records = query.order_by(Attendance.created_at.desc()).all()
    return [
        {
            "id": att.id,
            "user_id": att.user_id,
            "username": username,
            "latitude": att.latitude,
            "longitude": att.longitude,
            "address": att.address,
            "created_at": str(att.created_at)
        }
        for att, username in records
    ]