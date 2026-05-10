// ===============================================================
//  Audio "tink" synthesis (PWM on uio[7])
// ===============================================================
//  - Phase accumulator at 25.175 MHz, 24-bit.
//  - Phase increment  = 256 +_idx<<5)  →  ~382..1145 Hz
//  - 6-bit quarter-sine LUT, mirror-extended to a 64-step sine.
//  - Exponential envelope, retriggered to 0xFF on each peg hit
//    (note_toggle edge), then env -= (env>>6)+1 every 4096 clocks.
//  - 6-bit PWM at 25.175MHz/64 ≈ 393 kHz (above the PMOD's 200 kHz
//    recommendation), centred at 32 so silence is 50% duty cycle.
// ---------------------------------------------------------------

`default_nettype none

module audio_gen
(
   input  wire       clk,
   input  wire       rst_n,

   input  wire       note_toggle,
   input  wire [3:0] pitch_idx,
   output wire       pwm_out
);

    // ======================================================
    // Cross from frame-domain note_toggle to a 1-cycle pulse
    // ======================================================
    reg note_toggle_d;
    wire new_note_pulse = note_toggle ^ note_toggle_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            note_toggle_d <= 1'b0;
        else 
            note_toggle_d <= note_toggle;
    end

    // ======================================================
    // Phase accumulator
    // ======================================================
    wire [9:0 ] phase_inc = 10'd256 + ({6'd0, pitch_idx} << 5);
    reg  [23:0] phase_acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            phase_acc <= 24'd0;
        else
            phase_acc <= phase_acc + {14'd0, phase_inc};
    end

    // ======================================================
    // Sine: top 6 bits of phase index a 64-step sine
    // ======================================================
    wire [1:0] quadrant = phase_acc[23:22];
    wire [3:0] qphase   = phase_acc[21:18];
    wire [3:0] sin_idx  = quadrant[0] ? (4'd15 - qphase) : qphase;

    reg [4:0] sin_q;     // quarter-wave magnitude, 0..31
    always @(*) begin
        case (sin_idx)
            4'd0:  sin_q = 5'd0;
            4'd1:  sin_q = 5'd3;
            4'd2:  sin_q = 5'd6;
            4'd3:  sin_q = 5'd9;
            4'd4:  sin_q = 5'd12;
            4'd5:  sin_q = 5'd15;
            4'd6:  sin_q = 5'd18;
            4'd7:  sin_q = 5'd20;
            4'd8:  sin_q = 5'd22;
            4'd9:  sin_q = 5'd24;
            4'd10: sin_q = 5'd26;
            4'd11: sin_q = 5'd28;
            4'd12: sin_q = 5'd29;
            4'd13: sin_q = 5'd30;
            4'd14: sin_q = 5'd31;
            default: sin_q = 5'd31;
        endcase
    end
    wire signed [6:0] sine = quadrant[1] ? -$signed({2'b00, sin_q})
                                         :  $signed({2'b00, sin_q});

    // Exponential envelope (retrigger on each peg hit)
    reg [13:0] env_tick;
    reg [7:0]  env;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            env_tick <= 14'd0;
            env      <= 8'd0;
        end else begin
            if (new_note_pulse) begin
                env      <= 8'hFF;
                env_tick <= 14'd0;
            end else begin
                env_tick <= env_tick + 14'd1;
                if (env_tick == 14'h3FFF && env != 8'd0)
                    env <= env - {6'd0, env[7:6]} - 8'd1;
            end
        end
    end

    // sine [-31..+31] * env [0..255] → [-7905..+7905] (signed 14b),
    // shift right 8 → [-30..+30], add 32 → unsigned 6-bit PWM level.
    wire signed [14:0] mod_s    = sine * $signed({1'b0, env});
    wire signed [6:0]  sample_s = mod_s[14:8];
    wire signed [7:0]  pwm_s    = $signed(8'd32) + {sample_s[6], sample_s};
    wire        [5:0]  pwm_lvl  = pwm_s[5:0];

    // 6-bit PWM
    reg [5:0] pwm_cnt;
    reg       pwm_out_r;
    always @(posedge clk) begin
        if (!rst_n) begin
            pwm_cnt   <= 6'd0;
            pwm_out_r <= 1'b0;
        end else begin
            pwm_cnt   <= pwm_cnt + 6'd1;
            pwm_out_r <= (pwm_cnt < pwm_lvl);
        end
    end
    assign pwm_out = pwm_out_r;

endmodule

