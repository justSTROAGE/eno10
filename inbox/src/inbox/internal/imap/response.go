package imap

import (
	"fmt"
	"io"
)

type Writer struct {
	w io.Writer
}

func NewWriter(w io.Writer) *Writer {
	return &Writer{w: w}
}

func (w *Writer) Untagged(format string, args ...any) error {
	_, err := fmt.Fprintf(w.w, "* "+format+"\r\n", args...)
	return err
}

func (w *Writer) Tagged(tag, status, format string, args ...any) error {
	msg := fmt.Sprintf(format, args...)
	_, err := fmt.Fprintf(w.w, "%s %s %s\r\n", tag, status, msg)
	return err
}

func (w *Writer) OK(tag, text string) error {
	return w.Tagged(tag, "OK", "%s", text)
}

func (w *Writer) NO(tag, text string) error {
	return w.Tagged(tag, "NO", "%s", text)
}

func (w *Writer) BAD(tag, text string) error {
	return w.Tagged(tag, "BAD", "%s", text)
}

func (w *Writer) Literal(data []byte) error {
	_, err := fmt.Fprintf(w.w, "{%d}\r\n", len(data))
	if err != nil {
		return err
	}
	_, err = w.w.Write(data)
	return err
}

func (w *Writer) Raw(b []byte) error {
	_, err := w.w.Write(b)
	return err
}
