package session

import (
	"fmt"
	"inbox/internal/db"
	"inbox/internal/imap"
	"sort"
	"strconv"
	"strings"
	"time"
)

func cmdUid(s *Session, cmd *imap.Command) error {
	if s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "UID not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "UID requires a subcommand")
	}
	sub := strings.ToUpper(cmd.Args[0])

	inner := &imap.Command{
		Tag:     cmd.Tag,
		Name:    sub,
		Args:    cmd.Args[1:],
		Literal: cmd.Literal,
	}
	switch sub {
	case "FETCH":
		return doFetch(s, inner, true)
	case "STORE":
		return doStore(s, inner, true)
	case "SEARCH":
		return doSearch(s, inner, true)
	case "COPY":
		return doCopy(s, inner, true)
	case "EXPUNGE":
		return cmdExpunge(s, inner)
	default:
		return s.w.BAD(cmd.Tag, fmt.Sprintf("UID %s not supported", sub))
	}
}

func cmdStore(s *Session, cmd *imap.Command) error { return doStore(s, cmd, false) }

func doStore(s *Session, cmd *imap.Command, useUID bool) error {
	if s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "STORE not allowed in this state")
	}
	if len(cmd.Args) < 3 {
		return s.w.BAD(cmd.Tag, "STORE requires sequence, item and flags")
	}
	setStr := cmd.Args[0]
	itemName := strings.ToUpper(cmd.Args[1])
	flagsArg := cmd.Args[2]

	silent := strings.HasSuffix(itemName, ".SILENT")
	op := strings.TrimSuffix(itemName, ".SILENT")

	var mode int
	switch op {
	case "FLAGS":
		mode = 0
	case "+FLAGS":
		mode = 1
	case "-FLAGS":
		mode = -1
	default:
		return s.w.BAD(cmd.Tag, fmt.Sprintf("STORE unknown item %q", cmd.Args[1]))
	}

	newFlags := strings.Fields(strings.Trim(flagsArg, "()"))

	mailbox := s.selectedMailbox
	username := mailbox.Username

	if s.db.IsArchived(username, mailbox.Name) {
		return s.w.NO(cmd.Tag, "STORE failed: mailbox is read-only (archived)")
	}

	var uids []int64
	var seqOf map[int64]int64
	if useUID {
		set, err := resolveUIDSet(s, setStr)
		if err != nil {
			return s.w.BAD(cmd.Tag, fmt.Sprintf("UID STORE invalid set: %v", err))
		}
		uids = set
		all, _ := s.db.SortedUIDs(username, mailbox.Name)
		seqOf = make(map[int64]int64, len(all))
		for i, u := range all {
			seqOf[u] = int64(i) + 1
		}
	} else {
		total, _ := s.db.CountMessages(username, mailbox.Name)
		seqs, err := imap.ParseSequenceSet(setStr, total)
		if err != nil {
			return s.w.BAD(cmd.Tag, fmt.Sprintf("STORE invalid sequence: %v", err))
		}
		uids, _ = s.db.SeqToUID(username, mailbox.Name, seqs)
		all, _ := s.db.SortedUIDs(username, mailbox.Name)
		seqOf = make(map[int64]int64, len(all))
		for i, u := range all {
			seqOf[u] = int64(i) + 1
		}
	}

	for _, uid := range uids {
		cur, err := s.db.GetFlags(username, mailbox.Name, uid)
		if err != nil {
			continue
		}
		curSet := flagSet(cur)
		switch mode {
		case 0:
			curSet = map[string]bool{}
			for _, f := range newFlags {
				curSet[f] = true
			}
		case 1:
			for _, f := range newFlags {
				curSet[f] = true
			}
		case -1:
			for _, f := range newFlags {
				delete(curSet, f)
			}
		}
		final := flagsString(curSet)
		_ = s.db.UpdateFlags(username, mailbox.Name, uid, final)
		if !silent {
			extra := ""
			if useUID {
				extra = fmt.Sprintf(" UID %d", uid)
			}
			s.w.Untagged("%d FETCH (FLAGS (%s)%s)", seqOf[uid], final, extra)
		}
	}

	return s.w.OK(cmd.Tag, "STORE completed")
}

func flagSet(s string) map[string]bool {
	out := map[string]bool{}
	for _, f := range strings.Fields(s) {
		out[f] = true
	}
	return out
}

func flagsString(m map[string]bool) string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return strings.Join(keys, " ")
}

