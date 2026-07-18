package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leonardopreuss/leet_date/internal/auth"
	"github.com/leonardopreuss/leet_date/internal/realtime"
)

type ConversationDeps struct {
	Pool *pgxpool.Pool
	Hub  *realtime.Hub
}

type conversationDTO struct {
	ID            string           `json:"id"`
	OtherUser     publicProfileDTO `json:"other_user"`
	CreatedAt     time.Time        `json:"created_at"`
	LastMessageAt *time.Time       `json:"last_message_at"`
}

type messageDTO struct {
	ID             int64     `json:"id"`
	ConversationID string    `json:"conversation_id"`
	SenderID       int64     `json:"sender_id"`
	Body           string    `json:"body"`
	CreatedAt      time.Time `json:"created_at"`
}

type sendMessageReq struct {
	Body string `json:"body"`
}

func (d *ConversationDeps) List(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)

	rows, err := d.Pool.Query(c.Request.Context(), `
        SELECT id, user_a, user_b, created_at, last_message_at
        FROM conversations
        WHERE user_a = $1 OR user_b = $1
        ORDER BY COALESCE(last_message_at, created_at) DESC`,
		userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	defer rows.Close()

	type rawConv struct {
		id            string
		userA, userB  int64
		createdAt     time.Time
		lastMessageAt *time.Time
	}
	raws := []rawConv{}
	for rows.Next() {
		var r rawConv
		if err := rows.Scan(&r.id, &r.userA, &r.userB, &r.createdAt, &r.lastMessageAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		raws = append(raws, r)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
		return
	}

	out := []conversationDTO{}
	for _, r := range raws {
		otherID := r.userA
		if otherID == userID {
			otherID = r.userB
		}
		dto, err := loadPublicProfile(c, d.Pool, otherID)
		if err != nil {
			continue
		}
		out = append(out, conversationDTO{
			ID:            r.id,
			OtherUser:     dto,
			CreatedAt:     r.createdAt,
			LastMessageAt: r.lastMessageAt,
		})
	}
	c.JSON(http.StatusOK, gin.H{"conversations": out})
}

func (d *ConversationDeps) Show(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)
	convID, ok := parseConvID(c)
	if !ok {
		return
	}

	var userA, userB int64
	var createdAt time.Time
	var lastMessageAt *time.Time
	err := d.Pool.QueryRow(c.Request.Context(),
		`SELECT user_a, user_b, created_at, last_message_at FROM conversations WHERE id = $1`,
		convID,
	).Scan(&userA, &userB, &createdAt, &lastMessageAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if userA != userID && userB != userID {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	otherID := userA
	if otherID == userID {
		otherID = userB
	}
	dto, err := loadPublicProfile(c, d.Pool, otherID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	c.JSON(http.StatusOK, conversationDTO{
		ID:            convID,
		OtherUser:     dto,
		CreatedAt:     createdAt,
		LastMessageAt: lastMessageAt,
	})
}

func (d *ConversationDeps) ListMessages(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)
	convID, ok := parseConvID(c)
	if !ok {
		return
	}
	if !d.userInConversation(c, userID, convID) {
		return
	}

	rows, err := d.Pool.Query(c.Request.Context(), `
        SELECT id, conversation_id, sender_id, body, created_at
        FROM messages
        WHERE conversation_id = $1
        ORDER BY created_at ASC, id ASC
        LIMIT 500`, convID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	defer rows.Close()

	out := []messageDTO{}
	for rows.Next() {
		var m messageDTO
		if err := rows.Scan(&m.ID, &m.ConversationID, &m.SenderID, &m.Body, &m.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		out = append(out, m)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"messages": out})
}

func (d *ConversationDeps) SendMessage(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)
	convID, ok := parseConvID(c)
	if !ok {
		return
	}

	var req sendMessageReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON body"})
		return
	}
	body := strings.TrimSpace(req.Body)
	if body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "body is required"})
		return
	}
	if len(body) > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "body max 2000 chars"})
		return
	}

	var userA, userB int64
	err := d.Pool.QueryRow(c.Request.Context(),
		`SELECT user_a, user_b FROM conversations WHERE id = $1`, convID,
	).Scan(&userA, &userB)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if userA != userID && userB != userID {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return
	}

	var msg messageDTO
	err = d.Pool.QueryRow(c.Request.Context(), `
        INSERT INTO messages (conversation_id, sender_id, body)
        VALUES ($1, $2, $3)
        RETURNING id, conversation_id, sender_id, body, created_at`,
		convID, userID, body,
	).Scan(&msg.ID, &msg.ConversationID, &msg.SenderID, &msg.Body, &msg.CreatedAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "send failed"})
		return
	}
	_, _ = d.Pool.Exec(c.Request.Context(),
		`UPDATE conversations SET last_message_at = $1 WHERE id = $2`,
		msg.CreatedAt, convID,
	)

	if d.Hub != nil {
		otherID := userA
		if otherID == userID {
			otherID = userB
		}
		envelope := map[string]any{
			"type":    "message",
			"message": msg,
		}
		payload, _ := json.Marshal(envelope)
		d.Hub.Broadcast(userID, payload)
		if otherID != userID {
			d.Hub.Broadcast(otherID, payload)
		}
		d.Hub.BroadcastToConvo(convID, payload)
	}

	c.JSON(http.StatusOK, msg)
}

func (d *ConversationDeps) userInConversation(c *gin.Context, userID int64, convID string) bool {
	var userA, userB int64
	err := d.Pool.QueryRow(c.Request.Context(),
		`SELECT user_a, user_b FROM conversations WHERE id = $1`, convID,
	).Scan(&userA, &userB)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
			return false
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return false
	}
	if userA != userID && userB != userID {
		c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"})
		return false
	}
	return true
}

func parseConvID(c *gin.Context) (string, bool) {
	convID := c.Param("id")
	if convID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return "", false
	}
	return convID, true
}

func loadPublicProfile(c *gin.Context, pool *pgxpool.Pool, userID int64) (publicProfileDTO, error) {
	var dto publicProfileDTO
	err := pool.QueryRow(c.Request.Context(), `
        SELECT id, handle, display_name, age, gender, looking_for,
               city, bio, interests
        FROM users WHERE id = $1`, userID,
	).Scan(
		&dto.ID, &dto.Handle, &dto.DisplayName,
		&dto.Age, &dto.Gender, &dto.LookingFor,
		&dto.City, &dto.Bio, &dto.Interests,
	)
	if err != nil {
		return dto, err
	}
	photos, err := loadPhotos(c.Request.Context(), pool, userID)
	if err != nil {
		return dto, err
	}
	dto.Photos = photos
	return dto, nil
}
