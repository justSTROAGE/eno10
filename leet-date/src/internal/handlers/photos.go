package handlers

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leonardopreuss/leet_date/internal/auth"
	"github.com/leonardopreuss/leet_date/internal/compressclient"
	"github.com/leonardopreuss/leet_date/internal/storage"
)

const (
	maxPhotosPerUser  = 6
	maxPhotoBytes     = 5 << 20
	maxStoredBytes    = 2*maxPhotoBytes + 64
	compressThreshold = 256 << 10
	codecFormat       = "codec"
	thumbMaxDim       = 320
	maxDecodePixels   = 12 << 20
	decodeConcurrency = 2
)

var decodeLimiter = make(chan struct{}, decodeConcurrency)

const thumbCacheCap = 2048

type thumbEntry struct {
	data  []byte
	ctype string
}

type thumbCache struct {
	mu sync.Mutex
	m  map[int64]thumbEntry
}

func (t *thumbCache) get(id int64) (thumbEntry, bool) {
	t.mu.Lock()
	defer t.mu.Unlock()
	e, ok := t.m[id]
	return e, ok
}

func (t *thumbCache) put(id int64, e thumbEntry) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if len(t.m) >= thumbCacheCap {
		for k := range t.m {
			delete(t.m, k)
			break
		}
	}
	t.m[id] = e
}

var thumbnails = &thumbCache{m: make(map[int64]thumbEntry)}

type PhotoDeps struct {
	Pool  *pgxpool.Pool
	Store *storage.Store
	Img   *compressclient.Client
}

func extForContentType(ct string) (string, bool) {
	switch ct {
	case "image/jpeg":
		return "jpg", true
	case "image/png":
		return "png", true
	case "image/webp":
		return "webp", true
	}
	return "", false
}

func (d *PhotoDeps) codecCtx(c *gin.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(c.Request.Context(), 8*time.Second)
}

func (d *PhotoDeps) Upload(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)

	fh, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing 'file' field"})
		return
	}
	if fh.Size > maxPhotoBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "max 5 MiB per photo"})
		return
	}

	src, err := fh.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not open upload"})
		return
	}
	defer src.Close()

	raw, err := io.ReadAll(io.LimitReader(src, maxPhotoBytes+1))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read upload"})
		return
	}
	if len(raw) > maxPhotoBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "max 5 MiB per photo"})
		return
	}

	var (
		contentType  string
		ext          string
		isCompressed bool
		stored       []byte
	)

	if c.PostForm("format") == codecFormat {
		contentType = c.PostForm("content_type")
		if _, ok := extForContentType(contentType); !ok {
			c.JSON(http.StatusUnsupportedMediaType, gin.H{"error": "content_type must be jpeg, png or webp"})
			return
		}
		ext = "ldz"
		isCompressed = true
		stored = raw
	} else {
		sniff := raw
		if len(sniff) > 512 {
			sniff = sniff[:512]
		}
		contentType = http.DetectContentType(sniff)
		imgExt, ok := extForContentType(contentType)
		if !ok {
			c.JSON(http.StatusUnsupportedMediaType, gin.H{"error": "only jpeg, png, webp accepted"})
			return
		}
		if len(raw) > compressThreshold {
			ctx, cancel := d.codecCtx(c)
			blob, err := d.Img.Compress(ctx, raw)
			cancel()
			if err != nil {
				c.JSON(http.StatusBadGateway, gin.H{"error": "compression unavailable"})
				return
			}
			ext = "ldz"
			isCompressed = true
			stored = blob
		} else {
			ext = imgExt
			stored = raw
		}
	}

	ctx := c.Request.Context()

	var existing int
	if err := d.Pool.QueryRow(ctx,
		`SELECT count(*) FROM photos WHERE user_id = $1`, userID,
	).Scan(&existing); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if existing >= maxPhotosPerUser {
		c.JSON(http.StatusConflict, gin.H{"error": "max photos reached"})
		return
	}

	var nextSort int
	if err := d.Pool.QueryRow(ctx,
		`SELECT COALESCE(MAX(sort_order), -1) + 1 FROM photos WHERE user_id = $1`, userID,
	).Scan(&nextSort); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}

	var photoID int64
	err = d.Pool.QueryRow(ctx, `
        INSERT INTO photos (user_id, filename, content_type, sort_order, is_compressed)
        VALUES ($1, '', $2, $3, $4) RETURNING id`,
		userID, contentType, nextSort, isCompressed,
	).Scan(&photoID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "insert failed"})
		return
	}

	filename := fmt.Sprintf("%d.%s", photoID, ext)
	if _, err := d.Store.Save(userID, filename, bytes.NewReader(stored)); err != nil {
		_, _ = d.Pool.Exec(ctx, `DELETE FROM photos WHERE id = $1`, photoID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "save failed"})
		return
	}

	if _, err := d.Pool.Exec(ctx,
		`UPDATE photos SET filename = $1 WHERE id = $2`, filename, photoID,
	); err != nil {
		_ = d.Store.Delete(userID, filename)
		_, _ = d.Pool.Exec(ctx, `DELETE FROM photos WHERE id = $1`, photoID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "save failed"})
		return
	}

	c.JSON(http.StatusCreated, photoDTO{
		ID:        photoID,
		URL:       fmt.Sprintf("/api/photos/%d", photoID),
		SortOrder: nextSort,
	})
}

