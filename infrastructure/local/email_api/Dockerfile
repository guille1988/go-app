FROM golang:1.25-alpine

RUN apk add --no-cache git make build-base
RUN go install github.com/air-verse/air@latest

WORKDIR /email

COPY microservices/email/go.mod microservices/email/go.sum ./
COPY microservices/email/internal/shared/ ./internal/shared/
RUN go mod download

COPY microservices/email/ .
COPY infrastructure/local/email_api/.air.toml /etc/air.toml

CMD ["air", "-c", "/etc/air.toml"]