func cmdExpunge(s *Session, cmd *imap.Command) error {
	if s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "EXPUNGE not allowed in this state")
	}
	mb := s.selectedMailbox
	if s.db.IsArchived(mb.Username, mb.Name) {
		return s.w.NO(cmd.Tag, "EXPUNGE failed: mailbox is read-only (archived)")
	}
	seqs, err := s.db.ExpungeDeleted(mb.Username, mb.Name)
	if err != nil {
		return s.w.NO(cmd.Tag, "EXPUNGE failed")
	}

	for i := len(seqs) - 1; i >= 0; i-- {
		s.w.Untagged("%d EXPUNGE", seqs[i])
	}
	return s.w.OK(cmd.Tag, "EXPUNGE completed")
}

func cmdSearch(s *Session, cmd *imap.Command) error { return doSearch(s, cmd, false) }

func doSearch(s *Session, cmd *imap.Command, useUID bool) error {
	if s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "SEARCH not allowed in this state")
	}
	mb := s.selectedMailbox

	args := cmd.Args
	if len(args) >= 2 && strings.EqualFold(args[0], "CHARSET") {
		args = args[2:]
	}
	if len(args) == 0 {
		args = []string{"ALL"}
	}

	uids, err := s.db.SortedUIDs(mb.Username, mb.Name)
	if err != nil {
		return s.w.NO(cmd.Tag, "SEARCH failed")
	}
	msgs, _ := s.db.FetchMessagesByUIDs(mb.Username, mb.Name, uids)

	matched := make([]bool, len(msgs))
	for i := range matched {
		matched[i] = true
	}

	i := 0
	for i < len(args) {
		key := strings.ToUpper(args[i])
		switch key {
		case "ALL":
			i++
		case "ANSWERED", "FLAGGED", "DELETED", "DRAFT", "SEEN", "RECENT":
			flag := `\` + strings.Title(strings.ToLower(key))
			applyFlagFilter(matched, msgs, flag, true)
			i++
		case "UNANSWERED", "UNFLAGGED", "UNDELETED", "UNDRAFT", "UNSEEN":
			flag := `\` + strings.Title(strings.ToLower(key[2:]))
			applyFlagFilter(matched, msgs, flag, false)
			i++
		case "NEW":
			applyFlagFilter(matched, msgs, `\Recent`, true)
			applyFlagFilter(matched, msgs, `\Seen`, false)
			i++
		case "OLD":
			applyFlagFilter(matched, msgs, `\Recent`, false)
			i++
		case "KEYWORD":
			if i+1 >= len(args) {
				return s.w.BAD(cmd.Tag, "SEARCH KEYWORD requires a flag")
			}
			applyFlagFilter(matched, msgs, args[i+1], true)
			i += 2
		case "UNKEYWORD":
			if i+1 >= len(args) {
				return s.w.BAD(cmd.Tag, "SEARCH UNKEYWORD requires a flag")
			}
			applyFlagFilter(matched, msgs, args[i+1], false)
			i += 2
		case "UID":
			if i+1 >= len(args) {
				return s.w.BAD(cmd.Tag, "SEARCH UID requires a set")
			}
			set, err := resolveUIDSet(s, args[i+1])
			if err != nil {
				return s.w.BAD(cmd.Tag, fmt.Sprintf("SEARCH invalid uid set: %v", err))
			}
			want := make(map[int64]bool, len(set))
			for _, u := range set {
				want[u] = true
			}
			for j, m := range msgs {
				if !want[m.UID] {
					matched[j] = false
				}
			}
			i += 2
		case "NOT":

			i += 2
		case "OR":

			i += 3
		case "HEADER":
			if i+2 >= len(args) {
				return s.w.BAD(cmd.Tag, "SEARCH HEADER requires name and value")
			}
			name := strings.ToLower(args[i+1])
			value := strings.ToLower(strings.Trim(args[i+2], `"`))
			for j, m := range msgs {
				h := parseHeaders(m.Body)
				if !strings.Contains(strings.ToLower(h[name]), value) {
					matched[j] = false
				}
			}
			i += 3
		case "SUBJECT", "FROM", "TO", "CC", "BCC":
			if i+1 >= len(args) {
				return s.w.BAD(cmd.Tag, "SEARCH "+key+" requires a value")
			}
			value := strings.ToLower(strings.Trim(args[i+1], `"`))
			fieldName := strings.ToLower(key)
			for j, m := range msgs {
				h := parseHeaders(m.Body)
				if !strings.Contains(strings.ToLower(h[fieldName]), value) {
					matched[j] = false
				}
			}
			i += 2
		case "BODY", "TEXT":
			if i+1 >= len(args) {
				return s.w.BAD(cmd.Tag, "SEARCH "+key+" requires a value")
			}
			value := strings.ToLower(strings.Trim(args[i+1], `"`))
			for j, m := range msgs {
				if !strings.Contains(strings.ToLower(string(m.Body)), value) {
					matched[j] = false
				}
			}
			i += 2
		case "LARGER":
			if i+1 >= len(args) {
				return s.w.BAD(cmd.Tag, "SEARCH LARGER requires a number")
			}
			n, _ := strconv.ParseInt(args[i+1], 10, 64)
			for j, m := range msgs {
				if m.Size <= n {
					matched[j] = false
				}
			}
			i += 2
		case "SMALLER":
			if i+1 >= len(args) {
				return s.w.BAD(cmd.Tag, "SEARCH SMALLER requires a number")
			}
			n, _ := strconv.ParseInt(args[i+1], 10, 64)
			for j, m := range msgs {
				if m.Size >= n {
					matched[j] = false
				}
			}
			i += 2
		case "SINCE", "BEFORE", "ON", "SENTSINCE", "SENTBEFORE", "SENTON":

			i += 2
		default:

			if looksLikeSequence(args[i]) {
				total := int64(len(msgs))
				seqs, err := imap.ParseSequenceSet(args[i], total)
				if err == nil {
					want := make(map[int64]bool, len(seqs))
					for _, n := range seqs {
						want[n] = true
					}
					for j := range msgs {
						if !want[int64(j)+1] {
							matched[j] = false
						}
					}
				}
				i++
				continue
			}

			i++
		}
	}

	var hits []string
	for j, ok := range matched {
		if !ok {
			continue
		}
		if useUID {
			hits = append(hits, strconv.FormatInt(msgs[j].UID, 10))
		} else {
			hits = append(hits, strconv.FormatInt(int64(j)+1, 10))
		}
	}
	if len(hits) == 0 {
		s.w.Untagged("SEARCH")
	} else {
		s.w.Untagged("SEARCH " + strings.Join(hits, " "))
	}
	return s.w.OK(cmd.Tag, "SEARCH completed")
}

