package config

import (
	"fmt"
	"os"
	"strings"
)

type Config struct {
	DatabaseURL     string
	ListenAddr      string
	CookieDomain    string
	CookieSecure    bool
	CORSOrigins     []string
	CORSAllowAny    bool
	UploadDir       string
	PaymentsJWKSURL string
	ImgSvcAddr      string
}

func Load() (Config, error) {
	c := Config{
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		ListenAddr:      getenv("LISTEN_ADDR", ":8000"),
		CookieDomain:    os.Getenv("COOKIE_DOMAIN"),
		CookieSecure:    os.Getenv("COOKIE_SECURE") == "1",
		UploadDir:       getenv("UPLOAD_DIR", "/data/uploads"),
		PaymentsJWKSURL: getenv("PAYMENTS_JWKS_URL", "http://payments:7000/.well-known/jwks.json"),
		ImgSvcAddr:      getenv("IMGSVC_ADDR", "imgsvc:9000"),
	}
	if c.DatabaseURL == "" {
		return c, fmt.Errorf("DATABASE_URL is required")
	}
	rawCORS := getenv("CORS_ORIGIN", "http://localhost:5173,http://localhost:6789")
	if strings.TrimSpace(rawCORS) == "*" {
		c.CORSAllowAny = true
	} else {
		c.CORSOrigins = splitCSV(rawCORS)
	}
	return c, nil
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func splitCSV(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if t := strings.TrimSpace(p); t != "" {
			out = append(out, t)
		}
	}
	return out
}
