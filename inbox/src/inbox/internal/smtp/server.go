package smtp

import (
	"bufio"
	"bytes"
	"encoding/base64"
	"fmt"
	"inbox/internal/db"
	"log"
	"net"
	"strings"
	"time"
)

type Server struct {
	listener net.Listener
	db       *db.DB
	host     string
}

func New(addr string, database *db.DB) (*Server, error) {
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, err
	}
	return &Server{listener: ln, db: database, host: "inbox.local"}, nil
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
				log.Printf("smtp accept temporary error: %v; retrying in %v", err, tempDelay)
				time.Sleep(tempDelay)
				continue
			}

			log.Printf("smtp accept error: %v", err)
			return
		}
		tempDelay = 0
		go newSession(conn, s.db, s.host).run()
	}
}

func (s *Server) Close() error { return s.listener.Close() }

type session struct {
	conn       net.Conn
	r          *bufio.Reader
	db         *db.DB
	host       string
	helo       string
	authedUser string
	mailFrom   string
	rcptTo     []string
}

func newSession(c net.Conn, database *db.DB, host string) *session {
	return &session{
		conn: c,
		r:    bufio.NewReaderSize(c, 65536),
		db:   database,
		host: host,
	}
}

func (s *session) reply(format string, args ...any) {
	fmt.Fprintf(s.conn, format+"\r\n", args...)
}

func (s *session) reset() {
	s.mailFrom = ""
	s.rcptTo = nil
}

func (s *session) run() {
	defer s.conn.Close()
	s.reply("220 %s SMTP ready", s.host)

	for {
		line, err := s.r.ReadString('\n')
		if err != nil {
			return
		}
		line = strings.TrimRight(line, "\r\n")
		verb, arg := splitVerb(line)
		switch strings.ToUpper(verb) {
		case "HELO":
			s.helo = arg
			s.reply("250 %s hello %s", s.host, arg)
		case "EHLO":
			s.helo = arg
			s.reply("250-%s hello %s", s.host, arg)
			s.reply("250-PIPELINING")
			s.reply("250-8BITMIME")
			s.reply("250-AUTH PLAIN")
			s.reply("250-SIZE 1048576")
			s.reply("250 HELP")
		case "NOOP":
			s.reply("250 OK")
		case "RSET":
			s.reset()
			s.reply("250 OK")
		case "QUIT":
			s.reply("221 %s closing", s.host)
			return
		case "AUTH":
			s.cmdAuth(arg)
		case "MAIL":
			s.cmdMail(arg)
		case "RCPT":
			s.cmdRcpt(arg)
		case "DATA":
			s.cmdData()
		case "HELP":
			s.reply("214 verbs: HELO EHLO AUTH MAIL RCPT DATA NOOP RSET QUIT")
		default:
			s.reply("500 5.5.1 command unrecognized")
		}
	}
}

func (s *session) cmdAuth(arg string) {
	if s.authedUser != "" {
		s.reply("503 5.5.1 already authenticated")
		return
	}
	parts := strings.SplitN(arg, " ", 2)
	if len(parts) < 1 || strings.ToUpper(parts[0]) != "PLAIN" {
		s.reply("504 5.5.4 mechanism not supported")
		return
	}
	var encoded string
	if len(parts) == 2 {
		encoded = strings.TrimSpace(parts[1])
	} else {
		s.reply("334 ")
		line, err := s.r.ReadString('\n')
		if err != nil {
			return
		}
		encoded = strings.TrimRight(line, "\r\n")
	}
	if encoded == "*" {
		s.reply("501 5.5.0 authentication aborted")
		return
	}
	decoded, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		s.reply("501 5.5.2 invalid base64")
		return
	}

	pieces := bytes.SplitN(decoded, []byte{0}, 3)
	if len(pieces) != 3 {
		s.reply("501 5.5.2 malformed PLAIN response")
		return
	}
	username := string(pieces[1])
	password := string(pieces[2])
	if !isValidUsername(username) {
		s.reply("535 5.7.8 authentication failed")
		return
	}
	if _, ok := s.db.Authenticate(username, password); !ok {
		s.reply("535 5.7.8 authentication failed")
		return
	}
	s.authedUser = username
	s.reply("235 2.7.0 authentication successful")
}

