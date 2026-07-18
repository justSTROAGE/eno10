#include <erl_nif.h>
#include <string.h>
#include <stdlib.h>

static inline int paeth_predictor(int a, int b, int c) {
    int p = a + b - c;
    int pa = abs(p - a);
    int pb = abs(p - b);
    int pc = abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

static ERL_NIF_TERM fast_defilter_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary bin;
    int width, bit_depth, color_type, bpp;

    if (!enif_inspect_binary(env, argv[0], &bin) ||
        !enif_get_int(env, argv[1], &width) ||
        !enif_get_int(env, argv[2], &bit_depth) ||
        !enif_get_int(env, argv[3], &color_type) ||
        !enif_get_int(env, argv[4], &bpp)) {
        return enif_make_badarg(env);
    }

    int channels = 1;
    if (color_type == 2) channels = 3;
    else if (color_type == 4) channels = 2;
    else if (color_type == 6) channels = 4;

    int bits_per_row = width * channels * bit_depth;
    int photo_row_bytes = (bits_per_row + 7) / 8;

    ErlNifBinary out_bin;
    if (!enif_alloc_binary(bin.size - (bin.size / (photo_row_bytes + 1)), &out_bin)) {
        return enif_make_badarg(env);
    }

    const unsigned char* in = bin.data;
    unsigned char* out = out_bin.data;
    
    unsigned char* prev_row = (unsigned char*)calloc(photo_row_bytes, 1);
    if (!prev_row) {
        enif_release_binary(&out_bin);
        return enif_make_badarg(env);
    }

    int in_idx = 0;
    int out_idx = 0;

    while (in_idx < bin.size) {
        int filter = in[in_idx++];
        unsigned char* current_row = out + out_idx;

        for (int i = 0; i < photo_row_bytes; i++) {
            int x = in[in_idx + i];
            int a = (i >= bpp) ? current_row[i - bpp] : 0;
            int b = prev_row[i];
            int c = (i >= bpp) ? prev_row[i - bpp] : 0;

            if (filter == 0) {
                current_row[i] = x;
            } else if (filter == 1) {
                current_row[i] = (x + a) & 0xFF;
            } else if (filter == 2) {
                current_row[i] = (x + b) & 0xFF;
            } else if (filter == 3) {
                current_row[i] = (x + ((a + b) / 2)) & 0xFF;
            } else if (filter == 4) {
                current_row[i] = (x + paeth_predictor(a, b, c)) & 0xFF;
            }
        }

        memcpy(prev_row, current_row, photo_row_bytes);
        in_idx += photo_row_bytes;
        out_idx += photo_row_bytes;
    }

    free(prev_row);
    return enif_make_binary(env, &out_bin);
}

static ErlNifFunc nif_funcs[] = {
    {"fast_defilter", 5, fast_defilter_nif}
};

ERL_NIF_INIT(fast_png, nif_funcs, NULL, NULL, NULL, NULL)
