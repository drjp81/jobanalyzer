#use docker build to generate an image that works in ARM64 and AMD64
docker buildx create --use --platform=linux/amd64,linux/arm64 --name my-multi-platform-builder --driver=docker-container
docker buildx build --platform linux/amd64,linux/arm64 -t drjp81/linkedinscrape:latest --pull --push .