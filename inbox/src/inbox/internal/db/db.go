package db

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type DB struct {
	root string
}

func Open(root string) (*DB, error) {
	if err := os.MkdirAll(filepath.Join(root, "users"), 0700); err != nil {
		return nil, err
	}
	return &DB{root: root}, nil
}

func (d *DB) Close() error { return nil }

func (d *DB) Root() string { return d.root }

func (d *DB) userDir(username string) string {
	return filepath.Join(d.root, "users", username)
}

func (d *DB) mailboxDir(username, mailbox string) string {
	return filepath.Join(d.userDir(username), mailbox)
}

func (d *DB) emlPath(username, mailbox string, uid int64) string {
	return filepath.Join(d.mailboxDir(username, mailbox), fmt.Sprintf("%d.eml", uid))
}

func (d *DB) metaPath(username, mailbox string, uid int64) string {
	return filepath.Join(d.mailboxDir(username, mailbox), fmt.Sprintf("%d.meta", uid))
}

func (d *DB) subscriptionsPath(username string) string {
	return filepath.Join(d.userDir(username), "subscriptions")
}

func hashPassword(pw string) string {
	h := sha256.Sum256([]byte(pw))
	return fmt.Sprintf("%x", h)
}

type User struct {
	Username        string
	GovernmentAgent bool
}

type Mailbox struct {
	Username    string
	Name        string
	UIDValidity int64
	UIDNext     int64
	Subscribed  bool
}

type Message struct {
	MailboxUsername string
	MailboxName     string
	UID             int64
	Flags           string
	InternalDate    int64
	Body            []byte
	Size            int64
	SeqNum          int64
}

func (d *DB) Authenticate(username, password string) (User, bool) {
	p := filepath.Join(d.userDir(username), "password")
	data, err := os.ReadFile(p)
	if err != nil {
		return User{}, false
	}
	stored := strings.TrimSpace(string(data))
	if stored != hashPassword(password) {
		return User{}, false
	}
	m := filepath.Join(d.userDir(username), "meta")

	agent := false
	if data, err := os.ReadFile(m); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			if after, ok := strings.CutPrefix(line, "agent: "); ok {
				agentVal := strings.TrimSpace(after)
				if agentVal == "true" {
					agent = true
				}
			}
		}
	}

	return User{Username: username, GovernmentAgent: agent}, true
}

func readInt64File(path string) (int64, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	return strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
}

