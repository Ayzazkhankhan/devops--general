# KubeEdge Automated Token Generation & Edge Node Management

## 📋 Overview

This project implements an automated token generation and distribution system for KubeEdge edge computing deployments. It eliminates manual token handling by providing a web-based dashboard that automatically generates, distributes, and manages edge node authentication tokens.

### Key Features

- 🎯 **One-Click Token Generation**: Generate KubeEdge join tokens from a web dashboard
- 🤖 **Automatic Edge Node Joining**: Edge devices automatically fetch tokens and join the cluster
- 📊 **Real-Time Monitoring**: Live status updates for all edge devices
- 🔄 **Auto-Deployment**: Automatically deploys edge applications after successful node joining
- 🔐 **Secure Token Management**: JWT-based token system with expiration and tracking
- 💾 **Database Integration**: SQLite/PostgreSQL for persistent token and device management

---

## 🏗️ System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Dashboard     │    │   Master API    │    │   Edge Device   │
│   (Browser)     │───▶│   (Flask App)   │◀───│   (Agent)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────┐
                       │  Database    │
                       │  (SQLite)    │
                       └──────────────┘
```

### Communication Flow

1. **User** clicks "Generate Token" on dashboard
2. **Master API** generates JWT token and stores in database
3. **Edge Agent** polls API every 5 seconds for token
4. **Edge Agent** executes `keadm join` command with token
5. **Edge Agent** reports join status back to Master API
6. **Master API** automatically deploys edge application
7. **Dashboard** displays updated device status

---

## 🚀 Quick Start

### Prerequisites

- **Cloud Server**: Ubuntu 22.04, K3s, KubeEdge CloudCore v1.18.0
- **Edge Device**: Ubuntu 22.04, Containerd, CNI plugins
- Python 3.8+, Flask, SQLite/PostgreSQL
- `kubectl` and `keadm` installed

### Installation

#### 1. Master Server Setup

```bash
# Clone repository
git clone https://github.com/your-org/kubeedge-automation.git
cd kubeedge-automation/master-app

# Install dependencies
pip install -r requirements.txt

# Initialize database
python -c "from app import init_db; init_db()"

# Run Flask application
python app.py
```

#### 2. Edge Device Setup

```bash
# Download edge agent script
curl -O http://YOUR_MASTER_IP:30500/scripts/edge_agent.sh
chmod +x edge_agent.sh

# Configure device ID
nano edge_agent.sh
# Set: DEVICE_ID="edge-device-001"

# Run agent
sudo ./edge_agent.sh
```

#### 3. Install as Systemd Service (Optional)

```bash
# Copy service file
sudo cp kubeedge-agent.service /etc/systemd/system/

# Enable and start service
sudo systemctl enable kubeedge-agent
sudo systemctl start kubeedge-agent

# Check status
sudo systemctl status kubeedge-agent
```

---

## 📂 Project Structure

```
kubeedge-automation/
├── master-app/
│   ├── app.py                  # Main Flask application
│   ├── templates/
│   │   └── dashboard.html      # Web dashboard UI
│   ├── scripts/                # Generated edge join scripts
│   ├── deployments/            # Kubernetes deployment YAMLs
│   ├── requirements.txt        # Python dependencies
│   └── tokens.db              # SQLite database
├── edge-agent/
│   ├── edge_agent.sh          # Edge device agent script
│   └── kubeedge-agent.service # Systemd service file
├── docs/
│   ├── API.md                 # API documentation
│   ├── ARCHITECTURE.md        # Architecture details
│   └── TROUBLESHOOTING.md     # Common issues & solutions
└── README.md
```

---

## 🔧 API Endpoints

### Token Management

#### Generate Token
```http
POST /api/generate-token
Content-Type: application/json

{
  "device_id": "edge-device-001",
  "node_name": "edge-node-1",
  "expiry_hours": 24
}
```

**Response:**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "device_id": "edge-device-001",
  "node_name": "edge-node-1",
  "script_path": "/scripts/edge_join_edge-device-001.sh"
}
```

#### Get Token (Edge Device)
```http
GET /api/get-token/<device_id>
```

**Response:**
```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "status": "generated"
}
```

#### Report Join Status
```http
POST /api/execute-join
Content-Type: application/json

{
  "device_id": "edge-device-001",
  "status": "success",
  "output": "Edge node joined successfully"
}
```

### Device Management

