#!/bin/bash -x
set -euo pipefail

# 用法:
#   fetch-blob <BLOB_URL_PREFIX> <DEST_DIR>
# 说明:
#   - 使用 AKS Workload Identity 登录 azcopy（最新推荐方式）
#   - 每次执行全量同步：先清空 DEST_DIR，再 azcopy sync 源目录 -> 目标目录
#   - 自动给源和目标补全末尾斜杠，确保按目录处理

if [ $# -lt 2 ]; then
  echo "用法: fetch-blob <BLOB_URL_PREFIX> <DEST_DIR>"
  exit 1
fi

SRC_URL_RAW="$1"
DEST_DIR_RAW="$2"

# 规范化：确保目录末尾有 /
SRC_URL="${SRC_URL_RAW%/}/"
DEST_DIR="${DEST_DIR_RAW%/}/"

# 校验 Workload Identity 环境变量（由 AKS 注入/你在 Pod 中配置）
: "${AZURE_TENANT_ID:?需要设置 AZURE_TENANT_ID}"
: "${AZURE_CLIENT_ID:?需要设置 AZURE_CLIENT_ID}"
: "${AZURE_FEDERATED_TOKEN_FILE:?需要设置 AZURE_FEDERATED_TOKEN_FILE}"
[ -s "$AZURE_FEDERATED_TOKEN_FILE" ] || { echo "联邦令牌文件为空: $AZURE_FEDERATED_TOKEN_FILE"; exit 2; }

# 使用 Workload Identity 登录（最新 azcopy 推荐方法）
azcopy login --login-type workload >/dev/null

# 退出时登出
trap 'azcopy logout >/dev/null 2>&1 || true' EXIT

# 全量同步
if [ -z "$DEST_DIR" ] || [ "$DEST_DIR" = "/" ]; then
  echo "[ERROR] DEST_DIR 非法: '$DEST_DIR'"
  exit 9
fi

echo "[INFO] 全量同步: $SRC_URL -> $DEST_DIR"
mkdir -p "$DEST_DIR"

# 同步（递归；注意两端均为目录）
azcopy sync "$SRC_URL" "$DEST_DIR" \
  --recursive \
  --delete-destination=false \
  --log-level WARNING

echo "[INFO] 全量同步完成"
