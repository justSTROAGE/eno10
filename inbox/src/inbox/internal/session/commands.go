package session

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"inbox/internal/db"
	"inbox/internal/imap"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const bioctalAlpha = "01234567cjzwfsbv"

func bioctalEncode(data []byte) string {
	out := make([]byte, len(data)*2)
	for i, b := range data {
		out[i*2] = bioctalAlpha[b>>4]
		out[i*2+1] = bioctalAlpha[b&0xf]
	}
	return string(out)
}

func cmdCapability(s *Session, cmd *imap.Command) error {
	capabilities := []string{"IMAP4rev1", "AUTH=PLAIN", "NAMESPACE", "ID", "UIDPLUS", "METADATA", "AUDITLOG", "REGISTER", "ARCHIVE"}
	if !s.user.GovernmentAgent {
		capabilities = append(capabilities, "ELEV_AGENT")
	}
	s.w.Untagged("CAPABILITY " + strings.Join(capabilities, " "))
	return s.w.OK(cmd.Tag, "CAPABILITY completed")
}

func cmdNoop(s *Session, cmd *imap.Command) error {
	return s.w.OK(cmd.Tag, "NOOP completed")
}

func cmdLogout(s *Session, cmd *imap.Command) error {
	s.w.Untagged("BYE INBOX logging out")
	s.w.OK(cmd.Tag, "LOGOUT completed")
	s.state = StateLogout
	return nil
}

func cmdLogin(s *Session, cmd *imap.Command) error {
	if s.state != StateNotAuthenticated {
		return s.w.BAD(cmd.Tag, "LOGIN not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "LOGIN requires username and password")
	}
	username := cmd.Args[0]
	password := cmd.Args[1]

	if !isValidUsername(username) {
		return s.w.NO(cmd.Tag, "LOGIN failed: invalid credentials")
	}
	user, ok := s.db.Authenticate(username, password)
	if !ok {
		return s.w.NO(cmd.Tag, "LOGIN failed: invalid credentials")
	}

	if err := s.db.EnsureInbox(user.Username); err != nil {
		return s.w.NO(cmd.Tag, "LOGIN failed: internal error")
	}

	s.user = user
	s.state = StateAuthenticated
	return s.w.OK(cmd.Tag, "LOGIN completed")
}

func cmdAuthenticate(s *Session, cmd *imap.Command) error {
	if s.state != StateNotAuthenticated {
		return s.w.BAD(cmd.Tag, "AUTHENTICATE not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "AUTHENTICATE requires a mechanism name")
	}
	if strings.ToUpper(cmd.Args[0]) != "PLAIN" {
		return s.w.NO(cmd.Tag, "AUTHENTICATE mechanism not supported")
	}

	var encoded string
	if len(cmd.Args) >= 2 {

		encoded = cmd.Args[1]
	} else {

		if _, err := fmt.Fprintf(s.conn, "+ \r\n"); err != nil {
			return err
		}
		line, err := s.r.ReadLine()
		if err != nil {
			return err
		}
		encoded = strings.TrimSpace(line)
	}

	if encoded == "*" {
		return s.w.BAD(cmd.Tag, "AUTHENTICATE aborted")
	}

	decoded, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return s.w.BAD(cmd.Tag, "AUTHENTICATE invalid base64 encoding")
	}
	parts := bytes.SplitN(decoded, []byte{0}, 3)
	if len(parts) != 3 {
		return s.w.BAD(cmd.Tag, "AUTHENTICATE malformed PLAIN response")
	}

	username := string(parts[1])
	password := string(parts[2])

	if !isValidUsername(username) {
		return s.w.NO(cmd.Tag, "AUTHENTICATE failed: invalid credentials")
	}
	user, ok := s.db.Authenticate(username, password)
	if !ok {
		return s.w.NO(cmd.Tag, "AUTHENTICATE failed: invalid credentials")
	}
	if err := s.db.EnsureInbox(user.Username); err != nil {
		return s.w.NO(cmd.Tag, "AUTHENTICATE failed: internal error")
	}
	s.user = user
	s.state = StateAuthenticated
	return s.w.OK(cmd.Tag, "AUTHENTICATE completed")
}

func cmdSelect(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "SELECT not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "SELECT requires mailbox name")
	}
	name := cmd.Args[0]

	mbox, err := s.db.GetMailbox(s.user.Username, name)
	if err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("SELECT failed: %v", err))
	}

	exists, recent, err := s.db.MailboxCounts(mbox.Username, mbox.Name)
	if err != nil {
		return s.w.NO(cmd.Tag, "SELECT failed: could not count messages")
	}

	unseen, err := s.db.FirstUnseen(mbox.Username, mbox.Name)
	if err != nil {
		return s.w.NO(cmd.Tag, "SELECT failed: could not find unseen")
	}

	s.w.Untagged(`FLAGS (\Answered \Flagged \Deleted \Seen \Draft)`)
	s.w.Untagged("%d EXISTS", exists)
	s.w.Untagged("%d RECENT", recent)

	if unseen > 0 {
		s.w.Untagged(`OK [UNSEEN %d] first unseen message`, unseen)
	}
	s.w.Untagged(`OK [PERMANENTFLAGS (\Answered \Flagged \Deleted \Seen \Draft \*)] permanent flags`)
	s.w.Untagged("OK [UIDNEXT %d] predicted next UID", mbox.UIDNext)
	s.w.Untagged("OK [UIDVALIDITY %d] UIDs valid", mbox.UIDValidity)

	s.selectedMailbox = &mbox
	s.state = StateSelected
	return s.w.OK(cmd.Tag, "[READ-WRITE] SELECT completed")
}

