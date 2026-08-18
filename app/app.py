from flask import Flask, jsonify
import os
import psycopg2

app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health():
    try:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST', 'db'),
            port=os.environ.get('DB_PORT', '5432'),
            dbname=os.environ.get('DB_NAME', 'appdb'),
            user=os.environ.get('DB_USER', 'appuser'),
            password=os.environ.get('DB_PASSWORD', 'secretpassword'),
        )
        conn.close()
        return jsonify({"status": "ok", "app": os.environ.get('APP_NAME', 'app1'), "database": "reachable"})
    except Exception as exc:
        return jsonify({"status": "degraded", "app": os.environ.get('APP_NAME', 'app1'), "database_error": str(exc)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
