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
//    reg [16:0] lfsr;
    reg [10:0] lfsr2;
    reg [22:0] lfsr3;
//    wire lfsr_fb  = lfsr[16]  ^ lfsr[13];
    wire lfsr2_fb = lfsr2[10] ^ lfsr2[8];
    wire lfsr3_fb = lfsr3[22] ^ lfsr3[17];

    always @(posedge clk) begin
        if (!rst_n) begin
//            lfsr  <= 17'h12000;
            lfsr2 <= 11'h500;
            lfsr3 <= 23'h420000;
        end else begin
            if (flip)
            begin
//              lfsr  <= {lfsr[15:0],  lfsr_fb};
              lfsr2 <= {lfsr2[9:0],  lfsr2_fb};
              lfsr3 <= {lfsr3[21:0],  lfsr3_fb};
            end
        end
    end
//    assign coin = lfsr[0] ^ lfsr2[0] ^ lfsr3[0];
    assign coin = lfsr2[0] ^ lfsr3[0];

endmodule

