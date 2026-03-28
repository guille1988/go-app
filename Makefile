DOCKER_COMPOSE = docker-compose -f docker/docker-compose.yml

.PHONY: up down restart build ps logs test migrate seed clean help

## help: Muestra los comandos disponibles
help:
	@echo "Comandos disponibles:"
	@grep -E '^##' $(MAKEFILE_LIST) | sed -e 's/## //g' | column -t -s ':' |  sed -e 's/^/ /'

## up: Levanta todos los servicios en segundo plano
up:
	$(DOCKER_COMPOSE) up -d

## down: Detiene y elimina los contenedores
down:
	$(DOCKER_COMPOSE) down

## restart: Reinicia los contenedores (down y luego up)
restart: down up

## build: Reconstruye las imágenes de los servicios
build:
	$(DOCKER_COMPOSE) build

## ps: Muestra el estado de los contenedores
ps:
	$(DOCKER_COMPOSE) ps

## logs: Muestra los logs en tiempo real
logs:
	$(DOCKER_COMPOSE) logs -f

## test: Ejecuta los tests en ambos microservicios
test:
	@echo "Executing tests on auth microservice..."
	docker exec -it auth go test ./...
	@echo "Executing tests on e-mail microservice..."
	docker exec -it email go test ./...

## migrate: Corre las migraciones en ambos microservicios
migrate:
	@echo "Running migrations for auth..."
	docker exec -it auth go run cmd/migrate/main.go
	@echo "Running migrations for email..."
	docker exec -it email go run cmd/migrate/main.go

## seed: Puebla las bases de datos con datos iniciales
seed:
	@echo "Running seeds for auth..."
	docker exec -it auth go run cmd/seed/main.go
	@echo "Running seeds for email..."
	docker exec -it email go run cmd/seed/main.go

## clean: Elimina contenedores, volúmenes y huérfanos
clean:
	$(DOCKER_COMPOSE) down -v --remove-orphans
