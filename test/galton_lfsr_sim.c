/*
 * galton_lfsr_sim.c
 *
 * Pure-C model of the four XOR-mixed LFSRs and 12-peg deflection
 * sequence used by src/galton.v.  Runs N balls and prints a 13-bin
 * histogram, plus the count and (if any) first ball index that ever
 * landed in the outermost bins (bin 0 = 12 lefts in a row, bin 12 =
 * 12 rights in a row).
 *
 * Build:  gcc -O2 -Wall -o galton_lfsr_sim galton_lfsr_sim.c
 * Run:    ./galton_lfsr_sim [num_balls]      (default 1,000,000)
 *
 * RTL reference (src/galton.v):
 *   reg [6:0]  lfsr;   wire fb  = lfsr [ 6] ^ lfsr [ 5];
 *   reg [10:0] lfsr2;  wire fb2 = lfsr2[10] ^ lfsr2[ 8];
 *   reg [14:0] lfsr3;  wire fb3 = lfsr3[14] ^ lfsr3[13];
 *   reset values: 7'h60, 11'h500, 15'h6000
 *   coin = lfsr[0] ^ lfsr2[0] ^ lfsr3[0]
 *   On each deflect:  lfsrN <= {lfsrN[width-2:0], fbN}  (sample then shift)
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PEGS  12
#define BINS  (PEGS + 1)       /* 13 bins, index = #right deflections */

/* LFSR widths */
#define W1 7
#define W2 11
#define W3 15

#define MASK1 ((1u << W1) - 1u)
#define MASK2 ((1u << W2) - 1u)
#define MASK3 ((1u << W3) - 1u)

static inline uint32_t step(uint32_t s, uint32_t fb_bit, uint32_t mask)
{
    /* RTL: lfsr <= {lfsr[width-2:0], fb}  → left shift, fb into bit 0 */
    return ((s << 1) | (fb_bit & 1u)) & mask;
}

