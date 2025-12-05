```markdown
# Clean-up: Remove master-app from Kubernetes

This guide walks through a **complete teardown** of the `master-app` workload.  
Run each step in the order shown and verify the output before continuing.

---

## ✅ STEP 1 – Delete the Deployment
Remove the top-level controller so no new ReplicaSets or Pods are created.

```bash
kubectl delete deployment master-app
```

---

## ✅ STEP 2 – Delete ALL ReplicaSets of master-app
Remove any ReplicaSets that still exist (owned by the deleted Deployment or leftovers).

```bash
kubectl delete rs -l app=master-app --ignore-not-found
```

### Verify
The following command **must return nothing**.  
If any lines appear, repeat the delete command above.

```bash
kubectl get rs | grep master-app
```

---

## ✅ STEP 3 – Delete ALL Pods of master-app
Remove any running or terminating Pods that still carry the label.

```bash
kubectl delete pod -l app=master-app --ignore-not-found
```

### Verify
The following command **must show 0 pods**.  
Any output means Pods are still present; repeat the delete command.

```bash
kubectl get pods | grep master-app
```

---

## Done
When all three verifications return empty results, `master-app` has been completely removed from the cluster.
```
