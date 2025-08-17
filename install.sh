#!/usr/bin/env python3
from flask import Flask, request, render_template_string, redirect, url_for, Response
import os
import subprocess
import psutil
from datetime import datetime
from functools import wraps

# ---------------- CONFIG ----------------
CONFIG_FILE = os.path.expanduser("~/pleroma/config/prod.secret.exs")
PLEROMA_SERVICE = "pleroma"

# Set your login credentials here
AUTH_USER = "admin"
AUTH_PASS = "your_secret_key"

# ---------------- FLASK APP ----------------
app = Flask(__name__)

# Basic Auth decorator
def check_auth(username, password):
    return username == AUTH_USER and password == AUTH_PASS

def authenticate():
    return Response(
        'Login Required', 401,
        {'WWW-Authenticate': 'Basic realm="Login Required"'}
    )

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated

# ---------------- HELPER FUNCTIONS ----------------
def read_config():
    banned_words = []
    host = ""
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                if "prohibited_words" in line:
                    banned_words = line.split('=')[1].strip().replace('[','').replace(']','').replace('"','').split()
                if "host:" in line:
                    host = line.split(":")[1].strip().replace('"','')
    return banned_words, host

def write_config(banned_words, host):
    lines = []
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE) as f:
            for line in f:
                if "prohibited_words" in line:
                    lines.append(f"  prohibited_words: {banned_words}\n")
                elif "host:" in line:
                    lines.append(f'  host: "{host}"\n')
                else:
                    lines.append(line)
        with open(CONFIG_FILE, "w") as f:
            f.writelines(lines)

def run_systemctl(action):
    subprocess.run(["sudo", "systemctl", action, PLEROMA_SERVICE], check=True)

def update_pleroma():
    pleroma_home = os.path.expanduser("~/pleroma")
    subprocess.run(["git", "-C", pleroma_home, "pull"], check=True)
    subprocess.run(["mix", "deps.get", "--only", "prod"], cwd=pleroma_home, check=True)
    subprocess.run(["mix", "deps.compile"], cwd=pleroma_home, check=True)
    subprocess.run(["mix", "compile"], cwd=pleroma_home, check=True)
    subprocess.run([f"{pleroma_home}/_build/prod/rel/pleroma/bin/pleroma", "stop"], cwd=pleroma_home, check=True)
    subprocess.run([f"{pleroma_home}/_build/prod/rel/pleroma/bin/pleroma", "start"], cwd=pleroma_home, check=True)

def service_status():
    try:
        output = subprocess.check_output(["systemctl", "is-active", PLEROMA_SERVICE]).decode().strip()
        return output
    except:
        return "unknown"

def system_usage():
    mem = psutil.virtual_memory()
    cpu = psutil.cpu_percent(interval=0.5)
    return cpu, mem.percent

# ---------------- HTML TEMPLATE ----------------
HTML = """
<!doctype html>
<title>Pleroma Admin GUI</title>
<meta http-equiv="refresh" content="5">
<h2>Pleroma Admin Dashboard</h2>

<p><b>Service Status:</b> {{status}}</p>
<p><b>CPU Usage:</b> {{cpu}}% | <b>RAM Usage:</b> {{ram}}%</p>
<p><b>Last Update:</b> {{last_update}}</p>

<form method=post>
Instance Host: <input name=host value="{{host}}"><br><br>
Banned Words (space-separated): <input name=bw value="{{bw}}"><br><br>
<input type=submit name=action value="Save Config">
<input type=submit name=action value="Restart Pleroma">
<input type=submit name=action value="Update & Restart">
</form>

<p>Page auto-refreshes every 5 seconds.</p>
"""

# ---------------- ROUTES ----------------
@app.route("/", methods=["GET","POST"])
@requires_auth
def gui():
    banned_words, host = read_config()
    last_update = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    status = service_status()
    cpu, ram = system_usage()
    
    if request.method == "POST":
        action = request.form.get("action")
        if action == "Save Config":
            bw = request.form.get("bw","").split()
            host = request.form.get("host", host)
            write_config(bw, host)
        elif action == "Restart Pleroma":
            run_systemctl("restart")
        elif action == "Update & Restart":
            update_pleroma()
        return redirect(url_for("gui"))
    
    banned_words, host = read_config()
    status = service_status()
    cpu, ram = system_usage()
    
    return render_template_string(
        HTML, 
        bw=" ".join(banned_words), 
        host=host,
        status=status,
        cpu=cpu,
        ram=ram,
        last_update=last_update
    )

# ---------------- MAIN ----------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
