package main

import (
	"context"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"

	"github.com/leonardopreuss/leet_date/internal/compression"
	"github.com/leonardopreuss/leet_date/internal/compresspb"
)

type server struct {
	compresspb.UnimplementedCompressorServer
}

func (server) Compress(_ context.Context, req *compresspb.CompressRequest) (*compresspb.CompressResponse, error) {
	return &compresspb.CompressResponse{Blob: compression.Compress(req.GetRaw())}, nil
}

func (server) Decompress(_ context.Context, req *compresspb.DecompressRequest) (*compresspb.DecompressResponse, error) {
	raw, err := compression.Decompress(req.GetBlob())
	if err != nil {
		return nil, err
	}
	return &compresspb.DecompressResponse{Raw: raw}, nil
}

func main() {
	addr := os.Getenv("IMGSVC_ADDR")
	if addr == "" {
		addr = ":9000"
	}

	lis, err := net.Listen("tcp", addr)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}

	grpcServer := grpc.NewServer(
		grpc.MaxRecvMsgSize(32<<20),
		grpc.MaxSendMsgSize(32<<20),
	)
	compresspb.RegisterCompressorServer(grpcServer, server{})

	go func() {
		log.Printf("imgsvc listening on %s", addr)
		if err := grpcServer.Serve(lis); err != nil {
			log.Fatalf("serve: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Printf("shutting down")
	grpcServer.GracefulStop()
}
