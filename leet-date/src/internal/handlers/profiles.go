package handlers

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leonardopreuss/leet_date/internal/auth"
)

type ProfileDeps struct {
	Pool *pgxpool.Pool
}

type photoDTO struct {
	ID        int64  `json:"id"`
	URL       string `json:"url"`
	SortOrder int    `json:"sort_order"`
}

type meDTO struct {
	ID             int64      `json:"id"`
	Handle         string     `json:"handle"`
	DisplayName    string     `json:"display_name"`
	Age            *int16     `json:"age"`
	Gender         *string    `json:"gender"`
	LookingFor     []string   `json:"looking_for"`
	City           *string    `json:"city"`
	Bio            *string    `json:"bio"`
	Interests      []string   `json:"interests"`
	PrivateContact *string    `json:"private_contact"`
	IsPremium      bool       `json:"is_premium"`
	Photos         []photoDTO `json:"photos"`
}

type publicProfileDTO struct {
	ID          int64      `json:"id"`
	Handle      string     `json:"handle"`
	DisplayName string     `json:"display_name"`
	Age         *int16     `json:"age"`
	Gender      *string    `json:"gender"`
	LookingFor  []string   `json:"looking_for"`
	City        *string    `json:"city"`
	Bio         *string    `json:"bio"`
	Interests   []string   `json:"interests"`
	IsPremium   bool       `json:"is_premium"`
	Photos      []photoDTO `json:"photos"`
}

type patchReq struct {
	Age            *int16    `json:"age"`
	Gender         *string   `json:"gender"`
	LookingFor     *[]string `json:"looking_for"`
	City           *string   `json:"city"`
	Bio            *string   `json:"bio"`
	Interests      *[]string `json:"interests"`
	PrivateContact *string   `json:"private_contact"`
}

var (
	allowedGenders = map[string]struct{}{
		"female": {}, "male": {}, "other": {},
	}
	interestRe = regexp.MustCompile(`^[a-z0-9_-]{1,24}$`)
)

func (d *ProfileDeps) Me(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)

	var dto meDTO
	err := d.Pool.QueryRow(c.Request.Context(), `
        SELECT id, handle, display_name, age, gender, looking_for,
               city, bio, interests, private_contact, is_premium
        FROM users WHERE id = $1`,
		userID,
	).Scan(
		&dto.ID, &dto.Handle, &dto.DisplayName,
		&dto.Age, &dto.Gender, &dto.LookingFor,
		&dto.City, &dto.Bio, &dto.Interests, &dto.PrivateContact, &dto.IsPremium,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}

	photos, err := loadPhotos(c.Request.Context(), d.Pool, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	dto.Photos = photos

	c.JSON(http.StatusOK, dto)
}

func (d *ProfileDeps) PublicProfile(c *gin.Context) {
	handle := strings.ToLower(strings.TrimSpace(c.Param("handle")))
	if !handleRe.MatchString(handle) {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	var dto publicProfileDTO
	err := d.Pool.QueryRow(c.Request.Context(), `
        SELECT id, handle, display_name, age, gender, looking_for,
               city, bio, interests, is_premium
        FROM users WHERE handle = $1`,
		handle,
	).Scan(
		&dto.ID, &dto.Handle, &dto.DisplayName,
		&dto.Age, &dto.Gender, &dto.LookingFor,
		&dto.City, &dto.Bio, &dto.Interests, &dto.IsPremium,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
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

	c.JSON(http.StatusOK, dto)
}

func (d *ProfileDeps) PatchMe(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)

	var req patchReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON body"})
		return
	}

	sets := []string{}
	args := []any{}
	idx := 1

	if req.Age != nil {
		if *req.Age < 18 || *req.Age > 120 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "age must be 18..120"})
			return
		}
		sets = append(sets, fmt.Sprintf("age = $%d", idx))
		args = append(args, *req.Age)
		idx++
	}

	if req.Gender != nil {
		g := strings.TrimSpace(*req.Gender)
		if g != "" {
			if _, ok := allowedGenders[g]; !ok {
				c.JSON(http.StatusBadRequest, gin.H{"error": "gender must be female|male|other"})
				return
			}
		}
		sets = append(sets, fmt.Sprintf("gender = $%d", idx))
		args = append(args, nullIfEmpty(g))
		idx++
	}

	if req.LookingFor != nil {
		seen := map[string]struct{}{}
		out := []string{}
		for _, v := range *req.LookingFor {
			v = strings.TrimSpace(v)
			if v == "" {
				continue
			}
			if _, ok := allowedGenders[v]; !ok {
				c.JSON(http.StatusBadRequest, gin.H{"error": "looking_for entries must be in female|male|other"})
				return
			}
			if _, dup := seen[v]; dup {
				continue
			}
			seen[v] = struct{}{}
			out = append(out, v)
		}
		if len(out) > 4 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "looking_for max 4 entries"})
			return
		}
		sets = append(sets, fmt.Sprintf("looking_for = $%d", idx))
		args = append(args, out)
		idx++
	}

	if req.City != nil {
		v := strings.TrimSpace(*req.City)
		if len(v) > 80 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "city max 80 chars"})
			return
		}
		sets = append(sets, fmt.Sprintf("city = $%d", idx))
		args = append(args, nullIfEmpty(v))
		idx++
	}

	if req.Bio != nil {
		if len(*req.Bio) > 500 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "bio max 500 chars"})
			return
		}
		sets = append(sets, fmt.Sprintf("bio = $%d", idx))
		args = append(args, nullIfEmpty(*req.Bio))
		idx++
	}

	if req.Interests != nil {
		seen := map[string]struct{}{}
		out := []string{}
		for _, v := range *req.Interests {
			v = strings.ToLower(strings.TrimSpace(v))
			if v == "" {
				continue
			}
			if !interestRe.MatchString(v) {
				c.JSON(http.StatusBadRequest, gin.H{"error": "interests must match [a-z0-9_-]{1,24}"})
				return
			}
			if _, dup := seen[v]; dup {
				continue
			}
			seen[v] = struct{}{}
			out = append(out, v)
		}
		if len(out) > 10 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "interests max 10 entries"})
			return
		}
		sets = append(sets, fmt.Sprintf("interests = $%d", idx))
		args = append(args, out)
		idx++
	}

	if req.PrivateContact != nil {
		if len(*req.PrivateContact) > 200 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "private_contact max 200 chars"})
			return
		}
		sets = append(sets, fmt.Sprintf("private_contact = $%d", idx))
		args = append(args, nullIfEmpty(*req.PrivateContact))
		idx++
	}

	if len(sets) == 0 {
		d.Me(c)
		return
	}

	sets = append(sets, "profile_updated_at = now()")
	args = append(args, userID)
	q := fmt.Sprintf(`UPDATE users SET %s WHERE id = $%d`, strings.Join(sets, ", "), idx)
	if _, err := d.Pool.Exec(c.Request.Context(), q, args...); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "update failed"})
		return
	}

	d.Me(c)
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func loadPhotos(ctx context.Context, pool *pgxpool.Pool, userID int64) ([]photoDTO, error) {
	rows, err := pool.Query(ctx, `
        SELECT id, sort_order FROM photos
        WHERE user_id = $1
        ORDER BY sort_order ASC, id ASC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []photoDTO{}
	for rows.Next() {
		var p photoDTO
		if err := rows.Scan(&p.ID, &p.SortOrder); err != nil {
			return nil, err
		}
		p.URL = fmt.Sprintf("/api/photos/%d", p.ID)
		out = append(out, p)
	}
	return out, rows.Err()
}
