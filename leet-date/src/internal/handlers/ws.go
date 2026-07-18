package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/leonardopreuss/leet_date/internal/auth"
	"github.com/leonardopreuss/leet_date/internal/config"
	"github.com/leonardopreuss/leet_date/internal/realtime"
)

type WSDeps struct {
	Pool *pgxpool.Pool
	Hub  *realtime.Hub
	Cfg  config.Config
}

func (d *WSDeps) Handle(c *gin.Context) {
	userID := c.GetInt64(auth.ContextUserID)

	upgrader := websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin: func(r *http.Request) bool {
			origin := r.Header.Get("Origin")
			if origin == "" || d.Cfg.CORSAllowAny {
				return true
			}
			for _, o := range d.Cfg.CORSOrigins {
				if origin == o {
					return true
				}
			}
			return false
		},
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	client := &realtime.Client{
		UserID: userID,
		Send:   make(chan []byte, 32),
	}
	d.Hub.Register(client)

	hello, _ := json.Marshal(map[string]any{"type": "hello", "user_id": userID})
	_ = conn.WriteMessage(websocket.TextMessage, hello)

	go func() {
		for payload := range client.Send {
			if err := conn.WriteMessage(websocket.TextMessage, payload); err != nil {
				return
			}
		}
	}()

	for {
		_, raw, err := conn.ReadMessage()
		if err != nil {
			break
		}
		var in struct {
			Type           string `json:"type"`
			ConversationID string `json:"conversation_id"`
		}
		if err := json.Unmarshal(raw, &in); err != nil {
			continue
		}
		switch in.Type {
		case "subscribe":
			if in.ConversationID != "" {
				d.Hub.Subscribe(in.ConversationID, client)
				d.hydrateRecent(c, client, in.ConversationID)
			}
		case "unsubscribe":
			if in.ConversationID != "" {
				d.Hub.Unsubscribe(in.ConversationID, client)
			}
		}
	}

	d.Hub.Unregister(client)
	close(client.Send)
	_ = conn.Close()
}

func (d *WSDeps) hydrateRecent(c *gin.Context, client *realtime.Client, convID string) {
	rows, err := d.Pool.Query(c.Request.Context(), `
        SELECT id, conversation_id, sender_id, body, created_at
        FROM (
            SELECT id, conversation_id, sender_id, body, created_at
            FROM messages
            WHERE conversation_id = $1
            ORDER BY created_at DESC, id DESC
            LIMIT 50
        ) sub
        ORDER BY created_at ASC, id ASC`, convID)
	if err != nil {
		return
	}
	defer rows.Close()

	for rows.Next() {
		var m messageDTO
		if err := rows.Scan(&m.ID, &m.ConversationID, &m.SenderID, &m.Body, &m.CreatedAt); err != nil {
			return
		}
		payload, err := json.Marshal(map[string]any{"type": "message", "message": m})
		if err != nil {
			continue
		}
		select {
		case client.Send <- payload:
		default:
			return
		}
	}
}
