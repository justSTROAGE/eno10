package main

import (
	"flag"
	"inbox/internal/db"
	"inbox/internal/server"
	"inbox/internal/session"
	"inbox/internal/smtp"
	"log"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	addr := flag.String("addr", ":1234", "TCP address to listen on (IMAP)")
	smtpAddr := flag.String("smtpaddr", ":4321", "TCP address to listen on (SMTP)")
	dbPath := flag.String("db", "maildir", "path to mail store")
	debug := flag.Bool("debug", false, "print every command to stderr as *user*: command")
	flag.Parse()

	session.Debug = *debug

	database, err := db.Open(*dbPath)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer database.Close()

	srv, err := server.New(*addr, database)
	if err != nil {
		log.Fatalf("imap listen: %v", err)
	}
	log.Printf("INBOX (IMAP) listening on %s", srv.Addr())

	smtpSrv, err := smtp.New(*smtpAddr, database)
	if err != nil {
		log.Fatalf("smtp listen: %v", err)
	}
	log.Printf("INBOX (SMTP) listening on %s", smtpSrv.Addr())

	go srv.Serve()
	go smtpSrv.Serve()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("shutting down")
	srv.Close()
	smtpSrv.Close()
}
