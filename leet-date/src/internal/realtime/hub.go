package realtime

import "sync"

type Client struct {
	UserID int64
	Send   chan []byte
}

type Hub struct {
	mu           sync.RWMutex
	clients      map[int64]map[*Client]struct{}
	convoClients map[string]map[*Client]struct{}
}

func NewHub() *Hub {
	return &Hub{
		clients:      map[int64]map[*Client]struct{}{},
		convoClients: map[string]map[*Client]struct{}{},
	}
}

func (h *Hub) Register(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[c.UserID] == nil {
		h.clients[c.UserID] = map[*Client]struct{}{}
	}
	h.clients[c.UserID][c] = struct{}{}
}

func (h *Hub) Unregister(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if set, ok := h.clients[c.UserID]; ok {
		delete(set, c)
		if len(set) == 0 {
			delete(h.clients, c.UserID)
		}
	}
	for convID, set := range h.convoClients {
		if _, ok := set[c]; ok {
			delete(set, c)
			if len(set) == 0 {
				delete(h.convoClients, convID)
			}
		}
	}
}

func (h *Hub) Broadcast(userID int64, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients[userID] {
		select {
		case c.Send <- payload:
		default:
		}
	}
}

func (h *Hub) Subscribe(convID string, c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.convoClients[convID] == nil {
		h.convoClients[convID] = map[*Client]struct{}{}
	}
	h.convoClients[convID][c] = struct{}{}
}

func (h *Hub) Unsubscribe(convID string, c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if set, ok := h.convoClients[convID]; ok {
		delete(set, c)
		if len(set) == 0 {
			delete(h.convoClients, convID)
		}
	}
}

func (h *Hub) BroadcastToConvo(convID string, payload []byte) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.convoClients[convID] {
		select {
		case c.Send <- payload:
		default:
		}
	}
}
