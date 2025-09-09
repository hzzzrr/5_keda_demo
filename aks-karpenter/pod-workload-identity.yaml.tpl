---
# make name space exists before we create ServiceAccount
apiVersion: v1
kind: Namespace
metadata:
  name: ${SERVICE_ACCOUNT_NAMESPACE}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${USER_ASSIGNED_CLIENT_ID}"
  name: "${SERVICE_ACCOUNT_NAME}"
  namespace: "${SERVICE_ACCOUNT_NAMESPACE}"
