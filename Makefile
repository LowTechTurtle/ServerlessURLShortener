.PHONY: all fmt lint test build clean

all: fmt lint test build

# Format all Go files
fmt:
	@echo "Formatting Go code..."
	go fmt ./...

# Run static analysis
lint:
	@echo "Running go vet..."
	go vet ./...

# Run unit tests with coverage
test:
	@echo "Running unit tests..."
	go test -v -cover ./internal/tests/unit/...

# Build the Lambda functions
build: build-generate build-redirect build-delete

build-generate:
	@echo "Building generate function..."
	GOOS=linux GOARCH=amd64 go build -o internal/adapters/functions/generate/bootstrap internal/adapters/functions/generate/main.go

build-redirect:
	@echo "Building redirect function..."
	GOOS=linux GOARCH=amd64 go build -o internal/adapters/functions/redirect/bootstrap internal/adapters/functions/redirect/main.go

build-delete:
	@echo "Building delete function..."
	GOOS=linux GOARCH=amd64 go build -o internal/adapters/functions/delete/bootstrap internal/adapters/functions/delete/main.go

# Clean generated binaries
clean:
	@echo "Cleaning up..."
	rm -f internal/adapters/functions/generate/bootstrap
	rm -f internal/adapters/functions/redirect/bootstrap
	rm -f internal/adapters/functions/delete/bootstrap

# Build Docker images
docker-build: docker-build-generate docker-build-redirect docker-build-delete

docker-build-generate:
	@echo "Building Docker image for generate function..."
	docker build --build-arg FUNCTION=generate -t url-shortener-generate .

docker-build-redirect:
	@echo "Building Docker image for redirect function..."
	docker build --build-arg FUNCTION=redirect -t url-shortener-redirect .

docker-build-delete:
	@echo "Building Docker image for delete function..."
	docker build --build-arg FUNCTION=delete -t url-shortener-delete .

# Docker Compose management
up:
	@echo "Starting the full stack locally..."
	docker compose up -d

down:
	@echo "Stopping the local stack..."
	docker compose down

logs:
	docker compose logs -f
