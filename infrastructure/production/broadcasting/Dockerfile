FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git build-base

WORKDIR /broadcasting

COPY microservices/broadcasting/go.mod microservices/broadcasting/go.sum ./
COPY microservices/broadcasting/internal/shared/ ./internal/shared/
RUN go mod download

COPY microservices/broadcasting/ .

RUN go build -o bin/consumer ./cmd/consumer/main.go

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /broadcasting

COPY --from=builder /broadcasting/bin/ ./bin/

EXPOSE 8082

CMD ["./bin/consumer"]