int main(int argc, char **argv)
{
    long n_balls = (argc > 1) ? strtol(argv[1], NULL, 0) : 1000000L;
    if (n_balls <= 0) {
        fprintf(stderr, "num_balls must be > 0\n");
        return 1;
    }

    uint32_t l1 = 0x60u;
    uint32_t l2 = 0x500u;
    uint32_t l3 = 0x6000u;

    uint64_t hist[BINS];
    memset(hist, 0, sizeof hist);

    long first_left  = -1;       /* first ball landing in bin 0  */
    long first_right = -1;       /* first ball landing in bin 12 */
    long left_hits   = 0;
    long right_hits  = 0;

    for (long b = 0; b < n_balls; ++b) {
        int rights = 0;
        for (int p = 0; p < PEGS; ++p) {
            /* Sample coin BEFORE shifting (matches RTL semantics) */
            int coin = (int)((l1 ^ l2 ^ l3) & 1u);
            if (coin) ++rights;

            uint32_t fb1 = ((l1 >>  6) ^ (l1 >>  5)) & 1u;   /* bits  6, 5 */
            uint32_t fb2 = ((l2 >> 10) ^ (l2 >>  8)) & 1u;   /* bits 10, 8 */
            uint32_t fb3 = ((l3 >> 14) ^ (l3 >> 13)) & 1u;   /* bits 14,13 */

            l1 = step(l1, fb1, MASK1);
            l2 = step(l2, fb2, MASK2);
            l3 = step(l3, fb3, MASK3);
        }

        hist[rights]++;
        if (rights == 0) {
            if (first_left  < 0) first_left  = b;
            ++left_hits;
        }
        if (rights == PEGS) {
            if (first_right < 0) first_right = b;
            ++right_hits;
        }
    }

    /* Expected counts under a fair coin (binomial C(12,k) / 4096) */
    static const long binom[BINS] = {
        1, 12, 66, 220, 495, 792, 924, 792, 495, 220, 66, 12, 1
    };

    printf("Balls simulated: %ld\n", n_balls);
    printf("\n bin |   actual  |  expected | act/exp\n");
    printf(" ----+-----------+-----------+--------\n");
    double total = (double)n_balls;
    for (int k = 0; k < BINS; ++k) {
        double exp_k = total * (double)binom[k] / 4096.0;
        double ratio = (exp_k > 0.0) ? (double)hist[k] / exp_k : 0.0;
        printf(" %3d | %9llu | %9.1f |  %5.3f\n",
               k, (unsigned long long)hist[k], exp_k, ratio);
    }

    printf("\nOuter-bin summary:\n");
    printf("  bin  0 (12 lefts):  %ld hits", left_hits);
    if (first_left >= 0)
        printf("   (first at ball #%ld)\n", first_left);
    else
        printf("   NEVER\n");

    printf("  bin 12 (12 rights): %ld hits", right_hits);
    if (first_right >= 0)
        printf("   (first at ball #%ld)\n", first_right);
    else
        printf("   NEVER\n");

    /* Final LFSR state, useful if you want to chain runs. */
    printf("\nFinal LFSR state: l1=0x%02x l2=0x%03x l3=0x%04x\n",
           l1, l2, l3);

    /* ------------------------------------------------------------------
     * Vertical bar chart using Unicode block characters.
     *   - 30 rows tall, one column-group per bin (3-char-wide bar + gap).
     *   - Each row resolves 8 sub-steps via partial block glyphs
     *     ▁▂▃▄▅▆▇█ → ~240 sub-units of dynamic range.
     * ------------------------------------------------------------------ */
    {
        const int rows     = 30;
        const int sub      = 8;            /* sub-steps per row */
        const int bar_w    = 3;            /* glyph width per bar */
        const int gap_w    = 1;
        /* UTF-8 partial-block bytes (height 1/8..7/8). 0 == empty. */
        static const char *partial[8] = {
            " ", "\u2581", "\u2582", "\u2583",
            "\u2584", "\u2585", "\u2586", "\u2587"
        };
        static const char *full = "\u2588";

        uint64_t max_v = 0;
        for (int k = 0; k < BINS; ++k)
            if (hist[k] > max_v) max_v = hist[k];
        if (max_v == 0) max_v = 1;

        int height_sub[BINS];
        for (int k = 0; k < BINS; ++k) {
            /* round-half-up scaling into 0..rows*sub */
            uint64_t num = hist[k] * (uint64_t)(rows * sub) + max_v / 2;
            height_sub[k] = (int)(num / max_v);
        }

        printf("\nHistogram (max bin = %llu):\n",
               (unsigned long long)max_v);

        for (int r = rows - 1; r >= 0; --r) {
            for (int k = 0; k < BINS; ++k) {
                int hs = height_sub[k];
                int row_full   = hs / sub;
                int row_part   = hs % sub;
                /* Tiny but non-zero bins (height rounds to 0 sub-units)
                 * are rendered as "..." on the bottom row so the user
                 * can see the bin was hit at all. */
                if (hs == 0 && hist[k] > 0 && r == 0) {
                    for (int w = 0; w < bar_w; ++w) fputc('_', stdout);
                } else {
                    const char *g;
                    if (r < row_full)            g = full;
                    else if (r == row_full)      g = partial[row_part];
                    else                         g = " ";
                    for (int w = 0; w < bar_w; ++w) fputs(g, stdout);
                }
                for (int w = 0; w < gap_w; ++w) fputc(' ', stdout);
            }
            fputc('\n', stdout);
        }
        /* X axis: hyphen line then 2-digit bin labels under each bar */
        for (int k = 0; k < BINS; ++k) {
            for (int w = 0; w < bar_w; ++w) fputc('-', stdout);
            for (int w = 0; w < gap_w; ++w) fputc('-', stdout);
        }
        fputc('\n', stdout);
        for (int k = 0; k < BINS; ++k) {
            printf("%02d", k);
            for (int w = 2; w < bar_w; ++w) fputc(' ', stdout);
            for (int w = 0; w < gap_w; ++w) fputc(' ', stdout);
        }
        fputc('\n', stdout);
    }

    return 0;
}
