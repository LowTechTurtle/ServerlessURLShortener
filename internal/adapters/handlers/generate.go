package handlers

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"math/big"
	"net/http"
	"time"

	"github.com/LowTechTurtle/ServerlessURLShortener/internal/core/domain"
	"github.com/LowTechTurtle/ServerlessURLShortener/internal/core/services"
	"github.com/aws/aws-lambda-go/events"
)

type RequestBody struct {
	Long string `json:"long"`
}
type GenerateLinkFunctionHandler struct {
	linkService *services.LinkService
}

func NewGenerateLinkFunctionHandler(l *services.LinkService) *GenerateLinkFunctionHandler {
	return &GenerateLinkFunctionHandler{linkService: l}
}

func (h *GenerateLinkFunctionHandler) CreateShortLink(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayProxyResponse, error) {
	var requestBody RequestBody

	err := json.Unmarshal([]byte(req.Body), &requestBody)
	if err != nil {
		return ClientError(http.StatusBadRequest, "Invalid JSON")
	}

	if requestBody.Long == "" {
		return ClientError(http.StatusBadRequest, "URL cannot be empty")
	}
	if len(requestBody.Long) < 15 {
		return ClientError(http.StatusBadRequest, "URL must be at least 15 characters long")
	}
	if !IsValidLink(requestBody.Long) {
		return ClientError(http.StatusBadRequest, "Invalid URL format")
	}

	link := domain.Link{
		Id:          GenerateShortURLID(8),
		OriginalURL: requestBody.Long,
		CreatedAt:   time.Now(),
	}

	err = h.linkService.Create(ctx, link)
	if err != nil {
		return ServerError(err)
	}

	js, err := json.Marshal(link)
	if err != nil {
		return ServerError(err)
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
    		"Access-Control-Allow-Origin":     "*", // or "https://your-site.example"
    		"Access-Control-Allow-Headers":    "Content-Type,Authorization",
    		"Access-Control-Allow-Methods":    "OPTIONS,POST,GET,PUT,DELETE",
    		"Access-Control-Expose-Headers":   "Content-Length",
  		},
		Body: string(js),
	}, nil
}

func GenerateShortURLID(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	result := make([]byte, length)
	for i := 0; i < length; i++ {
		charIndex, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		result[i] = charset[charIndex.Int64()]
	}
	return string(result)
}
