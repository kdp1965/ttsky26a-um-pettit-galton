// =================================================================
//  coin_flip : uses LFSRs to decide Left/Right decision like
//              flipping a coin.
// =================================================================

`default_nettype none

module coin_flip
(
   input  wire       clk,
   input  wire       rst_n,
   input  wire       flip,
   output wire       coin
);

    // ===============================================================
    //  Three coprime LFSRs whose outputs are XOR-mixed.
    // ===============================================================
    reg [6:0]  lfsr;
    reg [10:0] lfsr2;
    reg [14:0] lfsr3;
    wire lfsr_fb  = lfsr[6]  ^ lfsr[5];
    wire lfsr2_fb = lfsr2[10] ^ lfsr2[8];
    wire lfsr3_fb = lfsr3[14] ^ lfsr3[13];

    always @(posedge clk) begin
        if (!rst_n) begin
            lfsr  <= 7'h60;
            lfsr2 <= 11'h500;
            lfsr3 <= 15'h6000;
        end else begin
            if (flip)
            begin
              lfsr  <= {lfsr[5:0],  lfsr_fb};
              lfsr2 <= {lfsr2[9:0],  lfsr2_fb};
              lfsr3 <= {lfsr3[13:0],  lfsr3_fb};
            end
        end
    end
    assign coin = lfsr[0] ^ lfsr2[0] ^ lfsr3[0];

endmodule