func applyFlagFilter(matched []bool, msgs []db.Message, flag string, want bool) {
	for j, m := range msgs {
		has := false
		for _, f := range strings.Fields(m.Flags) {
			if strings.EqualFold(f, flag) {
				has = true
				break
			}
		}
		if has != want {
			matched[j] = false
		}
	}
}

func looksLikeSequence(s string) bool {
	for _, c := range s {
		if !((c >= '0' && c <= '9') || c == ':' || c == ',' || c == '*') {
			return false
		}
	}
	return s != ""
}

func cmdStatus(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "STATUS not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "STATUS requires mailbox and items")
	}
	name := cmd.Args[0]
	items := strings.Fields(strings.Trim(cmd.Args[1], "()"))

	if _, err := s.db.GetMailbox(s.user.Username, name); err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("STATUS failed: %v", err))
	}
	exists, recent, unseen, uidnext, uidvalidity, err := s.db.MailboxStatus(s.user.Username, name)
	if err != nil {
		return s.w.NO(cmd.Tag, "STATUS failed")
	}

	var out []string
	for _, it := range items {
		switch strings.ToUpper(it) {
		case "MESSAGES":
			out = append(out, fmt.Sprintf("MESSAGES %d", exists))
		case "RECENT":
			out = append(out, fmt.Sprintf("RECENT %d", recent))
		case "UIDNEXT":
			out = append(out, fmt.Sprintf("UIDNEXT %d", uidnext))
		case "UIDVALIDITY":
			out = append(out, fmt.Sprintf("UIDVALIDITY %d", uidvalidity))
		case "UNSEEN":
			out = append(out, fmt.Sprintf("UNSEEN %d", unseen))
		}
	}
	s.w.Untagged(`STATUS %s (%s)`, quoteMailboxName(name), strings.Join(out, " "))
	return s.w.OK(cmd.Tag, "STATUS completed")
}

