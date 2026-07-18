package handlers

import (
	"net/http"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leonardopreuss/leet_date/internal/auth"
	"github.com/leonardopreuss/leet_date/internal/compressclient"
	"github.com/leonardopreuss/leet_date/internal/config"
	"github.com/leonardopreuss/leet_date/internal/premiumjwt"
	"github.com/leonardopreuss/leet_date/internal/realtime"
	"github.com/leonardopreuss/leet_date/internal/storage"
)

func NewRouter(pool *pgxpool.Pool, cfg config.Config, hub *realtime.Hub, verifier *premiumjwt.Verifier, img *compressclient.Client) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())
	r.MaxMultipartMemory = 8 << 20

	corsCfg := cors.Config{
		AllowMethods:     []string{"GET", "POST", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Content-Type"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}
	if cfg.CORSAllowAny {
		corsCfg.AllowOriginFunc = func(origin string) bool { return true }
	} else {
		corsCfg.AllowOrigins = cfg.CORSOrigins
	}
	r.Use(cors.New(corsCfg))

	authDeps := &AuthDeps{Pool: pool, Cfg: cfg}
	profileDeps := &ProfileDeps{Pool: pool}
	photoDeps := &PhotoDeps{Pool: pool, Store: storage.New(cfg.UploadDir), Img: img}
	swipeDeps := &SwipeDeps{Pool: pool}
	convDeps := &ConversationDeps{Pool: pool, Hub: hub}
	wsDeps := &WSDeps{Pool: pool, Hub: hub, Cfg: cfg}
	premiumDeps := &PremiumDeps{Pool: pool, Verifier: verifier}

	api := r.Group("/api")
	{
		api.GET("/healthz", Healthz)
		api.POST("/register", authDeps.Register)
		api.POST("/login", authDeps.Login)
		api.GET("/users/:handle", profileDeps.PublicProfile)
		api.GET("/photos/:id", photoDeps.Serve)

		authed := api.Group("")
		authed.Use(auth.RequireAuth(pool))
		{
			authed.POST("/logout", authDeps.Logout)
			authed.GET("/me", profileDeps.Me)
			authed.PATCH("/me", profileDeps.PatchMe)
			authed.POST("/me/photos", photoDeps.Upload)
			authed.PATCH("/me/photos/:id", photoDeps.Reorder)
			authed.DELETE("/me/photos/:id", photoDeps.Delete)
			authed.GET("/me/photos/:id/original", photoDeps.ServeOriginal)
			authed.GET("/discover", swipeDeps.Discover)
			authed.POST("/swipe", swipeDeps.Swipe)
			authed.GET("/matches", swipeDeps.ListMatches)
			authed.GET("/users/:handle/matches", swipeDeps.ListMatchesByHandle)
			authed.GET("/conversations", convDeps.List)
			authed.GET("/conversations/:id", convDeps.Show)
			authed.GET("/conversations/:id/messages", convDeps.ListMessages)
			authed.POST("/conversations/:id/messages", convDeps.SendMessage)
			authed.GET("/ws", wsDeps.Handle)
			authed.POST("/me/redeem-premium", premiumDeps.RedeemPremium)
			authed.POST("/me/perk", premiumDeps.SetMyPerk)
			authed.GET("/users/:handle/perk", premiumDeps.GetUserPerk)
		}
	}

	r.NoRoute(func(c *gin.Context) {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
	})

	return r
}
