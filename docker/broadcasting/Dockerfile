FROM golang:1.25-alpine

RUN apk add --no-cache git make build-base
RUN go install github.com/air-verse/air@latest

WORKDIR /broadcasting

COPY broadcasting/go.mod broadcasting/go.sum ./
RUN go mod download

COPY broadcasting/ .
COPY docker/broadcasting/.air.toml /etc/air.toml

CMD ["air", "-c", "/etc/air.toml"]
