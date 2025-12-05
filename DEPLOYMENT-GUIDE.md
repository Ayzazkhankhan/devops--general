# ☸ Master App – Kubernetes Deployment Guide

This document explains **exactly how to deploy Master App into Kubernetes**,  
how `keadm` is used, how Docker images are built, and how to solve common errors.

---

# 📌 1. Overview

Master App is deployed as a **Kubernetes Deployment + NodePort Service**.  
The app requires:

### ✔ A Docker image  
### ✔ `keadm` binary inside the image  
### ✔ A Kubernetes cluster (K3s in your case)  
### ✔ A ServiceAccount with cluster-admin permissions  

We will walk through each step.

---

# 📦 2. Dockerfile (Final Version)

This Dockerfile embeds **keadm directly inside the image**,  
so NO initContainers, NO hostPath volumes, NO crashes.

```dockerfile
FROM python:3.10-slim

# Install dependencies needed for kubernetes API client
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy keadm binary from repo root → image
COPY keadm /usr/local/bin/keadm
RUN chmod +x /usr/local/bin/keadm

# Install python dependencies
RUN pip install flask kubernetes

WORKDIR /app
COPY app.py /app/app.py

CMD ["python3", "app.py"]
