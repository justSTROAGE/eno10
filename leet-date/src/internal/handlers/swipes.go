package handlers

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leonardopreuss/leet_date/internal/auth"
	"github.com/leonardopreuss/leet_date/internal/chat"
)

type SwipeDeps struct {
	Pool *pgxpool.Pool
}

type swipeReq struct {
	TargetID  int64  `json:"target_id"`
	Direction string `json:"direction"`
}

type swipeResp struct {
	Matched bool `json:"matched"`
}

type matchEntry struct {
	User      publicProfileDTO `json:"user"`
	MatchedAt time.Time        `json:"matched_at"`
}

func (d *SwipeDeps) Discover(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)

	var (
		meGender     *string
		meLookingFor []string
	)
	if err := d.Pool.QueryRow(c.Request.Context(),
		`SELECT gender, looking_for FROM users WHERE id = $1`, userID,
	).Scan(&meGender, &meLookingFor); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if meLookingFor == nil {
		meLookingFor = []string{}
	}
	gender := ""
	if meGender != nil {
		gender = *meGender
	}

	var dto publicProfileDTO
	err := d.Pool.QueryRow(c.Request.Context(), `
        SELECT u.id, u.handle, u.display_name, u.age, u.gender, u.looking_for,
               u.city, u.bio, u.interests
        FROM users u
        WHERE u.id <> $1
          AND NOT EXISTS (
            SELECT 1 FROM swipes s
            WHERE s.user_id = $1 AND s.target_id = u.id
          )
          AND (
            cardinality($2::text[]) = 0
            OR u.gender = ANY($2::text[])
          )
          AND (
            $3::text = ''
            OR u.looking_for IS NULL
            OR cardinality(u.looking_for) = 0
            OR $3::text = ANY(u.looking_for)
          )
        ORDER BY random()
        LIMIT 1`,
		userID, meLookingFor, gender,
	).Scan(
		&dto.ID, &dto.Handle, &dto.DisplayName,
		&dto.Age, &dto.Gender, &dto.LookingFor,
		&dto.City, &dto.Bio, &dto.Interests,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusOK, gin.H{"user": nil})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}

	photos, err := loadPhotos(c.Request.Context(), d.Pool, dto.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	dto.Photos = photos

	c.JSON(http.StatusOK, gin.H{"user": dto})
}

func (d *SwipeDeps) Swipe(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)

	var req swipeReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON body"})
		return
	}
	if req.Direction != "like" && req.Direction != "pass" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "direction must be like|pass"})
		return
	}
	if req.TargetID == userID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot swipe self"})
		return
	}

	var exists bool
	if err := d.Pool.QueryRow(c.Request.Context(),
		`SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)`, req.TargetID,
	).Scan(&exists); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	if _, err := d.Pool.Exec(c.Request.Context(), `
        INSERT INTO swipes (user_id, target_id, direction)
        VALUES ($1, $2, $3)
        ON CONFLICT (user_id, target_id) DO NOTHING`,
		userID, req.TargetID, req.Direction,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "swipe failed"})
		return
	}

	matched := false
	if req.Direction == "like" {
		if err := d.Pool.QueryRow(c.Request.Context(), `
            SELECT EXISTS(
                SELECT 1 FROM swipes
                WHERE user_id = $1 AND target_id = $2 AND direction = 'like'
            ) AND EXISTS(
                SELECT 1 FROM swipes
                WHERE user_id = $2 AND target_id = $1 AND direction = 'like'
            )`,
			req.TargetID, userID,
		).Scan(&matched); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
			return
		}
		if matched {
			a, b := userID, req.TargetID
			if a > b {
				a, b = b, a
			}
			var handleA, handleB string
			if err := d.Pool.QueryRow(c.Request.Context(),
				`SELECT handle FROM users WHERE id = $1`, a,
			).Scan(&handleA); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
				return
			}
			if err := d.Pool.QueryRow(c.Request.Context(),
				`SELECT handle FROM users WHERE id = $1`, b,
			).Scan(&handleB); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
				return
			}
			convID := chat.ConversationID(handleA, handleB)
			if _, err := d.Pool.Exec(c.Request.Context(), `
                INSERT INTO conversations (id, user_a, user_b)
                VALUES ($1, $2, $3)
                ON CONFLICT (user_a, user_b) DO NOTHING`,
				convID, a, b,
			); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "conversation create failed"})
				return
			}
		}
	}

	c.JSON(http.StatusOK, swipeResp{Matched: matched})
}

type matchByHandleEntry struct {
	Handle    string    `json:"handle"`
	MatchedAt time.Time `json:"matched_at"`
}

func (d *SwipeDeps) ListMatchesByHandle(c *gin.Context) {
	handle := strings.ToLower(strings.TrimSpace(c.Param("handle")))
	if !handleRe.MatchString(handle) {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	var targetID int64
	err := d.Pool.QueryRow(c.Request.Context(),
		`SELECT id FROM users WHERE handle = $1`, handle,
	).Scan(&targetID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}

	rows, err := d.Pool.Query(c.Request.Context(), `
        SELECT
            CASE WHEN m.user_a = $1 THEN ub.handle ELSE ua.handle END AS peer_handle,
            m.matched_at
        FROM matches m
        JOIN users ua ON ua.id = m.user_a
        JOIN users ub ON ub.id = m.user_b
        WHERE m.user_a = $1 OR m.user_b = $1
        ORDER BY m.matched_at DESC`,
		targetID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	defer rows.Close()

	out := []matchByHandleEntry{}
	for rows.Next() {
		var m matchByHandleEntry
		if err := rows.Scan(&m.Handle, &m.MatchedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		out = append(out, m)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"matches": out})
}

func (d *SwipeDeps) ListMatches(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)

	rows, err := d.Pool.Query(c.Request.Context(), `
        SELECT
            CASE WHEN m.user_a = $1 THEN m.user_b ELSE m.user_a END AS other_id,
            m.matched_at
        FROM matches m
        WHERE m.user_a = $1 OR m.user_b = $1
        ORDER BY m.matched_at DESC`,
		userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	defer rows.Close()

	type pair struct {
		otherID   int64
		matchedAt time.Time
	}
	pairs := []pair{}
	for rows.Next() {
		var p pair
		if err := rows.Scan(&p.otherID, &p.matchedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		pairs = append(pairs, p)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
		return
	}

	out := []matchEntry{}
	for _, p := range pairs {
		var dto publicProfileDTO
		err := d.Pool.QueryRow(c.Request.Context(), `
            SELECT id, handle, display_name, age, gender, looking_for,
                   city, bio, interests
            FROM users WHERE id = $1`, p.otherID,
		).Scan(
			&dto.ID, &dto.Handle, &dto.DisplayName,
			&dto.Age, &dto.Gender, &dto.LookingFor,
			&dto.City, &dto.Bio, &dto.Interests,
		)
		if err != nil {
			continue
		}
		photos, err := loadPhotos(c.Request.Context(), d.Pool, p.otherID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
			return
		}
		dto.Photos = photos
		out = append(out, matchEntry{User: dto, MatchedAt: p.matchedAt})
	}

	c.JSON(http.StatusOK, gin.H{"matches": out})
}
