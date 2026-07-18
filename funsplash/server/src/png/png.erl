-module(png).
-export([parse_png/1, build_idat/1, defilter_image/5, premium_mask/2]).

build_idat(CompressedIoList) ->
    Length = erlang:iolist_size(CompressedIoList),
    CRC = erlang:crc32(["IDAT", CompressedIoList]),
    [<<Length:32, "IDAT">>, CompressedIoList, <<CRC:32>>].

parse_png(<<137, 80, 78, 71, 13, 10, 26, 10, Rest/binary>>) ->
    Signature = <<137, 80, 78, 71, 13, 10, 26, 10>>,
    parse_chunks(Rest, Signature, <<>>, <<>>, {});
parse_png(_) ->
    erlang:error(invalid_signature).

parse_chunks(<<Length:32, "IHDR", Data:Length/binary, CRC:32, Rest/binary>>, Headers, IDATs, Footer, _Meta) ->
    <<W:32, H:32, BitDepth:8, ColorType:8, _/binary>> = Data,
    NewHeaders = <<Headers/binary, Length:32, "IHDR", Data/binary, CRC:32>>,
    parse_chunks(Rest, NewHeaders, IDATs, Footer, {W, H, BitDepth, ColorType});
parse_chunks(<<Length:32, "IDAT", Data:Length/binary, _CRC:32, Rest/binary>>, Headers, IDATs, Footer, Meta) ->
    parse_chunks(Rest, Headers, <<IDATs/binary, Data/binary>>, Footer, Meta);
parse_chunks(<<Length:32, "IEND", Data:Length/binary, CRC:32, _Rest/binary>>, Headers, IDATs, _Footer, Meta) ->
    FooterChunk = <<Length:32, "IEND", Data/binary, CRC:32>>,
    RawPixels = zlib:uncompress(IDATs),
    {Meta, Headers, RawPixels, FooterChunk};
parse_chunks(<<Length:32, Type:4/binary, Data:Length/binary, CRC:32, Rest/binary>>, Headers, IDATs, Footer, Meta) ->
    NewHeaders = <<Headers/binary, Length:32, Type/binary, Data/binary, CRC:32>>,
    parse_chunks(Rest, NewHeaders, IDATs, Footer, Meta);
parse_chunks(_, _Headers, _IDATs, _Footer, _Meta) ->
    erlang:error(malformed_chunk).

defilter_image(PhotoPixels, Width, BitDepth, ColorType, Bpp) ->
    Channels = case ColorType of
        0 -> 1; 2 -> 3; 3 -> 1; 4 -> 2; 6 -> 4 
    end,
    BitsPerRow = Width * Channels * BitDepth,
    PhotoRowBytes = (BitsPerRow + 7) div 8,
    PrevRow = <<0:(PhotoRowBytes*8)>>,
    extract_raw(PhotoRowBytes, Bpp, PhotoPixels, PrevRow, <<>>).

extract_raw(PhotoRowBytes, Bpp, PhotoPixels, PrevRow, Acc) ->
    case PhotoPixels of
        <<Filter:8, Row:PhotoRowBytes/binary, Rest/binary>> ->
            RawRow = defilter(Filter, Row, PrevRow, Bpp),
            extract_raw(PhotoRowBytes, Bpp, Rest, RawRow, <<Acc/binary, RawRow/binary>>);
        <<>> ->
            Acc
    end.