type reorderReq struct {
	SortOrder int `json:"sort_order"`
}

func (d *PhotoDeps) Reorder(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
		return
	}
	var req reorderReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid JSON body"})
		return
	}

	tag, err := d.Pool.Exec(c.Request.Context(),
		`UPDATE photos SET sort_order = $1 WHERE id = $2 AND user_id = $3`,
		req.SortOrder, id, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "update failed"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func (d *PhotoDeps) Delete(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
		return
	}

	var filename string
	err = d.Pool.QueryRow(c.Request.Context(),
		`DELETE FROM photos WHERE id = $1 AND user_id = $2 RETURNING filename`,
		id, userID,
	).Scan(&filename)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "delete failed"})
		return
	}

	_ = d.Store.Delete(userID, filename)
	c.Status(http.StatusNoContent)
}

func (d *PhotoDeps) Serve(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
		return
	}

	raw, contentType, isCompressed, ok := d.loadPhotoBytes(c, id, nil)
	if !ok {
		return
	}

	if isCompressed {
		ctx, cancel := d.codecCtx(c)
		plain, err := d.Img.Decompress(ctx, raw)
		cancel()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "decode failed"})
			return
		}
		if e, ok := thumbnails.get(id); ok {
			c.Header("Cache-Control", "no-store")
			c.Data(http.StatusOK, e.ctype, e.data)
			return
		}
		thumb, ctype, ok := makeThumbnail(plain)
		if !ok {
			c.Header("Cache-Control", "no-store")
			c.Data(http.StatusOK, contentType, plain)
			return
		}
		thumbnails.put(id, thumbEntry{data: thumb, ctype: ctype})
		c.Header("Cache-Control", "no-store")
		c.Data(http.StatusOK, ctype, thumb)
		return
	}

	c.Header("Cache-Control", "public, max-age=86400")
	c.Data(http.StatusOK, contentType, raw)
}

func (d *PhotoDeps) ServeOriginal(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
		return
	}

	raw, contentType, isCompressed, ok := d.loadPhotoBytes(c, id, &userID)
	if !ok {
		return
	}

	if isCompressed {
		ctx, cancel := d.codecCtx(c)
		plain, err := d.Img.Decompress(ctx, raw)
		cancel()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "decode failed"})
			return
		}
		c.Header("Cache-Control", "no-store")
		c.Data(http.StatusOK, contentType, plain)
		return
	}

	c.Header("Cache-Control", "no-store")
	c.Data(http.StatusOK, contentType, raw)
}

func (d *PhotoDeps) loadPhotoBytes(c *gin.Context, id int64, owner *int64) ([]byte, string, bool, bool) {
	var (
		ownerID      int64
		filename     string
		contentType  string
		isCompressed bool
	)
	err := d.Pool.QueryRow(c.Request.Context(),
		`SELECT user_id, filename, content_type, is_compressed FROM photos WHERE id = $1`, id,
	).Scan(&ownerID, &filename, &contentType, &isCompressed)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
			return nil, "", false, false
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return nil, "", false, false
	}
	if owner != nil && ownerID != *owner {
		c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
		return nil, "", false, false
	}

	f, err := d.Store.Open(ownerID, filename)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "photo not found"})
		return nil, "", false, false
	}
	defer f.Close()

	readCap := int64(maxPhotoBytes) + 1
	if isCompressed {
		readCap = maxStoredBytes + 1
	}
	raw, err := io.ReadAll(io.LimitReader(f, readCap))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "read failed"})
		return nil, "", false, false
	}
	return raw, contentType, isCompressed, true
}

func makeThumbnail(plain []byte) ([]byte, string, bool) {
	cfg, _, err := image.DecodeConfig(bytes.NewReader(plain))
	if err != nil {
		return nil, "", false
	}
	if cfg.Width*cfg.Height > maxDecodePixels {
		return nil, "", false
	}

	decodeLimiter <- struct{}{}
	defer func() { <-decodeLimiter }()

	img, _, err := image.Decode(bytes.NewReader(plain))
	if err != nil {
		return nil, "", false
	}
	img = downscale(img, thumbMaxDim)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 82}); err != nil {
		return nil, "", false
	}
	return buf.Bytes(), "image/jpeg", true
}

func downscale(src image.Image, maxDim int) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	if w <= maxDim && h <= maxDim {
		return src
	}
	nw, nh := w, h
	if w >= h {
		nw = maxDim
		nh = h * maxDim / w
	} else {
		nh = maxDim
		nw = w * maxDim / h
	}
	if nw < 1 {
		nw = 1
	}
	if nh < 1 {
		nh = 1
	}
	dst := image.NewRGBA(image.Rect(0, 0, nw, nh))
	for y := 0; y < nh; y++ {
		sy := b.Min.Y + y*h/nh
		for x := 0; x < nw; x++ {
			sx := b.Min.X + x*w/nw
			dst.Set(x, y, src.At(sx, sy))
		}
	}
	return dst
}