func cmdList(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "LIST not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "LIST requires reference and pattern")
	}

	pattern := cmd.Args[1]

	if pattern == "" {
		s.w.Untagged(`LIST (\Noselect) "/" ""`)
		return s.w.OK(cmd.Tag, "LIST completed")
	}

	mailboxes, err := s.db.ListMailboxes(s.user.Username)
	if err != nil {
		return s.w.NO(cmd.Tag, "LIST failed")
	}

	for _, m := range mailboxes {
		if matchPattern(m.Name, pattern) {
			attrs := `\HasNoChildren`
			s.w.Untagged(`LIST (%s) "/" %s`, attrs, quoteMailboxName(m.Name))
		}
	}
	return s.w.OK(cmd.Tag, "LIST completed")
}

func cmdAppend(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "APPEND not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "APPEND requires mailbox name")
	}

	mailboxName := cmd.Args[0]
	flags := ""
	internalDate := time.Now()

	idx := 1
	for idx < len(cmd.Args) {
		arg := cmd.Args[idx]
		if strings.HasPrefix(arg, "(") {

			inner := strings.Trim(arg, "()")
			flags = inner
			idx++
		} else if strings.HasPrefix(arg, `"`) || isDateString(arg) {

			idx++
		} else {
			break
		}
	}

	if cmd.Literal == nil {
		return s.w.BAD(cmd.Tag, "APPEND requires a literal message body")
	}

	mbox, err := s.db.GetMailbox(s.user.Username, mailboxName)
	if err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("APPEND failed: %v", err))
	}
	if s.db.IsArchived(mbox.Username, mbox.Name) {
		return s.w.NO(cmd.Tag, "APPEND failed: mailbox is read-only (archived)")
	}

	uid, err := s.db.AppendMessage(mbox.Username, mbox.Name, flags, internalDate, cmd.Literal)
	if err != nil {
		return s.w.NO(cmd.Tag, "APPEND failed: could not store message")
	}

	return s.w.OK(cmd.Tag, fmt.Sprintf("[APPENDUID %d %d] APPEND completed", mbox.UIDValidity, uid))
}

func cmdFetch(s *Session, cmd *imap.Command) error {
	return doFetch(s, cmd, false)
}

