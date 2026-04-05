FROM golang:1.25-alpine

RUN apk add --no-cache git make build-base
RUN go install github.com/air-verse/air@latest

WORKDIR /auth

COPY microservices/auth/go.mod microservices/auth/go.sum ./
COPY microservices/auth/internal/shared/ ./internal/shared/
RUN go mod download

COPY microservices/auth/ .
COPY infrastructure/local/auth/.air.toml /etc/air.toml

CMD ["air", "-c", "/etc/air.toml"]