#### Register Device
```http
POST /api/register-device
Content-Type: application/json

{
  "device_id": "edge-device-001",
  "hostname": "laptop-ubuntu",
  "ip_address": "192.168.1.100"
}
```

#### Heartbeat
```http
POST /api/heartbeat
Content-Type: application/json

{
  "device_id": "edge-device-001",
  "timestamp": "2024-12-03T10:30:00Z"
}
```

---

## 💾 Database Schema

### Tokens Table
```sql
CREATE TABLE tokens (
    id INTEGER PRIMARY KEY,
    token TEXT NOT NULL,
    device_id TEXT,
    node_name TEXT,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMP,
    expires_at TIMESTAMP,
    used_at TIMESTAMP
);
```

### Devices Table
```sql
CREATE TABLE devices (
    id INTEGER PRIMARY KEY,
    device_id TEXT UNIQUE,
    node_name TEXT,
    token_id INTEGER,
    ip_address TEXT,
    last_seen TIMESTAMP,
    status TEXT DEFAULT 'offline'
);
```

---

## 🔐 Security Implementation

### Token Security

- **JWT Tokens**: Industry-standard JSON Web Tokens
- **Expiration**: Configurable token expiry (default 24 hours)
- **One-Time Use**: Tokens marked as used after successful join
- **Encryption**: Store tokens encrypted in database (production)

### API Security

```python
# Add authentication decorator
def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token:
            return jsonify({'error': 'Unauthorized'}), 401
        try:
            data = jwt.decode(token, SECRET_KEY, algorithms=['HS256'])
        except:
            return jsonify({'error': 'Invalid token'}), 401
        return f(*args, **kwargs)
    return decorated
```

### Best Practices

- ✅ Use HTTPS in production
- ✅ Implement rate limiting (Flask-Limiter)
- ✅ Validate all user inputs
- ✅ Regular token rotation
- ✅ Audit logging for compliance
- ✅ Environment variables for secrets

---

## 🎯 Usage Examples

### Example 1: Single Edge Device

```bash
# On Master Dashboard
1. Navigate to http://3.70.53.21:30500
2. Enter Device ID: edge-device-001
3. Click "Generate Token"
4. Token automatically distributed

# On Edge Device
# Agent automatically:
# - Fetches token
# - Executes join command
# - Reports status back
```

### Example 2: Multiple Edge Devices

```python
# Bulk token generation script
import requests

devices = [
    {"device_id": "edge-device-001", "node_name": "edge-node-1"},
    {"device_id": "edge-device-002", "node_name": "edge-node-2"},
    {"device_id": "edge-device-003", "node_name": "edge-node-3"}
]

for device in devices:
    response = requests.post(
        "http://3.70.53.21:30500/api/generate-token",
        json=device
    )
    print(f"Token generated for {device['device_id']}: {response.json()}")
```

### Example 3: Token with Custom Expiry

```bash
curl -X POST http://3.70.53.21:30500/api/generate-token \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "edge-device-001",
    "node_name": "edge-node-1",
    "expiry_hours": 48
  }'
```

---

## 📊 Monitoring & Logging

### Prometheus Metrics

```python
from prometheus_client import Counter, Histogram

TOKEN_GENERATED = Counter('tokens_generated_total', 'Total tokens generated')
TOKEN_VALIDATED = Counter('tokens_validated_total', 'Total tokens validated')
JOIN_SUCCESS = Counter('edge_joins_success_total', 'Successful edge joins')
JOIN_FAILED = Counter('edge_joins_failed_total', 'Failed edge joins')

@app.route('/metrics')
def metrics():
    return generate_latest()
```

### Audit Logging

```python
import logging

audit_logger = logging.getLogger('audit')
audit_logger.setLevel(logging.INFO)

handler = logging.FileHandler('/var/log/kubeedge-audit.log')
formatter = logging.Formatter('%(asctime)s - %(message)s')
handler.setFormatter(formatter)
audit_logger.addHandler(handler)

# Log all token operations
audit_logger.info(f"Token generated - Device: {device_id}, User: {user_ip}")
```

---

## 🔄 Workflow Automation

### Automated Edge Deployment

When an edge device successfully joins:

1. **Create Kubernetes Deployment**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-app-${DEVICE_ID}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: edge-app-${DEVICE_ID}
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: ${DEVICE_ID}
      containers:
      - name: edge-app
        image: your-registry/edge-app:latest
