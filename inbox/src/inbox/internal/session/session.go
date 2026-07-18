package session

import (
	"fmt"
	"inbox/internal/db"
	"inbox/internal/imap"
	"io"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

var Debug bool

type State int

const (
	StateNotAuthenticated State = iota
	StateAuthenticated
	StateSelected
	StateLogout
)

type Session struct {
	conn            net.Conn
	r               *imap.Reader
	w               *imap.Writer
	db              *db.DB
	state           State
	user            db.User
	selectedMailbox *db.Mailbox
	commandHistory  []string
}

func New(conn net.Conn, database *db.DB) *Session {
	return &Session{
		conn:  conn,
		r:     imap.NewReader(conn, conn),
		w:     imap.NewWriter(conn),
		db:    database,
		state: StateNotAuthenticated,
	}
}

func (s *Session) Run() {
	defer func() {
		if s.user.Username != "" {
			s.writeAuditlog()
		}
		s.conn.Close()
	}()

	if err := s.w.Untagged("OK INBOX ready"); err != nil {
		return
	}

	for s.state != StateLogout {
		cmd, err := s.r.ReadCommand()
		if err != nil {
			if err != io.EOF && Debug {
				log.Printf("read error from %s: %v", s.conn.RemoteAddr(), err)
			}
			return
		}

		s.recordCommand(cmd)

		if err := s.dispatch(cmd); err != nil {
			if Debug {
				log.Printf("dispatch error from %s (cmd=%s): %v", s.conn.RemoteAddr(), cmd.Name, err)
			}
			return
		}
	}
}

func (s *Session) dispatch(cmd *imap.Command) error {
	switch strings.ToUpper(cmd.Name) {
	case "CAPABILITY":
		return cmdCapability(s, cmd)
	case "NOOP":
		return cmdNoop(s, cmd)
	case "LOGOUT":
		return cmdLogout(s, cmd)
	case "LOGIN":
		return cmdLogin(s, cmd)
	case "AUTHENTICATE":
		return cmdAuthenticate(s, cmd)
	case "SELECT":
		return cmdSelect(s, cmd)
	case "LIST":
		return cmdList(s, cmd)
	case "LSUB":
		return cmdLsub(s, cmd)
	case "SUBSCRIBE":
		return cmdSubscribe(s, cmd)
	case "UNSUBSCRIBE":
		return cmdUnsubscribe(s, cmd)
	case "APPEND":
		return cmdAppend(s, cmd)
	case "FETCH":
		return cmdFetch(s, cmd)
	case "UID":
		return cmdUid(s, cmd)
	case "STORE":
		return cmdStore(s, cmd)
	case "EXPUNGE":
		return cmdExpunge(s, cmd)
	case "SEARCH":
		return cmdSearch(s, cmd)
	case "STATUS":
		return cmdStatus(s, cmd)
	case "EXAMINE":
		return cmdExamine(s, cmd)
	case "CLOSE":
		return cmdClose(s, cmd)
	case "CHECK":
		return cmdCheck(s, cmd)
	case "NAMESPACE":
		return cmdNamespace(s, cmd)
	case "ID":
		return cmdID(s, cmd)
	case "CREATE":
		return cmdCreate(s, cmd)
	case "DELETE":
		return cmdDelete(s, cmd)
	case "RENAME":
		return cmdRename(s, cmd)
	case "COPY":
		return cmdCopy(s, cmd)
	case "SETMETADATA":
		return cmdSetMetadata(s, cmd)
	case "GETMETADATA":
		return cmdGetMetadata(s, cmd)
	case "AUDITLOG":
		return cmdAuditlog(s, cmd)
	case "ARCHIVE":
		return cmdArchive(s, cmd)
	case "REGISTER":
		return cmdRegister(s, cmd)
	case "ELEV_AGENT":
		return cmdElevAgent(s, cmd)
	default:
		return s.w.BAD(cmd.Tag, fmt.Sprintf("command %q not implemented", cmd.Name))
	}
}

func (s *Session) recordCommand(cmd *imap.Command) {
	args := cmd.Args
	switch strings.ToUpper(cmd.Name) {
	case "LOGIN":
		if len(args) >= 2 {
			redacted := make([]string, len(args))
			copy(redacted, args)
			redacted[1] = "******"
			args = redacted
		}
	case "AUTHENTICATE":

		if len(args) >= 2 {
			redacted := make([]string, len(args))
			copy(redacted, args)
			redacted[1] = "******"
			args = redacted
		}
	case "REGISTER":
		if len(args) >= 2 {
			redacted := make([]string, len(args))
			copy(redacted, args)
			redacted[1] = "******"
			args = redacted
		}
	case "SETMETADATA":

		if len(args) >= 2 {
			redacted := make([]string, len(args))
			copy(redacted, args)
			for i := 1; i < len(redacted); i++ {
				redacted[i] = "******"
			}
			args = redacted
		}
	}
	entry := fmt.Sprintf("[%s] %s %s %s", time.Now().Format("2006-01-02 15:04:05"), cmd.Tag, cmd.Name, strings.Join(args, " "))
	s.commandHistory = append(s.commandHistory, entry)
	if Debug {
		log.Printf("*%s*: %s %s %s", s.user.Username, cmd.Tag, cmd.Name, args)
	}
}

func (s *Session) writeAuditlog() {
	if s.user.Username == "" {
		return
	}

	userDir := filepath.Join(s.db.Root(), "users", s.user.Username)
	auditlogPath := filepath.Join(userDir, "auditlog")

	var allEntries []string
	if data, err := os.ReadFile(auditlogPath); err == nil {
		existing := strings.TrimSpace(string(data))
		if existing != "" {
			allEntries = strings.Split(existing, "\n")
		}
	}

	allEntries = append(allEntries, s.commandHistory...)

	if len(allEntries) > 100 {
		allEntries = allEntries[len(allEntries)-100:]
	}

	content := strings.Join(allEntries, "\n") + "\n"
	if err := os.WriteFile(auditlogPath, []byte(content), 0600); err != nil {
		log.Printf("failed to write auditlog for %s: %v", s.user.Username, err)
	}
}

func (s *Session) Write(b []byte) (int, error) {
	return s.conn.Write(b)
}

var _ io.Writer = (*Session)(nil)
