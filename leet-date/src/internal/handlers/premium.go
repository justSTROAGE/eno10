package handlers

import (
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leonardopreuss/leet_date/internal/auth"
	"github.com/leonardopreuss/leet_date/internal/premiumjwt"
)

type PremiumDeps struct {
	Pool     *pgxpool.Pool
	Verifier *premiumjwt.Verifier
}

type redeemReq struct {
	Token string `json:"token"`
}

type perkReq struct {
	PerkText string `json:"perk_text"`
}

type perkRes struct {
	Handle   string `json:"handle"`
	PerkText string `json:"perk_text"`
}

func (d *PremiumDeps) RedeemPremium(c *gin.Context) {
	var req redeemReq
	if err := c.ShouldBindJSON(&req); err != nil || strings.TrimSpace(req.Token) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "token required"})
		return
	}

	claims, err := d.Verifier.Verify(c.Request.Context(), req.Token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid receipt"})
		return
	}

	sessHandle := c.GetString(auth.ContextHandle)
	if !strings.EqualFold(claims.Subject, sessHandle) {
		c.JSON(http.StatusForbidden, gin.H{"error": "receipt subject does not match session"})
		return
	}

	userID := c.GetInt64(auth.ContextUserID)
	if _, err := d.Pool.Exec(c.Request.Context(),
		`UPDATE users SET is_premium = true WHERE id = $1`, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "upgrade failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"ok":           true,
		"is_premium":   true,
		"amount_cents": claims.AmountCents,
	})
}

func (d *PremiumDeps) SetMyPerk(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)
	premium, err := userIsPremium(c, d.Pool, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if !premium {
		c.JSON(http.StatusForbidden, gin.H{"error": "premium required"})
		return
	}

	var req perkReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON body"})
		return
	}
	text := strings.TrimSpace(req.PerkText)
	if text == "" || len(text) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "perk_text must be 1..500 chars"})
		return
	}

	if _, err := d.Pool.Exec(c.Request.Context(), `
        INSERT INTO premium_perks (user_id, perk_text)
        VALUES ($1, $2)
        ON CONFLICT (user_id) DO UPDATE SET perk_text = EXCLUDED.perk_text, updated_at = now()
    `, userID, text); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "save failed"})
		return
	}

	c.JSON(http.StatusOK, perkRes{Handle: c.GetString(auth.ContextHandle), PerkText: text})
}

func (d *PremiumDeps) GetUserPerk(c *gin.Context) {
	handle := strings.ToLower(strings.TrimSpace(c.Param("handle")))
	if !handleRe.MatchString(handle) {
		c.JSON(http.StatusNotFound, gin.H{"error": "perk not found"})
		return
	}

	viewerID := c.GetInt64(auth.ContextUserID)
	viewerHandle := strings.ToLower(c.GetString(auth.ContextHandle))
	viewerPremium, err := userIsPremium(c, d.Pool, viewerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if !viewerPremium {
		c.JSON(http.StatusNotFound, gin.H{"error": "perk not found"})
		return
	}

	// Defense (IDOR): a premium user may only read their OWN perk_text. Reading
	// another user's perk exposed every team's flag via this endpoint. Any
	// request for a handle other than the authenticated viewer's is refused.
	if handle != viewerHandle {
		c.JSON(http.StatusNotFound, gin.H{"error": "perk not found"})
		return
	}

	var (
		targetIsPremium bool
		perkText        *string
	)
	err = d.Pool.QueryRow(c.Request.Context(), `
        SELECT u.is_premium, p.perk_text
        FROM users u
        LEFT JOIN premium_perks p ON p.user_id = u.id
        WHERE u.handle = $1
    `, handle).Scan(&targetIsPremium, &perkText)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "perk not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if !targetIsPremium || perkText == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "perk not found"})
		return
	}

	c.JSON(http.StatusOK, perkRes{Handle: handle, PerkText: *perkText})
}

func userIsPremium(c *gin.Context, pool *pgxpool.Pool, userID int64) (bool, error) {
	var b bool
	if err := pool.QueryRow(c.Request.Context(),
		`SELECT is_premium FROM users WHERE id = $1`, userID).Scan(&b); err != nil {
		return false, err
	}
	return b, nil
}
