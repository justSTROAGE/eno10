package premiumjwt

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"

	"github.com/lestrrat-go/jwx/v2/jwk"
	"github.com/lestrrat-go/jwx/v2/jws"
	"github.com/lestrrat-go/jwx/v2/jwt"
)

type Verifier struct {
	jwksURL string
	issuer  string
	aud     string
	client  *http.Client

	mu  sync.RWMutex
	set jwk.Set
}

type Claims struct {
	Subject     string
	AmountCents int64
	IssuedAt    time.Time
	ExpiresAt   time.Time
}

func New(jwksURL, issuer, aud string) *Verifier {
	return &Verifier{
		jwksURL: jwksURL,
		issuer:  issuer,
		aud:     aud,
		client:  &http.Client{Timeout: 5 * time.Second},
		set:     jwk.NewSet(),
	}
}

func (v *Verifier) Refresh(ctx context.Context) error {
	set, err := v.fetchSet(ctx, v.jwksURL)
	if err != nil {
		return err
	}
	v.mu.Lock()
	v.set = set
	v.mu.Unlock()
	return nil
}

func (v *Verifier) fetchSet(ctx context.Context, jwksURL string) (jwk.Set, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", jwksURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := v.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		io.Copy(io.Discard, resp.Body)
		return nil, fmt.Errorf("jwks fetch: %s", resp.Status)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return jwk.Parse(body)
}

func (v *Verifier) keyByID(kid string) (jwk.Key, bool) {
	v.mu.RLock()
	defer v.mu.RUnlock()
	if kid == "" {
		return nil, false
	}
	return v.set.LookupKeyID(kid)
}

func (v *Verifier) Verify(ctx context.Context, tokenStr string) (*Claims, error) {
	parsed, err := jws.Parse([]byte(tokenStr))
	if err != nil {
		return nil, fmt.Errorf("parse: %w", err)
	}
	sigs := parsed.Signatures()
	if len(sigs) != 1 {
		return nil, errors.New("expected exactly one signature")
	}
	hdr := sigs[0].ProtectedHeaders()
	kid := hdr.KeyID()
	alg := hdr.Algorithm()

	// Defense: never honor attacker-supplied key material. Reject any token
	// that carries an inline JWK or a "jku" header pointing elsewhere — the
	// verification key must come ONLY from the configured payments JWKS URL.
	if hdr.JWK() != nil {
		return nil, errors.New("inline JWK is not allowed")
	}
	if jkuStr := hdr.JWKSetURL(); jkuStr != "" {
		return nil, errors.New("jku header is not allowed")
	}

	var key jwk.Key

	if k, ok := v.keyByID(kid); ok {
		key = k
	}

	if key == nil {
		if err := v.Refresh(ctx); err == nil {
			if k, ok := v.keyByID(kid); ok {
				key = k
			}
		}
	}

	if key == nil {
		return nil, errors.New("no verification key")
	}

	tok, err := jwt.Parse([]byte(tokenStr),
		jwt.WithKey(alg, key),
		jwt.WithVerify(true),
		jwt.WithValidate(true),
		jwt.WithIssuer(v.issuer),
		jwt.WithAudience(v.aud),
	)
	if err != nil {
		return nil, fmt.Errorf("verify: %w", err)
	}

	var amount int64
	if raw, ok := tok.Get("amount_cents"); ok {
		switch x := raw.(type) {
		case int64:
			amount = x
		case float64:
			amount = int64(x)
		case json.Number:
			amount, _ = x.Int64()
		}
	}

	return &Claims{
		Subject:     tok.Subject(),
		AmountCents: amount,
		IssuedAt:    tok.IssuedAt(),
		ExpiresAt:   tok.Expiration(),
	}, nil
}
