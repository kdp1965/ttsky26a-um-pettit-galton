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
//  Target: 4-tile TinyTapeout (2x2). VGA timing is 640x480@60Hz
//  on the standard TinyVGA PMOD pinout.
//
//  Geometry (all in screen pixels):
//    - Playfield x  : 96..543 (448 wide, 13 bins x 32 px)
//    - Side rails   : 94..95 and 544..545 (2 px white)
//    - Peg rows     : y = 40 + r*32, r = 0..12 (13 rows)
//    - Peg columns  : x = 320 + slot*16, slot ∈ {-r,-r+2,...,r}
//    - Bin floor    : y = 476 (white line)
//    - Bin bars     : grow from y=476 upward, 2 px per ball
//                     (16 balls × 2 px = 32 px max)
//
//  Ball state (slot lattice, 1 ball in flight):
//    - ball_y[9:0]    : pixel y, advances 2 px / frame
//    - stage[3:0]     : pegs hit so far (0..12)
//
//  When ball_y crosses the next peg row (40 + stage*32) the LFSR
//  decides the deflection. After 12 deflections the ball falls
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
    wire is_bitmap = h_count > 0 && h_count < 91 && v_count > 0 && v_count < 92;
    wire is_namemap = h_count > 0 && h_count < 91 && v_count > 93 && v_count < 133;
    reg  half_frame;
    reg  quarter_frame;
    reg  insane;
    reg  frame_end;

    assign uo_out[7] = hsync;
    assign uo_out[6] = B[0];
    assign uo_out[5] = G[0];
    assign uo_out[4] = R[0];
    assign uo_out[3] = vsync;
    assign uo_out[2] = B[1];
    assign uo_out[1] = G[1];
    assign uo_out[0] = R[1];

    // uio_out[7] is audio PWM (driven by the audio block at the bottom).
    // All other uio bits are unused outputs.
    wire pwm_out;
    assign uio_out = {pwm_out, 7'b0};
    assign uio_oe  = 8'b1000_0000;

    wire deflect_trigger;

    // ===============================================================
    // Instantiate the gampad controller
    // ===============================================================
    wire gamepad_is_present;
    wire gamepad_b;
    wire gamepad_y;
    wire gamepad_select;
    wire gamepad_start;
    wire gamepad_up;
    wire gamepad_down;
    wire gamepad_left;
    wire gamepad_right;
    wire gamepad_a;
    wire gamepad_x;
    wire gamepad_l;
    wire gamepad_r;

    gamepad_pmod_single gamepad
    (
        // Inputs:
        .rst_n      ( rst_n              ),
        .clk        ( clk                ),
        .pmod_data  ( ui_in[6]           ),
        .pmod_clk   ( ui_in[5]           ),
        .pmod_latch ( ui_in[4]           ),
  
        // Outputs:
        .is_present ( gamepad_is_present ),
        .b          ( gamepad_b          ),
        .y          ( gamepad_y          ),
        .select     ( gamepad_select     ),
        .start      ( gamepad_start      ),
        .up         ( gamepad_up         ),
        .down       ( gamepad_down       ),
        .left       ( gamepad_left       ),
        .right      ( gamepad_right      ),
        .a          ( gamepad_a          ),
        .x          ( gamepad_x          ),
        .l          ( gamepad_l          ),
        .r          ( gamepad_r          )
    );

    // ===============================================================
    //  Three coprime LFSRs whose outputs are XOR-mixed.
    // ===============================================================
    wire    coin;
    wire    flip;
    reg     far_out;
    reg     far_out_p0;
    reg     far_out_p1;

    coin_flip coin_flip_i
    (
        .clk        ( clk                ),
        .rst_n      ( rst_n              ),
        .flip       ( flip &!far_out     ),
        .coin       ( coin               )
    );

    // ===============================================================
    //  Game State Machine
    // ===============================================================
    localparam [1:0] PH_FALL  = 2'd0;
    localparam [1:0] PH_PSHRT = 2'd1;
    localparam [1:0] PH_PLONG = 2'd2;

    reg [1:0]        phase;
    reg [9:0]        ball_y;
    reg [9:0]        ball_x;
    wire [9:0]       ball_x_off;
    reg [3:0]        stage;         // 0..12 pegs hit
    reg [1:0]        pause_count;
    reg [3:0]        ball_speed;
    reg              faster_p1;
    reg              slower_p1;
    reg [12:0]       rom_addr;
    wire [1:0]       rom_color;
    reg  [1:0]       rom_color_r;
    wire             name_pix;
    reg              name_pix_r;

    // ---- Pinball-style nudge: left/right gamepad buttons ----------
    // The user can "nudge" the the top 2 decision points
    wire nudge_left  = stage < 4'h2 && gamepad_left;
    wire nudge_right = stage < 4'h2 && gamepad_right;

    assign flip = (phase == PH_PSHRT) | deflect_trigger | ui_in[0] | gamepad_a | gamepad_left | gamepad_right;

    // Cumulative ball-drop counter, displayed top-right as 4 BCD digits
    // (0000..9999, wraps).  Increments every time a ball lands in a bin,
    // and is NOT cleared when the histogram is reset between cycles.
    reg [15:0]       drop_bcd;      // {hundreds, tens, units}

    // ---- Audio "tink" state -----------------------------------------
    //   - last_dir : direction of previous deflection (0=L, 1=R)
    //   - pitch_idx: 0..15, increments when ball continues same dir,
    //                resets to 0 on direction change OR new ball.
    //   - note_toggle: flipped on every peg hit.  Edge-detected in the
    //                  pixel-clock audio block to (re)trigger envelope.
    reg              last_dir;
    reg [3:0]        pitch_idx;
    reg              note_toggle;

    // ---- Scaled histogram display (gamepad B toggle) ----------------
    reg              show_histogram;
    reg              b_p1;

    // 14 histogram bins, up to 10 bits each (max 1023).  Outer bins
    // have fewer bits (likely still too many)
    reg [6:0] hist0, hist1, hist11, hist12;
    reg [8:0] hist2, hist10;
    reg [9:0] hist3, hist4,  hist5,  hist6,
              hist7, hist8,  hist9;
    reg [2:0] scale_bits;
    wire      hist_b9 = hist4[9] | hist5[9] | hist6[9] | hist7[9] | hist8[9];
    wire      hist_b8 = hist4[8] | hist5[8] | hist6[8] | hist7[8] | hist8[8];
    wire      hist_b7 = hist4[7] | hist5[7] | hist6[7] | hist7[7] | hist8[7];
    wire      hist_b6 = hist4[6] | hist5[6] | hist6[6] | hist7[6] | hist8[6];
    wire      hist_b5 = hist4[5] | hist5[5] | hist6[5] | hist7[5] | hist8[5];
    wire      hist_b4 = hist4[4] | hist5[4] | hist6[4] | hist7[4] | hist8[4];

    // bin index from final slot: ball_x - left_edge (96) / 32 (slot size)
    wire [3:0] bin_idx;
    assign ball_x_off = ball_x - 96;
    assign bin_idx    = ball_x_off[8:5]-1;

    // current count for the bin the ball is heading into
    reg [9:0] cur_hist;
    wire [9:0] next_hist = cur_hist == 10'h3ff ? 10'h3ff : cur_hist + 1;
    always @(*) begin
        case (bin_idx)
            4'd0:  cur_hist = {3'h0, hist0};
            4'd1:  cur_hist = {3'h0, hist1};
            4'd2:  cur_hist = {2'h0, hist2};
            4'd3:  cur_hist = hist3;
            4'd4:  cur_hist = hist4;
            4'd5:  cur_hist = hist5;
            4'd6:  cur_hist = hist6;
            4'd7:  cur_hist = hist7;
            4'd8:  cur_hist = hist8;
            4'd9:  cur_hist = hist9;
            4'd10: cur_hist = {2'h0, hist10};
            4'd11: cur_hist = {3'h0, hist11};
            default: cur_hist = {3'h0, hist12};
        endcase
    end

    // Landing y = 472 - 2*cur_hist  (ball center sits on bar top)
    wire [9:0] landing_y = 10'd472 - {4'd0, (|cur_hist[9:6] ? 10'd64 : cur_hist)};

    // Y at which the ball first "touches" the peg in row `stage` from above.
    // Ball radius 8 + peg radius 3 = 11 px between centres at contact.
    wire [9:0] next_touch_y = 10'd32 + ({6'd0, stage} << 5);   // 40 - 11 + stage*32

    // Target x = slot * 16 (signed). Ball slides 1 px/frame toward target,
    // giving a 45° diagonal between pegs (ball_y moves 2 px/frame, columns
    // 16 px apart, peg rows 32 px apart → 16 frames per row, 16 px slide).
    reg  [9:0] target_x_pix;
    wire at_target = (ball_x[9:3] == target_x_pix[9:3]);

    assign deflect_trigger = (phase == PH_FALL) && (stage < 4'd12) && at_target && (ball_y >= next_touch_y);
    wire land_trigger      = (phase == PH_FALL) && (stage == 4'd12) && at_target && (ball_y >= landing_y);
    wire faster            = gamepad_up | ui_in[1];
    wire slower            = gamepad_down | ui_in[2];

    always @(posedge clk) begin
        if (!rst_n) begin
            phase         <= PH_FALL;
            ball_y        <= 0;
            ball_x    <= 320;
            target_x_pix  <= 320;
            stage         <= 0;
            pause_count   <= 0;
            hist0         <= 0; hist1  <= 0; hist2  <= 0; hist3  <= 0;
            hist4         <= 0; hist5  <= 0; hist6  <= 0; hist7  <= 0;
            hist8         <= 0; hist9  <= 0; hist10 <= 0; hist11 <= 0;
            hist12        <= 0;
            drop_bcd      <= 16'hfff0;
            ball_speed    <= 3'd6;
            faster_p1     <= 0;
            slower_p1     <= 0;
            last_dir      <= 1'b0;
            pitch_idx     <= 4'd0;
            note_toggle   <= 1'b0;
            far_out_p1    <= 1'b0;
            far_out       <= 1'b0;
            show_histogram <= 1'b0;
            b_p1          <= 1'b0;
            scale_bits    <= 3'h0;
            frame_end     <= 1'b0;
            half_frame    <= 1'b0;
            quarter_frame <= 1'b0;
            insane        <= 1'b0;
        end else begin
            // Register ROM output bits for better timing
            rom_color_r <= rom_color;
            name_pix_r  <= name_pix;

            // Register frame location detection for better timing
            frame_end     <= (h_count == 799) && (v_count == 524);
            half_frame    <= (h_count == 399) && (v_count == 524) && (ball_speed > 4'd9);
            quarter_frame <= (h_count == 199 || h_count == 599) && (v_count == 524) && (ball_speed > 4'd10);
            insane        <= (h_count[4:0] == 6'h0 && v_count == 524 && ball_speed > 4'd11);

            // Histogram toggle on B button (edge detect)
            b_p1 <= gamepad_b | ui_in[3];
            if ((gamepad_b | ui_in[3]) && !b_p1) begin
                show_histogram <= ~show_histogram;
                scale_bits <= hist_b9 ? 3'h0 : hist_b8 ? 3'h1 : hist_b7 ? 3'h2 :
                              hist_b6 ? 3'h3 : hist_b5 ? 3'h4 : hist_b4 ? 3'h5 : 3'h6;
            end

            // Far Out (put ball in outer bin)
            far_out_p0 <= gamepad_x | ui_in[7];
            if ((gamepad_x | ui_in[7]) & !far_out_p0)
                far_out_p1 <= 1'b1;

            // Process ball drop based on speed and frame position
            if ((frame_end || half_frame || quarter_frame || insane) && !show_histogram) begin
                faster_p1 <= faster;
                slower_p1 <= slower;

                // Make the ball drop faster
                if (faster && !faster_p1 && ball_speed != 12)
                    ball_speed <= ball_speed + 3'h1;

                // Make the ball drop slower
                if (slower && !slower_p1 && ball_speed != 2)
                    ball_speed <= ball_speed - 3'h1;

                // Main FSM ... FALL, Short Pause, Long Pause
                case (phase)
                PH_FALL: begin
                    // Ball alternates between two motion modes:
                    //   - sliding horizontally (when not yet at slot's column)
                    //   - falling vertically  (when at slot's column)
                    // This makes the peg "catch" the ball: descent stops while
                    // the ball slides off to its new column.
                    if (!at_target) begin
                        if (ball_x < target_x_pix)
                            ball_x <= ball_x + (ball_speed > 4'd8 ? 10'sd8 : ball_speed > 4'd7 ? 10'sd4 : 10'sd2);
                        else
                            ball_x <= ball_x - (ball_speed > 4'd8 ? 10'sd8 : ball_speed > 4'd7 ? 10'sd4 : 10'sd2);
                    end else if (deflect_trigger) begin
                        // Ball is at a peg ... decide direction
                        ball_y <= next_touch_y;          // snap to contact y
                        stage  <= stage + 4'd1;
                        // Pinball nudge: Decide the direction of the first 2 pegs
                        if (nudge_left) begin
                            target_x_pix <= ball_x - 16;
                        end else if (nudge_right) begin
                            target_x_pix <= ball_x + 16;
                        end else begin
                            target_x_pix <= coin ? ball_x + 16
                                                 : ball_x - 16;
                        end

                        // ---- Audio "tink": pick direction, update pitch ----
                        // deflect_dir : 0=left, 1=right (matches coin).
                        // First peg of the ball (stage==0) always starts low.
                        // Otherwise: same dir → pitch up (sat), else → reset.
                        note_toggle <= ~note_toggle;
                        last_dir    <= nudge_left  ? 1'b0 :
                                       nudge_right ? 1'b1 : coin;
                        if (stage == 4'd0) begin
                            pitch_idx <= 4'd0;
                        end else if ((nudge_left  ? 1'b0 :
                                      nudge_right ? 1'b1 : coin) == last_dir) begin
                            if (pitch_idx != 4'hF)
                                pitch_idx <= pitch_idx + 4'd1;
                        end else begin
                            pitch_idx <= 4'd0;
                        end
                    end else if (land_trigger) begin
                        // Ball has exited the peg field ... decide a bin
                        case (bin_idx)
                            4'd0:  hist0  <= next_hist[6:0];
                            4'd1:  hist1  <= next_hist[6:0];
                            4'd2:  hist2  <= next_hist[7:0];
                            4'd3:  hist3  <= next_hist;
                            4'd4:  hist4  <= next_hist;
                            4'd5:  hist5  <= next_hist;
                            4'd6:  hist6  <= next_hist;
                            4'd7:  hist7  <= next_hist;
                            4'd8:  hist8  <= next_hist;
                            4'd9:  hist9  <= next_hist;
                            4'd10: hist10 <= next_hist[7:0];
                            4'd11: hist11 <= next_hist[6:0];
                            default: hist12 <= next_hist[6:0];
                        endcase
                        pause_count <= 0;
                        far_out <= 1'b0;
                        phase <= (cur_hist == 10'h3be) ? PH_PLONG : PH_PSHRT;
                        ball_y <= (cur_hist == 10'h3be) ? 0 : landing_y;             // snap to landing y

                        // Ball count ... BCD increment with wrap at 9999
                        if (drop_bcd[3:0] == 4'd9) begin
                            drop_bcd[3:0] <= 4'd0;
                            if (drop_bcd[7:4] == 4'd9) begin
                                drop_bcd[7:4] <= 4'd0;
                                if (drop_bcd[11:8] == 4'd9) begin
                                    drop_bcd[11:8] <= 4'd0;
                                    if (drop_bcd[15:12] == 4'd9)
                                        drop_bcd[15:12] <= 4'd0;
                                    else if (drop_bcd[15:12] == 4'd15)
                                        drop_bcd[15:12] <= 4'd1;
                                    else
                                        drop_bcd[15:12] <= drop_bcd[15:12] + 4'd1;
                                end else if (drop_bcd[11:8] == 4'd15)
                                    drop_bcd[11:8] <= 4'd1;
                                else
                                    drop_bcd[11:8] <= drop_bcd[11:8] + 4'd1;
                            end else if (drop_bcd[7:4] == 4'd15)
                                drop_bcd[7:4] <= 4'd1;
                            else
                                drop_bcd[7:4] <= drop_bcd[7:4] + 4'd1;
                        end else
                            drop_bcd[3:0] <= drop_bcd[3:0] + 4'd1;
                    end else begin
                        // Free fall ... process unles held by gamepad_a or ui_in[0]
                        if ((!gamepad_a && !ui_in[0]) || ball_y > 25)
                          ball_y <= ball_y + {6'h0, ball_speed > 4'd7 ? 4'd8 : ball_speed};        // free fall
                    end
                end
                
                PH_PSHRT: begin
                    // Short Pause
                    pause_count <= pause_count + 2'd1;
                    if (pause_count == 2'd3 || ball_speed > 4'd9) begin
                        ball_y       <= 5;
                        ball_x   <= 320;
                        target_x_pix <= 320;
                        stage        <= 0;
                        phase        <= PH_FALL;
                        if (far_out_p1)
                            far_out <= 1'b1;
                        far_out_p1 <= 1'b0;
                    end
                end
                
                PH_PLONG: begin
                    // Long pause after board fills.  If gamepad is present,
                    // waits for START button to be pressed.  Reuses ball_y
                    // register as the timer to save space since no ball
                    // activity anyway.
                    if (ball_y >= 10'd180) begin
                        if (!gamepad_is_present || gamepad_start) begin
                            ball_y       <= 0;
                            ball_x   <= 320;
                            target_x_pix <= 320;
                            stage        <= 0;
                            drop_bcd     <= 16'hfff0;
                            hist0        <= 0; hist1  <= 0; hist2  <= 0; hist3  <= 0;
                            hist4        <= 0; hist5  <= 0; hist6  <= 0; hist7  <= 0;
                            hist8        <= 0; hist9  <= 0; hist10 <= 0; hist11 <= 0;
                            hist12       <= 0;
                            phase        <= PH_FALL;
                        end
                    end
                    else
                        ball_y <= ball_y + 10'd1;
                end
                
                default: phase <= PH_FALL;
                endcase
            end
            else if (v_count < 133) begin
                // Register the ROM address
                if (h_count < 90)
                    rom_addr <= rom_addr + 1;
                else if (v_count == 93)
                    rom_addr <= 0;
            end else
                rom_addr <= 0;
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

    // ===============================================================
    // Peg Hit Test 
    // ===============================================================
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

    // Filled circle, radius 2 ...  no squares, just approx since so small
    wire is_peg = in_pf && pfy_valid && nr_valid && peg_in_range &&
                  ((dx_abs_p + dy_abs_p) <= 6'd2);

    // ===============================================================
    // Active Ball Rendering
    // ===============================================================
    // Signed ball location for rendering
    wire signed [10:0] ball_x_s = {1'b0, ball_x};
    wire signed [10:0] dxb = $signed({1'b0, h_count}) - ball_x_s;
    wire signed [10:0] dyb = $signed({1'b0, v_count}) - $signed({1'b0, ball_y});
    wire        [10:0] dxb_abs = dxb[10] ? (~dxb + 11'sd1) : dxb;
    wire        [10:0] dyb_abs = dyb[10] ? (~dyb + 11'sd1) : dyb;
    wire               ball_visible = (phase == PH_FALL);

    // 10x10 ball bitmap (replaces multipliers/adder/compare):
    //         0001111000
    //         0111111110
    //         0111111110
    //         1111111111
    //         1111111111
    //         1111111111
    //         1111111111
    //         0111111110
    //         0111111110
    //         0001111000
    //
    // Bitmap is symmetric in both axes. Fold to a 5x5 quarter:
    //   mx\my  0  1  2  3  4
    //     0:   1  1  1  1  1
    //     1:   1  1  1  1  1
    //     2:   1  1  1  1  0
    //     3:   1  1  1  1  0
    //     4:   1  1  0  0  0
    //
    // Mirror coords for even-size sprite (dx -5..+4 → mx 0..4)
    wire [3:0] ball_mx = dxb[10] ? (dxb_abs[3:0] - 4'd1) : dxb_abs[3:0];
    wire [3:0] ball_my = dyb[10] ? (dyb_abs[3:0] - 4'd1) : dyb_abs[3:0];
    wire ball_in_bbox = (dxb[10] ? (dxb_abs <= 11'd5) : (dxb_abs <= 11'd4))
                     && (dyb[10] ? (dyb_abs <= 11'd5) : (dyb_abs <= 11'd4));
    wire ball_shape = (ball_my <= 4'd1)
                   || ((ball_my <= 4'd3) && (ball_mx <= 4'd3))
                   || ((ball_my == 4'd4) && (ball_mx <= 4'd1));
    wire is_ball = ball_visible && in_pf && ball_in_bbox && ball_shape;

    // ===============================================================
    // Bottom bin Histogram Bars
    // ===============================================================
    wire [9:0] hbin_off = h_count - 10'd80;             // 0..447
    wire [3:0] hbin     = hbin_off[8:5];                // 0..13
    wire [4:0] hbin_x   = hbin_off[4:0];                // 0..31

    reg [9:0] hist_for_bin;
    always @(*) begin
        case (hbin)
            4'd1:  hist_for_bin = {3'h0, hist0};
            4'd2:  hist_for_bin = {3'h0, hist1};
            4'd3:  hist_for_bin = {2'h0, hist2};
            4'd4:  hist_for_bin = hist3;
            4'd5:  hist_for_bin = hist4;
            4'd6:  hist_for_bin = hist5;
            4'd7:  hist_for_bin = hist6;
            4'd8:  hist_for_bin = hist7;
            4'd9:  hist_for_bin = hist8;
            4'd10:  hist_for_bin = hist9;
            4'd11: hist_for_bin = {2'h0, hist10};
            4'd12: hist_for_bin = {3'h0, hist11};
            4'd13: hist_for_bin = {3'h0, hist12};
            default: hist_for_bin = 0;
        endcase
    end

    wire [9:0] full_top  = 10'd476 - {4'd0, (|hist_for_bin[9:6] ? 6'd63 : hist_for_bin[5:0])};
    wire [9:0] bar_top   = 10'd476 - {4'd0, hist_for_bin[5:0]};
    wire       in_bar_y  = (v_count >= bar_top) && (v_count < 10'd476);
    wire       in_full_y = (v_count >= full_top) && (v_count < 10'd476);
    wire       in_bar_x  = (hbin_x >= 5'd3) && (hbin_x < 5'd29);
    wire       is_bar    = in_pf && in_bar_y && in_bar_x && (hist_for_bin != 10'd0);
    wire       is_full   = in_pf && in_full_y && in_bar_x && (|hist_for_bin[9:6]);

    // Faint vertical bin separators below the peg field
    wire bin_sep = in_pf && (v_count >= 10'd410) && (v_count < 10'd476) && (hbin_x == 5'd0);

    // ===============================================================
    // Scaled Histogram Bars (gamepad B mode)
    // ===============================================================
    // Bars occupy up to 360 pixels (y=116..475), scaled based on the 
    // tallest bin.
    localparam [9:0] HIST_TOP = 10'd116;
    wire [9:0] y_dist       = 10'd476 - v_count;
    wire       in_hist_y    = (v_count >= HIST_TOP) && (v_count < 10'd476);
    wire [9:0] scale_hist   = hist_for_bin << scale_bits;
    wire [9:0] scale_sum    = {2'h0, scale_hist[9:2]} + {3'h0, scale_hist[9:3]};
    wire in_scaled_bar      = in_hist_y && (v_count > 10'd476 - scale_sum);

    // Non-zero bins that scale to zero still get a 1-pixel line
    wire in_min_bar         = (hist_for_bin != 10'd0) && (v_count == 10'd475);
    wire is_hist_bar        = show_histogram && in_pf && in_bar_x && (in_scaled_bar || in_min_bar);

    // ===============================================================
    // Ball-Drop Counter (4 BCD digits, top-right)
    // ===============================================================
    // 3x5 block font scaled 4x: each digit cell is 12x20 px, with a
    // 4 px gap between digits.  Total width = 4*16 - 4 = 60 px.
    // Placed at h_count 580..639, v_count 8..27.
    localparam [9:0] CNT_X0 = 10'd580;
    localparam [9:0] CNT_Y0 = 10'd8;
    wire in_cnt_box = (h_count >= CNT_X0) && (h_count < CNT_X0 + 10'd60)
                   && (v_count >= CNT_Y0) && (v_count < CNT_Y0 + 10'd20);
    wire [9:0] cnt_h     = h_count - CNT_X0;       // 0..59
    wire [9:0] cnt_v     = v_count - CNT_Y0;       // 0..19
    wire [2:0] cnt_digit = {is_full, cnt_h[5:4]};  // 0..3 (h/16)
    wire [3:0] cnt_h_in  = cnt_h[3:0];             // 0..15 within digit slot
    wire       in_cell   = (cnt_h_in < 4'd12);     // last 4 px = inter-digit gap
    wire [1:0] glyph_col = cnt_h_in[3:2];          // 0..2 (h/4 within cell)
    wire [2:0] glyph_row = cnt_v[4:2];             // 0..4 (v/4)

    reg [3:0] cur_digit;
    always @(*) begin
        case (cnt_digit)
            3'd0:    cur_digit = drop_bcd[15:12];  // thousands
            3'd1:    cur_digit = drop_bcd[11:8];   // hundreds
            3'd2:    cur_digit = drop_bcd[7:4];    // tens
            3'd3:    cur_digit = drop_bcd[3:0];    // units
            default: cur_digit = hist_for_bin[9:6];
        endcase
    end

    // ===============================================================
    // 3x5 block font, packed row-major: bit[14]=top-left .. bit[0]=bot-right
    // ===============================================================
    reg [14:0] glyph;
    always @(*) begin
        case (cur_digit)
            4'd0:    glyph = 15'b111_101_101_101_111;
            4'd1:    glyph = 15'b010_110_010_010_111;
            4'd2:    glyph = 15'b111_001_111_100_111;
            4'd3:    glyph = 15'b111_001_011_001_111;
            4'd4:    glyph = 15'b101_101_111_001_001;
            4'd5:    glyph = 15'b111_100_111_001_111;
            4'd6:    glyph = 15'b111_100_111_101_111;
            4'd7:    glyph = 15'b111_001_010_010_010;
            4'd8:    glyph = 15'b111_101_111_101_111;
            4'd9:    glyph = 15'b111_101_111_001_111;
            4'd10:   glyph = 15'b010_101_111_101_101;
            4'd11:   glyph = 15'b110_101_110_101_110;
            4'd12:   glyph = 15'b011_100_100_100_011;
            4'd13:   glyph = 15'b110_101_101_101_110;
            4'd14:   glyph = 15'b111_100_110_100_111;
            4'd15:   glyph = 15'b000_000_000_000_000;
            default: glyph = 15'b0;
        endcase
    end

    wire [3:0] glyph_row3 = {glyph_row, 1'b0} + {1'b0, glyph_row};  // row*3
    wire [3:0] bit_idx     = 4'd14 - glyph_row3 - {2'b0, glyph_col};
    wire       glyph_pixel = glyph[bit_idx];
    wire       is_count    = in_cnt_box && in_cell && glyph_pixel;

    // =======================================================================
    // Display fill level in full bars
    // =======================================================================
    wire [9:0] lcnt_h     = hbin_x-10;
    wire [9:0] lcnt_v     = v_count - 456;
    wire [3:0] lcnt_h_in  = lcnt_h[3:0];             // 0..15 within digit slot
    wire       lin_cell   = hbin_x > 6 && hbin_x < 22 && (lcnt_h_in < 4'd12);     // last 4 px = inter-digit gap
    wire [1:0] lglyph_col = lcnt_h_in[3:2];          // 0..2 (h/4 within cell)
    wire [2:0] lglyph_row = lcnt_v[4:2];             // 0..4 (v/4)
    wire [3:0] lglyph_row3 = {lglyph_row, 1'b0} + {1'b0, lglyph_row};  // row*3
    wire [3:0] lbit_idx     = 4'd14 - lglyph_row3 - {2'b0, lglyph_col};
    wire       lglyph_pixel = glyph[lbit_idx];
    wire       in_level_y  = v_count >= 424 && v_count < 444;
    wire       is_level    = is_full && lin_cell && lglyph_pixel && in_level_y;

    // Mux normal vs. histogram-mode signals for color_gen
    wire final_is_bar    = show_histogram ? is_hist_bar : is_bar;
    wire final_is_full   = show_histogram ? 1'b0 : is_full;
    wire final_is_level  = show_histogram ? 1'b0 : is_level;
    wire final_is_ball   = show_histogram ? 1'b0 : is_ball;
    wire final_is_peg    = show_histogram ? 1'b0 : is_peg;
    wire final_bin_sep   = show_histogram
                         ? (in_pf && (v_count >= HIST_TOP) && (v_count < 10'd476) && (hbin_x == 5'd0))
                         : bin_sep;

    // =======================================================================
    // Side Banners: "TINY" left, "GALTON" right
    // =======================================================================
    // Same 3x5 block font scaled 4x as the BCD counter.  Both banners
    // sit inside the playfield, above peg row 0 (which starts at y=40).
    //   TINY   : 4 letters → 4*16-4 = 60 px wide @ h=100..159
    //   GALTON : 6 letters → 6*16-4 = 92 px wide @ h=448..539
    localparam [9:0] TINY_X0 = 10'd100;
    localparam [9:0] GAL_X0  = 10'd448;
    localparam [9:0] BAN_Y0  = 10'd8;

    wire in_tiny_box = (h_count >= TINY_X0) && (h_count < TINY_X0 + 10'd60)
                    && (v_count >= BAN_Y0)  && (v_count < BAN_Y0 + 10'd20);
    wire in_gal_box  = (h_count >= GAL_X0)  && (h_count < GAL_X0 + 10'd92)
                    && (v_count >= BAN_Y0)  && (v_count < BAN_Y0 + 10'd20);

    wire [9:0] tiny_h    = h_count - TINY_X0;
    wire [9:0] gal_h     = h_count - GAL_X0;
    wire [9:0] ban_v     = v_count - BAN_Y0;
    wire [1:0] tiny_idx  = tiny_h[5:4];                  // 0..3
    wire [2:0] gal_idx   = gal_h[6:4];                 // 0..5
    wire [3:0] ban_h_in  = in_tiny_box ? tiny_h[3:0] : gal_h[3:0];
    wire       ban_in_cell  = (ban_h_in < 4'd12);
    wire [1:0] ban_glyph_col = ban_h_in[3:2];
    wire [2:0] ban_glyph_row = ban_v[4:2];

    // Letter codes shared by both banners
    localparam [2:0] LT_T = 3'd0, LT_I = 3'd1, LT_N = 3'd2, LT_Y = 3'd3,
                     LT_G = 3'd4, LT_A = 3'd5, LT_L = 3'd6, LT_O = 3'd7;

    reg [2:0] cur_letter;
    always @(*) begin
        if (in_tiny_box) begin
            case (tiny_idx)
                2'd0:    cur_letter = LT_T;
                2'd1:    cur_letter = LT_I;
                2'd2:    cur_letter = LT_N;
                default: cur_letter = LT_Y;
            endcase
        end else begin
            case (gal_idx)                                // GALTON
                3'd0:    cur_letter = LT_G;
                3'd1:    cur_letter = LT_A;
                3'd2:    cur_letter = LT_L;
                3'd3:    cur_letter = LT_T;
                3'd4:    cur_letter = LT_O;
                default: cur_letter = LT_N;
            endcase
        end
    end

    // 3x5 block font for letters (row-major, bit[14]=top-left)
    reg [14:0] letter_glyph;
    always @(*) begin
        case (cur_letter)
            LT_T:    letter_glyph = 15'b111_010_010_010_010;
            LT_I:    letter_glyph = 15'b111_010_010_010_111;
            LT_N:    letter_glyph = 15'b101_111_111_111_101;
            LT_Y:    letter_glyph = 15'b101_101_010_010_010;
            LT_G:    letter_glyph = 15'b111_100_101_101_111;
            LT_A:    letter_glyph = 15'b010_101_111_101_101;
            LT_L:    letter_glyph = 15'b100_100_100_100_111;
            default: letter_glyph = 15'b111_101_101_101_111; // O
        endcase
    end

    wire [3:0] ban_row3    = {ban_glyph_row, 1'b0} + {1'b0, ban_glyph_row};
    wire [3:0] ban_bit_idx = 4'd14 - ban_row3 - {2'b0, ban_glyph_col};
    wire       ban_pixel   = letter_glyph[ban_bit_idx];
    wire       is_text     = (in_tiny_box || in_gal_box)
                          && ban_in_cell && ban_pixel;

    // ===============================================================
    // Instantiate the Galton bitmap
    // ===============================================================
    galton_rom rom1
    (
        .addr ( rom_addr  ),
        .out  ( rom_color )
    );

    // ===============================================================
    // Instantiate the "Sir Francis Galton" bitmap
    // ===============================================================
    name_rom rom2
    (
        .addr ( rom_addr[11:0] ),
        .out  ( name_pix       )
    );

    // ===============================================================
    //  Color Composition
    // ===============================================================
    color_gen color_gen_i
    (
       .clk          ( clk          ),
       .rst_n        ( rst_n        ),
       .video_active ( video_active ),
       .is_bitmap    ( is_bitmap    ),
       .is_namemap   ( is_namemap   ),
       .is_side_rail ( side_rail    ),
       .is_bin_floor ( bin_floor    ),
       .is_count     ( is_count     ),
       .is_text      ( is_text      ),
       .is_ball      ( final_is_ball ),
       .is_peg       ( final_is_peg  ),
       .is_full      ( final_is_full ),
       .is_bar       ( final_is_bar  ),
       .is_bin_sep   ( final_bin_sep ),
       .is_level     ( final_is_level ),
       .bitmap_lvl   ( rom_color_r  ),
       .name_pix     ( name_pix_r   ),
       .R            ( R            ),
       .G            ( G            ),
       .B            ( B            )
    );

    // ===============================================================
    //  Audio "tink" generator
    // ===============================================================
    audio_gen audio_gen_i
    (
        .clk         ( clk         ),
        .rst_n       ( rst_n       ),
        .note_toggle ( note_toggle ),
        .pitch_idx   ( pitch_idx   ),
        .pwm_out     ( pwm_out     )
    );

    wire _unused = &{ena, uio_in, 1'b0};

endmodule
