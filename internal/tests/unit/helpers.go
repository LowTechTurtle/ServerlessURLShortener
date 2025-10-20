package unit

import (
	"context"

	"github.com/LowTechTurtle/ServerlessURLShortener/internal/adapters/cache"
	"github.com/LowTechTurtle/ServerlessURLShortener/internal/core/domain"
)

func FillCache(cache *cache.RedisCache, links []domain.Link) error {
	for _, link := range links {
		err := cache.Set(context.Background(), link.Id, link.OriginalURL)
		if err != nil {
			return err
		}
	}
	return nil
}
