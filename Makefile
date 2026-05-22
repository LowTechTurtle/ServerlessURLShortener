.PHONY: all fmt check-fmt lint test build clean tf-fmt tf-fmt-check tf-validate tf-lint trivy-scan docker-build

all: fmt check-fmt lint test build tf-fmt tf-fmt-check tf-validate tf-lint trivy-scan

# Format all Go files
fmt:
	@echo "Formatting Go code..."
	go fmt ./...

check-fmt:
	@echo "Checking Go format..."
	@if [ "$$(gofmt -s -l . | wc -l)" -gt 0 ]; then echo "Go code is not formatted. Run 'make fmt' locally."; exit 1; fi

# Run static analysis
lint:
	@echo "Running go vet..."
	go vet ./...

# Run unit tests with coverage
test:
	@echo "Running unit tests..."
	go test -v ./internal/tests/unit/...

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

# ==========================================
# Terraform Code Quality Commands
# ==========================================
tf-fmt:
	@echo "Formatting Terraform code..."
	terraform -chdir=terraform fmt -recursive

tf-fmt-check:
	@echo "Checking Terraform format..."
	terraform -chdir=terraform fmt -check -recursive

tf-validate:
	@echo "Validating Terraform code..."
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform validate

tf-lint:
	@echo "Running tflint..."
	cd terraform && tflint --init && tflint

trivy-scan:
	@echo "Running Trivy vulnerability scanner on IaC & Dockerfile..."
	trivy config ./terraform
	trivy config Dockerfile

tf-init:
	@echo "Initializing Terraform Backend..."
	terraform -chdir=terraform init

tf-apply:
	@echo "Applying Terraform configuration..."
	terraform -chdir=terraform apply -auto-approve