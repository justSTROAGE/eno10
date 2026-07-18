package auth

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	CookieName     = "ld_session"
	SessionTTL     = 24 * time.Hour
	ContextUserID  = "user_id"
	ContextHandle  = "handle"
	ContextDispNm  = "display_name"
	ContextSessTok = "session_token"
)

var ErrSessionNotFound = errors.New("session not found")

type Session struct {
	Token       string
	UserID      int64
	Handle      string
	DisplayName string
	ExpiresAt   time.Time
}

func newToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func CreateSession(ctx context.Context, pool *pgxpool.Pool, userID int64) (string, time.Time, error) {
	token, err := newToken()
	if err != nil {
		return "", time.Time{}, err
	}
	expires := time.Now().Add(SessionTTL)
	if _, err := pool.Exec(ctx,
		`INSERT INTO sessions (token, user_id, expires_at) VALUES ($1, $2, $3)`,
		token, userID, expires); err != nil {
		return "", time.Time{}, err
	}
	return token, expires, nil
}

func LookupSession(ctx context.Context, pool *pgxpool.Pool, token string) (Session, error) {
	row := pool.QueryRow(ctx, `
        SELECT s.token, s.user_id, s.expires_at, u.handle, u.display_name
        FROM sessions s
        JOIN users u ON u.id = s.user_id
        WHERE s.token = $1 AND s.expires_at > now()`,
		token)
	var s Session
	if err := row.Scan(&s.Token, &s.UserID, &s.ExpiresAt, &s.Handle, &s.DisplayName); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Session{}, ErrSessionNotFound
		}
		return Session{}, err
	}
	return s, nil
}

func DeleteSession(ctx context.Context, pool *pgxpool.Pool, token string) error {
	_, err := pool.Exec(ctx, `DELETE FROM sessions WHERE token = $1`, token)
	return err
}

func SetSessionCookie(c *gin.Context, token string, expires time.Time, secure bool, domain string) {
	c.SetSameSite(http.SameSiteLaxMode)
	c.SetCookie(CookieName, token, int(time.Until(expires).Seconds()), "/", domain, secure, true)
}

func ClearSessionCookie(c *gin.Context, secure bool, domain string) {
	c.SetSameSite(http.SameSiteLaxMode)
	c.SetCookie(CookieName, "", -1, "/", domain, secure, true)
}

func RequireAuth(pool *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		token, err := c.Cookie(CookieName)
		if err != nil || token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
			return
		}
		s, err := LookupSession(c.Request.Context(), pool, token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "not authenticated"})
			return
		}
		c.Set(ContextUserID, s.UserID)
		c.Set(ContextHandle, s.Handle)
		c.Set(ContextDispNm, s.DisplayName)
		c.Set(ContextSessTok, s.Token)
		c.Next()
	}
}
