DOCKER_COMPOSE   = docker-compose -f infrastructure/local/docker-compose.yml
KUBECTL          = kubectl -n go-app
MINIKUBE_PROFILE = go-app
K8S_DIR          = infrastructure/production/k8s

.PHONY: \
	help \
	local-up local-down local-restart local-build local-ps local-logs \
	local-test local-migrate local-migrate-fresh local-seed local-migrate-seed \
	local-init local-update local-compile local-compile-all \
	up down restart build ps logs test migrate migrate-fresh seed migrate-seed \
	init update clean compile compile-all \
	production-setup production-build production-up production-down production-restart \
	production-ps production-logs production-test production-migrate \
    production-init production-url production-stress

help:
	@echo "Available commands:"
	@grep -E '^##' $(MAKEFILE_LIST) | sed -e 's/## //g' | column -t -s ':' |  sed -e 's/^/ /'

# ── LOCAL (docker-compose) ────────────────────────────────────────────────────

local-up:
	@echo "Starting local containers..."
	$(DOCKER_COMPOSE) up -d

local-down:
	@echo "Removing local containers..."
	$(DOCKER_COMPOSE) down -v --remove-orphans

local-restart: local-down local-up

local-build:
	@echo "Building local Docker images..."
	$(DOCKER_COMPOSE) build

local-ps:
	@echo "Checking container status..."
	$(DOCKER_COMPOSE) ps

local-logs:
	@echo "Viewing logs..."
	$(DOCKER_COMPOSE) logs -f

local-test:
	@echo "Executing tests on auth microservice..."
	docker exec auth go test ./tests/...
	@echo "Executing tests on email microservice..."
	docker exec email go test ./tests/...
	@echo "Executing tests on broadcasting microservice..."
	docker exec broadcasting go test ./tests/...

local-migrate:
	@echo "Running migrations for auth microservice..."
	docker exec auth go run cmd/migrate/main.go
	@echo "Running migrations for email microservice..."
	docker exec email go run cmd/migrate/main.go

local-migrate-fresh:
	@echo "Running fresh migrations for auth..."
	docker exec auth go run cmd/migrate/main.go -fresh
	@echo "Running fresh migrations for email..."
	docker exec email go run cmd/migrate/main.go -fresh

local-seed:
	@echo "Running seeds for auth microservice..."
	docker exec auth go run cmd/seed/main.go

local-migrate-seed: local-migrate-fresh local-seed

local-init: local-up local-update local-migrate-seed local-test

local-update:
	@echo "Running go mod tidy on auth microservice..."
	docker exec auth go mod tidy
	@echo "Running go mod tidy on email microservice..."
	docker exec email go mod tidy
	@echo "Running go mod tidy on broadcasting microservice..."
	docker exec broadcasting go mod tidy

local-compile:
	@echo "Compiling API in auth microservice..."
	docker exec auth go build -o bin/api cmd/api/main.go
	@echo "Compiling consumer in email microservice..."
	docker exec email go build -o bin/consumer cmd/consumer/main.go
	@echo "Compiling consumer in broadcasting microservice..."
	docker exec broadcasting go build -o bin/consumer cmd/consumer/main.go

local-compile-all:
	@echo "Compiling all auth microservice (api, migrate, seed)..."
	docker exec auth go build -o bin/api cmd/api/main.go
	docker exec auth go build -o bin/migrate cmd/migrate/main.go
	docker exec auth go build -o bin/seed cmd/seed/main.go
	@echo "Compiling all email microservice (consumer, migrate)..."
	docker exec email go build -o bin/consumer cmd/consumer/main.go
	docker exec email go build -o bin/migrate cmd/migrate/main.go
	@echo "Compiling broadcasting microservice (consumer)..."
	docker exec broadcasting go build -o bin/consumer cmd/consumer/main.go

# ── ALIASES (backwards-compatible originals) ─────────────────────────────────

up: local-up
down: local-down
restart: local-restart
build: local-build
ps: local-ps
logs: local-logs
test: local-test
migrate: local-migrate
migrate-fresh: local-migrate-fresh
seed: local-seed
migrate-seed: local-migrate-seed
init: local-init
update: local-update
compile: local-compile
compile-all: local-compile-all

# ── PRODUCTION (minikube / kubectl) ───────────────────────────────────────────