func (s *session) cmdMail(arg string) {
	if s.authedUser == "" {
		s.reply("530 5.7.0 authentication required")
		return
	}
	addr, ok := parseAddrParam(arg, "FROM")
	if !ok {
		s.reply("501 5.5.4 syntax: MAIL FROM:<addr>")
		return
	}
	s.mailFrom = addr
	s.rcptTo = nil
	s.reply("250 2.1.0 OK")
}

func (s *session) cmdRcpt(arg string) {
	if s.authedUser == "" {
		s.reply("530 5.7.0 authentication required")
		return
	}
	if s.mailFrom == "" {
		s.reply("503 5.5.1 need MAIL FROM first")
		return
	}
	addr, ok := parseAddrParam(arg, "TO")
	if !ok {
		s.reply("501 5.5.4 syntax: RCPT TO:<addr>")
		return
	}
	local := localPart(addr)
	if !isValidUsername(local) || !s.db.UserExists(local) {
		s.reply("550 5.1.1 no such user")
		return
	}
	s.rcptTo = append(s.rcptTo, local)
	s.reply("250 2.1.5 OK")
}

func (s *session) cmdData() {
	if s.authedUser == "" {
		s.reply("530 5.7.0 authentication required")
		return
	}
	if s.mailFrom == "" || len(s.rcptTo) == 0 {
		s.reply("503 5.5.1 need MAIL FROM and RCPT TO first")
		return
	}
	s.reply("354 end with <CRLF>.<CRLF>")

	body, err := readDotStuffed(s.r)
	if err != nil {
		s.reply("554 5.6.0 read failure")
		return
	}

	if len(body) > 1024*1024 {
		s.reply("552 5.3.4 message too large")
		s.reset()
		return
	}

	sender := localPart(s.mailFrom)
	if sender != "" {
		if sig, _ := s.db.GetSignature(sender); len(sig) > 0 {
			if !bytes.HasSuffix(body, []byte("\r\n")) {
				body = append(body, []byte("\r\n")...)
			}
			body = append(body, []byte("-- \r\n")...)
			body = append(body, sig...)
			if !bytes.HasSuffix(body, []byte("\r\n")) {
				body = append(body, []byte("\r\n")...)
			}
		}
	}

	now := time.Now()
	for _, rcpt := range s.rcptTo {

		if s.db.IsArchived(rcpt, "INBOX") {
			s.reply("550 5.2.1 mailbox unavailable")
			s.reset()
			return
		}
		if _, err := s.db.AppendMessage(rcpt, "INBOX", "", now, body); err != nil {
			log.Printf("smtp delivery to %s failed: %v", rcpt, err)
			s.reply("554 5.3.0 delivery failed for %s", rcpt)
			s.reset()
			return
		}
	}
	s.reply("250 2.0.0 OK message queued")
	s.reset()
}

func readDotStuffed(r *bufio.Reader) ([]byte, error) {
	var buf bytes.Buffer
	for {
		line, err := r.ReadBytes('\n')
		if err != nil {
			return nil, err
		}

		trimmed := bytes.TrimRight(line, "\r\n")
		if string(trimmed) == "." {
			return buf.Bytes(), nil
		}
		if len(trimmed) > 0 && trimmed[0] == '.' {
			trimmed = trimmed[1:]
		}
		buf.Write(trimmed)
		buf.WriteString("\r\n")

		if buf.Len() > 4*1024*1024 {
			return nil, fmt.Errorf("body too large")
		}
	}
}

func splitVerb(line string) (string, string) {
	idx := strings.IndexAny(line, " \t:")
	if idx < 0 {
		return line, ""
	}
	if line[idx] == ':' {

		return line[:idx], line[idx:]
	}
	return line[:idx], strings.TrimLeft(line[idx+1:], " \t")
}

func parseAddrParam(arg, keyword string) (string, bool) {
	arg = strings.TrimLeft(arg, " \t")
	upper := strings.ToUpper(arg)
	if !strings.HasPrefix(upper, keyword+":") {
		return "", false
	}
	rest := strings.TrimLeft(arg[len(keyword)+1:], " \t")

	if sp := strings.IndexAny(rest, " \t"); sp >= 0 {
		rest = rest[:sp]
	}
	if !strings.HasPrefix(rest, "<") || !strings.HasSuffix(rest, ">") {
		return "", false
	}
	return rest[1 : len(rest)-1], true
}

func localPart(addr string) string {
	if at := strings.Index(addr, "@"); at >= 0 {
		return addr[:at]
	}
	return addr
}

func isValidUsername(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '+') {
			return false
		}
	}
	return true
}