func writeAtomic(path string, data []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func writeInt64File(path string, n int64) error {
	return writeAtomic(path, []byte(strconv.FormatInt(n, 10)+"\n"))
}

func (d *DB) EnsureInbox(username string) error {
	if err := d.ensureMailbox(username, "INBOX"); err != nil {
		return err
	}

	return d.Subscribe(username, "INBOX")
}

func (d *DB) readSubscriptions(username string) ([]string, error) {
	data, err := os.ReadFile(d.subscriptionsPath(username))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	var out []string
	for _, line := range strings.Split(strings.TrimSpace(string(data)), "\n") {
		if line != "" {
			out = append(out, line)
		}
	}
	return out, nil
}

func (d *DB) Subscribe(username, mailbox string) error {
	if !isValidMailboxName(mailbox) {
		return fmt.Errorf("invalid mailbox name")
	}
	subs, _ := d.readSubscriptions(username)
	for _, s := range subs {
		if s == mailbox {
			return nil
		}
	}
	subs = append(subs, mailbox)
	return writeAtomic(d.subscriptionsPath(username), []byte(strings.Join(subs, "\n")+"\n"))
}

func (d *DB) Unsubscribe(username, mailbox string) error {
	if !isValidMailboxName(mailbox) {
		return fmt.Errorf("invalid mailbox name")
	}
	subs, _ := d.readSubscriptions(username)
	var kept []string
	for _, s := range subs {
		if s != mailbox {
			kept = append(kept, s)
		}
	}
	if len(kept) == 0 {
		os.Remove(d.subscriptionsPath(username))
		return nil
	}
	return writeAtomic(d.subscriptionsPath(username), []byte(strings.Join(kept, "\n")+"\n"))
}

func (d *DB) IsSubscribed(username, mailbox string) bool {
	subs, _ := d.readSubscriptions(username)
	for _, s := range subs {
		if s == mailbox {
			return true
		}
	}
	return false
}

func (d *DB) ListSubscribed(username string) ([]string, error) {
	return d.readSubscriptions(username)
}

func (d *DB) ensureMailbox(username, name string) error {
	dir := d.mailboxDir(username, name)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	vp := filepath.Join(dir, "uidvalidity")
	if _, err := os.Stat(vp); os.IsNotExist(err) {
		if err := writeInt64File(vp, time.Now().Unix()); err != nil {
			return err
		}
	}
	np := filepath.Join(dir, "uidnext")
	if _, err := os.Stat(np); os.IsNotExist(err) {
		if err := writeInt64File(np, 1); err != nil {
			return err
		}
	}
	return nil
}

func (d *DB) GetMailbox(username, name string) (Mailbox, error) {
	// Defense-in-depth: validate the mailbox name charset first. This rejects
	// path separators and traversal segments ("..", leading ".") regardless of
	// any subscription state.
	if !isValidMailboxName(name) {
		return Mailbox{}, fmt.Errorf("no such mailbox: %s", name)
	}
	dir := d.mailboxDir(username, name)
	userBase := d.userDir(username)
	// Canonicalize and ensure the resolved mailbox directory stays strictly
	// under the requesting user's own directory. A subscription (IsSubscribed)
	// must NEVER authorize access to a mailbox that resolves outside the
	// caller's base — this closes the path-traversal IDOR.
	cleaned := filepath.Clean(dir)
	if cleaned != userBase && !strings.HasPrefix(cleaned, userBase+string(os.PathSeparator)) {
		return Mailbox{}, fmt.Errorf("no such mailbox: %s", name)
	}
	if _, err := os.Stat(dir); err != nil {
		return Mailbox{}, fmt.Errorf("no such mailbox: %s", name)
	}
	uv, err := readInt64File(filepath.Join(dir, "uidvalidity"))
	if err != nil {
		return Mailbox{}, fmt.Errorf("read uidvalidity: %w", err)
	}
	un, err := readInt64File(filepath.Join(dir, "uidnext"))
	if err != nil {
		return Mailbox{}, fmt.Errorf("read uidnext: %w", err)
	}
	return Mailbox{
		Username:    username,
		Name:        name,
		UIDValidity: uv,
		UIDNext:     un,
		Subscribed:  true,
	}, nil
}

func (d *DB) ListAllUsers() ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(d.root, "users"))
	if err != nil {
		return nil, err
	}
	var users []string
	for _, e := range entries {
		if e.IsDir() {
			users = append(users, e.Name())
		}
	}
	return users, nil
}

func (d *DB) ListMailboxes(username string) ([]Mailbox, error) {
	entries, err := os.ReadDir(d.userDir(username))
	if err != nil {
		return nil, err
	}
	var out []Mailbox
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		m, err := d.GetMailbox(username, e.Name())
		if err != nil {
			continue
		}
		out = append(out, m)
	}
	return out, nil
}

type meta struct {
	flags string
	date  int64
}

func readMeta(path string) (meta, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return meta{}, err
	}
	m := meta{}
	for _, line := range strings.Split(string(data), "\n") {
		if after, ok := strings.CutPrefix(line, "flags: "); ok {
			m.flags = strings.TrimSpace(after)
		} else if after, ok := strings.CutPrefix(line, "date: "); ok {
			m.date, _ = strconv.ParseInt(strings.TrimSpace(after), 10, 64)
		}
	}
	return m, nil
}

func writeMeta(path, flags string, date int64) error {
	content := fmt.Sprintf("flags: %s\ndate: %d\n", flags, date)
	return writeAtomic(path, []byte(content))
}

func (d *DB) sortedUIDs(username, mailbox string) ([]int64, error) {
	entries, err := os.ReadDir(d.mailboxDir(username, mailbox))
	if err != nil {
		return nil, err
	}
	var uids []int64
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".eml") {
			continue
		}
		uid, err := strconv.ParseInt(strings.TrimSuffix(name, ".eml"), 10, 64)
		if err != nil {
			continue
		}
		uids = append(uids, uid)
	}
	sort.Slice(uids, func(i, j int) bool { return uids[i] < uids[j] })
	return uids, nil
}

