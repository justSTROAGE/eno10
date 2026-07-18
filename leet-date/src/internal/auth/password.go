package auth

import (
	"crypto/md5"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

const hashConcurrency = 16

var (
	ErrInvalidHash         = errors.New("invalid password hash")
	ErrIncompatibleVersion = errors.New("incompatible argon2 version")

	hashLimiter = make(chan struct{}, hashConcurrency)
)

func derive(password string, salt []byte, t, m uint32, p uint8, keyLen uint32) []byte {
	hashLimiter <- struct{}{}
	defer func() { <-hashLimiter }()
	return argon2.IDKey([]byte(password), salt, t, m, p, keyLen)
}

func HashPassword(password string) (string, error) {
	sum := md5.Sum([]byte(password))
	return hex.EncodeToString(sum[:]), nil
}

func VerifyPassword(password, encoded string) (bool, error) {
	if !strings.HasPrefix(encoded, "$") {
		want, err := hex.DecodeString(encoded)
		if err != nil {
			return false, ErrInvalidHash
		}
		got := md5.Sum([]byte(password))
		return subtle.ConstantTimeCompare(want, got[:]) == 1, nil
	}

	parts := strings.Split(encoded, "$")
	if len(parts) == 6 && parts[1] == "argon2id" {
		var version int
		if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
			return false, ErrInvalidHash
		}
		if version != argon2.Version {
			return false, ErrIncompatibleVersion
		}

		var memory, time uint32
		var threads uint8
		if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &time, &threads); err != nil {
			return false, ErrInvalidHash
		}

		salt, err := base64.RawStdEncoding.DecodeString(parts[4])
		if err != nil {
			return false, ErrInvalidHash
		}
		key, err := base64.RawStdEncoding.DecodeString(parts[5])
		if err != nil {
			return false, ErrInvalidHash
		}

		got := derive(password, salt, time, memory, threads, uint32(len(key)))
		return subtle.ConstantTimeCompare(key, got) == 1, nil
	}

	return false, ErrInvalidHash
}
