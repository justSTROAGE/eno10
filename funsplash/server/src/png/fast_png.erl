-module(fast_png).
-export([init/0, fast_defilter/5]).
-on_load(init/0).

init() ->
    PrivDir = case code:priv_dir(server) of
        {error, bad_name} ->
            "../../priv";
        Path ->
            Path
    end,
    SoName = filename:join(PrivDir, "fast_png"),
    erlang:load_nif(SoName, 0).

fast_defilter(_PhotoPixels, _Width, _BitDepth, _ColorType, _Bpp) ->
    erlang:nif_error(nif_library_not_loaded).