func (d *DB) CountMessages(username, mailbox string) (int64, error) {
	uids, err := d.sortedUIDs(username, mailbox)
	return int64(len(uids)), err
}

func (d *DB) MailboxCounts(username, mailbox string) (exists, recent int64, err error) {
	uids, err := d.sortedUIDs(username, mailbox)
	if err != nil {
		return 0, 0, err
	}
	exists = int64(len(uids))
	for _, uid := range uids {
		m, err := readMeta(d.metaPath(username, mailbox, uid))
		if err != nil {
			continue
		}
		if containsFlag(m.flags, `\Recent`) {
			recent++
		}
	}
	return exists, recent, nil
}

func (d *DB) FirstUnseen(username, mailbox string) (int64, error) {
	uids, err := d.sortedUIDs(username, mailbox)
	if err != nil {
		return 0, err
	}
	for seq, uid := range uids {
		m, err := readMeta(d.metaPath(username, mailbox, uid))
		if err != nil {
			continue
		}
		if !containsFlag(m.flags, `\Seen`) {
			return int64(seq) + 1, nil
		}
	}
	return 0, nil
}

func (d *DB) FetchMessages(username, mailbox string, seqNums []int64) ([]Message, error) {
	uids, err := d.sortedUIDs(username, mailbox)
	if err != nil {
		return nil, err
	}
	want := make(map[int64]bool, len(seqNums))
	for _, s := range seqNums {
		want[s] = true
	}
	var out []Message
	for i, uid := range uids {
		seq := int64(i) + 1
		if !want[seq] {
			continue
		}
		body, err := os.ReadFile(d.emlPath(username, mailbox, uid))
		if err != nil {
			return nil, err
		}
		m, err := readMeta(d.metaPath(username, mailbox, uid))
		if err != nil {
			return nil, err
		}
		out = append(out, Message{
			MailboxUsername: username,
			MailboxName:     mailbox,
			UID:             uid,
			Flags:           m.flags,
			InternalDate:    m.date,
			Body:            body,
			Size:            int64(len(body)),
			SeqNum:          seq,
		})
	}
	return out, nil
}

func (d *DB) AppendMessage(username, mailbox, flags string, internalDate time.Time, body []byte) (uid int64, err error) {

	if !isValidMailboxName(mailbox) {
		return 0, fmt.Errorf("invalid mailbox name")
	}
	if d.IsArchived(username, mailbox) {
		return 0, fmt.Errorf("mailbox is read-only (archived)")
	}
	// Ensure the resolved mailbox stays under the requesting user's own
	// directory; reject path-traversal mailbox names even for appends.
	mbDir := filepath.Clean(d.mailboxDir(username, mailbox))
	userBase := d.userDir(username)
	if mbDir != userBase && !strings.HasPrefix(mbDir, userBase+string(os.PathSeparator)) {
		return 0, fmt.Errorf("invalid mailbox name")
	}
	uidnextPath := filepath.Join(d.mailboxDir(username, mailbox), "uidnext")

	f, err := os.OpenFile(uidnextPath, os.O_RDWR, 0600)
	if err != nil {
		return 0, fmt.Errorf("open uidnext: %w", err)
	}
	defer f.Close()

	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		return 0, fmt.Errorf("lock uidnext: %w", err)
	}
	defer syscall.Flock(int(f.Fd()), syscall.LOCK_UN)

	var buf [32]byte
	n, _ := f.Read(buf[:])
	uid, err = strconv.ParseInt(strings.TrimSpace(string(buf[:n])), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse uidnext: %w", err)
	}

	if err := os.WriteFile(d.emlPath(username, mailbox, uid)+".tmp", body, 0600); err != nil {
		return 0, err
	}
	if err := os.Rename(d.emlPath(username, mailbox, uid)+".tmp", d.emlPath(username, mailbox, uid)); err != nil {
		return 0, err
	}
	if err := writeMeta(d.metaPath(username, mailbox, uid), flags, internalDate.Unix()); err != nil {
		return 0, err
	}

	if _, err := f.Seek(0, 0); err != nil {
		return 0, err
	}
	if err := f.Truncate(0); err != nil {
		return 0, err
	}
	newVal := strconv.FormatInt(uid+1, 10) + "\n"
	if _, err := f.WriteString(newVal); err != nil {
		return 0, err
	}

	return uid, nil
}

