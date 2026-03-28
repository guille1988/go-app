FROM golang:1.25-alpine

RUN apk add --no-cache git make build-base
RUN go install github.com/air-verse/air@latest

WORKDIR /auth

COPY auth/go.mod auth/go.sum ./
RUN go mod download

COPY auth/ .
COPY docker/auth/.air.toml /etc/air.toml

CMD ["air", "-c", "/etc/air.toml"]