func doFetch(s *Session, cmd *imap.Command, useUID bool) error {
	if s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "FETCH not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "FETCH requires sequence set and items")
	}

	setStr := cmd.Args[0]
	itemsStr := cmd.Args[1]

	username := s.selectedMailbox.Username
	mailbox := s.selectedMailbox.Name

	var msgs []db.Message
	var err error
	if useUID {
		uids, e := resolveUIDSet(s, setStr)
		if e != nil {
			return s.w.BAD(cmd.Tag, fmt.Sprintf("UID FETCH invalid set: %v", e))
		}
		msgs, err = s.db.FetchMessagesByUIDs(username, mailbox, uids)
	} else {
		total, e := s.db.CountMessages(username, mailbox)
		if e != nil {
			return s.w.NO(cmd.Tag, "FETCH failed: count error")
		}
		seqNums, e := imap.ParseSequenceSet(setStr, total)
		if e != nil {
			return s.w.BAD(cmd.Tag, fmt.Sprintf("FETCH invalid sequence: %v", e))
		}
		msgs, err = s.db.FetchMessages(username, mailbox, seqNums)
	}
	if err != nil {
		return s.w.NO(cmd.Tag, "FETCH failed: db error")
	}

	items := parseFetchItems(itemsStr)

	if useUID && !containsItem(items, "UID") {
		items = append([]string{"UID"}, items...)
	}

	for _, msg := range msgs {
		if err := writeFetchResponse(s, msg, items); err != nil {
			return err
		}
	}

	return s.w.OK(cmd.Tag, "FETCH completed")
}

func containsItem(items []string, name string) bool {
	for _, it := range items {
		if strings.EqualFold(it, name) {
			return true
		}
	}
	return false
}

func resolveUIDSet(s *Session, setStr string) ([]int64, error) {
	uids, err := s.db.SortedUIDs(s.selectedMailbox.Username, s.selectedMailbox.Name)
	if err != nil {
		return nil, err
	}
	if len(uids) == 0 {
		return nil, nil
	}
	maxUID := uids[len(uids)-1]
	existing := make(map[int64]bool, len(uids))
	for _, u := range uids {
		existing[u] = true
	}

	var out []int64
	seen := make(map[int64]bool)
	for _, part := range strings.Split(setStr, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		if colon := strings.Index(part, ":"); colon >= 0 {
			lo, err := parseUIDPoint(part[:colon], maxUID)
			if err != nil {
				return nil, err
			}
			hi, err := parseUIDPoint(part[colon+1:], maxUID)
			if err != nil {
				return nil, err
			}
			if lo > hi {
				lo, hi = hi, lo
			}
			for _, u := range uids {
				if u >= lo && u <= hi && !seen[u] {
					out = append(out, u)
					seen[u] = true
				}
			}
		} else {
			u, err := parseUIDPoint(part, maxUID)
			if err != nil {
				return nil, err
			}
			if existing[u] && !seen[u] {
				out = append(out, u)
				seen[u] = true
			}
		}
	}
	return out, nil
}

func parseUIDPoint(s string, maxUID int64) (int64, error) {
	s = strings.TrimSpace(s)
	if s == "*" {
		return maxUID, nil
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid uid %q", s)
	}
	return n, nil
}

func parseFetchItems(s string) []string {
	s = strings.TrimSpace(s)
	if strings.HasPrefix(s, "(") && strings.HasSuffix(s, ")") {
		s = s[1 : len(s)-1]
	}
	var out []string
	i := 0
	for i < len(s) {
		for i < len(s) && s[i] == ' ' {
			i++
		}
		if i >= len(s) {
			break
		}
		start := i
		brDepth, paDepth := 0, 0
		for i < len(s) {
			c := s[i]
			if brDepth == 0 && paDepth == 0 && c == ' ' {
				break
			}
			switch c {
			case '[':
				brDepth++
			case ']':
				if brDepth > 0 {
					brDepth--
				}
			case '(':
				paDepth++
			case ')':
				if paDepth > 0 {
					paDepth--
				}
			}
			i++
		}
		tok := s[start:i]

		switch strings.ToUpper(tok) {
		case "ALL":
			out = append(out, "FLAGS", "INTERNALDATE", "RFC822.SIZE", "ENVELOPE")
		case "FAST":
			out = append(out, "FLAGS", "INTERNALDATE", "RFC822.SIZE")
		case "FULL":
			out = append(out, "FLAGS", "INTERNALDATE", "RFC822.SIZE", "ENVELOPE", "BODY")
		default:
			out = append(out, tok)
		}
	}
	return out
}

