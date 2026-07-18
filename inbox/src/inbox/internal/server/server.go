package server

import (
	"inbox/internal/db"
	"inbox/internal/session"
	"log"
	"net"
	"time"
)

type Server struct {
	listener net.Listener
	db       *db.DB
}

func New(addr string, database *db.DB) (*Server, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, err
	}
	return &Server{listener: ln, db: database}, nil
}

func (s *Server) Addr() net.Addr { return s.listener.Addr() }

func (s *Server) Serve() {
	var tempDelay time.Duration
	for {
		conn, err := s.listener.Accept()
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Temporary() {
				if tempDelay == 0 {
					tempDelay = 5 * time.Millisecond
				} else {
					tempDelay *= 2
				}
				if tempDelay > time.Second {
					tempDelay = time.Second
				}
				log.Printf("accept temporary error: %v; retrying in %v", err, tempDelay)
				time.Sleep(tempDelay)
				continue
			}

			log.Printf("accept error: %v", err)
			return
		}
		tempDelay = 0
		go session.New(conn, s.db).Run()
	}
}

func (s *Server) Close() error { return s.listener.Close() }
