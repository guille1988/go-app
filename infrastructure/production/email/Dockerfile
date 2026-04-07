FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git build-base

WORKDIR /email

COPY microservices/email/go.mod microservices/email/go.sum ./
COPY microservices/email/internal/shared/ ./internal/shared/
RUN go mod download

COPY microservices/email/ .

RUN go build -o bin/consumer ./cmd/consumer/main.go && \
    go build -o bin/api ./cmd/api/main.go && \
    go build -o bin/migrate ./cmd/migrate/main.go

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /email

COPY --from=builder /email/bin/ ./bin/
COPY --from=builder /email/internal/infrastructure/database/migrations/ ./internal/infrastructure/database/migrations/
COPY --from=builder /email/internal/domain/email/templates/ ./internal/domain/email/templates/

CMD ["./bin/consumer"]
