package chat

import (
	"crypto/sha256"
	"encoding/hex"
)

const convoSalt = "leetdate-convo-v1"

func ConversationID(handleA, handleB string) string {
	a, b := handleA, handleB
	if a > b {
		a, b = b, a
	}
	sum := sha256.Sum256([]byte(a + "\x00" + b + "\x00" + convoSalt))
	return hex.EncodeToString(sum[:16])
}
