
# 🚀 Master App – GitHub Actions CI/CD Guide

This guide explains **how your application automatically builds, pushes,  
and deploys to Kubernetes** whenever you push code to GitHub.

It is written so even a **complete DevOps beginner** can understand it.  
(Industry-standard CI/CD best practices included.)

---

# 🧩 ""1. How CI/CD Works

Whenever you push code to GitHub:

1️⃣ GitHub Actions builds a new Docker image  
2️⃣ Pushes it to Docker Hub  
3️⃣ Uses kubeconfig to connect to your K3s master node  
4️⃣ Updates your Kubernetes Deployment  
5️⃣ Restarts the pod  
6️⃣ New version goes live **automatically**

No SSH, no manual kubectl needed.""

---

# 🔑 2. Add GitHub Secrets

Go to:

**GitHub → Repository → Settings → Secrets → Actions**

Add these:

| Secret Name | Value |
|-------------|--------|
| `KUBECONFIG_CONTENT` | Content of `/etc/rancher/k3s/k3s.yaml` |
| `DOCKERHUB_USERNAME` | Your DockerHub username |
| `DOCKERHUB_TOKEN` | Docker Hub Personal Access Token |

---

# 📄 3. Workflow File (`.github/workflows/deploy.yml`)

```yaml
name: Deploy Master App

on:
  push:
    branches: [ "main" ]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout
      uses: actions/checkout@v3

    - name: Restore kubeconfig
      run: |
        mkdir -p ~/.kube
        echo "${{ secrets.KUBECONFIG_CONTENT }}" > ~/.kube/config

    - name: Login to Docker Hub
      run: |
        echo "${{ secrets.DOCKERHUB_TOKEN }}" | docker login -u "${{ secrets.DOCKERHUB_USERNAME }}" --password-stdin

    - name: Build & push image
      run: |
        docker build -t ${{ secrets.DOCKERHUB_USERNAME }}/master-app:latest .
        docker push ${{ secrets.DOCKERHUB_USERNAME }}/master-app:latest

    - name: Deploy to Kubernetes
      run: |
        kubectl set image deployment/master-app master-app=${{ secrets.DOCKERHUB_USERNAME }}/master-app:latest
        kubectl rollout restart deployment/master-app
```
```
