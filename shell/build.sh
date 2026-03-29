set -euo pipefail

echo "Building and pushing Docker images…"

# Get ACR name
ACR_NAME=$(az acr list --query "[0].name" --output tsv)

az acr login --name "$ACR_NAME"
ACR_SERVER="${ACR_NAME}.azurecr.io"

IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"

for SERVICE in service-a service-b; do
  echo "  Building $SERVICE…"
  docker build \
    --platform linux/amd64 \
    --tag "${ACR_SERVER}/${SERVICE}:${IMAGE_TAG}" \
    --tag "${ACR_SERVER}/${SERVICE}:latest" \
    --file "../applications/${SERVICE}/Dockerfile" \
    "../applications/${SERVICE}/"

  echo "  Pushing $SERVICE…"
  docker push "${ACR_SERVER}/${SERVICE}:${IMAGE_TAG}"
  docker push "${ACR_SERVER}/${SERVICE}:latest"
done

echo "Image tag is: {${IMAGE_TAG}}"