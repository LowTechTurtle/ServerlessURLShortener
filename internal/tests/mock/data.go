package mock


import "github.com/LowTechTurtle/ServerlessURLShortener/internal/core/domain"

var MockLinkData []domain.Link = []domain.Link{
	{Id: "testid1", OriginalURL: "https://example.com/link1"},
	{Id: "testid2", OriginalURL: "https://example.com/link2"},
	{Id: "testid3", OriginalURL: "https://example.com/link3"},
}