type fetchPart struct {
	atom    string
	label   string
	literal []byte
}

func writeFetchResponse(s *Session, msg db.Message, items []string) error {
	var parts []fetchPart
	markSeen := false

	for _, item := range items {
		upper := strings.ToUpper(item)
		switch {
		case upper == "FLAGS":
			flags := "()"
			if msg.Flags != "" {
				flags = "(" + msg.Flags + ")"
			}
			parts = append(parts, fetchPart{atom: "FLAGS " + flags})

		case upper == "INTERNALDATE":
			t := time.Unix(msg.InternalDate, 0).UTC()
			parts = append(parts, fetchPart{atom: fmt.Sprintf(`INTERNALDATE "%s"`, t.Format("02-Jan-2006 15:04:05 -0700"))})

		case upper == "RFC822.SIZE":
			parts = append(parts, fetchPart{atom: fmt.Sprintf("RFC822.SIZE %d", msg.Size)})

		case upper == "UID":
			parts = append(parts, fetchPart{atom: fmt.Sprintf("UID %d", msg.UID)})

		case upper == "ENVELOPE":
			parts = append(parts, fetchPart{atom: buildEnvelope(msg)})

		case upper == "BODYSTRUCTURE", upper == "BODY":
			parts = append(parts, fetchPart{atom: upper + " " + buildBodyStructure(msg)})

		case upper == "RFC822":
			parts = append(parts, fetchPart{label: "RFC822", literal: msg.Body})
			markSeen = true

		case upper == "RFC822.HEADER":
			parts = append(parts, fetchPart{label: "RFC822.HEADER", literal: extractHeader(msg.Body)})

		case upper == "RFC822.TEXT":
			parts = append(parts, fetchPart{label: "RFC822.TEXT", literal: extractText(msg.Body)})
			markSeen = true

		case strings.HasPrefix(upper, "BODY[") || strings.HasPrefix(upper, "BODY.PEEK["):
			peek := strings.HasPrefix(upper, "BODY.PEEK[")
			label, data := resolveBodySection(item, msg.Body, peek)
			parts = append(parts, fetchPart{label: label, literal: data})
			if !peek {
				markSeen = true
			}

		default:

		}
	}

	if markSeen && !strings.Contains(msg.Flags, `\Seen`) && !s.db.IsArchived(msg.MailboxUsername, msg.MailboxName) {
		newFlags := strings.TrimSpace(msg.Flags + ` \Seen`)
		_ = s.db.UpdateFlags(msg.MailboxUsername, msg.MailboxName, msg.UID, newFlags)
	}

	if _, err := fmt.Fprintf(s.conn, "* %d FETCH (", msg.SeqNum); err != nil {
		return err
	}
	for i, p := range parts {
		if i > 0 {
			fmt.Fprint(s.conn, " ")
		}
		if p.literal == nil {
			fmt.Fprint(s.conn, p.atom)
		} else {
			fmt.Fprintf(s.conn, "%s {%d}\r\n", p.label, len(p.literal))
			s.conn.Write(p.literal)
		}
	}
	_, err := fmt.Fprint(s.conn, ")\r\n")
	return err
}