defilter(0, Row, _PrevRow, _Bpp) -> Row;
defilter(1, Row, _PrevRow, Bpp) when Bpp == 4 -> defilter_sub_4(Row, 0, 0, 0, 0, <<>>);
defilter(1, Row, _PrevRow, Bpp) when Bpp == 3 -> defilter_sub_3(Row, 0, 0, 0, <<>>);
defilter(1, Row, _PrevRow, Bpp) -> defilter_sub(Row, Bpp, <<>>);
defilter(2, Row, PrevRow, Bpp) when Bpp == 4 -> defilter_up_4(Row, PrevRow, <<>>);
defilter(2, Row, PrevRow, Bpp) when Bpp == 3 -> defilter_up_3(Row, PrevRow, <<>>);
defilter(2, Row, PrevRow, _Bpp) -> defilter_up(Row, PrevRow, <<>>);
defilter(3, Row, PrevRow, Bpp) when Bpp == 4 -> defilter_avg_4(Row, PrevRow, 0, 0, 0, 0, <<>>);
defilter(3, Row, PrevRow, Bpp) when Bpp == 3 -> defilter_avg_3(Row, PrevRow, 0, 0, 0, <<>>);
defilter(3, Row, PrevRow, Bpp) -> defilter_avg(Row, PrevRow, Bpp, <<>>);
defilter(4, Row, PrevRow, Bpp) when Bpp == 4 -> defilter_paeth_4(Row, PrevRow, 0, 0, 0, 0, 0, 0, 0, 0, <<>>);
defilter(4, Row, PrevRow, Bpp) when Bpp == 3 -> defilter_paeth_3(Row, PrevRow, 0, 0, 0, 0, 0, 0, <<>>);
defilter(4, Row, PrevRow, Bpp) -> defilter_paeth(Row, PrevRow, Bpp, <<>>).

%% FAST DEFILTER USING BINARY MATCHING (Bpp = 4)
defilter_sub_4(<<F1:8, F2:8, F3:8, F4:8, Rest/binary>>, P1, P2, P3, P4, Acc) ->
    R1 = (F1 + P1) band 255,
    R2 = (F2 + P2) band 255,
    R3 = (F3 + P3) band 255,
    R4 = (F4 + P4) band 255,
    defilter_sub_4(Rest, R1, R2, R3, R4, <<Acc/binary, R1:8, R2:8, R3:8, R4:8>>);
defilter_sub_4(<<F:8, Rest/binary>>, P1, P2, P3, P4, Acc) ->
    R1 = (F + P1) band 255,
    defilter_sub_4(Rest, P2, P3, P4, R1, <<Acc/binary, R1:8>>);
defilter_sub_4(<<>>, _, _, _, _, Acc) -> Acc.

defilter_sub_3(<<F1:8, F2:8, F3:8, Rest/binary>>, P1, P2, P3, Acc) ->
    R1 = (F1 + P1) band 255,
    R2 = (F2 + P2) band 255,
    R3 = (F3 + P3) band 255,
    defilter_sub_3(Rest, R1, R2, R3, <<Acc/binary, R1:8, R2:8, R3:8>>);
defilter_sub_3(<<F:8, Rest/binary>>, P1, P2, P3, Acc) ->
    R1 = (F + P1) band 255,
    defilter_sub_3(Rest, P2, P3, R1, <<Acc/binary, R1:8>>);
defilter_sub_3(<<>>, _, _, _, Acc) -> Acc.

defilter_up_4(<<F1:8, F2:8, F3:8, F4:8, RestF/binary>>, <<U1:8, U2:8, U3:8, U4:8, RestU/binary>>, Acc) ->
    defilter_up_4(RestF, RestU, <<Acc/binary, ((F1+U1) band 255):8, ((F2+U2) band 255):8, ((F3+U3) band 255):8, ((F4+U4) band 255):8>>);
defilter_up_4(<<F:8, RestF/binary>>, <<U:8, RestU/binary>>, Acc) ->
    defilter_up_4(RestF, RestU, <<Acc/binary, ((F+U) band 255):8>>);
defilter_up_4(<<>>, _, Acc) -> Acc.

defilter_up_3(<<F1:8, F2:8, F3:8, RestF/binary>>, <<U1:8, U2:8, U3:8, RestU/binary>>, Acc) ->
    defilter_up_3(RestF, RestU, <<Acc/binary, ((F1+U1) band 255):8, ((F2+U2) band 255):8, ((F3+U3) band 255):8>>);
defilter_up_3(<<F:8, RestF/binary>>, <<U:8, RestU/binary>>, Acc) ->
    defilter_up_3(RestF, RestU, <<Acc/binary, ((F+U) band 255):8>>);
defilter_up_3(<<>>, _, Acc) -> Acc.