func (d *DB) CreateUser(username, password string) error {
	if username == "" || strings.ContainsAny(username, "/\\.") {
		return fmt.Errorf("invalid username")
	}
	dir := d.userDir(username)
	if _, err := os.Stat(dir); err == nil {
		return fmt.Errorf("user already exists")
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	pwPath := filepath.Join(dir, "password")
	return writeAtomic(pwPath, []byte(hashPassword(password)))
}

func (d *DB) UserExists(username string) bool {
	if _, err := os.Stat(d.userDir(username)); err != nil {
		return false
	}
	return true
}

func (d *DB) SetSignature(username string, text []byte) error {
	if !d.UserExists(username) {
		return fmt.Errorf("no such user")
	}
	return writeAtomic(filepath.Join(d.userDir(username), "signature"), text)
}

func (d *DB) GetSignature(username string) ([]byte, error) {
	data, err := os.ReadFile(filepath.Join(d.userDir(username), "signature"))
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}
	return data, nil
}

func (d *DB) SetGovernmentAgent(username string) error {
	metaPath := filepath.Join(d.userDir(username), "meta")
	return writeAtomic(metaPath, []byte("agent: true\n"))
}

func (d *DB) SortedUIDs(username, mailbox string) ([]int64, error) {
	return d.sortedUIDs(username, mailbox)
}

func (d *DB) SeqToUID(username, mailbox string, seqs []int64) ([]int64, error) {
	uids, err := d.sortedUIDs(username, mailbox)
	if err != nil {
		return nil, err
	}
	var out []int64
	for _, s := range seqs {
		if s >= 1 && s <= int64(len(uids)) {
			out = append(out, uids[s-1])
		}
	}
	return out, nil
}

func (d *DB) FetchMessagesByUIDs(username, mailbox string, uids []int64) ([]Message, error) {
	all, err := d.sortedUIDs(username, mailbox)
	if err != nil {
		return nil, err
	}
	seqOf := make(map[int64]int64, len(all))
	for i, u := range all {
		seqOf[u] = int64(i) + 1
	}
	want := make(map[int64]bool, len(uids))
	for _, u := range uids {
		want[u] = true
	}
	var out []Message
	for _, uid := range all {
		if !want[uid] {
			continue
		}
		body, err := os.ReadFile(d.emlPath(username, mailbox, uid))
		if err != nil {
			continue
		}
		m, err := readMeta(d.metaPath(username, mailbox, uid))
		if err != nil {
			continue
		}
		out = append(out, Message{
			MailboxUsername: username,
			MailboxName:     mailbox,
			UID:             uid,
			Flags:           m.flags,
			InternalDate:    m.date,
			Body:            body,
			Size:            int64(len(body)),
			SeqNum:          seqOf[uid],
		})
	}
	return out, nil
}

func (d *DB) MailboxStatus(username, mailbox string) (exists, recent, unseen, uidnext, uidvalidity int64, err error) {
	mb, err := d.GetMailbox(username, mailbox)
	if err != nil {
		return
	}
	uidnext = mb.UIDNext
	uidvalidity = mb.UIDValidity
	uids, e := d.sortedUIDs(username, mailbox)
	if e != nil {
		err = e
		return
	}
	exists = int64(len(uids))
	for _, uid := range uids {
		m, err2 := readMeta(d.metaPath(username, mailbox, uid))
		if err2 != nil {
			continue
		}
		if containsFlag(m.flags, `\Recent`) {
			recent++
		}
		if !containsFlag(m.flags, `\Seen`) {
			unseen++
		}
	}
	return
}

func (d *DB) UpdateFlags(username, mailbox string, uid int64, flags string) error {
	m, err := readMeta(d.metaPath(username, mailbox, uid))
	if err != nil {
		return err
	}
	return writeMeta(d.metaPath(username, mailbox, uid), flags, m.date)
}

func (d *DB) GetFlags(username, mailbox string, uid int64) (string, error) {
	m, err := readMeta(d.metaPath(username, mailbox, uid))
	if err != nil {
		return "", err
	}
	return m.flags, nil
}

func (d *DB) DeleteMessage(username, mailbox string, uid int64) error {
	_ = os.Remove(d.emlPath(username, mailbox, uid))
	_ = os.Remove(d.metaPath(username, mailbox, uid))
	return nil
}

