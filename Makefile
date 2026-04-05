DOCKER_COMPOSE = docker-compose -f infrastructure/local/docker-compose.yml

.PHONY: up down restart build ps logs test migrate migrate-fresh seed migrate-seed init clean help compile compile-all update

help:
	@echo "Available commands:"
	@grep -E '^##' $(MAKEFILE_LIST) | sed -e 's/## //g' | column -t -s ':' |  sed -e 's/^/ /'

up:
	@echo "Starting containers..."
	$(DOCKER_COMPOSE) up -d

down:
	@echo "Stopping containers..."
	$(DOCKER_COMPOSE) down

restart: down up

build:
	@echo "Building Docker images..."
	$(DOCKER_COMPOSE) build

ps:
	@echo "Checking container status..."
	$(DOCKER_COMPOSE) ps

logs:
	@echo "Viewing logs..."
	$(DOCKER_COMPOSE) logs -f

test:
	@echo "Executing tests on auth microservice..."
	docker exec auth go test ./tests/...
	@echo "Executing tests on email microservice..."
	docker exec email go test ./tests/...
	@echo "Executing tests on broadcasting microservice..."
	docker exec broadcasting go test ./tests/...

migrate:
	@echo "Running migrations for auth microservice..."
	docker exec auth go run cmd/migrate/main.go
	@echo "Running migrations for email microservice..."
	docker exec email go run cmd/migrate/main.go

migrate-fresh:
	@echo "Running fresh migrations for auth..."
	docker exec auth go run cmd/migrate/main.go -fresh
	@echo "Running fresh migrations for email..."
	docker exec email go run cmd/migrate/main.go -fresh

seed:
	@echo "Running seeds for auth microservice..."
	docker exec auth go run cmd/seed/main.go

migrate-seed: migrate-fresh seed

init: up update migrate-seed test

update:
	@echo "Running go mod tidy on auth microservice..."
	docker exec auth go mod tidy
	@echo "Running go mod tidy on email microservice..."
	docker exec email go mod tidy
	@echo "Running go mod tidy on broadcasting microservice..."
	docker exec broadcasting go mod tidy

clean:
	@echo "Cleaning environment..."
	$(DOCKER_COMPOSE) down -v --remove-orphans

compile:
	@echo "Compiling API in auth microservice..."
	docker exec auth go build -o bin/api cmd/api/main.go
	@echo "Compiling consumer in email microservice..."
	docker exec email go build -o bin/consumer cmd/consumer/main.go
	@echo "Compiling consumer in broadcasting microservice..."
	docker exec broadcasting go build -o bin/consumer cmd/consumer/main.go

compile-all:
	@echo "Compiling all auth microservice (api, migrate, seed)..."
	docker exec auth go build -o bin/api cmd/api/main.go
	docker exec auth go build -o bin/migrate cmd/migrate/main.go
	docker exec auth go build -o bin/seed cmd/seed/main.go
	@echo "Compiling all email microservice (consumer, migrate)..."
	docker exec email go build -o bin/consumer cmd/consumer/main.go
	docker exec email go build -o bin/migrate cmd/migrate/main.go
	@echo "Compiling broadcasting microservice (consumer)..."
	docker exec broadcasting go build -o bin/consumer cmd/consumer/main.go
