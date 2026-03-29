DOCKER_COMPOSE = docker-compose -f docker/docker-compose.yml

.PHONY: up down restart build ps logs test migrate seed clean help

help:
	@echo "Comandos disponibles:"
	@grep -E '^##' $(MAKEFILE_LIST) | sed -e 's/## //g' | column -t -s ':' |  sed -e 's/^/ /'

up:
	$(DOCKER_COMPOSE) up -d

down:
	$(DOCKER_COMPOSE) down

restart: down up

build:
	$(DOCKER_COMPOSE) build

ps:
	$(DOCKER_COMPOSE) ps

logs:
	$(DOCKER_COMPOSE) logs -f

test:
	@echo "Executing tests on auth microservice..."
	docker exec -it auth go test ./...
	@echo "Executing tests on e-mail microservice..."
	docker exec -it email go test ./...

migrate:
	@echo "Running migrations for auth..."
	docker exec -it auth go run cmd/migrate/main.go
	@echo "Running migrations for email..."
	docker exec -it email go run cmd/migrate/main.go

seed:
	@echo "Running seeds for auth..."
	docker exec -it auth go run cmd/seed/main.go
	@echo "Running seeds for email..."
	docker exec -it email go run cmd/seed/main.go

clean:
	$(DOCKER_COMPOSE) down -v --remove-orphans
