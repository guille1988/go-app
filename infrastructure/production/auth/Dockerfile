FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git build-base

WORKDIR /auth

COPY microservices/auth/go.mod microservices/auth/go.sum ./
COPY microservices/auth/internal/shared/ ./internal/shared/
RUN go mod download

COPY microservices/auth/ .

RUN go build -o bin/api ./cmd/api/main.go && \
    go build -o bin/migrate ./cmd/migrate/main.go

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /auth

COPY --from=builder /auth/bin/ ./bin/
COPY --from=builder /auth/internal/infrastructure/database/migrations/ ./internal/infrastructure/database/migrations/

EXPOSE 8080

CMD ["./bin/api"]
