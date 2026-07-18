-module(compression).
-export([compress/1, init_compressor/0, close_compressor/1, compress_stream/2]).

%% zlib level 1 for maximum speed
compress(Data) ->
    Z = zlib:open(),
    ok = zlib:deflateInit(Z, 1),
    Compressed = zlib:deflate(Z, Data, finish),
    ok = zlib:deflateEnd(Z),
    ok = zlib:close(Z),
    Compressed.

%% for socket
init_compressor() ->
    Z = zlib:open(),
    ok = zlib:deflateInit(Z, 1),
    Z.

compress_stream(Z, Data) ->
    ok = zlib:deflateReset(Z),
    zlib:deflate(Z, Data, finish).

close_compressor(Z) ->
    _ = zlib:deflate(Z, <<>>, finish),
    ok = zlib:deflateEnd(Z),
    zlib:close(Z).
