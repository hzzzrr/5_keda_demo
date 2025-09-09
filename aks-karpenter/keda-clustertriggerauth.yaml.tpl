## we will use azure workload identity to authenticate to azure monitor workspace
## this is a suggested approach by keda team
---
apiVersion: keda.sh/v1alpha1
kind: ClusterTriggerAuthentication
metadata:
  name: azure-monitor-workspace-auth
spec:
  podIdentity:
    provider: azure-workload  
    identityId: ${USER_ASSIGNED_CLIENT_ID}
