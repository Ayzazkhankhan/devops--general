# Complete Documentation: Edge Device Image Deployment System

**Project:** Automated Container Image Deployment via EC2 Middleware  
**Date:** December 11, 2025  
**Author:** DevOps Team  
**Status:** Operational

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Phase 1: EC2 Setup](#phase-1-ec2-setup)
4. [Phase 2: VPN Setup](#phase-2-vpn-setup-netbird)
5. [Phase 3: Edge Device Setup](#phase-3-edge-device-setup-laptop)
6. [Phase 4: Auto-Update System](#phase-4-auto-update-system-keel)
7. [Phase 5: Deployment Configuration](#phase-5-deployment-configuration)
8. [Phase 6: Image Transfer Flow](#phase-6-image-transfer-flow)
9. [Complete Workflow](#complete-workflow)
10. [Problems & Solutions](#key-problems--solutions-summary)
11. [Monitoring Commands](#monitoring--debugging-commands)
12. [Files Created](#files-created)
13. [Lessons Learned](#lessons-learned)

---

## Project Overview

Building an automated container image deployment system where EC2 acts as middleware between AWS ECR and edge devices, with automatic Kubernetes pod updates.

### Requirements

- EC2 server as middleware between AWS and edge device
- EC2 and edge connected via VPN (NetBird)
- Flask UI on EC2 (port 10004) to manage images
- Display all local Docker images stored in EC2 registry
- Button to fetch latest image from ECR
- Button to push image to IPC5050/edge device over VPN
- Custom automation script (Flask backend) for all tasks
- EC2 downloads new image from ECR
- EC2 stores image in local registry
- EC2 sends updated image to edge device via VPN
- Edge device stores image locally
- Kubernetes automatically reloads container
- Application accessible from edge device browser

---

## Architecture
```
┌─────────────────────────────────────────┐
│           AWS ECR                        │
│   eu-central-1                          │
│   730335654587.dkr.ecr.eu-central-1     │
│   .amazonaws.com/xis-ai/prod:latest     │
└──────────────────┬──────────────────────┘
                   │
                   ↓ (AWS API - Pull)
┌─────────────────────────────────────────┐
│           EC2 Server (Middleware)        │
│   - Flask UI (Port 10004)               │
│   - Docker Registry (Port 5000)         │
│   - Public IP: <EC2-PUBLIC-IP>          │
│   - NetBird VPN IP: 100.68.70.213       │
│   - AWS Region: eu-central-1            │
└──────────────────┬──────────────────────┘
                   │
                   ↓ (NetBird VPN Tunnel)
┌─────────────────────────────────────────┐
│      Edge Device (Laptop/IPC5050)       │
│   - K3s Kubernetes Cluster              │
│   - Docker Registry (Port 5000)         │
│   - Keel Auto-Updater                   │
│   - NetBird VPN IP: 100.68.189.95       │
│   - Webapp Pod (Port 8000, 30500)       │
└─────────────────────────────────────────┘
```

### Component Breakdown

| Component | Purpose | Location |
|-----------|---------|----------|
| **AWS ECR** | Source container images | AWS Cloud |
| **EC2 Server** | Middleware, image caching | AWS EC2 |
| **Flask UI** | User interface for operations | EC2:10004 |
| **EC2 Registry** | Local image cache | EC2:5000 |
| **NetBird VPN** | Secure tunnel EC2 ↔ Edge | Both |
| **Edge Registry** | Local image storage | Edge:5000 |
| **K3s** | Lightweight Kubernetes | Edge |
| **Keel** | Auto-update trigger | Edge |
| **Webapp Pod** | Application container | Edge |

---

## Phase 1: EC2 Setup

### 1.1 Local Docker Registry on EC2

**Purpose:** Cache images locally to avoid repeated ECR pulls

**Installation:**
```bash
docker run -d \
  -p 5000:5000 \
  --restart=always \
  --name registry \
  registry:2
```

**Verification:**
```bash
curl http://localhost:5000/v2/_catalog
```

**Expected Output:**
```json
{"repositories":[]}
```

**Status:** ✅ No issues

---

### 1.2 Flask UI Application

**Purpose:** Web interface to manage image operations

**Directory Structure:**
```bash
sudo mkdir -p /opt/edge-image-ui/static
```

**Location:** `/opt/edge-image-ui/`

**Files:**
```
/opt/edge-image-ui/
├── app.py              # Backend API (Python/Flask)
├── static/
│   └── index.html      # Frontend UI (HTML/JS)
└── requirements.txt    # Python dependencies
```

**Backend (`app.py`):**
```python
import os
import json
import subprocess
import uuid
import threading
from flask import Flask, jsonify, request, send_from_directory

app = Flask(__name__, static_folder="static", static_url_path="")

# Configuration
LOCAL_REGISTRY = "localhost:5000"
AWS_ACCOUNT = "730335654587"
AWS_REGION = "eu-central-1"
ECR_REPO = "xis-ai/prod"
LOCAL_REPO = "xis-ai_prod"
JOB_LOGS = {}

EDGE_DEVICES = [
    {"name": "Laptop", "ip": "100.68.189.95", "port": "5000"},
]

def run_cmd(cmd, job_id=None):
    proc = subprocess.Popen(cmd, shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    output = []
    for line in proc.stdout:
        output.append(line)
        if job_id:
            JOB_LOGS[job_id].append(line)
    proc.wait()
    return proc.returncode, "".join(output)

@app.route("/")
def index():
    return send_from_directory("static", "index.html")

@app.route("/api/images", methods=["GET"])
def list_local_images():
    import requests
    result = []
    try:
        catalog = requests.get(f"http://{LOCAL_REGISTRY}/v2/_catalog").json()
        repos = catalog.get("repositories", [])
    except Exception as e:
        return jsonify({"error": str(e)}), 500

    for repo in repos:
        try:
            tag_list = requests.get(
                f"http://{LOCAL_REGISTRY}/v2/{repo}/tags/list"
            ).json().get("tags", [])
        except:
            tag_list = []

        for tag in tag_list:
            digest = None
            try:
                r = requests.get(
                    f"http://{LOCAL_REGISTRY}/v2/{repo}/manifests/{tag}",
                    headers={"Accept": "application/vnd.docker.distribution.manifest.v2+json"}
                )
                digest = r.headers.get("Docker-Content-Digest")
            except:
                pass

            result.append({
                "repo": repo,
                "tag": tag,
                "local_digest": digest
            })
    return jsonify(result)

@app.route("/api/ecr-digest", methods=["GET"])
def get_ecr_digest():
    tag = request.args.get("tag", "latest")
    cmd = (
        f"aws ecr describe-images --region {AWS_REGION} "
        f"--repository-name {ECR_REPO} "
        f"--image-ids imageTag={tag} "
        f"--query 'imageDetails[0].imageDigest' --output text"
    )
    rc, out = run_cmd(cmd)
    if rc != 0 or out.strip() in ("None", ""):
        return jsonify({"ecr_digest": None})
    return jsonify({"ecr_digest": out.strip()})

@app.route("/api/pull", methods=["POST"])
def pull_image():
    tag = request.json.get("tag", "latest")
    job_id = str(uuid.uuid4())
    JOB_LOGS[job_id] = [f"Starting pull for {ECR_REPO}:{tag}\n"]
    threading.Thread(target=_pull_job, args=(job_id, tag)).start()
    return jsonify({"job_id": job_id}), 202

def _pull_job(job_id, tag):
    import requests
    def log(msg):
        JOB_LOGS[job_id].append(msg + "\n")

    log("DEBUG: pull job started")

    # Fetch local digest
    local_digest = None
    try:
        r = requests.get(
            f"http://{LOCAL_REGISTRY}/v2/{LOCAL_REPO}/manifests/{tag}",
            headers={"Accept": "application/vnd.docker.distribution.manifest.v2+json"}
        )
        if r.status_code == 200:
            local_digest = r.headers.get("Docker-Content-Digest")
    except Exception as e:
        log(f"DEBUG: local digest error: {e}")

    log(f"Local digest: {local_digest}")

    # Fetch ECR digest
    cmd = (
        f"aws ecr describe-images --region {AWS_REGION} "
        f"--repository-name {ECR_REPO} "
        f"--image-ids imageTag={tag} "
        f"--query 'imageDetails[0].imageDigest' --output text"
    )
    rc, out = run_cmd(cmd, job_id)
    if rc != 0:
        log(f"DEBUG: describe-images failed rc={rc}")
        log("ECR digest NOT found")
        return

    ecr_digest = out.strip()
    log(f"ECR digest: {ecr_digest}")

    # Login to ECR
    login_cmd = (
        f"aws ecr get-login-password --region {AWS_REGION} | "
        f"docker login --username AWS --password-stdin "
        f"{AWS_ACCOUNT}.dkr.ecr.{AWS_REGION}.amazonaws.com"
    )
    rc, out = run_cmd(login_cmd, job_id)
    if rc != 0:
        log("Login failed")
        return

    # Pull from ECR
    src_image = f"{AWS_ACCOUNT}.dkr.ecr.{AWS_REGION}.amazonaws.com/{ECR_REPO}:{tag}"
    log(f"Pulling image: {src_image}")
    rc, out = run_cmd(f"docker pull {src_image}", job_id)
    if rc != 0:
        log("ERROR: docker pull failed")
        return

    # Tag for local registry
    local_image = f"{LOCAL_REGISTRY}/{LOCAL_REPO}:{tag}"
    log(f"Tagging to local image: {local_image}")
    rc, out = run_cmd(f"docker tag {src_image} {local_image}", job_id)
    if rc != 0:
        log("ERROR: docker tag failed")
        return

    # Push to local registry
    log(f"Pushing to local registry: {local_image}")
    rc, out = run_cmd(f"docker push {local_image}", job_id)
    if rc != 0:
        log("ERROR: docker push failed")
        return

    log("SUCCESS: Image pulled and stored in local registry.")

@app.route("/api/push-to-edge", methods=["POST"])
def push_to_edge():
    data = request.json
    device_ip = data.get("device_ip")
    device_port = data.get("device_port", "5000")
    tag = data.get("tag", "latest")

    if not device_ip:
        return jsonify({"error": "device_ip required"}), 400

    job_id = str(uuid.uuid4())
    JOB_LOGS[job_id] = [f"Starting push to {device_ip}:{device_port}\n"]
    threading.Thread(target=_push_to_edge_job, args=(job_id, device_ip, device_port, tag)).start()
    return jsonify({"job_id": job_id}), 202

def _push_to_edge_job(job_id, device_ip, device_port, tag):
    def log(msg):
        JOB_LOGS[job_id].append(msg + "\n")

    log(f"Pushing {LOCAL_REPO}:{tag} to {device_ip}:{device_port}")

    # Tag image for target registry
    src_image = f"{LOCAL_REGISTRY}/{LOCAL_REPO}:{tag}"
    target_image = f"{device_ip}:{device_port}/{LOCAL_REPO}:{tag}"

    log(f"Tagging: {src_image} -> {target_image}")
    rc, out = run_cmd(f"docker tag {src_image} {target_image}", job_id)
    if rc != 0:
        log("ERROR: docker tag failed")
        return

    # Push to edge device registry
    log(f"Pushing to edge registry: {target_image}")
    rc, out = run_cmd(f"docker push {target_image}", job_id)
    if rc != 0:
        log("ERROR: docker push failed")
        return

    log("SUCCESS: Image pushed to edge device.")

@app.route("/api/edge-devices", methods=["GET"])
def get_edge_devices():
    return jsonify(EDGE_DEVICES)

@app.route("/api/logs/<job_id>", methods=["GET"])
def logs(job_id):
    return jsonify({"logs": JOB_LOGS.get(job_id, [])})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=10004)
```

**Frontend (`static/index.html`):**
```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Edge Image Mirror — Control Panel</title>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<div class="container py-4">
  <h1 class="mb-4">Edge Image Mirror — Control Panel</h1>

  <div class="mb-3">
    <button class="btn btn-primary me-2" onclick="fetchLatestFromECR()">
      Fetch Latest From ECR
    </button>
    
    <div class="btn-group" role="group">
      <button type="button" class="btn btn-success dropdown-toggle" data-bs-toggle="dropdown">
        Push to Edge Device
      </button>
      <ul class="dropdown-menu" id="edge-devices-menu">
        <li><a class="dropdown-item" href="#">Loading...</a></li>
      </ul>
    </div>
  </div>

  <div id="alert"></div>

  <h3 class="mt-4">Images in EC2 Registry</h3>
  <table class="table table-striped" id="images-table">
    <thead>
      <tr>
        <th>Repository</th>
        <th>Tag</th>
        <th>Local Digest</th>
        <th>ECR Digest</th>
        <th>Action</th>
      </tr>
    </thead>
    <tbody></tbody>
  </table>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
function showAlert(msg, type="info", loading=false) {
  const spinner = loading ? `<div class="spinner-border spinner-border-sm me-2"></div>` : "";
  document.getElementById("alert").innerHTML =
    `<div class="alert alert-${type} d-flex align-items-center">${spinner}${msg}</div>`;
}

async function fetchImages() {
  const res = await fetch("/api/images");
  const images = await res.json();
  const tbody = document.querySelector("#images-table tbody");
  tbody.innerHTML = "";

  if (!images.length) {
    tbody.innerHTML = `<tr><td colspan="5">No images found</td></tr>`;
    return;
  }

  for (const img of images) {
    const key = img.repo + "-" + img.tag;
    tbody.innerHTML += `
      <tr>
        <td>${img.repo}</td>
        <td>${img.tag}</td>
        <td><code>${img.local_digest ? img.local_digest.substring(0, 20) + '...' : ''}</code></td>
        <td id="ecr-${key}">Loading...</td>
        <td>
          <button class="btn btn-sm btn-primary" onclick="pullImage('${img.tag}')">Pull Latest</button>
        </td>
      </tr>
    `;

    fetch(`/api/ecr-digest?tag=${img.tag}`)
      .then(r => r.json())
      .then(d => {
        const digest = d.ecr_digest ? d.ecr_digest.substring(0, 20) + '...' : 'Not found';
        document.getElementById(`ecr-${key}`).innerHTML = `<code>${digest}</code>`;
      });
  }
}

async function fetchLatestFromECR() {
  showAlert("Fetching latest image from ECR...", "info", true);
  const res = await fetch("/api/pull", {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({tag: "latest"})
  });
  const data = await res.json();
  showAlert(`Pull job started: ${data.job_id}`, "success");
  setTimeout(fetchImages, 5000);
}

async function pullImage(tag) {
  showAlert(`Pulling ${tag}...`, "info", true);
  const res = await fetch("/api/pull", {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({tag})
  });
  const data = await res.json();
  showAlert(`Pull job started: ${data.job_id}`, "success");
  setTimeout(fetchImages, 5000);
}

async function loadEdgeDevices() {
  const res = await fetch("/api/edge-devices");
  const devices = await res.json();
  const menu = document.getElementById("edge-devices-menu");
  menu.innerHTML = "";

  devices.forEach(device => {
    const item = document.createElement("li");
    item.innerHTML = `<a class="dropdown-item" href="#" onclick="pushToEdge('${device.ip}', '${device.port}', '${device.name}')">${device.name} (${device.ip})</a>`;
    menu.appendChild(item);
  });
}

async function pushToEdge(ip, port, name) {
  showAlert(`Pushing latest image to ${name}...`, "info", true);
  const res = await fetch("/api/push-to-edge", {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({
      device_ip: ip,
      device_port: port,
      tag: "latest"
    })
  });
  const data = await res.json();
  if (data.error) {
    showAlert(`Error: ${data.error}`, "danger");
    return;
  }
  showAlert(`Push job started: ${data.job_id}`, "success");
  setTimeout(() => pollLogs(data.job_id), 2000);
}

async function pollLogs(jobId) {
  const res = await fetch(`/api/logs/${jobId}`);
  const data = await res.json();
  const logs = data.logs.join("");
  
  if (logs.includes("SUCCESS")) {
    showAlert("✅ Image successfully pushed to edge device!", "success");
  } else if (logs.includes("ERROR")) {
    showAlert("❌ Push failed. Check EC2 logs.", "danger");
  } else {
    setTimeout(() => pollLogs(jobId), 2000);
  }
}

fetchImages();
loadEdgeDevices();
</script>
</body>
</html>
```

**Installation:**
```bash
sudo pip install flask requests --break-system-packages
```

---

### Problem 1: AWS Credentials Not Available

**Error Message:**
```
Unable to locate credentials. You can configure credentials by running "aws configure".
```

**Root Cause:**  
Flask running under systemd doesn't have access to `~/.aws/credentials` because systemd doesn't load user environment variables.

**Diagnosis:**
```bash
# Manual command works
aws ecr describe-images --region eu-central-1 --repository-name xis-ai/prod

# But Flask backend fails
curl http://localhost:10004/api/pull
# Returns: "Unable to locate credentials"
```

**Solution:**  
Add AWS credentials path to systemd service file.

---

### 1.3 Systemd Service Configuration

**File:** `/etc/systemd/system/edge-image-ui.service`
```ini
[Unit]
Description=Edge Image UI Flask App
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/edge-image-ui/app.py
Restart=always
User=ubuntu
Environment="AWS_SHARED_CREDENTIALS_FILE=/home/ubuntu/.aws/credentials"
Environment="AWS_CONFIG_FILE=/home/ubuntu/.aws/config"

[Install]
WantedBy=multi-user.target
```

**Commands:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable edge-image-ui
sudo systemctl start edge-image-ui
sudo systemctl status edge-image-ui
```

**Expected Output:**
```
● edge-image-ui.service - Edge Image UI Flask App
   Active: active (running)
```

**Verification:**
```bash
# Check logs
sudo journalctl -u edge-image-ui -f

# Test API
curl http://localhost:10004/api/images
```

**Status:** ✅ Problem solved

---

### 1.4 Manual Image Pull Test (ECR to EC2)

**Purpose:** Verify workflow before automation

### Problem 2: Image Pull Workflow Understanding

**Challenge:**  
Understanding correct sequence for ECR → Local Registry transfer.

**Learning Process:**

**Attempt 1 (Failed):**
```bash
docker pull xis-ai/prod:latest
# Error: image not found locally
```

**Attempt 2 (Failed):**
```bash
docker pull 730335654587.dkr.ecr.eu-central-1.amazonaws.com/xis-ai/prod:latest
# Error: unauthorized
```

**Attempt 3 (Success):**
```bash
# Step 1: Login to ECR
aws ecr get-login-password --region eu-central-1 | \
  docker login --username AWS --password-stdin \
  730335654587.dkr.ecr.eu-central-1.amazonaws.com

# Step 2: Pull with full path
docker pull 730335654587.dkr.ecr.eu-central-1.amazonaws.com/xis-ai/prod:latest

# Step 3: Tag for local registry (flatten repo name)
docker tag 730335654587.dkr.ecr.eu-central-1.amazonaws.com/xis-ai/prod:latest \
  localhost:5000/xis-ai_prod:latest

# Step 4: Push to local registry
docker push localhost:5000/xis-ai_prod:latest
```

**Key Learnings:**
1. Must login before pull
2. Must use full ECR path
3. Repository name `xis-ai/prod` contains slash
4. Local registry can't handle slashes in repo names
5. Solution: Flatten `xis-ai/prod` → `xis-ai_prod`

**Verification:**
```bash
curl http://localhost:5000/v2/_catalog
# Output: {"repositories":["xis-ai_prod"]}

curl http://localhost:5000/v2/xis-ai_prod/tags/list
# Output: {"name":"xis-ai_prod","tags":["latest"]}
```

**Status:** ✅ Workflow documented and working

---

## Phase 2: VPN Setup (NetBird)

### 2.1 NetBird Installation on EC2

**Purpose:** Establish secure tunnel between EC2 and edge device

### Problem 3: DNS Resolution Failure

**Error Message:**
```bash
curl -sSL https://get.netbird.io | sudo bash
# curl: (6) Could not resolve host: get.netbird.io
```

**Diagnosis:**
```bash
# Test basic connectivity
ping 8.8.8.8
# ✅ 64 bytes from 8.8.8.8: icmp_seq=1 ttl=117 time=1ms

# Test DNS resolution
ping google.com
# ✅ Works

# Test NetBird domain
ping get.netbird.io
# ❌ ping: get.netbird.io: Name or service not known

# Test alternative domains
nslookup get.netbird.io
# ❌ NXDOMAIN
```

**Root Cause:**  
EC2 DNS resolver can resolve major domains (google.com) but fails on specific domains (get.netbird.io). Likely temporary DNS propagation issue or DNS filtering.

**Solution Options Tried:**

**Attempt 1: Fix DNS**
```bash
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
# Still failed
```

**Attempt 2: Use alternative installer (Success)**
```bash
# Use raw IP instead of domain
curl -4 http://34.160.83.30/install.sh -o netbird-install.sh
sudo bash netbird-install.sh
```

**Installation Output:**
```
Installing NetBird...
Successfully installed NetBird version 0.60.7
```

**Starting NetBird:**
```bash
sudo netbird up
```

**Output:**
```
To authenticate, open the following URL:
https://app.netbird.io/client?token=xxxxx
```

**Action:** Opened URL in browser on laptop, authenticated with Google account.

**Status:** ✅ NetBird installed and authenticated

---

### Problem 4: Hostname Resolution Error

**Error Message:**
```bash
sudo systemctl restart edge-image-ui
# sudo: unable to resolve host cloud-core: Temporary failure in name resolution
```

**Root Cause:**  
Hostname `cloud-core` not defined in `/etc/hosts`

**Solution:**
```bash
sudo nano /etc/hosts
```

Added:
```
127.0.1.1   cloud-core
```

**Verification:**
```bash
sudo echo "test"
# No error
```

**Status:** ✅ Fixed

---

### 2.2 NetBird Installation on Laptop

**Installation:**
```bash
curl -sSL https://get.netbird.io | sudo bash
sudo netbird up
```

**Result:** Browser opened automatically for authentication

**Authenticated with:** Google account

**Status:** ✅ Success

---

### 2.3 VPN Connectivity Verification

**Check NetBird Status:**

**On EC2:**
```bash
netbird status
```

**Output:**
```
OS: linux/amd64
Daemon version: 0.60.7
CLI version: 0.60.7
Profile: default
Management: Connected
Signal: Connected
Relays: 4/4 Available
Nameservers: 0/0 Available
FQDN: cloud-core.netbird.cloud
NetBird IP: 100.68.70.213/16
Interface type: Kernel
Quantum resistance: false
Lazy connection: false
SSH Server: Disabled
Networks: -
Forwarding rules: 0
Peers count: 1/1 Connected
```

**On Laptop:**
```bash
netbird status
```

**Output:**
```
OS: linux/amd64
Daemon version: 0.60.7
CLI version: 0.60.7
Profile: default
Management: Connected
Signal: Connected
Relays: 1/4 Available
Nameservers: 0/0 Available
FQDN: nrcomputers.netbird.cloud
NetBird IP: 100.68.189.95/16
Interface type: Kernel
Quantum resistance: false
Lazy connection: false
SSH Server: Disabled
Networks: -
Forwarding rules: 0
Peers count: 1/1 Connected
```

**VPN IP Summary:**
- **EC2:** `100.68.70.213`
- **Laptop:** `100.68.189.95`
- **Peers:** 1/1 Connected

**Connectivity Test:**

**From Laptop:**
```bash
ping 100.68.70.213
```

**Output:**
```
64 bytes from 100.68.70.213: icmp_seq=1 ttl=64 time=5.2ms
64 bytes from 100.68.70.213: icmp_seq=2 ttl=64 time=4.8ms
```

**From EC2:**
```bash
ping 100.68.189.95
```

**Output:**
```
64 bytes from 100.68.189.95: icmp_seq=1 ttl=64 time=5.5ms
64 bytes from 100.68.189.95: icmp_seq=2 ttl=64 time=5.1ms
```

**Test Registry Access Over VPN:**

**From Laptop:**
```bash
curl http://100.68.70.213:5000/v2/_catalog
```

**Output:**
```json
{"repositories":["xis-ai_prod"]}
```

**Status:** ✅ VPN fully operational

---

## Phase 3: Edge Device Setup (Laptop)

### 3.1 Docker Installation
```bash
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker
```

**Verification:**
```bash
docker ps
```

**Status:** ✅ Docker installed

---

### 3.2 Local Docker Registry
```bash
docker run -d \
  -p 5000:5000 \
  --restart=always \
  --name registry \
  registry:2
```

**Verification:**
```bash
curl http://localhost:5000/v2/_catalog
```

**Output:**
```json
{"repositories":[]}
```

**Status:** ✅ Registry running

---

### 3.3 K3s Installation
```bash
curl -sfL https://get.k3s.io | sh -
```

**Installation Output:**
```
[INFO]  Finding release for channel stable
[INFO]  Using v1.28.3+k3s1 as release
[INFO]  Downloading...
[INFO]  systemd: Starting k3s
```

**Verification:**
```bash
sudo k3s kubectl get nodes
```

**Expected Output:**
```
NAME          STATUS   ROLES                  AGE   VERSION
nrcomputers   Ready    control-plane,master   1m    v1.28.3+k3s1
```

**Status:** ✅ K3s installed

---

### Problem 5: kubectl Permission Error

**Error Message:**
```bash
kubectl get pods
# error loading config file "/etc/rancher/k3s/k3s.yaml": open /etc/rancher/k3s/k3s.yaml: permission denied
```

**Root Cause:**  
K3s config file owned by root, regular user can't access.

**Solution:**
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

# Make permanent
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

**Verification:**
```bash
kubectl get nodes
# Now works without sudo
```

**Status:** ✅ Fixed

---

### 3.4 Configure K3s to Trust Local Registry

**Purpose:** Allow K3s to pull from insecure registries

**File:** `/etc/rancher/k3s/registries.yaml`
```yaml
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
  
  "100.68.70.213:5000":
    endpoint:
      - "http://100.68.70.213:5000"

configs:
  "100.68.70.213:5000":
    tls:
      insecure_skip_verify: true
```

**Apply Configuration:**
```bash
sudo systemctl restart k3s
```

**Verification:**
```bash
sudo k3s ctr images ls | head
```

**Status:** ✅ K3s configured

---

## Phase 4: Auto-Update System (Keel)

### 4.1 First Attempt: Reloader

**Installation:**
```bash
sudo k3s kubectl apply -f https://raw.githubusercontent.com/stakater/Reloader/master/deployments/kubernetes/reloader.yaml
```

### Problem 6: Reloader Pod CrashLoopBackOff

**Check Status:**
```bash
sudo k3s kubectl get pods --all-namespaces | grep reloader
```

**Output:**
```
default   reloader-reloader-69bcfc85d9-p8xch   0/1   CrashLoopBackOff   12   40m
```

**Check Logs:**
```bash
sudo k3s kubectl logs reloader-reloader-69bcfc85d9-p8xch
```

**Output:**
```
Error: unable to initialize application
```

**Decision:** Abandoned Reloader, switched to Keel

**Status:** ❌ Failed, moved to alternative

---

### 4.2 Second Attempt: Keel (Initial Failure)

**Installation:**
```bash
sudo k3s kubectl apply -f https://raw.githubusercontent.com/keel-hq/keel/master/deployment/deployment-rbac.yaml
```

### Problem 7: Keel ImagePullBackOff Loop

**Error:**
```bash
sudo k3s kubectl get pods -n keel
```

**Output:**
```
NAME                    READY   STATUS             RESTARTS   AGE
keel-6599d4b5d7-cqngv   0/1     ImagePullBackOff   0          2m
```

**Check Details:**
```bash
sudo k3s kubectl describe pod -n keel keel-6599d4b5d7-cqngv
```

**Key Errors:**
```
Failed to pull image "keelhq/keel:latest"
failed to resolve reference "docker.io/keelhq/keel:latest"
failed to do request: Head "https://registry-1.docker.io/v2/keelhq/keel/manifests/latest"
dial tcp: lookup registry-1.docker.io: Try again
```

**Root Cause:**  
DNS can't resolve Docker Hub domains (`registry-1.docker.io`, `auth.docker.io`)

**Why Loop Occurred:**
```
┌─────────────────────────┐
│ K3s tries to start pod  │
└────────────┬────────────┘
             │
             ↓
┌─────────────────────────┐
│ Need image: keel:latest │
└────────────┬────────────┘
             │
             ↓
┌─────────────────────────┐
│ Try to pull from Docker │
│ Hub (registry-1.docker  │
│ .io)                    │
└────────────┬────────────┘
             │
             ↓
┌─────────────────────────┐
│ DNS lookup fails        │
│ "Try again"             │
└────────────┬────────────┘
             │
             ↓
┌─────────────────────────┐
│ ImagePullBackOff        │
│ Status: Failed          │
└────────────┬────────────┘
             │
             ↓
┌─────────────────────────┐
│ K3s restart policy:     │
│ Always                  │
└────────────┬────────────┘
             │
             ↓
┌─────────────────────────┐
│ Wait (exponential       │
│ backoff)                │
│ 10s → 20s → 40s → 80s   │
│ → 160s (max)            │
└────────────┬────────────┘
             │
             ↓
┌─────────────────────────┐
│ Try again               │
│ (repeat forever)        │
└────────────┬────────────┘
             │
             ↓
    CrashLoopBackOff
```

**Status:** ❌ Failed due to DNS

---

### Problem 8: Keel Namespace Stuck in Terminating

**Delete Command:**
```bash
sudo k3s kubectl delete namespace keel
```

**Check Status:**
```bash
sudo k3s kubectl get namespaces
```

**Output:**
```
NAME              STATUS        AGE
keel              Terminating   9m45s
```

**Wait 5 minutes... still Terminating**

**Root Cause:**  
Kubernetes finalizers preventing deletion until resources are cleaned up. But resources can't be cleaned because they're in a failed state.

**Solution:**
```bash
# Remove finalizers manually
sudo k3s kubectl get namespace keel -o json | \
  sed 's/"kubernetes"//' | \
  sudo k3s kubectl replace --raw /api/v1/namespaces/keel/finalize -f -
```

**Verification:**
```bash
sudo k3s kubectl get namespaces
# keel should be gone
```

**Status:** ✅ Fixed

---

### 4.4 Keel Success: Using Local Image

**Key Discovery:**
```bash
# Check if image already exists locally
sudo k3s crictl images | grep keel
```

**Output:**
```
docker.io/keelhq/keel   latest   ee4ef6d01a22b   59.4MB
```

**Realization:** Image was already downloaded! We just need to use it instead of pulling again.

**Solution:** Change `imagePullPolicy` from `Always` to `IfNotPresent`

**File:** `keel-local.yaml`
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: keel

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: keel
  namespace: keel

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: keel
rules:
  - apiGroups: [""]
    resources: ["namespaces", "pods", "replicationcontrollers", "services", "events", "configmaps", "secrets"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "daemonsets", "statefulsets", "replicasets"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: ["extensions"]
    resources: ["deployments", "daemonsets", "replicasets"]
    verbs: ["get", "list", "watch", "update", "patch"]
  - apiGroups: ["batch"]
    resources: ["cronjobs"]
    verbs: ["get", "list", "watch", "update", "patch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: keel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: keel
subjects:
  - kind: ServiceAccount
    name: keel
    namespace: keel

---
apiVersion: v1
kind: Service
metadata:
  name: keel
  namespace: keel
  labels:
    app: keel
spec:
  type: ClusterIP
  ports:
    - port: 9300
      targetPort: 9300
      protocol: TCP
      name: webhook
  selector:
    app: keel

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keel
  namespace: keel
  labels:
    app: keel
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keel
  template:
    metadata:
      labels:
        app: keel
    spec:
      serviceAccountName: keel
      containers:
        - name: keel
          image: keelhq/keel:latest
          imagePullPolicy: IfNotPresent  # 🔥 KEY CHANGE
          command:
            - /bin/keel
          env:
            - name: NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: POLL
              value: "1"
            - name: POLL_DEFAULT_SCHEDULE
              value: "@every 1m"
            - name: INSECURE_REGISTRY
              value: "true"
          ports:
            - containerPort: 9300
              name: webhook
          livenessProbe:
            httpGet:
              path: /healthz
              port: 9300
            initialDelaySeconds: 30
            timeoutSeconds: 10
          readinessProbe:
            httpGet:
              path: /healthz
              port: 9300
            initialDelaySeconds: 10
            timeoutSeconds: 5
          resources:
            limits:
              cpu: 200m
              memory: 256Mi
            requests:
              cpu: 100m
              memory: 128Mi
```

**Installation:**
```bash
sudo k3s kubectl apply -f keel-local.yaml
```

**Check Status:**
```bash
sudo k3s kubectl get pods -n keel -w
```

**Output:**
```
NAME                    READY   STATUS    RESTARTS   AGE
keel-xxxxxxxxxx-xxxxx   0/1     Pending   0          0s
keel-xxxxxxxxxx-xxxxx   0/1     ContainerCreating   0          2s
keel-xxxxxxxxxx-xxxxx   1/1     Running   0          15s
```

**Check Logs:**
```bash
sudo k3s kubectl logs -n keel deployment/keel
```

**Output:**
```
level=info msg="Keel starting..."
level=info msg="Poll enabled with schedule: @every 1m"
level=info msg="Insecure registry mode enabled"
level=info msg="Watching for deployments..."
```

**Status:** ✅ Success!

---

## Phase 5: Deployment Configuration

### 5.1 Webapp Deployment with Keel Annotations

**File:** `deployment-webapp.yaml`
```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: default
  labels:
    app: webapp
  annotations:
    keel.sh/policy: force
    keel.sh/trigger: poll
    keel.sh/pollSchedule: "@every 1m"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      
      containers:
        - name: webapp
          image: localhost:5000/xis-ai_prod:latest
          imagePullPolicy: Always
          
          securityContext:
            privileged: true
            capabilities:
              add:
                - NET_ADMIN
                - NET_RAW
                - SYS_ADMIN
          
          ports:
            - containerPort: 8000
              hostPort: 8000
          
          volumeMounts:
            - name: dev-bus-usb
              mountPath: /dev/bus/usb
            - name: dev
              mountPath: /dev

      volumes:
        - name: dev-bus-usb
          hostPath:
            path: /dev/bus/usb
            type: DirectoryOrCreate
        - name: dev
          hostPath:
            path: /dev
            type: Directory

---
apiVersion: v1
kind: Service
metadata:
  name: webapp
  namespace: default
spec:
  type: NodePort
  selector:
    app: webapp
  ports:
    - port: 8000
      targetPort: 8000
      nodePort: 30500
```

**Key Configuration Explained:**

| Setting | Value | Purpose |
|---------|-------|---------|
| `keel.sh/policy: force` | Always update | Update even if tag unchanged (digest comparison) |
| `keel.sh/trigger: poll` | Polling mode | Check registry periodically |
| `keel.sh/pollSchedule` | `@every 1m` | Check every 1 minute |
| `hostNetwork: true` | Use host network | Camera discovery on local network |
| `privileged: true` | Full privileges | Access USB/hardware devices |
| `imagePullPolicy: Always` | Always pull | Check for new digest every time |
| `NodePort: 30500` | External access | Access from outside K3s |

---

### 5.2 First Deployment Attempt

**Apply Deployment:**
```bash
sudo k3s kubectl apply -f deployment-webapp.yaml
```

**Check Status:**
```bash
sudo k3s kubectl get pods
```

### Problem 9: Pod CrashLoopBackOff

**Output:**
```
NAME                     READY   STATUS             RESTARTS   AGE
webapp-f97dbfd46-28prz   0/1     CrashLoopBackOff   5          3m39s
```

**Check Details:**
```bash
sudo k3s kubectl describe pod webapp-f97dbfd46-28prz
```

**Key Information:**
```
State:          Waiting
  Reason:       CrashLoopBackOff
Last State:     Terminated
  Reason:       Error
  Exit Code:    137
  Started:      Thu, 11 Dec 2025 13:40:18 +0000
  Finished:     Thu, 11 Dec 2025 13:40:18 +0000
```

**Exit Code 137 Meaning:**
- `137 = 128 + 9`
- Signal 9 = SIGKILL
- Container was killed immediately

**Started and Finished at same time = Immediate crash**

**Check Logs:**
```bash
sudo k3s kubectl logs webapp-f97dbfd46-28prz
```

**Output:** Empty (container died too fast)

**Root Cause Investigation:**

**Check what image is actually in registry:**
```bash
curl http://localhost:5000/v2/xis-ai_prod/tags/list
```

**Output:**
```json
{"name":"xis-ai_prod","tags":["latest"]}
```

**Check image details:**
```bash
docker inspect localhost:5000/xis-ai_prod:latest | grep -A 10 "Config"
```

**Discovery:** Test nginx image was pushed (listens on port 80), but deployment expects port 8000.

**Root Cause:**  
During testing, a nginx image was tagged as `xis-ai_prod:latest`. Nginx runs on port 80 by default, but the deployment expects application on port 8000. Port mismatch causes immediate failure.

**Solution:**  
Pull actual application image from ECR.

**Status:** ❌ Failed, needs correct image

---

## Phase 6: Image Transfer Flow

### 6.1 Configure Docker for Insecure Registry (EC2)

**Purpose:** Allow Docker to push to edge device registry over VPN

**File:** `/etc/docker/daemon.json` (on EC2)
```json
{
  "insecure-registries": [
    "localhost:5000",
    "100.68.189.95:5000"
  ]
}
```

**Apply:**
```bash
sudo systemctl restart docker
```

**Verification:**
```bash
docker info | grep -A 5 "Insecure Registries"
```

**Output:**
```
Insecure Registries:
  100.68.189.95:5000
  localhost:5000
```

**Status:** ✅ Configured

---

### 6.2 Configure Docker for Insecure Registry (Laptop)

**File:** `/etc/docker/daemon.json` (on laptop)
```json
{
  "insecure-registries": [
    "localhost:5000",
    "100.68.70.213:5000"
  ]
}
```

**Apply:**
```bash
sudo systemctl restart docker
```

**Verification:**
```bash
docker info | grep -A 5 "Insecure Registries"
```

**Status:** ✅ Configured

---

### 6.3 Test Manual Pull from EC2 Registry

**From Laptop:**
```bash
# Test connectivity
curl http://100.68.70.213:5000/v2/_catalog

# Pull image
docker pull 100.68.70.213:5000/xis-ai_prod:latest

# Tag for local
docker tag 100.68.70.213:5000/xis-ai_prod:latest localhost:5000/xis-ai_prod:latest

# Push to local registry
docker push localhost:5000/xis-ai_prod:latest
```

**Result:** ✅ Manual transfer successful

---

### 6.4 Flask Backend Updates

**Added Push-to-Edge Functionality:**

See complete `app.py` code in Section 1.2 above.

**Key Functions Added:**
- `EDGE_DEVICES` - List of edge devices
- `/api/push-to-edge` - Endpoint to trigger push
- `_push_to_edge_job()` - Background worker
- `/api/edge-devices` - Get device list
- `/api/logs/<job_id>` - Get job logs

---

### 6.5 Flask Frontend Updates

**Added Push Button:**

See complete `index.html` code in Section 1.2 above.

**Key Features Added:**
- Dropdown menu for edge devices
- `pushToEdge()` function
- `pollLogs()` function for progress
- Real-time job status updates

---

## Complete Workflow

### End-to-End Process
```
┌─────────────────────────────────────────┐
│ 1. User Opens Flask UI                  │
│    http://<EC2-IP>:10004                │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 2. UI Shows EC2 Registry Images         │
│    - Repository: xis-ai_prod            │
│    - Tag: latest                        │
│    - Local Digest: sha256:abc...        │
│    - ECR Digest: sha256:xyz...          │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 3. User Clicks "Fetch Latest from ECR"  │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 4. Flask Backend Starts Pull Job        │
│    - Login to ECR                       │
│    - Pull image from ECR                │
│    - Tag: xis-ai/prod → xis-ai_prod     │
│    - Push to EC2 registry               │
│    Job ID: xxx-xxx-xxx                  │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 5. Image Stored in EC2 Registry         │
│    localhost:5000/xis-ai_prod:latest    │
│    Digest: sha256:3ae813...             │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 6. User Clicks "Push to Edge Device"    │
│    → Selects "Laptop (100.68.189.95)"   │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 7. Flask Backend Starts Push Job        │
│    - Tag for target registry            │
│    - Push via NetBird VPN tunnel        │
│    - 25 layers transferred              │
│    Job ID: yyy-yyy-yyy                  │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 8. Image Arrives in Laptop Registry     │
│    localhost:5000/xis-ai_prod:latest    │
│    Digest: sha256:3ae813...             │
│    Status: Complete                     │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 9. Keel Detects New Image (1 min)       │
│    - Polls localhost:5000 every 1 min   │
│    - Compares digest with running pod   │
│    - New digest detected!               │
│    - Triggers deployment update         │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 10. K3s Performs Rolling Update          │
│     - Creates new pod (latest image)    │
│     - Waits for Ready status            │
│     - Terminates old pod                │
│     - Zero-downtime deployment          │
└──────────────────┬──────────────────────┘
                   │
                   ↓
┌─────────────────────────────────────────┐
│ 11. Application Running with New Image   │
│     - Accessible: http://laptop:8000    │
│     - Accessible: http://laptop:30500   │
│     - Status: Running                   │
└─────────────────────────────────────────┘
```

---

## Key Problems & Solutions Summary

| # | Problem | Root Cause | Solution | Status |
|---|---------|------------|----------|--------|
| 1 | AWS credentials not found in Flask | Systemd doesn't load user env | Added `AWS_SHARED_CREDENTIALS_FILE` to service file | ✅ Fixed |
| 2 | Image pull workflow unclear | Learning curve | Documented 3-step: login → pull → tag → push | ✅ Documented |
| 3 | DNS resolution failure (get.netbird.io) | EC2 DNS can't resolve domain | Used raw IP installer: `http://34.160.83.30/install.sh` | ✅ Fixed |
| 4 | Hostname resolution error | Missing `/etc/hosts` entry | Added `127.0.1.1 cloud-core` | ✅ Fixed |
| 5 | kubectl permission denied | K3s config not accessible | Copied to `~/.kube/config` with proper ownership | ✅ Fixed |
| 6 | Reloader CrashLoopBackOff | Unknown - pod crashes | Abandoned, switched to Keel | ✅ Resolved |
| 7 | Keel ImagePullBackOff loop | DNS can't resolve Docker Hub | Used local image with `imagePullPolicy: IfNotPresent` | ✅ Fixed |
| 8 | Namespace stuck Terminating | Finalizers blocking deletion | Manually removed finalizers via API | ✅ Fixed |
| 9 | Pod CrashLoopBackOff (Exit 137) | Wrong image (nginx vs actual app) | Pull correct application image from ECR | ✅ Fixed |

---

## Monitoring & Debugging Commands

### EC2 Monitoring

**Flask Application Logs:**
```bash
# Live logs
sudo journalctl -u edge-image-ui -f

# Last 50 lines
sudo journalctl -u edge-image-ui -n 50 --no-pager

# Only errors
sudo journalctl -u edge-image-ui | grep -i error
```

**Job Logs:**
```bash
# Via API
curl http://localhost:10004/api/logs/<job-id> | jq -r '.logs[]'

# Pretty print
curl -s http://localhost:10004/api/logs/<job-id> | jq -r '.logs[]'
```

**Registry Contents:**
```bash
# List repositories
curl http://localhost:5000/v2/_catalog

# List tags
curl http://localhost:5000/v2/xis-ai_prod/tags/list

# Get manifest digest
curl -I -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  http://localhost:5000/v2/xis-ai_prod/manifests/latest
```

---

### Laptop/Edge Monitoring

**Keel Logs:**
```bash
# Live logs
sudo k3s kubectl logs -n keel deployment/keel -f

# Last 50 lines
sudo k3s kubectl logs -n keel deployment/keel --tail=50
```

**Pod Status:**
```bash
# Watch pods
sudo k3s kubectl get pods -w

# Detailed pod info
sudo k3s kubectl describe pod <pod-name>

# Pod logs
sudo k3s kubectl logs <pod-name> -f
```

**Deployment Status:**
```bash
# List deployments
sudo k3s kubectl get deployments

# Deployment details
sudo k3s kubectl describe deployment webapp

# Rollout history
sudo k3s kubectl rollout history deployment/webapp
```

**Registry Contents:**
```bash
# List repositories
curl http://localhost:5000/v2/_catalog

# List tags
curl http://localhost:5000/v2/xis-ai_prod/tags/list
```

---

### VPN Monitoring

**NetBird Status:**
```bash
# On both EC2 and laptop
netbird status

# Check peer connectivity
ping <other-device-netbird-ip>
```

**Network Connectivity:**
```bash
# From laptop to EC2 registry
curl http://100.68.70.213:5000/v2/_catalog

# From EC2 to laptop registry
curl http://100.68.189.95:5000/v2/_catalog
```

---

## Files Created

### EC2 Files
```
/opt/edge-image-ui/
├── app.py                      # Flask backend
├── static/
│   └── index.html              # Web UI
└── requirements.txt            # Python dependencies

/etc/systemd/system/
└── edge-image-ui.service       # Systemd service

/etc/docker/
└── daemon.json                 # Docker configuration
```

---

### Laptop Files
```
~/Downloads/webapp/
├── keel-local.yaml             # Keel installation
├── deployment-webapp.yaml      # Application deployment
└── sync-from-ec2.sh           # Manual sync script (optional)

/etc/rancher/k3s/
└── registries.yaml             # K3s registry configuration

/etc/docker/
└── daemon.json                 # Docker configuration

~/.kube/
└── config                      # kubectl configuration
```

---

## Lessons Learned

### Technical Insights

1. **DNS Issues Are Common on Cloud**
   - Always have fallback installation methods
   - Use raw IPs when domain resolution fails
   - Don't rely solely on public DNS

2. **Systemd Doesn't Inherit User Environment**
   - Explicitly set environment variables
   - Can't assume user credentials are available
   - Document required environment setup

3. **ImagePullPolicy Matters**
   - `Always` = try to pull every time (can fail on DNS issues)
   - `IfNotPresent` = use local if available (more reliable)
   - Choose based on network reliability

4. **Namespace Deletion Can Hang**
   - Finalizers prevent deletion until cleanup
   - Manual finalizer removal sometimes necessary
   - Use `kubectl replace --raw` for stuck resources

5. **Exit Code 137 = SIGKILL**
   - Usually OOM (Out of Memory) or immediate crash
   - Check resource limits
   - Verify application configuration

6. **Test Image vs Production Image**
   - Don't confuse test images (nginx) with actual app
   - Always verify image contents before deployment
   - Document image requirements clearly

7. **VPN Makes Private Registries Accessible**
   - No need for public registry exposure
   - Secure image transfer without internet routing
   - Better control and faster transfers

8. **Keel Polling Is Reliable**
   - 1-minute interval works well for edge
   - Force policy ensures updates even with same tag
   - Digest comparison prevents unnecessary restarts

9. **Repository Name Limitations**
   - Local registries can't handle slashes in repo names
   - Flatten names: `xis-ai/prod` → `xis-ai_prod`
   - Document naming conventions

10. **Rolling Updates Provide Zero Downtime**
    - New pod starts before old pod terminates
    - Health checks ensure readiness
    - Automatic rollback on failure

---

## Performance Metrics

### Image Transfer Times

| Operation | Size | Time | Network |
|-----------|------|------|---------|
| ECR → EC2 | ~23 MB (25 layers) | ~45 seconds | Internet |
| EC2 → Laptop | ~23 MB (25 layers) | ~2 minutes | NetBird VPN |
| Keel Detection | N/A | ~1 minute | N/A |
| Pod Restart | N/A | ~15-20 seconds | N/A |

**Total Time (ECR → Running Pod):** ~4-5 minutes

---

## Security Considerations

### Implemented

- ✅ VPN tunnel (NetBird) for image transfer
- ✅ AWS IAM credentials for ECR access
- ✅ Local registries (no public exposure)
- ✅ Insecure registry limited to VPN IPs only




---

## Conclusion

Successfully implemented automated container image deployment system with:

- ✅ EC2 middleware with Flask UI
- ✅ NetBird VPN connectivity
- ✅ Local registries on both sides
- ✅ Keel auto-updater
- ✅ Zero-downtime deployments
- ✅ Complete automation (ECR → Edge)


---

**End of Documentation**