func cmdExamine(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "EXAMINE not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "EXAMINE requires mailbox name")
	}
	name := cmd.Args[0]
	mbox, err := s.db.GetMailbox(s.user.Username, name)
	if err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("EXAMINE failed: %v", err))
	}
	exists, recent, _ := s.db.MailboxCounts(mbox.Username, mbox.Name)
	unseen, _ := s.db.FirstUnseen(mbox.Username, mbox.Name)
	s.w.Untagged(`FLAGS (\Answered \Flagged \Deleted \Seen \Draft)`)
	s.w.Untagged("%d EXISTS", exists)
	s.w.Untagged("%d RECENT", recent)
	if unseen > 0 {
		s.w.Untagged(`OK [UNSEEN %d] first unseen message`, unseen)
	}
	s.w.Untagged(`OK [PERMANENTFLAGS ()] no permanent flags permitted`)
	s.w.Untagged("OK [UIDNEXT %d] predicted next UID", mbox.UIDNext)
	s.w.Untagged("OK [UIDVALIDITY %d] UIDs valid", mbox.UIDValidity)
	s.selectedMailbox = &mbox
	s.state = StateSelected
	return s.w.OK(cmd.Tag, "[READ-ONLY] EXAMINE completed")
}

func cmdClose(s *Session, cmd *imap.Command) error {
	if s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "CLOSE not allowed in this state")
	}
	mb := s.selectedMailbox

	if !s.db.IsArchived(mb.Username, mb.Name) {
		_, _ = s.db.ExpungeDeleted(mb.Username, mb.Name)
	}
	s.selectedMailbox = nil
	s.state = StateAuthenticated
	return s.w.OK(cmd.Tag, "CLOSE completed")
}

func cmdCheck(s *Session, cmd *imap.Command) error {
	if s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "CHECK not allowed in this state")
	}
	return s.w.OK(cmd.Tag, "CHECK completed")
}

func cmdNamespace(s *Session, cmd *imap.Command) error {
	s.w.Untagged(`NAMESPACE (("" "/")) NIL NIL`)
	return s.w.OK(cmd.Tag, "NAMESPACE completed")
}

func cmdID(s *Session, cmd *imap.Command) error {
	s.w.Untagged(`ID NIL`)
	return s.w.OK(cmd.Tag, "ID completed")
}

func cmdCreate(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "CREATE not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "CREATE requires mailbox name")
	}
	name := strings.TrimRight(cmd.Args[0], "/")
	if err := s.db.CreateMailbox(s.user.Username, name); err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("CREATE failed: %v", err))
	}
	return s.w.OK(cmd.Tag, "CREATE completed")
}

func cmdDelete(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "DELETE not allowed in this state")
	}
	if len(cmd.Args) < 1 {
		return s.w.BAD(cmd.Tag, "DELETE requires mailbox name")
	}
	if err := s.db.DeleteMailbox(s.user.Username, cmd.Args[0]); err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("DELETE failed: %v", err))
	}
	return s.w.OK(cmd.Tag, "DELETE completed")
}

func cmdRename(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "RENAME not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "RENAME requires source and destination")
	}
	if err := s.db.RenameMailbox(s.user.Username, cmd.Args[0], cmd.Args[1]); err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("RENAME failed: %v", err))
	}
	return s.w.OK(cmd.Tag, "RENAME completed")
}

func cmdCopy(s *Session, cmd *imap.Command) error { return doCopy(s, cmd, false) }

const metadataFooterKey = "/private/footer"

func cmdSetMetadata(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "SETMETADATA not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "SETMETADATA requires mailbox and entry list")
	}
	if cmd.Args[0] != "" {
		return s.w.NO(cmd.Tag, "SETMETADATA: only server-scope metadata is supported")
	}
	inner := strings.TrimSpace(cmd.Args[1])
	if !strings.HasPrefix(inner, "(") || !strings.HasSuffix(inner, ")") {
		return s.w.BAD(cmd.Tag, "SETMETADATA expects parenthesised (entry value …) list")
	}
	tokens := tokenizeMetadata(inner[1 : len(inner)-1])
	if len(tokens)%2 != 0 {
		return s.w.BAD(cmd.Tag, "SETMETADATA entry/value count mismatch")
	}
	for i := 0; i < len(tokens); i += 2 {
		key := tokens[i]
		val := tokens[i+1]
		if !strings.EqualFold(key, metadataFooterKey) {

			continue
		}
		if strings.EqualFold(val, "NIL") {

			if err := s.db.SetSignature(s.user.Username, nil); err != nil {
				return s.w.NO(cmd.Tag, "SETMETADATA failed: "+err.Error())
			}
			continue
		}
		if err := s.db.SetSignature(s.user.Username, []byte(val)); err != nil {
			return s.w.NO(cmd.Tag, "SETMETADATA failed: "+err.Error())
		}
	}
	return s.w.OK(cmd.Tag, "SETMETADATA completed")
}