production-setup:
	@echo "Starting minikube..."
	minikube start --profile=$(MINIKUBE_PROFILE) --driver=docker --cpus=12 --memory=49152
	@echo "Enabling NGINX ingress addon..."
	minikube addons enable ingress --profile=$(MINIKUBE_PROFILE)
	@echo "Waiting for ingress controller..."
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=120s
	@echo "Enabling metrics-server addon..."
	minikube addons enable metrics-server --profile=$(MINIKUBE_PROFILE)
	kubectl wait --namespace kube-system \
		--for=condition=ready pod \
		--selector=k8s-app=metrics-server \
		--timeout=60s
	@echo "Exposing ingress metrics port..."
	kubectl apply -f infrastructure/production/k8s/ingress-metrics-svc.yaml
	@echo "Enabling ingress controller metrics..."
	kubectl -n ingress-nginx patch deployment ingress-nginx-controller \
		--type=json \
		-p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--enable-metrics=true"}]'
	kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=60s
	@echo "Tuning NGINX ingress for high throughput..."
	kubectl -n ingress-nginx patch configmap ingress-nginx-controller \
		--type merge \
		-p '{"data":{"worker-processes":"auto","keep-alive":"75","keep-alive-requests":"10000","upstream-keepalive-connections":"200","upstream-keepalive-requests":"10000"}}'

production-build:
	@echo "Building production images inside minikube daemon..."
	minikube image build --profile=$(MINIKUBE_PROFILE) -t auth:latest -f infrastructure/production/auth/Dockerfile .
	minikube image build --profile=$(MINIKUBE_PROFILE) -t email:latest -f infrastructure/production/email/Dockerfile .
	minikube image build --profile=$(MINIKUBE_PROFILE) -t broadcasting:latest -f infrastructure/production/broadcasting/Dockerfile .

production-up:
	@echo "Deploying to minikube..."
	kubectl apply -f $(K8S_DIR)/namespace.yaml
	$(KUBECTL) apply -f $(K8S_DIR)/secrets/
	$(KUBECTL) apply -f $(K8S_DIR)/infra/
	$(KUBECTL) apply -f $(K8S_DIR)/services/
	@echo "Waiting for infra pods (mysql, kafka, redis)..."
	$(KUBECTL) wait --for=condition=ready pod -l app=mysql-auth --timeout=180s
	$(KUBECTL) wait --for=condition=ready pod -l app=mysql-email --timeout=180s
	$(KUBECTL) wait --for=condition=ready pod -l app=kafka --timeout=180s
	$(KUBECTL) wait --for=condition=ready pod -l app=redis --timeout=180s
	@echo "Restarting app services after infra is ready..."
	$(KUBECTL) rollout restart deployment/auth deployment/email deployment/broadcasting
	$(KUBECTL) rollout status deployment/auth --timeout=120s
	$(KUBECTL) rollout status deployment/email --timeout=120s

production-down:
	@echo "Removing production deployment..."
	$(KUBECTL) delete -f $(K8S_DIR)/services/ --ignore-not-found
	$(KUBECTL) delete -f $(K8S_DIR)/infra/ --ignore-not-found
	$(KUBECTL) delete -f $(K8S_DIR)/secrets/ --ignore-not-found
	@echo "Deleting go-app namespace..."
	kubectl delete namespace go-app --ignore-not-found
	@echo "Stopping minikube..."
	minikube stop --profile=$(MINIKUBE_PROFILE)

production-restart:
	@echo "Restarting application deployments..."
	$(KUBECTL) rollout restart deployment/auth deployment/email deployment/email-api deployment/broadcasting

production-ps:
	@echo "Production pod status:"
	$(KUBECTL) get pods -o wide

production-logs:
	@echo "Viewing auth logs (Ctrl-C to stop)..."
	$(KUBECTL) logs -f deployment/auth

production-migrate:
	@echo "Running migrations for auth..."
	$(KUBECTL) exec deployment/auth -- ./bin/migrate
	@echo "Running migrations for email..."
	$(KUBECTL) exec deployment/email -- ./bin/migrate

production-stress:
	@echo "Deploying k6 stress job..."
	$(KUBECTL) delete job k6-stress --ignore-not-found
	$(KUBECTL) create configmap k6-stress-script \
		--from-file=stress.js=infrastructure/production/k6/stress.js \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) apply -f $(K8S_DIR)/k6/job.yaml
	@echo "Waiting for k6 job to complete..."
	$(KUBECTL) wait --for=condition=complete job/k6-stress --timeout=300s
	@echo "k6 results:"
	$(KUBECTL) logs job/k6-stress

production-init: production-setup production-build production-up production-migrate

production-tunnel:
	@echo "Starting minikube tunnel (keep this terminal open)..."
	minikube tunnel --profile=$(MINIKUBE_PROFILE)

production-url:
	@echo "Run 'make production-tunnel' in a separate terminal, then access:"
	@echo "  http://localhost/api/auth/api/health"

