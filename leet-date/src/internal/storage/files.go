package storage

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

type Store struct {
	Root string
}

func New(root string) *Store {
	return &Store{Root: root}
}

func (s *Store) userDir(userID int64) string {
	return filepath.Join(s.Root, fmt.Sprintf("%d", userID))
}

func (s *Store) Save(userID int64, filename string, src io.Reader) (string, error) {
	dir := s.userDir(userID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	full := filepath.Join(dir, filename)
	dst, err := os.OpenFile(full, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return "", err
	}
	defer dst.Close()
	if _, err := io.Copy(dst, src); err != nil {
		_ = os.Remove(full)
		return "", err
	}
	return full, nil
}

func (s *Store) Open(userID int64, filename string) (*os.File, error) {
	return os.Open(filepath.Join(s.userDir(userID), filename))
}

func (s *Store) Delete(userID int64, filename string) error {
	err := os.Remove(filepath.Join(s.userDir(userID), filename))
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
