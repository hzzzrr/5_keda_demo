# 创建资源组(如果不存在)
az group create --name 4-vllm-keda-dev --location eastus2

# 创建存储账户
az storage account create `
  --name 4stvllmkeda `
  --resource-group 4-vllm-keda-dev `
  --location eastus2 `
  --sku Standard_LRS `
  --encryption-services blob
  
# 创建容器
az storage container create `
  --name tfstate `
  --account-name 4stvllmkeda `
  --auth-mode login

# 在portal里修改blob的访问权限 
    1. access enable
    2. Entra ID auth via Az portal enable

# 增加access
PS D:\nvdeploy\terraform-infra-setup> $storageKey = (az storage account keys list --account-name 4stvllmkeda --query [0].value -o tsv)

# 将密钥添加到后端配置
$backendContent = Get-Content -Path "99_zr-test.tfbackend"
$backendContent += "access_key = `"$storageKey`""
$backendContent | Set-Content -Path "99_zr-test.tfbackend"

# 创建ACR
az acr create --resource-group "4-vllm-keda-dev--name "acr4vllmkeda" --sku Basic

# 获取ID
$acrId = az acr show --name "acr4vllmkeda" --resource-group "4-vllm-keda-dev" --query "id" -o tsv