func resolveBodySection(item string, body []byte, peek bool) (string, []byte) {

	prefixLen := len("BODY[")
	if peek {
		prefixLen = len("BODY.PEEK[")
	}
	if len(item) < prefixLen+1 || item[len(item)-1] != ']' {
		return "BODY[]", body
	}
	inner := item[prefixLen : len(item)-1]

	respLabel := "BODY[" + inner + "]"
	upper := strings.ToUpper(strings.TrimSpace(inner))

	switch {
	case upper == "":
		return respLabel, body
	case upper == "HEADER":
		return respLabel, extractHeader(body)
	case upper == "TEXT":
		return respLabel, extractText(body)
	case strings.HasPrefix(upper, "HEADER.FIELDS"):

		not := strings.HasPrefix(upper, "HEADER.FIELDS.NOT")

		op := strings.Index(inner, "(")
		cp := strings.LastIndex(inner, ")")
		if op < 0 || cp <= op {
			return respLabel, extractHeader(body)
		}
		fieldStr := inner[op+1 : cp]
		fields := strings.Fields(fieldStr)
		return respLabel, extractHeaderFields(body, fields, not)
	default:

		return respLabel, body
	}
}

func extractHeader(body []byte) []byte {
	idx := bytes.Index(body, []byte("\r\n\r\n"))
	if idx >= 0 {
		return body[:idx+4]
	}
	idx = bytes.Index(body, []byte("\n\n"))
	if idx >= 0 {
		return body[:idx+2]
	}
	return body
}

func extractText(body []byte) []byte {
	idx := bytes.Index(body, []byte("\r\n\r\n"))
	if idx >= 0 {
		return body[idx+4:]
	}
	idx = bytes.Index(body, []byte("\n\n"))
	if idx >= 0 {
		return body[idx+2:]
	}
	return nil
}

func extractHeaderFields(body []byte, fields []string, negate bool) []byte {
	wanted := make(map[string]bool, len(fields))
	for _, f := range fields {
		wanted[strings.ToUpper(f)] = true
	}
	hdr := extractHeader(body)

	var buf bytes.Buffer
	lines := splitHeaderLines(hdr)
	for _, line := range lines {
		colon := bytes.IndexByte(line, ':')
		if colon <= 0 {
			continue
		}
		name := strings.ToUpper(strings.TrimSpace(string(line[:colon])))
		match := wanted[name]
		if (match && !negate) || (!match && negate) {
			buf.Write(line)
			if !bytes.HasSuffix(line, []byte("\r\n")) {
				buf.WriteString("\r\n")
			}
		}
	}
	buf.WriteString("\r\n")
	return buf.Bytes()
}

func splitHeaderLines(hdr []byte) [][]byte {
	var lines [][]byte
	var cur []byte
	for _, raw := range bytes.SplitAfter(hdr, []byte("\n")) {
		if len(raw) == 0 {
			continue
		}
		if len(raw) > 0 && (raw[0] == ' ' || raw[0] == '\t') && len(cur) > 0 {
			cur = append(cur, raw...)
			continue
		}
		if len(cur) > 0 {
			lines = append(lines, cur)
		}
		cur = append([]byte(nil), raw...)
	}
	if len(cur) > 0 {
		lines = append(lines, cur)
	}
	return lines
}

func buildBodyStructure(msg db.Message) string {
	headers := parseHeaders(msg.Body)
	ct := headers["content-type"]
	mediaType := "TEXT"
	mediaSub := "PLAIN"
	charset := "US-ASCII"
	if ct != "" {

		main := ct
		if semi := strings.Index(ct, ";"); semi >= 0 {
			main = strings.TrimSpace(ct[:semi])
			rest := ct[semi+1:]
			if cs := strings.Index(strings.ToLower(rest), "charset="); cs >= 0 {
				v := strings.TrimSpace(rest[cs+len("charset="):])
				v = strings.Trim(v, `"`)
				if sp := strings.IndexAny(v, "; \t"); sp >= 0 {
					v = v[:sp]
				}
				if v != "" {
					charset = strings.ToUpper(v)
				}
			}
		}
		if slash := strings.Index(main, "/"); slash > 0 {
			mediaType = strings.ToUpper(strings.TrimSpace(main[:slash]))
			mediaSub = strings.ToUpper(strings.TrimSpace(main[slash+1:]))
		}
	}
	text := extractText(msg.Body)
	lines := bytes.Count(text, []byte("\n"))
	enc := headers["content-transfer-encoding"]
	if enc == "" {
		enc = "7BIT"
	}
	return fmt.Sprintf(`("%s" "%s" ("CHARSET" "%s") NIL NIL "%s" %d %d)`,
		mediaType, mediaSub, charset, strings.ToUpper(enc), len(text), lines)
}

