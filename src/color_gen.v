// ===============================================================
//  Color Generation module
// ===============================================================
`default_nettype none

module color_gen
(
   input  wire          clk,
   input  wire          rst_n,

   input  wire          video_active,
   input  wire          is_bitmap,
   input  wire          is_namemap,
   input  wire          is_side_rail,
   input  wire          is_bin_floor,
   input  wire          is_count,
   input  wire          is_text,
   input  wire          is_ball,
   input  wire          is_peg,
   input  wire          is_full,
   input  wire          is_bar,
   input  wire          is_level,
   input  wire          is_bin_sep,
   
   input  wire [1:0]    bitmap_lvl,
   input  wire          name_pix,

   output reg  [1:0]    R,
   output reg  [1:0]    G,
   output reg  [1:0]    B
);

    // Count color masking - slight red
    wire [1:0] count_r = {2{is_count}} & 2'd3;
    wire [1:0] count_g = {2{is_count}} & 2'd2;
    wire [1:0] count_b = {2{is_count}} & 2'd2;

    // Bitmap color masking
    wire [1:0] bitmap_r = {2{is_bitmap}} & bitmap_lvl;
    wire [1:0] bitmap_g = {2{is_bitmap}} & bitmap_lvl;
    wire [1:0] bitmap_b = {2{is_bitmap}} & bitmap_lvl;

    // Name Bitmap color masking
    wire [1:0] namemap_r = {2{is_namemap & name_pix}} & 2'd1;
    wire [1:0] namemap_g = {2{is_namemap & name_pix}} & 2'd3;
    wire [1:0] namemap_b = {2{is_namemap & name_pix}} & 2'd1;

    // Side and bottom rails ... dark grey
    wire [1:0] rail_r  = {2{is_side_rail | is_bin_floor | is_bin_sep}} & 2'd1;
    wire [1:0] rail_g  = {2{is_side_rail | is_bin_floor | is_bin_sep}} & 2'd1;
    wire [1:0] rail_b  = {2{is_side_rail | is_bin_floor | is_bin_sep}} & 2'd1;

    // Text ... yellow
    wire [1:0] text_r  = {2{is_text}} & 2'd3;
    wire [1:0] text_g  = {2{is_text}} & 2'd3;
    wire [1:0] text_b  = {2{is_text}} & 2'd0;

    // Peg ... yellow
    wire [1:0] peg_r   = {2{is_peg}} & 2'd2;
    wire [1:0] peg_g   = {2{is_peg}} & 2'd2;
    wire [1:0] peg_b   = {2{is_peg}} & 2'd3;

    // Bar ... grey
    wire [1:0] bar_r   = {2{is_bar & !is_level}} & 2'd2;
    wire [1:0] bar_g   = {2{is_bar & !is_level}} & 2'd2;
    wire [1:0] bar_b   = {2{is_bar & !is_level}} & 2'd2;

    // Full ... yellow
    wire [1:0] full_r  = {2{is_full & !is_bar & !is_level}} & 2'd3;
    wire [1:0] full_g  = {2{is_full & !is_bar & !is_level}} & 2'd3;
    wire [1:0] full_b  = {2{is_full & !is_bar & !is_level}} & 2'd0;

    // ===============================================================
    //  Color Composition
    // ===============================================================
    always @(posedge clk) begin
        if (!video_active) begin
            R <= 2'd0; G <= 2'd0; B <= 2'd0;
        end else if (is_ball) begin
            R <= 2'd3; G <= 2'd3; B <= 2'd3;        // white ball
        end else begin
            R <= bitmap_r | count_r | rail_r | text_r | peg_r | bar_r | full_r | namemap_r;
            G <= bitmap_g | count_g | rail_g | text_g | peg_g | bar_g | full_g | namemap_g;
            B <= bitmap_b | count_b | rail_b | text_b | peg_b | bar_b | full_b | namemap_b;
        end
    end

endmodule
