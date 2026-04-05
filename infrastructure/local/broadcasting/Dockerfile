FROM golang:1.25-alpine

RUN apk add --no-cache git make build-base
RUN go install github.com/air-verse/air@latest

WORKDIR /broadcasting

COPY microservices/broadcasting/go.mod microservices/broadcasting/go.sum ./
COPY microservices/broadcasting/internal/shared/ ./internal/shared/
RUN go mod download

COPY microservices/broadcasting/ .
COPY infrastructure/local/broadcasting/.air.toml /etc/air.toml

CMD ["air", "-c", "/etc/air.toml"]
