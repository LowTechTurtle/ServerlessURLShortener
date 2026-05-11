FROM golang:1.23 AS builder

WORKDIR /app

# Copy go.mod and go.sum first to leverage Docker cache
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source code
COPY . .

# Argument to select which function to build (default to generate)
ARG FUNCTION=generate

# Build the binary
# GOOS=linux GOARCH=amd64 is required for the Lambda execution environment
RUN GOOS=linux GOARCH=amd64 go build -o bootstrap internal/adapters/functions/${FUNCTION}/main.go

# Stage 2: AWS Lambda Runtime
FROM public.ecr.aws/lambda/provided:al2023

# Copy the compiled binary from the builder stage
# The lambda runtime expects the executable to be located at ${LAMBDA_RUNTIME_DIR}/bootstrap
COPY --from=builder /app/bootstrap ${LAMBDA_RUNTIME_DIR}/bootstrap

# Set the command to run the bootstrap file
CMD [ "bootstrap" ]
