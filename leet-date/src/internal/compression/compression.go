package compression

import (
	"encoding/binary"
	"errors"
	"sync"
)

const (
	magic      = "LZ1\x00"
	opLiteral  = 0x00
	opMatch    = 0x01
	windowSize = 1 << 16
	windowMask = windowSize - 1
	maxOutput  = 16 << 20
)

var ErrBadStream = errors.New("compression: malformed stream")

var (
	mu     sync.Mutex
	window [windowSize]byte
)

const (
	minMatch = 3
	maxMatch = 65535
	maxDist  = 65536
	maxChain = 128
)

func Compress(raw []byte) []byte {
	out := make([]byte, 0, len(raw)/2+8)
	out = append(out, magic...)

	n := len(raw)
	heads := make(map[uint32]int)
	prev := make([]int, n)
	for j := range prev {
		prev[j] = -1
	}

	key := func(i int) uint32 {
		return uint32(raw[i])<<16 | uint32(raw[i+1])<<8 | uint32(raw[i+2])
	}
	insert := func(i int) {
		if i+minMatch > n {
			return
		}
		k := key(i)
		if old, ok := heads[k]; ok {
			prev[i] = old
		}
		heads[k] = i
	}

	i := 0
	for i < n {
		bestLen, bestDist := 0, 0
		if i+minMatch <= n {
			cand, ok := heads[key(i)]
			for d := 0; ok && d < maxChain; d++ {
				dist := i - cand
				if dist <= 0 || dist > maxDist {
					break
				}
				l := 0
				for i+l < n && l < maxMatch && raw[cand+l] == raw[i+l] {
					l++
				}
				if l > bestLen {
					bestLen, bestDist = l, dist
				}
				if prev[cand] < 0 {
					break
				}
				cand = prev[cand]
			}
		}

		if bestLen >= minMatch {
			out = append(out, opMatch)
			out = binary.LittleEndian.AppendUint16(out, uint16(bestDist-1))
			out = binary.LittleEndian.AppendUint16(out, uint16(bestLen))
			for end := i + bestLen; i < end; i++ {
				insert(i)
			}
		} else {
			out = append(out, opLiteral, raw[i])
			insert(i)
			i++
		}
	}
	return out
}

func Decompress(blob []byte) ([]byte, error) {
	mu.Lock()
	defer mu.Unlock()

	if len(blob) < 4 || string(blob[:4]) != magic {
		return nil, ErrBadStream
	}
	p := blob[4:]
	out := make([]byte, 0, 1024)
	pos := 0

	for len(p) > 0 {
		switch p[0] {
		case opLiteral:
			if len(p) < 2 {
				return nil, ErrBadStream
			}
			if len(out)+1 > maxOutput {
				return nil, ErrBadStream
			}
			b := p[1]
			window[pos&windowMask] = b
			out = append(out, b)
			pos++
			p = p[2:]

		case opMatch:
			if len(p) < 5 {
				return nil, ErrBadStream
			}
			dist := int(binary.LittleEndian.Uint16(p[1:3])) + 1
			length := int(binary.LittleEndian.Uint16(p[3:5]))
			if len(out)+length > maxOutput {
				return nil, ErrBadStream
			}
			for i := 0; i < length; i++ {
				src := (pos - dist) & windowMask
				b := window[src]
				window[pos&windowMask] = b
				out = append(out, b)
				pos++
			}
			p = p[5:]

		default:
			return nil, ErrBadStream
		}
	}
	return out, nil
}