```

2. **Apply via kubectl**
```bash
kubectl apply -f deployments/edge_app_${DEVICE_ID}.yaml
```

3. **Verify Deployment**
```bash
kubectl get pods -o wide | grep ${DEVICE_ID}
```

---

## 🐛 Troubleshooting

### Common Issues

#### Issue 1: Token Not Received by Edge Device

**Symptoms**: Edge agent keeps polling but never receives token

**Solution**:
```bash
# Check if token was generated
curl http://3.70.53.21:30500/api/get-token/edge-device-001

# Check master API logs
tail -f master-app/logs/api.log

# Verify network connectivity
ping 3.70.53.21
telnet 3.70.53.21 30500
```

#### Issue 2: Join Command Fails

**Symptoms**: Edge receives token but `keadm join` fails

**Solution**:
```bash
# Check containerd is running
sudo systemctl status containerd

# Check CNI plugins
ls -la /opt/cni/bin/

# Check CloudCore ports
telnet 3.70.53.21 30374

# Review edge agent logs
sudo journalctl -u kubeedge-agent -f
```

#### Issue 3: Token Expired

**Symptoms**: `"error": "Token expired"` in response

**Solution**:
```bash
# Generate new token from dashboard
# Or via API:
curl -X POST http://3.70.53.21:30500/api/generate-token \
  -H "Content-Type: application/json" \
  -d '{"device_id": "edge-device-001", "expiry_hours": 24}'
```

---

## 🧪 Testing

### Unit Tests

```python
# test_token_api.py
import unittest
from app import app, init_db

class TestTokenAPI(unittest.TestCase):
    def setUp(self):
        app.config['TESTING'] = True
        self.client = app.test_client()
        init_db()
    
    def test_generate_token(self):
        response = self.client.post('/api/generate-token', json={
            'device_id': 'test-device-001',
            'node_name': 'test-node-1',
            'expiry_hours': 1
        })
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertTrue(data['success'])
        self.assertIn('token', data)

if __name__ == '__main__':
    unittest.main()
```

### Integration Tests

```bash
# Run integration test script
./tests/integration_test.sh
```

---

## 📈 Performance Optimization

### Database Indexing

```sql
CREATE INDEX idx_device_id ON tokens(device_id);
CREATE INDEX idx_status ON tokens(status);
CREATE INDEX idx_expires_at ON tokens(expires_at);
```

### Caching

```python
from flask_caching import Cache

cache = Cache(app, config={'CACHE_TYPE': 'redis'})

@app.route('/api/get-token/<device_id>')
@cache.cached(timeout=60)
def get_token_cached(device_id):
    # Cached for 60 seconds
    return get_token_for_device(device_id)
```

---

## 🚢 Production Deployment

### Docker Compose

```yaml
version: '3.8'

services:
  master-api:
    build: ./master-app
    ports:
      - "30500:30500"
    environment:
      - SECRET_KEY=${SECRET_KEY}
      - DATABASE_URL=postgresql://user:pass@db/kubeedge
    depends_on:
      - db
  
  db:
    image: postgres:14
    environment:
      - POSTGRES_DB=kubeedge_automation
      - POSTGRES_USER=admin
      - POSTGRES_PASSWORD=${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
  
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

volumes:
  postgres_data:
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubeedge-master-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: kubeedge-master-api
  template:
    spec:
      containers:
      - name: api
        image: your-registry/kubeedge-master-api:latest
        ports:
        - containerPort: 30500
        env:
        - name: SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: api-secrets
              key: secret-key
---
apiVersion: v1
kind: Service
metadata:
  name: kubeedge-master-api
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 30500
  selector:
    app: kubeedge-master-api
```

---

## 📝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [KubeEdge Project](https://kubeedge.io/)
- [K3s - Lightweight Kubernetes](https://k3s.io/)
- [Flask Framework](https://flask.palletsprojects.com/)

---

## 📞 Support

For issues, questions, or contributions:

- 📧 Email: support@your-domain.com
- 🐛 Issues: [GitHub Issues](https://github.com/your-org/kubeedge-automation/issues)
- 📖 Documentation: [Full Docs](https://docs.your-domain.com)

---

## 🗺️ Roadmap

- [ ] Add OAuth2 authentication
- [ ] Implement LDAP integration
- [ ] Add Grafana dashboard for monitoring
- [ ] Support for multiple cloud regions
- [ ] Mobile app for device management
- [ ] Automated backup and recovery
- [ ] Multi-tenancy support

---

**Made with ❤️ for Edge Computing**
