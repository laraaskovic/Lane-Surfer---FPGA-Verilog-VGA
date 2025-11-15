/*
 * Lane Runner - TOP MODULE (lane_runner_top.v)
 * 
 * FIXED VERSION - Added obstacle support
 * 
 * KEY CHANGES:
 * 1. Added obstacle_manager instantiation
 * 2. Added VGA arbiter to multiplex player + obstacle drawing
 * 3. Connected collision signal to LEDR[9]
 */

`default_nettype none

module lane_runner_top(
    input wire CLOCK_50,
    input wire [9:0] SW,
    input wire [3:0] KEY,
    inout wire PS2_CLK,
    inout wire PS2_DAT,
    output wire [9:0] LEDR,
    output wire [6:0] HEX0,
    output wire [6:0] HEX1,
    output wire [7:0] VGA_R,
    output wire [7:0] VGA_G,
    output wire [7:0] VGA_B,
    output wire VGA_HS,
    output wire VGA_VS,
    output wire VGA_BLANK_N,
    output wire VGA_SYNC_N,
    output wire VGA_CLK
);

    parameter nX = 10;
    parameter nY = 9;
    parameter COLOR_DEPTH = 9;
    
    wire Resetn;
    wire move_left_key, move_right_key;
    wire move_left_kb, move_right_kb;
    wire move_left, move_right;
    
    assign Resetn = KEY[3];
    assign move_left = move_left_key | move_left_kb;
    assign move_right = move_right_key | move_right_kb;
    
    // ===== PLAYER SIGNALS =====
    wire [2:0] player_lane;
    wire [nX-1:0] player_x;
    wire [nY-1:0] player_y;
    wire [COLOR_DEPTH-1:0] player_color;
    wire player_write;
    
    // ===== NEW: OBSTACLE SIGNALS =====
    wire [nX-1:0] obstacle_x;
    wire [nY-1:0] obstacle_y;
    wire [COLOR_DEPTH-1:0] obstacle_color;
    wire obstacle_write;
    wire collision;
    
    // ===== NEW: VGA ARBITER =====
    // Multiplexes between player and obstacle drawing
    // Priority: Obstacles first (drawn in back), then player (drawn on top)
    reg [nX-1:0] vga_x_mux;
    reg [nY-1:0] vga_y_mux;
    reg [COLOR_DEPTH-1:0] vga_color_mux;
    reg vga_write_mux;
    
    always @(*) begin
        if (obstacle_write) begin
            // Obstacle wants to draw - give it priority
            vga_x_mux = obstacle_x;
            vga_y_mux = obstacle_y;
            vga_color_mux = obstacle_color;
            vga_write_mux = obstacle_write;
        end
        else if (player_write) begin
            // Player wants to draw
            vga_x_mux = player_x;
            vga_y_mux = player_y;
            vga_color_mux = player_color;
            vga_write_mux = player_write;
        end
        else begin
            // Nobody drawing
            vga_x_mux = 10'd0;
            vga_y_mux = 9'd0;
            vga_color_mux = 9'd0;
            vga_write_mux = 1'b0;
        end
    end
    
    // PS/2 Signals
    wire [7:0] ps2_key_data;
    wire ps2_key_pressed;
    
    // Button Synchronizers
    sync left_sync (~KEY[1], Resetn, CLOCK_50, move_left_key);
    sync right_sync (~KEY[0], Resetn, CLOCK_50, move_right_key);
    
    // PS/2 Keyboard Controller
    PS2_Controller #(.INITIALIZE_MOUSE(0)) PS2 (
        .CLOCK_50(CLOCK_50),
        .reset(~Resetn),
        .the_command(8'h00),
        .send_command(1'b0),
        .PS2_CLK(PS2_CLK),
        .PS2_DAT(PS2_DAT),
        .command_was_sent(),
        .error_communication_timed_out(),
        .received_data(ps2_key_data),
        .received_data_en(ps2_key_pressed)
    );
    
    // Keyboard Decoder
    keyboard_decoder KB_DEC (
        .clk(CLOCK_50),
        .reset(~Resetn),
        .ps2_data(ps2_key_data),
        .ps2_valid(ps2_key_pressed),
        .left_arrow(move_left_kb),
        .right_arrow(move_right_kb)
    );
    
    // ===== PLAYER MODULE =====
    player_object PLAYER (
        .Resetn(Resetn),
        .Clock(CLOCK_50),
        .move_left(move_left),
        .move_right(move_right),
        .player_lane(player_lane),
        .VGA_x(player_x),
        .VGA_y(player_y),
        .VGA_color(player_color),
        .VGA_write(player_write)
    );
    
    // ===== NEW: OBSTACLE MANAGER =====
    obstacle_manager OBSTACLES (
        .Resetn(Resetn),
        .Clock(CLOCK_50),
        .player_lane(player_lane),      // For collision detection
        .player_y(10'd360),             // Player Y position (fixed)
        .collision(collision),          // Collision output
        .VGA_x(obstacle_x),             // Obstacle drawing outputs
        .VGA_y(obstacle_y),
        .VGA_color(obstacle_color),
        .VGA_write(obstacle_write)
    );
    
    // ===== VGA ADAPTER =====
    // NOW CONNECTED TO ARBITER (can draw player OR obstacles)
    vga_adapter VGA (
        .resetn(Resetn),
        .clock(CLOCK_50),
        .color(vga_color_mux),      // ← From arbiter!
        .x(vga_x_mux),              // ← From arbiter!
        .y(vga_y_mux),              // ← From arbiter!
        .write(vga_write_mux),      // ← From arbiter!
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_CLK(VGA_CLK)
    );
        defparam VGA.RESOLUTION = "640x480";
        defparam VGA.BACKGROUND_IMAGE = "image.colour.mif";
    
    // ===== LED DISPLAY =====
    assign LEDR[2:0] = player_lane;
    assign LEDR[6:3] = 4'b0;
    assign LEDR[7] = move_left_kb;
    assign LEDR[8] = move_right_kb;
    assign LEDR[9] = collision;         // ← Collision indicator!
    
    // ===== HEX DISPLAY (unused for now) =====
    assign HEX0 = 7'b1111111;  // Off
    assign HEX1 = 7'b1111111;  // Off
    
endmodule


// ===== KEYBOARD DECODER (unchanged) =====
module keyboard_decoder(
    input wire clk,
    input wire reset,
    input wire [7:0] ps2_data,
    input wire ps2_valid,
    output reg left_arrow,
    output reg right_arrow
);

    parameter LEFT_ARROW_CODE = 8'h6B;
    parameter RIGHT_ARROW_CODE = 8'h74;
    parameter EXTENDED_CODE = 8'hE0;
    parameter BREAK_CODE = 8'hF0;
    
    parameter WAIT_CODE = 2'b00;
    parameter WAIT_EXTENDED = 2'b01;
    parameter WAIT_BREAK = 2'b10;
    
    reg [1:0] decode_state;
    reg waiting_for_break_after_extended;
    
    always @(posedge clk) begin
        if (reset) begin
            decode_state <= WAIT_CODE;
            waiting_for_break_after_extended <= 0;
            left_arrow <= 0;
            right_arrow <= 0;
        end
        else if (ps2_valid) begin
            case (decode_state)
                WAIT_CODE: begin
                    if (ps2_data == EXTENDED_CODE) begin
                        decode_state <= WAIT_EXTENDED;
                    end
                    else if (ps2_data == BREAK_CODE) begin
                        decode_state <= WAIT_BREAK;
                    end
                end
                WAIT_EXTENDED: begin
                    if (ps2_data == BREAK_CODE) begin
                        waiting_for_break_after_extended <= 1;
                        decode_state <= WAIT_BREAK;
                    end
                    else if (ps2_data == LEFT_ARROW_CODE) begin
                        left_arrow <= 1;
                        decode_state <= WAIT_CODE;
                    end
                    else if (ps2_data == RIGHT_ARROW_CODE) begin
                        right_arrow <= 1;
                        decode_state <= WAIT_CODE;
                    end
                    else begin
                        decode_state <= WAIT_CODE;
                    end
                end
                WAIT_BREAK: begin
                    if (waiting_for_break_after_extended) begin
                        if (ps2_data == LEFT_ARROW_CODE) begin
                            left_arrow <= 0;
                        end
                        else if (ps2_data == RIGHT_ARROW_CODE) begin
                            right_arrow <= 0;
                        end
                        waiting_for_break_after_extended <= 0;
                    end
                    decode_state <= WAIT_CODE;
                end
                
                default: decode_state <= WAIT_CODE;
            endcase
        end
    end

endmodule


// ===== SYNCHRONIZER (unchanged) =====
module sync(D, Resetn, Clock, Q);
    input wire D;
    input wire Resetn, Clock;
    output reg Q;
    reg Qi;

    always @(posedge Clock) begin
        if (Resetn == 0) begin
            Qi <= 1'b0;
            Q <= 1'b0;
        end
        else begin
            Qi <= D;
            Q <= Qi;
        end
    end
endmodule