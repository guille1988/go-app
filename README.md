# Go-App Microservices Project

A modern, scalable microservices architecture built with **Go 1.25**, focusing on clean code, asynchronous communication, and containerized deployments.

---

### 🧱 Architecture Overview

This project is a distributed system consisting of several specialized microservices that communicate via REST APIs and asynchronous messaging (Kafka).

*   **[Auth Microservice](./auth)**: Manages user authentication, JWT issuance, and user profiles. Uses Redis for token management.
*   **[Email Microservice](./email)**: Handles email dispatching. Consumes messages from Kafka to send transactional emails asynchronously.
*   **Message Broker**: Kafka serves as the central hub for inter-service communication.
*   **Database**: Each microservice manages its own database (MySQL/PostgreSQL/SQLite) ensuring data isolation.

---

### 🚀 Quick Start

#### Prerequisites
- [Docker](https://www.docker.com/) & Docker Compose.
- `make` utility.

#### 1. Start the entire system
From the root directory, run:
```bash
make up
```
This will start MySQL, Redis, Kafka, Promtail, and all microservices defined in the `docker-compose.yml`.

#### 2. Run Database Migrations
Initialize schemas for all services:
```bash
make migrate
```

#### 3. Seed initial data (Optional)
```bash
make seed
```

---

### 🛠 Centralized Management (Makefile)

The project includes a root-level `Makefile` to manage all microservices at once:

| Command | Description |
| :--- | :--- |
| `make up` | Start all containers in detached mode. |
| `make down` | Stop and remove all containers. |
| `make build` | Rebuild all Docker images. |
| `make test` | Execute tests for ALL microservices. |
| `make migrate` | Run migrations for ALL microservices. |
| `make compile-all` | Compile binaries for all services and their CLI tools. |
| `make clean` | Remove containers and their associated volumes. |

---

### 📁 Project Structure

```text
.
├── auth/               # Auth microservice source code
├── email/              # Email microservice source code
├── docker/             # Dockerfiles and infrastructure configuration
│   ├── auth/
│   ├── email/
│   └── docker-compose.yml
└── Makefile            # Main orchestration file
```

---

### 📡 System Communication Flow

1.  **User Registration**: Client hits the `Auth` API.
2.  **User Persisted**: `Auth` service saves user data to its database.
3.  **Event Published**: `Auth` service publishes a `WelcomeEmail` message to the Kafka topic `user.created`.
4.  **Event Consumed**: `Email` service consumes the message from the topic.
5.  **Email Sent**: `Email` service renders the template and sends it via SMTP.

---

### 🧪 Testing Strategy

Each service contains its own testing suite. You can run all of them from the root:
```bash
make test
```
The integration tests use **Testcontainers**, ensuring that services are tested against real instances of MySQL, Redis, and Kafka.

---

### 📈 Monitoring & Logs

The system includes **Promtail** for log aggregation, designed to work within a Grafana/Loki stack for centralized observability.
