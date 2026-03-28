FROM golang:1.25-alpine

RUN apk add --no-cache git make build-base
RUN go install github.com/air-verse/air@latest

WORKDIR /email

COPY email/go.mod email/go.sum ./
RUN go mod download

COPY email/ .
COPY docker/email/.air.toml /etc/air.toml

CMD ["air", "-c", "/etc/air.toml"]