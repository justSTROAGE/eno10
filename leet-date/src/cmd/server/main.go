package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/leonardopreuss/leet_date/internal/compressclient"
	"github.com/leonardopreuss/leet_date/internal/config"
	"github.com/leonardopreuss/leet_date/internal/db"
	"github.com/leonardopreuss/leet_date/internal/handlers"
	"github.com/leonardopreuss/leet_date/internal/premiumjwt"
	"github.com/leonardopreuss/leet_date/internal/realtime"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx := context.Background()

	pool, err := db.NewPool(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db connect: %v", err)
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatalf("migrate: %v", err)
	}
	log.Printf("migrations applied")

	if err := os.MkdirAll(cfg.UploadDir, 0o755); err != nil {
		log.Fatalf("mkdir upload dir: %v", err)
	}

	hub := realtime.NewHub()

	verifier := premiumjwt.New(cfg.PaymentsJWKSURL, "leetdate-payments", "leetdate")
	if err := verifier.Refresh(ctx); err != nil {
		log.Printf("warn: initial JWKS refresh failed: %v (will retry on first verify)", err)
	}

	img, err := compressclient.New(cfg.ImgSvcAddr)
	if err != nil {
		log.Fatalf("imgsvc client: %v", err)
	}
	defer img.Close()

	router := handlers.NewRouter(pool, cfg, hub, verifier, img)

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("listening on %s", cfg.ListenAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Printf("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
}