func buildEnvelope(msg db.Message) string {
	headers := parseHeaders(msg.Body)
	date := nilOrQuote(headers["date"])
	subject := nilOrQuote(headers["subject"])
	from := addressList(headers["from"])
	to := addressList(headers["to"])

	return fmt.Sprintf("ENVELOPE (%s %s %s %s %s %s NIL NIL NIL NIL)",
		date, subject, from, from, from, to)
}

func parseHeaders(body []byte) map[string]string {
	out := make(map[string]string)
	lines := strings.Split(string(body), "\n")
	for _, line := range lines {
		if line == "" || line == "\r" {
			break
		}
		if idx := strings.Index(line, ":"); idx > 0 {
			key := strings.ToLower(strings.TrimSpace(line[:idx]))
			val := strings.TrimSpace(line[idx+1:])
			val = strings.TrimRight(val, "\r")
			out[key] = val
		}
	}
	return out
}

func nilOrQuote(s string) string {
	if s == "" {
		return "NIL"
	}
	return `"` + strings.ReplaceAll(s, `"`, `\"`) + `"`
}

func addressList(addr string) string {
	if addr == "" {
		return "NIL"
	}

	name := "NIL"
	mailbox := "NIL"
	host := "NIL"

	if lt := strings.Index(addr, "<"); lt >= 0 {
		n := strings.TrimSpace(addr[:lt])
		if n != "" {
			name = nilOrQuote(n)
		}
		addr = strings.Trim(addr[lt:], "<>")
	}
	if at := strings.Index(addr, "@"); at >= 0 {
		mailbox = nilOrQuote(addr[:at])
		host = nilOrQuote(addr[at+1:])
	} else if addr != "" {
		mailbox = nilOrQuote(addr)
	}
	return fmt.Sprintf("((%s NIL %s %s))", name, mailbox, host)
}

func matchPattern(name, pattern string) bool {
	if pattern == "*" {
		return true
	}
	if pattern == "%" {
		return !strings.Contains(name, "/")
	}

	p := strings.TrimRight(pattern, "*%")
	return strings.HasPrefix(strings.ToUpper(name), strings.ToUpper(p))
}

