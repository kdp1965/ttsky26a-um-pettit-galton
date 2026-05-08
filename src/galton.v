// =================================================================
//  tt_um_pettit_galton : Galton Board / Plinko VGA Demo
//
//  Drops one "steel ball" at a time through a 13-row diamond peg
//  array. At each peg the ball randomly deflects left or right.
//  After the final row it falls into one of 14 collection bins,
//  building a histogram that approximates a binomial / Gaussian
//  distribution. After 16 balls have landed the histogram is
//  briefly displayed, then cleared, and the cycle repeats.
//
//  Target: 2-tile TinyTapeout (1x2). VGA timing is 640x480@60Hz
//  on the standard TinyVGA PMOD pinout.
//
//  Geometry (all in screen pixels):
//    - Playfield x  : 96..543 (448 wide, 14 bins x 32 px)
//    - Side rails   : 94..95 and 544..545 (2 px white)
//    - Peg rows     : y = 40 + r*32, r = 0..12 (13 rows)
//    - Peg columns  : x = 320 + slot*16, slot ∈ {-r,-r+2,...,r}
//    - Bin floor    : y = 476 (white line)
//    - Bin bars     : grow from y=476 upward, 2 px per ball
//                     (16 balls × 2 px = 32 px max)
//
//  Ball state (slot lattice, 1 ball in flight):
//    - ball_y[9:0]    : pixel y, advances 2 px / frame
//    - slot[4:0]signed: -13..+13, step ±1 per peg row
//    - stage[3:0]     : pegs hit so far (0..13)
//
//  When ball_y crosses the next peg row (40 + stage*32) the LFSR
//  decides the deflection. After 13 deflections the ball falls
//  vertically until it lands on top of its bin's bar.
// =================================================================
`default_nettype none

module tt_um_pettit_galton
(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,   // VGA PMOD outputs
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ---------------------------------------------------------------
    //  VGA Timing: 640x480 @ 60Hz (25.175 MHz pixel clock)
    // ---------------------------------------------------------------
    reg [9:0] h_count;
    reg [9:0] v_count;
    reg [1:0] R, G, B;

    always @(posedge clk) begin
        if (!rst_n) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if (h_count == 799) begin
                h_count <= 0;
                if (v_count == 524) v_count <= 0;
                else                v_count <= v_count + 1;
            end else h_count <= h_count + 1;
        end
    end

    wire video_active = (h_count < 640) && (v_count < 480);
    wire hsync = ~(h_count >= 656 && h_count < 752);
    wire vsync = ~(v_count >= 490 && v_count < 492);

    assign uo_out[7] = hsync;
    assign uo_out[6] = B[0];
    assign uo_out[5] = G[0];
    assign uo_out[4] = R[0];
    assign uo_out[3] = vsync;
    assign uo_out[2] = B[1];
    assign uo_out[1] = G[1];
    assign uo_out[0] = R[1];

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    wire frame_end = (h_count == 799) && (v_count == 524);
    wire deflect_trigger;

    // ---------------------------------------------------------------
    //  Two coprime LFSRs whose outputs are XOR-mixed.  A single 16-bit
    //  LFSR sampled at fixed per-ball intervals only has ~65k reachable
    //  13-bit deflection sequences, so all-left / all-right runs are
    //  effectively unreachable and the extreme bins never fill.
    //  Combining a 16-bit (taps 16,14,13,11) and a 17-bit (taps 17,14)
    //  maximal LFSR gives a period of (2^16-1)*(2^17-1) ~ 8.6e9 and
    //  removes the structural correlation.
    // ---------------------------------------------------------------
    reg [16:0] lfsr;
    wire lfsr_fb = lfsr[16] ^ lfsr[13];
    always @(posedge clk) begin
        if (!rst_n) begin
            lfsr <= 17'h12000;
        end else begin
            if (deflect_trigger)
              lfsr  <= {lfsr[16:0],  lfsr_fb};
        end
    end
    wire coin = lfsr[0];

    // ---------------------------------------------------------------
    //  Game State Machine
    // ---------------------------------------------------------------
    localparam [1:0] PH_FALL  = 2'd0;
    localparam [1:0] PH_PSHRT = 2'd1;
    localparam [1:0] PH_PLONG = 2'd2;

    reg [1:0]        phase;
    reg [9:0]        ball_y;
    reg [9:0]        ball_x_pix;    // pixel x offset from 320 (slides toward slot*16)
    wire [9:0]       ball_x_off;
    reg [3:0]        stage;         // 0..13 pegs hit
//    reg [5:0]        ball_count;    // 0..16
    reg [7:0]        pause_count;

    // 14 histogram bins, 5 bits each (max 16)
    reg [4:0] hist0,  hist1,  hist2,  hist3,
              hist4,  hist5,  hist6,  hist7,
              hist8,  hist9,  hist10, hist11,
              hist12;

    // bin index from final slot: ball_x_pix - left_edge (96) / 32 (slot size)
    wire [3:0] bin_idx;
    assign ball_x_off = ball_x_pix - 96;
    assign bin_idx    = ball_x_off[8:5];

    // current count for the bin the ball is heading into
    reg [4:0] cur_hist;
    always @(*) begin
        case (bin_idx)
            4'd0:  cur_hist = hist0;
            4'd1:  cur_hist = hist1;
            4'd2:  cur_hist = hist2;
            4'd3:  cur_hist = hist3;
            4'd4:  cur_hist = hist4;
            4'd5:  cur_hist = hist5;
            4'd6:  cur_hist = hist6;
            4'd7:  cur_hist = hist7;
            4'd8:  cur_hist = hist8;
            4'd9:  cur_hist = hist9;
            4'd10: cur_hist = hist10;
            4'd11: cur_hist = hist11;
            default: cur_hist = hist12;
        endcase
    end

    // Landing y = 472 - 2*cur_hist  (ball center sits on bar top)
    wire [9:0] landing_y = 10'd472 - {4'd0, cur_hist, 1'b0};

    // Y at which the ball first "touches" the peg in row `stage` from above.
    // Ball radius 8 + peg radius 3 = 11 px between centres at contact.
    wire [9:0] next_touch_y = 10'd32 + ({6'd0, stage} << 5);   // 40 - 11 + stage*32

    wire at_target = (ball_x_pix == target_x_pix);

    assign deflect_trigger = (phase == PH_FALL) && (stage < 4'd12)
                           && at_target && (ball_y >= next_touch_y);
    wire land_trigger    = (phase == PH_FALL) && (stage == 4'd12)
                           && at_target && (ball_y >= landing_y);

    // Target x = slot * 16 (signed). Ball slides 1 px/frame toward target,
    // giving a 45° diagonal between pegs (ball_y moves 2 px/frame, columns
    // 16 px apart, peg rows 32 px apart → 16 frames per row, 16 px slide).
    //wire signed [9:0] target_x_pix = {{5{slot[4]}}, slot} <<< 4;
    reg  [9:0] target_x_pix;
 
    always @(posedge clk) begin
        if (!rst_n) begin
            phase       <= PH_FALL;
            ball_y      <= 0;
            ball_x_pix  <= 320;
            target_x_pix <= 320;
            stage       <= 0;
//            ball_count  <= 0;
            pause_count <= 0;
            hist0  <= 0; hist1  <= 0; hist2  <= 0; hist3  <= 0;
            hist4  <= 0; hist5  <= 0; hist6  <= 0; hist7  <= 0;
            hist8  <= 0; hist9  <= 0; hist10 <= 0; hist11 <= 0;
            hist12 <= 0;;
        end else if (frame_end) begin
            case (phase)
            PH_FALL: begin
                // Ball alternates between two motion modes:
                //   - sliding horizontally (when not yet at slot's column)
                //   - falling vertically  (when at slot's column)
                // This makes the peg "catch" the ball: descent stops while
                // the ball slides off to its new column.
                if (!at_target) begin
                    if (ball_x_pix < target_x_pix)
                        ball_x_pix <= ball_x_pix + 10'sd2;
                    else
                        ball_x_pix <= ball_x_pix - 10'sd2;
                end else if (deflect_trigger) begin
                    ball_y <= next_touch_y;          // snap to contact y
                    stage  <= stage + 4'd1;
                    target_x_pix <= coin ? ball_x_pix + 16 : ball_x_pix - 16;
                end else if (land_trigger) begin
                    ball_y <= landing_y;             // snap to landing y
                    case (bin_idx)
                        4'd0:  hist0  <= cur_hist + 5'd1;
                        4'd1:  hist1  <= cur_hist + 5'd1;
                        4'd2:  hist2  <= cur_hist + 5'd1;
                        4'd3:  hist3  <= cur_hist + 5'd1;
                        4'd4:  hist4  <= cur_hist + 5'd1;
                        4'd5:  hist5  <= cur_hist + 5'd1;
                        4'd6:  hist6  <= cur_hist + 5'd1;
                        4'd7:  hist7  <= cur_hist + 5'd1;
                        4'd8:  hist8  <= cur_hist + 5'd1;
                        4'd9:  hist9  <= cur_hist + 5'd1;
                        4'd10: hist10 <= cur_hist + 5'd1;
                        4'd11: hist11 <= cur_hist + 5'd1;
                        default: hist12 <= cur_hist + 5'd1;
                    endcase
//                    ball_count  <= ball_count + 6'd1;
                    pause_count <= 0;
//                    phase <= (ball_count == 6'd63) ? PH_PLONG : PH_PSHRT;
                    phase <= (cur_hist == 5'd31) ? PH_PLONG : PH_PSHRT;
                end else begin
                    if (!ui_in[0] || ball_y > 25)
                    ball_y <= ball_y + 10'd6;        // free fall
                end
            end

            PH_PSHRT: begin
                pause_count <= pause_count + 8'd1;
                if (pause_count >= 8'd30) begin
                    ball_y     <= 5;
                    ball_x_pix <= 320;
                    target_x_pix <= 320;
                    stage      <= 0;
                    phase      <= PH_FALL;
                end
            end

            PH_PLONG: begin
                pause_count <= pause_count + 8'd1;
                if (pause_count >= 8'd180) begin
                    ball_y     <= 0;
                    ball_x_pix <= 320;
                    target_x_pix <= 320;
                    stage      <= 0;
//                    ball_count <= 0;
                    hist0  <= 0; hist1  <= 0; hist2  <= 0; hist3  <= 0;
                    hist4  <= 0; hist5  <= 0; hist6  <= 0; hist7  <= 0;
                    hist8  <= 0; hist9  <= 0; hist10 <= 0; hist11 <= 0;
                    hist12 <= 0;
                    phase  <= PH_FALL;
                end
            end

            default: phase <= PH_FALL;
            endcase
        end
    end

    // ===============================================================
    //  Pixel Rendering  (combinational from h_count, v_count, state)
    // ===============================================================

    // Playfield bounds & frame
    wire in_pf      = (h_count >= 10'd96) && (h_count < 10'd544)
                      && (v_count < 10'd480);
    wire side_rail  = ((h_count == 10'd94) || (h_count == 10'd95)
                    || (h_count == 10'd544) || (h_count == 10'd545))
                      && (v_count < 10'd480);
    wire bin_floor  = in_pf && (v_count == 10'd476);

    // ----------- Peg Hit Test --------------------------------------
    // Peg lattice: row r at y = 40 + r*32; pegs at slot ∈ {-r,…,r}
    // step 2, x = 320 + slot*16. Even rows have pegs on x≡0 (mod 32
    // relative to centre); odd rows on x≡16.
    //
    // Use origin at y=24 (16 px above peg row 0) so that the full
    // top half of peg row 0 is within the non-negative range and
    // gets rendered.
    wire [9:0] pfy        = v_count - 10'd24;          // valid when v >= 24
    wire       pfy_valid  = (v_count >= 10'd24) && (v_count < 10'd420);
    wire [3:0] nr         = pfy[8:5];                  // nearest peg row 0..12
    wire [4:0] yir        = pfy[4:0];                  // 0..31, 16 = on peg row
    wire signed [5:0] dy_s = $signed({1'b0, yir}) - 6'sd16;
    wire [4:0] dy_abs_p   = dy_s[5] ? (~dy_s[4:0] + 5'd1) : dy_s[4:0]; // 0..16
    wire       nr_valid   = (nr <= 4'd12);

    // Horizontal: shift x for odd rows so target is multiple of 32
    wire signed [10:0] hp      = $signed({1'b0, h_count}) - 11'sd320;
    wire signed [10:0] hp_adj  = hp - (nr[0] ? 11'sd16 : 11'sd0);
    wire signed [10:0] hp_p16  = hp_adj + 11'sd16;
    wire        [4:0]  hp_mod  = hp_p16[4:0];
    wire signed [5:0]  dx_s    = $signed({1'b0, hp_mod}) - 6'sd16;
    wire        [4:0]  dx_abs_p = dx_s[5] ? (~dx_s[4:0] + 5'd1)
                                          : dx_s[4:0];

    // Slot of nearest peg (for range check)
    wire signed [10:0] peg_k    = hp_p16 >>> 5;        // arith shift
    wire signed [5:0]  peg_slot = {peg_k[4:0], 1'b0} + {5'd0, nr[0]};
    wire        [5:0]  peg_slot_abs = peg_slot[5] ? (~peg_slot + 6'sd1)
                                                  : peg_slot;
    wire peg_in_range = (peg_slot_abs <= {2'd0, nr});

    // Filled circle, radius 3 (dx²+dy² ≤ 9)
    wire [8:0] dx_sq = dx_abs_p * dx_abs_p;
    wire [8:0] dy_sq = dy_abs_p * dy_abs_p;
    wire is_peg = in_pf && pfy_valid && nr_valid && peg_in_range
               && ((dx_abs_p + dy_abs_p) <= 10'd2);

    // ----------- Active Ball Rendering -----------------------------
    // Ball x = 320 + ball_x_pix  (pixel-accurate, slides between pegs)
    //wire signed [10:0] ball_x_s = 11'sd320 + {ball_x_pix[9], ball_x_pix};
    wire signed [10:0] ball_x_s = ball_x_pix;

    wire signed [10:0] dxb = $signed({1'b0, h_count}) - ball_x_s;
    wire signed [10:0] dyb = $signed({1'b0, v_count}) - $signed({1'b0, ball_y});
    wire        [10:0] dxb_abs = dxb[10] ? (~dxb + 11'sd1) : dxb;
    wire        [10:0] dyb_abs = dyb[10] ? (~dyb + 11'sd1) : dyb;

    // Clip to small to avoid huge multipliers
    wire [4:0] dxb_s = (dxb_abs > 11'd10) ? 5'd10 : dxb_abs[4:0];
    wire [4:0] dyb_s = (dyb_abs > 11'd10) ? 5'd10 : dyb_abs[4:0];
    wire [9:0] ball_dist_sq = dxb_s*dxb_s + dyb_s*dyb_s;

    wire ball_visible = (phase == PH_FALL);
    wire is_ball = ball_visible && in_pf
                && (dxb_abs <= 11'd9) && (dyb_abs <= 11'd9)
                && (ball_dist_sq <= 10'd32);     // radius 8 (diameter 16)

    // ----------- Histogram Bars ------------------------------------
    wire [9:0] hbin_off = h_count - 10'd80;             // 0..447
    wire [3:0] hbin     = hbin_off[8:5];                // 0..13
    wire [4:0] hbin_x   = hbin_off[4:0];                // 0..31

    reg [4:0] hist_for_bin;
    always @(*) begin
        case (hbin)
            4'd0:  hist_for_bin = hist0;
            4'd1:  hist_for_bin = hist1;
            4'd2:  hist_for_bin = hist2;
            4'd3:  hist_for_bin = hist3;
            4'd4:  hist_for_bin = hist4;
            4'd5:  hist_for_bin = hist5;
            4'd6:  hist_for_bin = hist6;
            4'd7:  hist_for_bin = hist7;
            4'd8:  hist_for_bin = hist8;
            4'd9:  hist_for_bin = hist9;
            4'd10: hist_for_bin = hist10;
            4'd11: hist_for_bin = hist11;
            default: hist_for_bin = hist12;
        endcase
    end

    wire [9:0] bar_top   = 10'd476 - {4'd0, hist_for_bin, 1'b0};
    wire       in_bar_y  = (v_count >= bar_top) && (v_count < 10'd476);
    wire       in_bar_x  = (hbin_x >= 5'd3) && (hbin_x < 5'd29);
    wire       is_bar    = in_pf && in_bar_y && in_bar_x
                        && (hist_for_bin != 5'd0);

    // Faint vertical bin separators below the peg field
    wire bin_sep = in_pf && (v_count >= 10'd410) && (v_count < 10'd476)
                && (hbin_x == 5'd0);

    // ===============================================================
    //  Color Composition
    // ===============================================================
    always @(posedge clk) begin
        if (!video_active) begin
            R <= 2'd0; G <= 2'd0; B <= 2'd0;
        end else if (side_rail || bin_floor) begin
            R <= 2'd3; G <= 2'd3; B <= 2'd3;        // bright frame
        end else if (is_ball) begin
            R <= 2'd3; G <= 2'd3; B <= 2'd3;        // white ball
        end else if (is_peg) begin
            R <= 2'd2; G <= 2'd2; B <= 2'd3;        // light blue pegs
        end else if (is_bar) begin
            R <= 2'd2; G <= 2'd2; B <= 2'd2;        // gray bars
        end else if (bin_sep) begin
            R <= 2'd1; G <= 2'd1; B <= 2'd1;        // dim separator
        end else begin
            R <= 2'd0; G <= 2'd0; B <= 2'd0;
        end
    end

    wire _unused = &{ena, ui_in, uio_in, 1'b0};

endmodule

