from flask import Flask, jsonify, request
import os
import psycopg2
import psycopg2.extras

app = Flask(__name__)

def get_conn():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
    )

@app.get("/api/health")
def health():
    try:
        conn = get_conn()
        conn.close()
        return jsonify({"status": "ok", "app": os.environ.get("APP_NAME", "backend"), "database": "reachable"})
    except Exception as exc:
        return jsonify({"status": "degraded", "database_error": str(exc)}), 500

@app.get("/api/users")
def list_users():
    with get_conn() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT id, name, email FROM users ORDER BY id")
            return jsonify(cur.fetchall())

@app.post("/api/users")
def create_user():
    body = request.get_json(force=True)
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO users (name, email) VALUES (%s, %s) RETURNING id",
                (body["name"], body["email"]),
            )
            new_id = cur.fetchone()[0]
        conn.commit()
    return jsonify({"id": new_id, "name": body["name"], "email": body["email"]}), 201

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
