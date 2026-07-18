package imap

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"
)

const maxLiteral = 16 * 1024 * 1024

type Command struct {
	Tag  string
	Name string
	Args []string

	Literal []byte
}

type Reader struct {
	r *bufio.Reader
	w io.Writer
}

func NewReader(r io.Reader, w io.Writer) *Reader {
	return &Reader{r: bufio.NewReaderSize(r, 65536), w: w}
}

func (r *Reader) ReadLine() (string, error) { return r.readLine() }

func (r *Reader) ReadCommand() (*Command, error) {
	line, err := r.readLine()
	if err != nil {
		return nil, err
	}

	line, literal, err := r.consumeLiteral(line)
	if err != nil {
		return nil, err
	}

	tag, name, args := parseLine(line)
	if tag == "" {
		return nil, fmt.Errorf("empty tag")
	}
	return &Command{Tag: tag, Name: strings.ToUpper(name), Args: args, Literal: literal}, nil
}

func (r *Reader) readLine() (string, error) {
	line, err := r.r.ReadString('\n')
	if err != nil {
		return "", err
	}
	line = strings.TrimRight(line, "\r\n")
	return line, nil
}

func (r *Reader) consumeLiteral(line string) (string, []byte, error) {
	if !strings.HasSuffix(line, "}") {
		return line, nil, nil
	}
	open := strings.LastIndex(line, "{")
	if open <= 0 {
		return line, nil, nil
	}
	if prev := line[open-1]; prev != ' ' && prev != '\t' {
		return line, nil, nil
	}
	countStr := line[open+1 : len(line)-1]
	if countStr == "" {
		return line, nil, nil
	}
	for _, c := range countStr {
		if c < '0' || c > '9' {
			return line, nil, nil
		}
	}
	n, err := strconv.Atoi(countStr)
	if err != nil || n < 0 {
		return line, nil, nil
	}
	if n > maxLiteral {
		return "", nil, fmt.Errorf("literal too large: %d bytes (max %d)", n, maxLiteral)
	}

	if _, err := fmt.Fprintf(r.w, "+ Ready for literal data\r\n"); err != nil {
		return "", nil, err
	}
	buf := make([]byte, n)
	if _, err := io.ReadFull(r.r, buf); err != nil {
		return "", nil, fmt.Errorf("reading literal: %w", err)
	}
	return line[:open], buf, nil
}

func parseLine(line string) (tag, name string, args []string) {
	tokens := tokenize(line)
	if len(tokens) == 0 {
		return "", "", nil
	}
	if len(tokens) == 1 {
		return tokens[0], "", nil
	}
	tag = tokens[0]
	name = tokens[1]
	if len(tokens) > 2 {
		args = tokens[2:]
	}
	return
}

func tokenize(line string) []string {
	var tokens []string
	i := 0
	for i < len(line) {

		for i < len(line) && line[i] == ' ' {
			i++
		}
		if i >= len(line) {
			break
		}
		if line[i] == '"' {

			i++
			start := i
			for i < len(line) && line[i] != '"' {
				i++
			}
			tokens = append(tokens, line[start:i])
			if i < len(line) {
				i++
			}
		} else if line[i] == '(' {

			depth := 0
			start := i
			for i < len(line) {
				if line[i] == '(' {
					depth++
				} else if line[i] == ')' {
					depth--
					if depth == 0 {
						i++
						break
					}
				}
				i++
			}
			tokens = append(tokens, line[start:i])
		} else {
			start := i

			brDepth, paDepth := 0, 0
			for i < len(line) {
				c := line[i]
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
			tokens = append(tokens, line[start:i])
		}
	}
	return tokens
}

func ParseSequenceSet(s string, total int64) ([]int64, error) {
	if total == 0 {
		return nil, nil
	}
	var result []int64
	seen := make(map[int64]bool)
	parts := strings.Split(s, ",")
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if colonIdx := strings.Index(part, ":"); colonIdx >= 0 {
			loStr := part[:colonIdx]
			hiStr := part[colonIdx+1:]
			lo, err := parseSeqNum(loStr, total)
			if err != nil {
				return nil, err
			}
			hi, err := parseSeqNum(hiStr, total)
			if err != nil {
				return nil, err
			}
			if lo > hi {
				lo, hi = hi, lo
			}
			for n := lo; n <= hi; n++ {
				if n >= 1 && n <= total && !seen[n] {
					result = append(result, n)
					seen[n] = true
				}
			}
		} else {
			n, err := parseSeqNum(part, total)
			if err != nil {
				return nil, err
			}
			if n >= 1 && n <= total && !seen[n] {
				result = append(result, n)
				seen[n] = true
			}
		}
	}
	return result, nil
}

func parseSeqNum(s string, total int64) (int64, error) {
	if s == "*" {
		return total, nil
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid sequence number: %q", s)
	}
	return n, nil
}