defilter_avg_4(<<F1:8, F2:8, F3:8, F4:8, RestF/binary>>, <<U1:8, U2:8, U3:8, U4:8, RestU/binary>>, P1, P2, P3, P4, Acc) ->
    R1 = (F1 + ((P1 + U1) bsr 1)) band 255,
    R2 = (F2 + ((P2 + U2) bsr 1)) band 255,
    R3 = (F3 + ((P3 + U3) bsr 1)) band 255,
    R4 = (F4 + ((P4 + U4) bsr 1)) band 255,
    defilter_avg_4(RestF, RestU, R1, R2, R3, R4, <<Acc/binary, R1:8, R2:8, R3:8, R4:8>>);
defilter_avg_4(<<F:8, RestF/binary>>, <<U:8, RestU/binary>>, P1, P2, P3, P4, Acc) ->
    R1 = (F + ((P1 + U) bsr 1)) band 255,
    defilter_avg_4(RestF, RestU, P2, P3, P4, R1, <<Acc/binary, R1:8>>);
defilter_avg_4(<<>>, _, _, _, _, _, Acc) -> Acc.

defilter_avg_3(<<F1:8, F2:8, F3:8, RestF/binary>>, <<U1:8, U2:8, U3:8, RestU/binary>>, P1, P2, P3, Acc) ->
    R1 = (F1 + ((P1 + U1) bsr 1)) band 255,
    R2 = (F2 + ((P2 + U2) bsr 1)) band 255,
    R3 = (F3 + ((P3 + U3) bsr 1)) band 255,
    defilter_avg_3(RestF, RestU, R1, R2, R3, <<Acc/binary, R1:8, R2:8, R3:8>>);
defilter_avg_3(<<F:8, RestF/binary>>, <<U:8, RestU/binary>>, P1, P2, P3, Acc) ->
    R1 = (F + ((P1 + U) bsr 1)) band 255,
    defilter_avg_3(RestF, RestU, P2, P3, R1, <<Acc/binary, R1:8>>);
defilter_avg_3(<<>>, _, _, _, _, Acc) -> Acc.

defilter_paeth_4(<<F1:8, F2:8, F3:8, F4:8, RestF/binary>>, <<U1:8, U2:8, U3:8, U4:8, RestU/binary>>, P1, P2, P3, P4, UP1, UP2, UP3, UP4, Acc) ->
    R1 = (F1 + paeth_predictor(P1, U1, UP1)) band 255,
    R2 = (F2 + paeth_predictor(P2, U2, UP2)) band 255,
    R3 = (F3 + paeth_predictor(P3, U3, UP3)) band 255,
    R4 = (F4 + paeth_predictor(P4, U4, UP4)) band 255,
    defilter_paeth_4(RestF, RestU, R1, R2, R3, R4, U1, U2, U3, U4, <<Acc/binary, R1:8, R2:8, R3:8, R4:8>>);
defilter_paeth_4(<<F:8, RestF/binary>>, <<U:8, RestU/binary>>, P1, P2, P3, P4, UP1, UP2, UP3, UP4, Acc) ->
    R1 = (F + paeth_predictor(P1, U, UP1)) band 255,
    defilter_paeth_4(RestF, RestU, P2, P3, P4, R1, UP2, UP3, UP4, U, <<Acc/binary, R1:8>>);
defilter_paeth_4(<<>>, _, _, _, _, _, _, _, _, _, Acc) -> Acc.

defilter_paeth_3(<<F1:8, F2:8, F3:8, RestF/binary>>, <<U1:8, U2:8, U3:8, RestU/binary>>, P1, P2, P3, UP1, UP2, UP3, Acc) ->
    R1 = (F1 + paeth_predictor(P1, U1, UP1)) band 255,
    R2 = (F2 + paeth_predictor(P2, U2, UP2)) band 255,
    R3 = (F3 + paeth_predictor(P3, U3, UP3)) band 255,
    defilter_paeth_3(RestF, RestU, R1, R2, R3, U1, U2, U3, <<Acc/binary, R1:8, R2:8, R3:8>>);
