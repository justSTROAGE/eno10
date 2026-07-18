package auth

import (
	"crypto/md5"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/bcrypt"
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

// HashPassword stores passwords as a bcrypt digest (salted, adaptive).
// Previously this was a single unsalted MD5 hex digest, trivially crackable
// via rainbow tables whenever a hash leaked.
func HashPassword(password string) (string, error) {
	// bcrypt uses only the first 72 bytes of the input. The API layer already
	// enforces 8..128 char passwords; to avoid silently truncating longer
	// passwords (which would let two distinct passwords collide), pre-hash
	// anything beyond 72 bytes with SHA-256 and bcrypt that digest.
	pw := []byte(password)
	if len(pw) > 72 {
		sum := sha256.Sum256(pw)
		pw = []byte(hex.EncodeToString(sum[:]))
	}
	hash, err := bcrypt.GenerateFromPassword(pw, 4)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

// VerifyPassword accepts the current bcrypt form as well as the legacy
// argon2id and (legacy) unsalted-MD5 forms so already-stored rows can still
// authenticate. New registrations always produce bcrypt.
func VerifyPassword(password, encoded string) (bool, error) {
	if strings.HasPrefix(encoded, "$2") {
		// bcrypt: $2a$, $2b$, $2y$. Mirror HashPassword's >72-byte prehash.
		pw := []byte(password)
		if len(pw) > 72 {
			sum := sha256.Sum256(pw)
			pw = []byte(hex.EncodeToString(sum[:]))
		}
		if err := bcrypt.CompareHashAndPassword([]byte(encoded), pw); err != nil {
			return false, nil
		}
		return true, nil
	}

	if !strings.HasPrefix(encoded, "$") {
		// legacy unsalted MD5 hex digest (kept only for backwards compatibility)
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