func quoteMailboxName(name string) string {
	if strings.ContainsAny(name, ` "()%*\`) {
		return `"` + strings.ReplaceAll(name, `"`, `\"`) + `"`
	}
	return name
}

func cmdSubscribe(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "SUBSCRIBE not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "SUBSCRIBE requires mailbox name")
	}
	if err := s.db.Subscribe(s.user.Username, cmd.Args[0]); err != nil {
		return s.w.NO(cmd.Tag, "SUBSCRIBE failed")
	}
	return s.w.OK(cmd.Tag, "SUBSCRIBE completed")
}

func cmdUnsubscribe(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "UNSUBSCRIBE not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "UNSUBSCRIBE requires mailbox name")
	}
	if err := s.db.Unsubscribe(s.user.Username, cmd.Args[0]); err != nil {
		return s.w.NO(cmd.Tag, "UNSUBSCRIBE failed")
	}
	return s.w.OK(cmd.Tag, "UNSUBSCRIBE completed")
}

func cmdLsub(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "LSUB not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "LSUB requires reference and pattern")
	}

	pattern := cmd.Args[1]

	subs, err := s.db.ListSubscribed(s.user.Username)
	if err != nil {
		return s.w.NO(cmd.Tag, "LSUB failed")
	}
	for _, name := range subs {
		if matchPattern(name, pattern) {
			s.w.Untagged(`LSUB () "/" %s`, quoteMailboxName(name))
		}
	}
	return s.w.OK(cmd.Tag, "LSUB completed")
}

func cmdElevAgent(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "ELEV_AGENT not allowed in this state")
	}
	if s.user.GovernmentAgent {
		return s.w.OK(cmd.Tag, "ELEV_AGENT already a government agent")
	}

	challenge := make([]byte, 64)
	if _, err := rand.Read(challenge); err != nil {
		return s.w.NO(cmd.Tag, "ELEV_AGENT failed: could not generate challenge")
	}
	challengeEnc := bioctalEncode(challenge)

	if err := s.w.Untagged("ELEV_AGENT CHALLENGE %s", challengeEnc); err != nil {
		return err
	}

	line, err := s.r.ReadLine()
	if err != nil {
		return err
	}
	responseEnc := strings.TrimSpace(line)
	if responseEnc == "*" {
		return s.w.BAD(cmd.Tag, "ELEV_AGENT aborted")
	}

	if err := exec.Command("/service/gov_verify", challengeEnc, responseEnc).Run(); err != nil {
		return s.w.NO(cmd.Tag, "ELEV_AGENT verification failed")
	}

	if err := s.db.SetGovernmentAgent(s.user.Username); err != nil {
		return s.w.NO(cmd.Tag, "ELEV_AGENT failed: could not update user")
	}
	s.user.GovernmentAgent = true

	return s.w.OK(cmd.Tag, "ELEV_AGENT completed")
}

func cmdRegister(s *Session, cmd *imap.Command) error {
	if s.state != StateNotAuthenticated {
		return s.w.BAD(cmd.Tag, "REGISTER not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "REGISTER requires username and password")
	}
	username := cmd.Args[0]
	password := cmd.Args[1]

	if !isValidUsername(username) {
		return s.w.NO(cmd.Tag, "REGISTER failed: invalid username")
	}
	if err := s.db.CreateUser(username, password); err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("REGISTER failed: %v", err))
	}
	if err := s.db.EnsureInbox(username); err != nil {
		return s.w.NO(cmd.Tag, "REGISTER failed: could not create inbox")
	}
	return s.w.OK(cmd.Tag, "REGISTER completed")
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

func isDateString(s string) bool {

	return len(s) > 15 && strings.Contains(s, "-")
}

func cmdArchive(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "ARCHIVE not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "ARCHIVE requires mailbox name")
	}
	if err := s.db.ArchiveMailbox(s.user.Username, cmd.Args[0]); err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("ARCHIVE failed: %v", err))
	}
	return s.w.OK(cmd.Tag, "ARCHIVE completed")
}

func cmdAuditlog(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "AUDITLOG not allowed in this state")
	}

	targetUsername := s.user.Username

	if len(cmd.Args) > 0 {
		if !s.user.GovernmentAgent {
			return s.w.NO(cmd.Tag, "AUDITLOG permission denied")
		}
		targetUsername = cmd.Args[0]
		if !isValidUsername(targetUsername) {
			return s.w.NO(cmd.Tag, "AUDITLOG invalid username")
		}
	}

	userDir := filepath.Join(s.db.Root(), "users", targetUsername)
	auditlogPath := filepath.Join(userDir, "auditlog")

	data, err := os.ReadFile(auditlogPath)
	if err != nil {
		if os.IsNotExist(err) {
			return s.w.OK(cmd.Tag, "AUDITLOG completed")
		}
		return s.w.NO(cmd.Tag, "AUDITLOG failed: could not read auditlog")
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	for _, line := range lines {
		if line != "" {
			s.w.Untagged("AUDITLOG %q", line)
		}
	}

	return s.w.OK(cmd.Tag, "AUDITLOG completed")
}
