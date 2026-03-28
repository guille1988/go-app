### Authentication Microservice in Go

This is a robust and scalable authentication microservice built with **Go**, following clean architecture principles. It provides user registration, login, token refreshing, and user management functionalities, using **JWT** for secure authentication and **Redis** for token management/blacklisting.

---

### 🚀 Features

*   **User Authentication**: Secure Login and Registration using bcrypt for password hashing.
*   **JWT Management**: Issues Access and Refresh tokens.
*   **Token Revocation**: Logout functionality that blacklists tokens in Redis.
*   **User Management**: Full CRUD operations for user profiles (protected by auth middleware).
*   **Clean Architecture**: Separation of concerns into domain, infrastructure, and application layers.
*   **Containerized**: Fully Dockerized for easy deployment and local development.
*   **Database Migrations & Seeding**: Built-in tools for managing database schema and initial data.
*   **Testing Suite**: Includes both unit and integration tests using Testcontainers.

---

### 🛠 Tech Stack

*   **Language**: Go 1.25+
*   **Web Framework**: [Gin Gonic](https://github.com/gin-gonic/gin)
*   **ORM**: [GORM](https://gorm.io/) (supports MySQL, PostgreSQL, SQLite)
*   **Cache**: [Redis](https://redis.io/)
*   **Authentication**: [JWT (golang-jwt)](https://github.com/golang-jwt/jwt)
*   **Migrations**: [golang-migrate](https://github.com/golang-migrate/migrate)
*   **Testing**: [Testify](https://github.com/stretchr/testify) & [Testcontainers](https://testcontainers.com/)

---

### 📋 Prerequisites

*   [Docker](https://www.docker.com/) and Docker Compose.
*   [Go](https://golang.org/) (optional, for local development outside Docker).
*   `make` (utility to run Makefile commands).

---

### ⚙️ Getting Started

1.  **Clone the repository**:
    ```bash
    git clone <repository-url>
    cd auth
    ```

2.  **Initialize the project**:
    This command will copy the `.env.example`, start the Docker containers, run migrations, and execute tests.
    ```bash
    make init
    ```

3.  **Run the application (Development mode)**:
    ```bash
    make run-dev
    ```

---

### 🛠 Development Commands

The project includes a `Makefile` to simplify common tasks:

 Command | Description |
 :--- | :--- |
 `make up` | Start infrastructure (MySQL, Redis, etc.) in background. |
 `make down` | Stop all containers. |
 `make migrate` | Run database migrations. |
 `make migrate-fresh` | Drop all tables and rerun migrations. |
 `make seed` | Populate the database with dummy data. |
 `make test` | Run all integration and unit tests. |
 `make run-prod` | Build and run the service in production-like mode. |

---

### 📡 API Endpoints

#### Authentication (`/api/auth`)
*   `POST /register`: Register a new user.
*   `POST /login`: Authenticate and receive JWT tokens.
*   `POST /refresh`: Get a new access token using a refresh token.
*   `DELETE /logout`: Revoke current tokens.

#### Users (`/api/users`) - *Requires Authorization Header*
*   `GET /`: List all users.
*   `POST /`: Create a user manually.
*   `GET /:uuid`: Get user details by UUID.
*   `PATCH /:uuid`: Update user information.
*   `DELETE /:uuid`: Remove a user.

---

### 📂 Project Structure

```text
├── cmd/                # Entry points (API, Migrations, Seeder)
├── internal/
│   ├── bootstrap/      # App initialization logic
│   ├── domain/         # Business logic (Auth, User modules)
│   │   └── auth/       # Auth actions, handlers, services
│   │   └── user/       # User entity, repository, handlers
│   ├── infrastructure/ # Frameworks & Drivers (DB, Redis, Config, Middlewares)
├── tests/              # Integration and Unit tests
├── Dockerfile          # Production build configuration
└── docker-compose.yaml # Local development environment
```

---

### 🔐 Environment Variables

Key configurations found in `.env`:
*   `APP_PORT`: Server port (default: 8080).
*   `DB_DRIVER`: `mysql`, `postgres`, or `sqlite`.
*   `AUTH_JWT_SECRET`: Secret key for signing tokens.
*   `AUTH_ACCESS_TOKEN_EXPIRE`: Access token TTL in minutes.
*   `REDIS_HOST`: Redis connection host.

---

### 🧪 Testing

Run tests using Docker to ensure a clean environment (uses Testcontainers for DB/Redis):
```bash
make test
```
