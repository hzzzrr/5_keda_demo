---
# Ensure namespace exist
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
## we will use azure workload identity to authenticate to azure monitor workspace
## this is a suggested approach by keda team
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: azure-monitor-workspace-auth
  namespace: ${NAMESPACE}
spec:
  podIdentity:
    provider: azure-workload  
    identityId: ${USER_ASSIGNED_CLIENT_ID}
