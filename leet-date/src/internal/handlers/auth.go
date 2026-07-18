package handlers

import (
	"errors"
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leonardopreuss/leet_date/internal/auth"
	"github.com/leonardopreuss/leet_date/internal/config"
)

var handleRe = regexp.MustCompile(`^[a-z0-9_]{3,20}$`)

type AuthDeps struct {
	Pool *pgxpool.Pool
	Cfg  config.Config
}

type registerReq struct {
	Handle      string `json:"handle"`
	DisplayName string `json:"display_name"`
	Password    string `json:"password"`
}

type loginReq struct {
	Handle   string `json:"handle"`
	Password string `json:"password"`
}

type meResp struct {
	ID          int64  `json:"id"`
	Handle      string `json:"handle"`
	DisplayName string `json:"display_name"`
}

func (d *AuthDeps) Register(c *gin.Context) {
	var req registerReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON body"})
		return
	}
	req.Handle = strings.ToLower(strings.TrimSpace(req.Handle))
	req.DisplayName = strings.TrimSpace(req.DisplayName)

	if !handleRe.MatchString(req.Handle) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "handle must match [a-z0-9_]{3,20}"})
		return
	}
	if len(req.DisplayName) < 1 || len(req.DisplayName) > 64 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "display_name must be 1-64 chars"})
		return
	}
	if len(req.Password) < 8 || len(req.Password) > 128 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "password must be 8-128 chars"})
		return
	}

	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not hash password"})
		return
	}

	var userID int64
	err = d.Pool.QueryRow(c.Request.Context(),
		`INSERT INTO users (handle, display_name, password_hash)
         VALUES ($1, $2, $3) RETURNING id`,
		req.Handle, req.DisplayName, hash).Scan(&userID)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			c.JSON(http.StatusConflict, gin.H{"error": "handle already taken"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create user"})
		return
	}

	token, expires, err := auth.CreateSession(c.Request.Context(), d.Pool, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create session"})
		return
	}
	auth.SetSessionCookie(c, token, expires, d.Cfg.CookieSecure, d.Cfg.CookieDomain)

	c.JSON(http.StatusCreated, meResp{ID: userID, Handle: req.Handle, DisplayName: req.DisplayName})
}

func (d *AuthDeps) Login(c *gin.Context) {
	var req loginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON body"})
		return
	}
	req.Handle = strings.ToLower(strings.TrimSpace(req.Handle))

	var (
		userID      int64
		displayName string
		hash        string
	)
	err := d.Pool.QueryRow(c.Request.Context(),
		`SELECT id, display_name, password_hash FROM users WHERE handle = $1`,
		req.Handle).Scan(&userID, &displayName, &hash)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}

	ok, err := auth.VerifyPassword(req.Password, hash)
	if err != nil || !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	token, expires, err := auth.CreateSession(c.Request.Context(), d.Pool, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create session"})
		return
	}
	auth.SetSessionCookie(c, token, expires, d.Cfg.CookieSecure, d.Cfg.CookieDomain)

	c.JSON(http.StatusOK, meResp{ID: userID, Handle: req.Handle, DisplayName: displayName})
}

func (d *AuthDeps) Logout(c *gin.Context) {
	if tok, ok := c.Get(auth.ContextSessTok); ok {
		_ = auth.DeleteSession(c.Request.Context(), d.Pool, tok.(string))
	}
	auth.ClearSessionCookie(c, d.Cfg.CookieSecure, d.Cfg.CookieDomain)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
