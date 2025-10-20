package handlers

import (
	"context"

	"github.com/LowTechTurtle/ServerlessURLShortener/internal/core/services"
	"github.com/aws/aws-lambda-go/events"
)

type DeleteFunctionHandler struct {
	linkService *services.LinkService
}

func NewDeleteFunctionHandler(l *services.LinkService) *DeleteFunctionHandler {
	return &DeleteFunctionHandler{linkService: l}
}

func (s *DeleteFunctionHandler) Delete(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayProxyResponse, error) {
	id := req.PathParameters["id"]

	err := s.linkService.Delete(ctx, id)
	if err != nil {
		return events.APIGatewayProxyResponse{StatusCode: 500}, err
	}

	return events.APIGatewayProxyResponse{StatusCode: 204}, nil
}
