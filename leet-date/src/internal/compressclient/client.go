package compressclient

import (
	"context"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"github.com/leonardopreuss/leet_date/internal/compresspb"
)

type Client struct {
	conn *grpc.ClientConn
	rpc  compresspb.CompressorClient
}

func New(addr string) (*Client, error) {
	conn, err := grpc.NewClient(addr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithDefaultCallOptions(
			grpc.MaxCallRecvMsgSize(32<<20),
			grpc.MaxCallSendMsgSize(32<<20),
		),
	)
	if err != nil {
		return nil, err
	}
	return &Client{conn: conn, rpc: compresspb.NewCompressorClient(conn)}, nil
}

func (c *Client) Close() error {
	return c.conn.Close()
}

func (c *Client) Compress(ctx context.Context, raw []byte) ([]byte, error) {
	resp, err := c.rpc.Compress(ctx, &compresspb.CompressRequest{Raw: raw})
	if err != nil {
		return nil, err
	}
	return resp.GetBlob(), nil
}

func (c *Client) Decompress(ctx context.Context, blob []byte) ([]byte, error) {
	resp, err := c.rpc.Decompress(ctx, &compresspb.DecompressRequest{Blob: blob})
	if err != nil {
		return nil, err
	}
	return resp.GetRaw(), nil
}
