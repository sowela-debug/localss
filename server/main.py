import os
import sqlite3
import secrets
import hashlib
import hmac
from datetime import datetime, timezone, timedelta
from contextlib import contextmanager

from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from pwdlib import PasswordHash


# ==============================
# LOCALSS CONFIGURATION
# ==============================

APP_NAME = "LocalSS Server"

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

DATA_DIR = os.path.join(BASE_DIR, "data")

os.makedirs(DATA_DIR, exist_ok=True)

DB_PATH = os.path.join(DATA_DIR, "localss.db")

password_hash = PasswordHash.recommended()

security = HTTPBearer()

app = FastAPI(
    title=APP_NAME,
    version="0.1.0"
)


# ==============================
# DATABASE
# ==============================

@contextmanager
def database():

    conn = sqlite3.connect(
        DB_PATH,
        timeout=30
    )

    conn.row_factory = sqlite3.Row

    conn.execute("PRAGMA foreign_keys = ON")

    try:
        yield conn
        conn.commit()

    except Exception:
        conn.rollback()
        raise

    finally:
        conn.close()


def initialize_database():

    with database() as db:

        db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                is_admin INTEGER DEFAULT 0,
                last_seen TEXT,
                created_at TEXT NOT NULL
            )
        """)

        db.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                token_hash TEXT UNIQUE NOT NULL,
                expires_at TEXT NOT NULL,

                FOREIGN KEY(user_id)
                REFERENCES users(id)
                ON DELETE CASCADE
            )
        """)

        db.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sender_id INTEGER NOT NULL,
                receiver_id INTEGER NOT NULL,
                content TEXT NOT NULL,
                created_at TEXT NOT NULL,

                FOREIGN KEY(sender_id)
                REFERENCES users(id)
                ON DELETE CASCADE,

                FOREIGN KEY(receiver_id)
                REFERENCES users(id)
                ON DELETE CASCADE
            )
        """)


def utc_now():
    return datetime.now(timezone.utc)


def now_string():
    return utc_now().isoformat()


# ==============================
# REQUEST MODELS
# ==============================

class AuthRequest(BaseModel):

    username: str = Field(
        min_length=3,
        max_length=32,
        pattern=r"^[a-zA-Z0-9_]+$"
    )

    password: str = Field(
        min_length=8,
        max_length=128
    )


class MessageRequest(BaseModel):

    receiver_id: int

    content: str = Field(
        min_length=1,
        max_length=10000
    )


# ==============================
# PASSWORD SECURITY
# ==============================

def hash_password(password):

    return password_hash.hash(password)


def verify_password(password, stored_hash):

    return password_hash.verify(
        password,
        stored_hash
    )


def hash_token(token):

    return hashlib.sha256(
        token.encode()
    ).hexdigest()


# ==============================
# ADMIN INITIALIZATION
# ==============================

def initialize_admin():

    username = os.getenv(
        "LOCALSS_ADMIN_USERNAME",
        "admin"
    )

    password = os.getenv(
        "LOCALSS_ADMIN_PASSWORD"
    )

    if not password:
        raise RuntimeError(
            "LOCALSS_ADMIN_PASSWORD must be configured."
        )

    if len(password) < 12:
        raise RuntimeError(
            "Admin password must contain at least 12 characters."
        )

    with database() as db:

        admin = db.execute("""
            SELECT id FROM users
            WHERE is_admin = 1
        """).fetchone()

        if admin:
            return

        existing = db.execute("""
            SELECT id FROM users
            WHERE username = ?
        """, (username,)).fetchone()

        if existing:
            raise RuntimeError(
                "Admin username already belongs to another account."
            )

        db.execute("""
            INSERT INTO users (
                username,
                password_hash,
                is_admin,
                created_at
            )
            VALUES (?, ?, 1, ?)
        """, (
            username,
            hash_password(password),
            now_string()
        ))


# ==============================
# AUTHENTICATION
# ==============================

def create_session(user_id):

    token = secrets.token_urlsafe(48)

    expires = (
        utc_now() + timedelta(days=7)
    ).isoformat()

    with database() as db:

        db.execute("""
            INSERT INTO sessions (
                user_id,
                token_hash,
                expires_at
            )
            VALUES (?, ?, ?)
        """, (
            user_id,
            hash_token(token),
            expires
        ))

    return token


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
):

    token_hash = hash_token(
        credentials.credentials
    )

    with database() as db:

        user = db.execute("""
            SELECT
                users.id,
                users.username,
                users.is_admin,
                users.last_seen,
                sessions.expires_at

            FROM sessions

            JOIN users
            ON users.id = sessions.user_id

            WHERE sessions.token_hash = ?
        """, (token_hash,)).fetchone()

        if not user:
            raise HTTPException(
                status_code=401,
                detail="Invalid session"
            )

        if datetime.fromisoformat(
            user["expires_at"]
        ) <= utc_now():

            raise HTTPException(
                status_code=401,
                detail="Session expired"
            )

        return dict(user)


def require_admin(
    user=Depends(get_current_user)
):

    if not user["is_admin"]:

        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    return user


# ==============================
# SERVER STARTUP
# ==============================

@app.on_event("startup")
def startup():

    initialize_database()

    initialize_admin()


# ==============================
# SERVER STATUS
# ==============================

@app.get("/")
def root():

    return {
        "application": "LocalSS",
        "version": "0.1.0",
        "status": "running",
        "network": "local"
    }


# ==============================
# REGISTER
# ==============================

@app.post("/auth/register")
def register(data: AuthRequest):

    with database() as db:

        existing = db.execute("""
            SELECT id
            FROM users
            WHERE username = ?
        """, (
            data.username,
        )).fetchone()

        if existing:

            raise HTTPException(
                status_code=409,
                detail="Username already exists"
            )

        db.execute("""
            INSERT INTO users (
                username,
                password_hash,
                is_admin,
                created_at
            )
            VALUES (?, ?, 0, ?)
        """, (
            data.username,
            hash_password(data.password),
            now_string()
        ))

    return {
        "success": True,
        "message": "Account created successfully"
    }


# ==============================
# LOGIN
# ==============================

@app.post("/auth/login")
def login(data: AuthRequest):

    with database() as db:

        user = db.execute("""
            SELECT *
            FROM users
            WHERE username = ?
        """, (
            data.username,
        )).fetchone()

        if not user:

            raise HTTPException(
                status_code=401,
                detail="Invalid username or password"
            )

        if not verify_password(
            data.password,
            user["password_hash"]
        ):

            raise HTTPException(
                status_code=401,
                detail="Invalid username or password"
            )

        user_id = user["id"]

        db.execute("""
            UPDATE users
            SET last_seen = ?
            WHERE id = ?
        """, (
            now_string(),
            user_id
        ))

    token = create_session(user_id)

    return {
        "access_token": token,
        "token_type": "bearer",
        "user_id": user_id,
        "username": data.username,
        "is_admin": bool(user["is_admin"])
    }


# ==============================
# LOGOUT
# ==============================

@app.post("/auth/logout")
def logout(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    user=Depends(get_current_user)
):

    with database() as db:

        db.execute("""
            DELETE FROM sessions
            WHERE token_hash = ?
        """, (
            hash_token(credentials.credentials),
        ))

    return {
        "success": True
    }


# ==============================
# CURRENT USER
# ==============================

@app.get("/users/me")
def my_profile(
    user=Depends(get_current_user)
):

    return {
        "id": user["id"],
        "username": user["username"],
        "is_admin": bool(user["is_admin"])
    }


# ==============================
# HEARTBEAT
# ==============================

@app.post("/users/heartbeat")
def heartbeat(
    user=Depends(get_current_user)
):

    with database() as db:

        db.execute("""
            UPDATE users
            SET last_seen = ?
            WHERE id = ?
        """, (
            now_string(),
            user["id"]
        ))

    return {
        "success": True
    }


# ==============================
# USER LIST
# ==============================

@app.get("/users")
def list_users(
    user=Depends(get_current_user)
):

    cutoff = (
        utc_now() - timedelta(seconds=60)
    )

    with database() as db:

        rows = db.execute("""
            SELECT
                id,
                username,
                is_admin,
                last_seen

            FROM users
        """).fetchall()

    users = []

    for row in rows:

        online = False

        if row["last_seen"]:

            last_seen = datetime.fromisoformat(
                row["last_seen"]
            )

            online = last_seen >= cutoff

        users.append({
            "id": row["id"],
            "username": row["username"],
            "is_admin": bool(row["is_admin"]),
            "online": online,
            "last_seen": row["last_seen"]
        })

    users.sort(
        key=lambda u: (
            not u["online"],
            u["username"].lower()
        )
    )

    return users


# ==============================
# SEND PRIVATE MESSAGE
# ==============================

@app.post("/messages/send")
def send_message(
    data: MessageRequest,
    user=Depends(get_current_user)
):

    if data.receiver_id == user["id"]:

        raise HTTPException(
            status_code=400,
            detail="Cannot message yourself"
        )

    with database() as db:

        receiver = db.execute("""
            SELECT id
            FROM users
            WHERE id = ?
        """, (
            data.receiver_id,
        )).fetchone()

        if not receiver:

            raise HTTPException(
                status_code=404,
                detail="Receiver not found"
            )

        cursor = db.execute("""
            INSERT INTO messages (
                sender_id,
                receiver_id,
                content,
                created_at
            )
            VALUES (?, ?, ?, ?)
        """, (
            user["id"],
            data.receiver_id,
            data.content,
            now_string()
        ))

        message_id = cursor.lastrowid

    return {
        "success": True,
        "message_id": message_id
    }


# ==============================
# PRIVATE CHAT HISTORY
# ==============================

@app.get("/messages/{other_user_id}")
def get_messages(
    other_user_id: int,
    user=Depends(get_current_user)
):

    with database() as db:

        messages = db.execute("""
            SELECT
                id,
                sender_id,
                receiver_id,
                content,
                created_at

            FROM messages

            WHERE
                (
                    sender_id = ?
                    AND receiver_id = ?
                )

                OR

                (
                    sender_id = ?
                    AND receiver_id = ?
                )

            ORDER BY id ASC

            LIMIT 1000
        """, (
            user["id"],
            other_user_id,
            other_user_id,
            user["id"]
        )).fetchall()

    return [
        dict(message)
        for message in messages
    ]


# ==============================
# ADMIN: USER LIST
# ==============================

@app.get("/admin/users")
def admin_users(
    admin=Depends(require_admin)
):

    with database() as db:

        users = db.execute("""
            SELECT
                id,
                username,
                is_admin,
                created_at,
                last_seen

            FROM users

            ORDER BY username
        """).fetchall()

    return [
        dict(user)
        for user in users
    ]


# ==============================
# ADMIN: DELETE USER
# ==============================

@app.delete("/admin/users/{user_id}")
def delete_user(
    user_id: int,
    admin=Depends(require_admin)
):

    if user_id == admin["id"]:

        raise HTTPException(
            status_code=400,
            detail="Cannot delete your own admin account"
        )

    with database() as db:

        target = db.execute("""
            SELECT is_admin
            FROM users
            WHERE id = ?
        """, (user_id,)).fetchone()

        if not target:

            raise HTTPException(
                status_code=404,
                detail="User not found"
            )

        if target["is_admin"]:

            raise HTTPException(
                status_code=403,
                detail="Cannot delete administrator"
            )

        db.execute("""
            DELETE FROM users
            WHERE id = ?
        """, (user_id,))

    return {
        "success": True,
        "message": "User deleted"
    }


# ==============================
# ADMIN: DELETE CHAT HISTORY
# ==============================

@app.delete("/admin/history")
def delete_all_history(
    admin=Depends(require_admin)
):

    with database() as db:

        db.execute("""
            DELETE FROM messages
        """)

    return {
        "success": True,
        "message": "Chat history deleted"
    }


# ==============================
# RUN SERVER
# ==============================

if __name__ == "__main__":

    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=3000
    )