func cmdGetMetadata(s *Session, cmd *imap.Command) error {
	if s.state != StateAuthenticated && s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "GETMETADATA not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "GETMETADATA requires mailbox and entry/list")
	}
	if cmd.Args[0] != "" {
		return s.w.NO(cmd.Tag, "GETMETADATA: only server-scope metadata is supported")
	}

	raw := strings.TrimSpace(cmd.Args[1])
	var keys []string
	if strings.HasPrefix(raw, "(") && strings.HasSuffix(raw, ")") {
		keys = tokenizeMetadata(raw[1 : len(raw)-1])
	} else {
		keys = []string{raw}
	}
	var pairs []string
	for _, k := range keys {
		if !strings.EqualFold(k, metadataFooterKey) {
			pairs = append(pairs, k+" NIL")
			continue
		}
		val, err := s.db.GetSignature(s.user.Username)
		if err != nil || len(val) == 0 {
			pairs = append(pairs, k+" NIL")
			continue
		}
		pairs = append(pairs, k+" "+quoteMetadataValue(string(val)))
	}
	s.w.Untagged(`METADATA "" (%s)`, strings.Join(pairs, " "))
	return s.w.OK(cmd.Tag, "GETMETADATA completed")
}

func tokenizeMetadata(s string) []string {
	var out []string
	i := 0
	for i < len(s) {
		for i < len(s) && s[i] == ' ' {
			i++
		}
		if i >= len(s) {
			break
		}
		if s[i] == '"' {
			i++
			start := i
			for i < len(s) && s[i] != '"' {
				i++
			}
			out = append(out, s[start:i])
			if i < len(s) {
				i++
			}
		} else {
			start := i
			for i < len(s) && s[i] != ' ' {
				i++
			}
			out = append(out, s[start:i])
		}
	}
	return out
}

func quoteMetadataValue(v string) string {

	v = strings.ReplaceAll(v, `\`, `\\`)
	v = strings.ReplaceAll(v, `"`, `\"`)
	return `"` + v + `"`
}

func doCopy(s *Session, cmd *imap.Command, useUID bool) error {
	if s.state != StateSelected {
		return s.w.BAD(cmd.Tag, "COPY not allowed in this state")
	}
	if len(cmd.Args) < 2 {
		return s.w.BAD(cmd.Tag, "COPY requires set and destination")
	}
	setStr := cmd.Args[0]
	dst := cmd.Args[1]

	mb := s.selectedMailbox

	dstMbox, err := s.db.GetMailbox(s.user.Username, dst)
	if err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("[TRYCREATE] COPY failed: %v", err))
	}
	if s.db.IsArchived(dstMbox.Username, dstMbox.Name) {
		return s.w.NO(cmd.Tag, "COPY failed: destination is read-only (archived)")
	}

	var srcUIDs []int64
	if useUID {
		srcUIDs, err = resolveUIDSet(s, setStr)
	} else {
		total, _ := s.db.CountMessages(mb.Username, mb.Name)
		seqs, e := imap.ParseSequenceSet(setStr, total)
		if e != nil {
			return s.w.BAD(cmd.Tag, fmt.Sprintf("COPY invalid sequence: %v", e))
		}
		srcUIDs, err = s.db.SeqToUID(mb.Username, mb.Name, seqs)
	}
	if err != nil {
		return s.w.NO(cmd.Tag, fmt.Sprintf("COPY failed: %v", err))
	}

	var sourceUIDs, destUIDs []string
	for _, uid := range srcUIDs {
		newUID, err := s.db.CopyMessage(mb.Username, mb.Name, uid, dst)
		if err != nil {
			continue
		}
		sourceUIDs = append(sourceUIDs, strconv.FormatInt(uid, 10))
		destUIDs = append(destUIDs, strconv.FormatInt(newUID, 10))
	}
	_ = time.Now
	if len(destUIDs) > 0 {
		return s.w.OK(cmd.Tag, fmt.Sprintf("[COPYUID %d %s %s] COPY completed",
			dstMbox.UIDValidity, strings.Join(sourceUIDs, ","), strings.Join(destUIDs, ",")))
	}
	return s.w.OK(cmd.Tag, "COPY completed")
}
