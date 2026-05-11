# Verilator gate-level simulation for tt_um_pettit_galton.
#
# Usage:
#   make           # build the simulator
#   make run       # build and capture frame.ppm
#   make clean

TEST_DIR    := $(abspath $(CURDIR))
NETLIST     := $(TEST_DIR)/tt_um_pettit_galton.nl.v
SKY130_LIB  := $(TEST_DIR)/sky130_fd_sc_hd.v
PRIMITIVES  := $(TEST_DIR)/primitives.v

TOP         := tt_um_pettit_galton
OBJ_DIR     := obj_dir
BIN         := $(OBJ_DIR)/V$(TOP)

WARMUP      ?= 1

# FUNCTIONAL    -> use the behavioural cell models (no SDF timing).
# UNIT_DELAY=   -> drop the unit-delay annotations (Verilator ignores delays).
DEFINES := \
    +define+FUNCTIONAL \
    +define+UNIT_DELAY=

# Suppress noisy warnings that come from the auto-generated PDK Verilog.
WARN_FLAGS := \
    -Wno-fatal \
    -Wno-MULTITOP \
    -Wno-UNOPTFLAT \
    -Wno-WIDTH \
    -Wno-CASEINCOMPLETE \
    -Wno-UNUSED \
    -Wno-UNDRIVEN \
    -Wno-PINMISSING \
    -Wno-IMPLICIT \
    -Wno-SELRANGE \
    -Wno-TIMESCALEMOD \
    -Wno-STMTDLY \
    -Wno-INITIALDLY \
    -Wno-MULTIDRIVEN \
    -Wno-LATCH \
    -Wno-COMBDLY \
    -Wno-DECLFILENAME \
    -Wno-EOFNEWLINE

VERILATOR_FLAGS := \
    --cc --exe --build -j 0 \
    --top-module $(TOP) \
    --no-timing \
    -O2 -CFLAGS "-O2 -std=c++17" \
    $(WARN_FLAGS) $(DEFINES)

SOURCES := $(PRIMITIVES) $(SKY130_LIB) $(NETLIST) sim_main.cpp

all: $(BIN)

$(BIN): sim_main.cpp $(NETLIST) $(SKY130_LIB) $(PRIMITIVES)
	verilator $(VERILATOR_FLAGS) $(SOURCES)

run: $(BIN)
	$(BIN) -o frame.ppm --warmup $(WARMUP)

clean:
	rm -rf $(OBJ_DIR) frame.ppm

.PHONY: all run clean
