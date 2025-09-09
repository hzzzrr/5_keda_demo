 get token
```bash
FULL_URL="http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com"

curl -H "Metadata: true" \
    $FULL_URL
```

有多个 mi 时需要指定 client id

```bash
CLIENT_ID="35577749-8eea-4931-a540-5c8375de8561"
curl -H "Metadata: true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/&client_id=${CLIENT_ID}"
```    


开启 workload identity 后 pod 中会自动注入env
```
# env |grep AZURE_
AZURE_AUTHORITY_HOST=https://login.microsoftonline.com/
AZURE_CLIENT_ID=bab05220-115c-40c2-824e-4d306fd72c2c
AZURE_FEDERATED_TOKEN_FILE=/var/run/secrets/azure/tokens/azure-identity-token
AZURE_TENANT_ID=226ac565-2e4e-48be-a152-97707c0d4196
```

获取 jwt token
```
curl -H "Metadata: true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/&client_id=${AZURE_CLIENT_ID}"
```

jwt token 会自动保存到文件：
```
# cat /var/run/secrets/azure/tokens/azure-identity-token
```