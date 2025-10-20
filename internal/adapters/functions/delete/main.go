package main

import (
	"context"

	"github.com/LowTechTurtle/ServerlessURLShortener/internal/adapters/cache"
	"github.com/LowTechTurtle/ServerlessURLShortener/internal/adapters/handlers"
	"github.com/LowTechTurtle/ServerlessURLShortener/internal/adapters/repository"
	"github.com/LowTechTurtle/ServerlessURLShortener/internal/config"
	"github.com/LowTechTurtle/ServerlessURLShortener/internal/core/services"
	"github.com/aws/aws-lambda-go/lambda"
)

func main() {
	appConfig := config.NewConfig()
	redisAddress, redisPassword, redisDB := appConfig.GetRedisParams()
	linkTableName := appConfig.GetLinkTableName()

	cache := cache.NewRedisCache(redisAddress, redisPassword, redisDB)

	linkRepo := repository.NewLinkRepository(context.TODO(), linkTableName)
	linkService := services.NewLinkService(linkRepo, cache)

	handler := handlers.NewDeleteFunctionHandler(linkService)
	lambda.Start(handler.Delete)
}
