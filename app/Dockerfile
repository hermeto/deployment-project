# Multi-stage build: a static binary on a distroless, non-root base image (no shell, no package manager).
# Base images are pinned by digest; Renovate keeps them up to date.
FROM --platform=$BUILDPLATFORM golang:1.27.1-alpine3.24@sha256:8a5910f31396cd4d89662f56c68b3ae31d374308270a1c3bd96672ee5ed43414 AS build

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/go-app .

FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3

LABEL org.opencontainers.image.title="go-app" \
      org.opencontainers.image.source="https://github.com/hermeto/deployment-project" \
      org.opencontainers.image.description="Sample Go HTTP service deployed with Helm and Argo CD"

COPY --from=build /out/go-app /go-app
USER 65532:65532
EXPOSE 3000
ENTRYPOINT ["/go-app"]
