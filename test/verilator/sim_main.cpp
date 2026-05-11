// Verilator gate-level testbench for tt_um_pettit_galton.
//
// Drives the synthesised netlist (test/tt_um_pettit_galton.nl.v) with the
// Sky130 standard-cell functional models, runs long enough to settle, then
// captures one VGA frame from uo_out and writes it to frame.ppm (P6).
//
// uo_out bit map (from src/galton.v):
//   [7]=HSync  [6]=B0(msb) [5]=G0(msb) [4]=R0(msb)
//   [3]=VSync  [2]=B1(lsb) [1]=G1(lsb) [0]=R1(lsb)

#include <verilated.h>
#include "Vtt_um_pettit_galton.h"

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

// VGA 640x480 @ 60 Hz on a 25.175 MHz pixel clock (matches galton.v).
static constexpr int H_VISIBLE = 640;
static constexpr int V_VISIBLE = 480;
static constexpr int H_TOTAL   = 800;
static constexpr int V_TOTAL   = 525;
static constexpr int V_SYNC_END = 492;

using Dut = Vtt_um_pettit_galton;

static uint64_t g_time = 0;
double sc_time_stamp() { return static_cast<double>(g_time); }

static inline void tick(Dut* dut) {
    dut->clk = 0; dut->eval(); ++g_time;
    dut->clk = 1; dut->eval(); ++g_time;
}

static inline int vsync_high(Dut* dut)  { return (dut->uo_out >> 3) & 1; }

static void decode_pixel(uint8_t byte, uint8_t& r, uint8_t& g, uint8_t& b) {
    // bit [0] is LSB, bit [4] is MSB for R; same shape for G/B.
    int rv = (((byte >> 0) & 1) << 1) | ((byte >> 4) & 1);
    int gv = (((byte >> 1) & 1) << 1) | ((byte >> 5) & 1);
    int bv = (((byte >> 2) & 1) << 1) | ((byte >> 6) & 1);
    r = static_cast<uint8_t>(rv * 0x55);
    g = static_cast<uint8_t>(gv * 0x55);
    b = static_cast<uint8_t>(bv * 0x55);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    auto dut = std::make_unique<Dut>();

    const char* out_path = "frame.ppm";
    int warmup_frames = 1;
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "-o") && i + 1 < argc) out_path = argv[++i];
        else if (!std::strcmp(argv[i], "--warmup") && i + 1 < argc) warmup_frames = std::atoi(argv[++i]);
    }

    // Initial state + reset
    dut->clk = 0;
    dut->rst_n = 0;
    dut->ena = 1;
    dut->ui_in = 0;
    dut->uio_in = 0;
    for (int i = 0; i < 16; ++i) tick(dut.get());
    dut->rst_n = 1;

    // Let the design run for a few full frames so any startup behaviour settles.
    const uint64_t frame_cycles = static_cast<uint64_t>(H_TOTAL) * V_TOTAL;
    for (uint64_t i = 0; i < frame_cycles * warmup_frames; ++i) tick(dut.get());

    // 1) Synchronise to a clean falling/rising edge of VSync.
    const uint64_t sync_timeout = 2ULL * frame_cycles;
    uint64_t waited = 0;
    while (vsync_high(dut.get()) && waited < sync_timeout) { tick(dut.get()); ++waited; }
    if (waited == sync_timeout) { std::fprintf(stderr, "Timed out waiting for VSync low\n"); return 1; }
    waited = 0;
    while (!vsync_high(dut.get()) && waited < sync_timeout) { tick(dut.get()); ++waited; }
    if (waited == sync_timeout) { std::fprintf(stderr, "Timed out waiting for VSync high\n"); return 1; }

    // 2) Skip the rest of the vertical back porch (lines V_SYNC_END..V_TOTAL-1).
    //    +1 cycle compensates for the 1-clk pipeline delay between h_count and the
    //    registered R/G/B outputs (mirrors the cocotb test).
    const uint64_t back_porch = static_cast<uint64_t>(V_TOTAL - V_SYNC_END) * H_TOTAL + 1;
    for (uint64_t i = 0; i < back_porch; ++i) tick(dut.get());

    // 3) Capture one frame.
    std::vector<uint8_t> rgb(static_cast<size_t>(H_VISIBLE) * V_VISIBLE * 3);
    for (int y = 0; y < V_VISIBLE; ++y) {
        size_t row = static_cast<size_t>(y) * H_VISIBLE * 3;
        for (int x = 0; x < H_VISIBLE; ++x) {
            uint8_t r, g, b;
            decode_pixel(dut->uo_out, r, g, b);
            size_t off = row + static_cast<size_t>(x) * 3;
            rgb[off + 0] = r;
            rgb[off + 1] = g;
            rgb[off + 2] = b;
            tick(dut.get());
        }
        for (int i = 0; i < H_TOTAL - H_VISIBLE; ++i) tick(dut.get());
    }

    // 4) Write a PPM (P6) image — viewable by most image tools and trivial to produce.
    FILE* f = std::fopen(out_path, "wb");
    if (!f) { std::perror(out_path); return 1; }
    std::fprintf(f, "P6\n%d %d\n255\n", H_VISIBLE, V_VISIBLE);
    std::fwrite(rgb.data(), 1, rgb.size(), f);
    std::fclose(f);
    std::printf("Wrote %s (%d x %d)\n", out_path, H_VISIBLE, V_VISIBLE);

    dut->final();
    return 0;
}