func (d *DB) ExpungeDeleted(username, mailbox string) ([]int64, error) {
	uids, err := d.sortedUIDs(username, mailbox)
	if err != nil {
		return nil, err
	}
	var removedSeqs []int64
	for i, uid := range uids {
		m, err := readMeta(d.metaPath(username, mailbox, uid))
		if err != nil {
			continue
		}
		if containsFlag(m.flags, `\Deleted`) {
			d.DeleteMessage(username, mailbox, uid)
			removedSeqs = append(removedSeqs, int64(i)+1)
		}
	}

	return removedSeqs, nil
}

func isValidMailboxName(name string) bool {
	if name == "" {
		return false
	}
	if strings.ContainsAny(name, "/\\") {
		return false
	}

	if name == "." || name == ".." || strings.HasPrefix(name, ".") {
		return false
	}
	return true
}

func (d *DB) CreateMailbox(username, name string) error {
	if !isValidMailboxName(name) {
		return fmt.Errorf("invalid mailbox name")
	}
	dir := d.mailboxDir(username, name)
	if _, err := os.Stat(dir); err == nil {
		return fmt.Errorf("mailbox already exists")
	}
	return d.ensureMailbox(username, name)
}

func (d *DB) DeleteMailbox(username, name string) error {
	if !isValidMailboxName(name) {
		return fmt.Errorf("invalid mailbox name")
	}
	if strings.EqualFold(name, "INBOX") {
		return fmt.Errorf("cannot delete INBOX")
	}
	dir := d.mailboxDir(username, name)
	if _, err := os.Stat(dir); err != nil {
		return fmt.Errorf("no such mailbox")
	}
	if d.IsArchived(username, name) {
		return fmt.Errorf("mailbox is read-only (archived)")
	}
	d.Unsubscribe(username, name)
	return os.RemoveAll(dir)
}

func (d *DB) archivedPath(username, mailbox string) string {
	return filepath.Join(d.mailboxDir(username, mailbox), ".archived")
}

func (d *DB) ArchiveMailbox(username, name string) error {
	if !isValidMailboxName(name) {
		return fmt.Errorf("invalid mailbox name")
	}
	dir := d.mailboxDir(username, name)
	if _, err := os.Stat(dir); err != nil {
		return fmt.Errorf("no such mailbox")
	}
	return writeAtomic(d.archivedPath(username, name), []byte("1\n"))
}

func (d *DB) IsArchived(username, mailbox string) bool {
	_, err := os.Stat(d.archivedPath(username, mailbox))
	return err == nil
}

func (d *DB) RenameMailbox(username, oldName, newName string) error {
	if !isValidMailboxName(oldName) || !isValidMailboxName(newName) {
		return fmt.Errorf("invalid mailbox name")
	}
	if strings.EqualFold(oldName, "INBOX") {
		return fmt.Errorf("cannot rename INBOX")
	}
	src := d.mailboxDir(username, oldName)
	dst := d.mailboxDir(username, newName)
	if _, err := os.Stat(src); err != nil {
		return fmt.Errorf("no such mailbox")
	}
	if d.IsArchived(username, oldName) {
		return fmt.Errorf("mailbox is read-only (archived)")
	}
	if _, err := os.Stat(dst); err == nil {
		return fmt.Errorf("destination exists")
	}
	if err := os.Rename(src, dst); err != nil {
		return err
	}
	if d.IsSubscribed(username, oldName) {
		d.Unsubscribe(username, oldName)
		d.Subscribe(username, newName)
	}
	return nil
}

func (d *DB) CopyMessage(username, srcMailbox string, srcUID int64, dstMailbox string) (int64, error) {
	body, err := os.ReadFile(d.emlPath(username, srcMailbox, srcUID))
	if err != nil {
		return 0, err
	}
	meta, err := readMeta(d.metaPath(username, srcMailbox, srcUID))
	if err != nil {
		return 0, err
	}
	return d.AppendMessage(username, dstMailbox, meta.flags, time.Unix(meta.date, 0), body)
}

func containsFlag(flags, flag string) bool {
	for _, f := range strings.Fields(flags) {
		if f == flag {
			return true
		}
	}
	return false
}