defilter_paeth_3(<<F:8, RestF/binary>>, <<U:8, RestU/binary>>, P1, P2, P3, UP1, UP2, UP3, Acc) ->
    R1 = (F + paeth_predictor(P1, U, UP1)) band 255,
    defilter_paeth_3(RestF, RestU, P2, P3, R1, UP2, UP3, U, <<Acc/binary, R1:8>>);
defilter_paeth_3(<<>>, _, _, _, _, _, _, _, Acc) -> Acc.

%% FALLBACK DEFILTER FOR BPP != 4
defilter_sub(Row, Bpp, Acc) when byte_size(Acc) < byte_size(Row) ->
    I = byte_size(Acc),
    F = binary:at(Row, I),
    P = if I < Bpp -> 0; true -> binary:at(Acc, I - Bpp) end,
    Raw = (F + P) band 255,
    defilter_sub(Row, Bpp, <<Acc/binary, Raw:8>>);
defilter_sub(_, _, Acc) -> Acc.

defilter_up(Row, PrevRow, Acc) when byte_size(Acc) < byte_size(Row) ->
    I = byte_size(Acc),
    F = binary:at(Row, I),
    U = binary:at(PrevRow, I),
    Raw = (F + U) band 255,
    defilter_up(Row, PrevRow, <<Acc/binary, Raw:8>>);
defilter_up(_, _, Acc) -> Acc.

defilter_avg(Row, PrevRow, Bpp, Acc) when byte_size(Acc) < byte_size(Row) ->
    I = byte_size(Acc),
    F = binary:at(Row, I),
    U = binary:at(PrevRow, I),
    P = if I < Bpp -> 0; true -> binary:at(Acc, I - Bpp) end,
    Raw = (F + ((P + U) bsr 1)) band 255,
    defilter_avg(Row, PrevRow, Bpp, <<Acc/binary, Raw:8>>);
defilter_avg(_, _, _, Acc) -> Acc.

defilter_paeth(Row, PrevRow, Bpp, Acc) when byte_size(Acc) < byte_size(Row) ->
    I = byte_size(Acc),
    F = binary:at(Row, I),
    U = binary:at(PrevRow, I),
    P = if I < Bpp -> 0; true -> binary:at(Acc, I - Bpp) end,
    UP = if I < Bpp -> 0; true -> binary:at(PrevRow, I - Bpp) end,
    Raw = (F + paeth_predictor(P, U, UP)) band 255,
    defilter_paeth(Row, PrevRow, Bpp, <<Acc/binary, Raw:8>>);
defilter_paeth(_, _, _, Acc) -> Acc.

paeth_predictor(A, B, C) ->
    P = A + B - C,
    Pa = abs(P - A),
    Pb = abs(P - B),
    Pc = abs(P - C),
    if (Pa =< Pb) andalso (Pa =< Pc) -> A;
       Pb =< Pc -> B;
       true -> C
    end.

premium_mask(Width, Height) ->
    XStart = Width div 3,
    XEnd = (Width * 2) div 3,
    YStart = Height div 3,
    YEnd = (Height * 2) div 3,
    EmptyPixel = <<0,0,0,0>>,
    SolidPixel = <<0,0,0,255>>,
    RowHorizontal = [0, binary:copy(SolidPixel, Width)],
    Width1 = XStart,
    Width2 = XEnd - XStart + 1,
    Width3 = Width - XEnd - 1,
    Part1 = binary:copy(EmptyPixel, Width1),
    Part2 = binary:copy(SolidPixel, Width2),
    Part3 = binary:copy(EmptyPixel, Width3),
    RowVertical = [0, Part1, Part2, Part3],
    Height1 = YStart,
    Height2 = YEnd - YStart + 1,
    Height3 = Height - YEnd - 1,
    Rows1 = lists:duplicate(Height1, RowVertical),
    Rows2 = lists:duplicate(Height2, RowHorizontal),
    Rows3 = lists:duplicate(Height3, RowVertical),
    erlang:iolist_to_binary([Rows1, Rows2, Rows3]).
