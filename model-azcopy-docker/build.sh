IMAGE=model-azcopy
PLATFORMS=linux/amd64

docker buildx build \
  --platform "$PLATFORMS" \
  -t "$IMAGE" \
 .
