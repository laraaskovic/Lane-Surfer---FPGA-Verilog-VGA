/*
 * Lane Runner - TOP MODULE (lane_runner_top.v)
 * 
 * Save this as: lane_runner_top.v
 * 
 * 640x480 VGA Resolution Version
 * - Player moves between 5 lanes
 * - No erasing (background shows through)
 * - Keyboard arrow keys or KEY buttons for control
 * 
 * Controls:
 * - LEFT arrow key or KEY[1] = move LEFT
 * - RIGHT arrow key or KEY[0] = move RIGHT
 * - KEY[3] = reset to middle lane
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

    // VGA Parameters - 640x480 Resolution
    //same as player thign
    parameter nX = 10;          // 10 bits for X (640 pixels, 2^10 = 1024)
    parameter nY = 9;           // 9 bits for Y (480 pixels, 2^9 = 512)
    parameter COLOR_DEPTH = 9;  // 9-bit color (RGB: 3-3-3)
    
    wire Resetn;
    wire move_left_key, move_right_key;  // From buttons
    wire move_left_kb, move_right_kb;    // From keyboard
    wire move_left, move_right;          // Combined inputs
    
    // Reset is active LOW on KEY[3]
    assign Resetn = KEY[3];
    
    // Combine keyboard and button inputs
    assign move_left = move_left_key | move_left_kb;
    assign move_right = move_right_key | move_right_kb;
    
    // Player Signals
    wire [2:0] player_lane; // Current lane
    wire [nX-1:0] player_x;            
    wire [nY-1:0] player_y;            
    wire [COLOR_DEPTH-1:0] player_color; // Player pixel color
    wire player_write;                   // VGA write enable
    
    // PS/2 Signals
    wire [7:0] ps2_key_data; //8 bit scan code from keyboard
    wire ps2_key_pressed;
    
    // Button Synchronizers
    sync left_sync (~KEY[1], Resetn, CLOCK_50, move_left_key);
    sync right_sync (~KEY[0], Resetn, CLOCK_50, move_right_key);
    
    // PS/2 Keyboard Controller
    //copied from the demo file!!!!!
    PS2_Controller #(.INITIALIZE_MOUSE(0)) PS2 (
        .CLOCK_50(CLOCK_50),
        .reset(~Resetn),                    // Active HIGH reset
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
    



    // Player Object (from player_object.v)
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
    
    // VGA Adapter - 640x480 Resolution
    vga_adapter VGA (
        .resetn(Resetn),
        .clock(CLOCK_50),
        .color(player_color),
        .x(player_x),
        .y(player_y),
        .write(player_write),
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
    
    // LED Display
    assign LEDR[2:0] = player_lane;  
    assign LEDR[6:3] = 4'b0;         
    assign LEDR[7] = move_left_kb;         // Left arrow pressed
    assign LEDR[8] = move_right_kb;        // Right arrow pressed
    assign LEDR[9] = ps2_key_pressed;      // PS/2 activity
endmodule


// KEYBOARD DECODER Detects arrow keys from PS/2
// Converts raw PS/2 bytes into boolean “left_arrow” or “right_arrow” flags
module keyboard_decoder(
    input wire clk,
    input wire reset,
    input wire [7:0] ps2_data,
    input wire ps2_valid, // High for one clock cycle when new byte arrives
    output reg left_arrow,
    output reg right_arrow
);

    // PS/2 scan codes
    parameter LEFT_ARROW_CODE = 8'h6B; ///found in document!!!
    parameter RIGHT_ARROW_CODE = 8'h74;
    parameter EXTENDED_CODE = 8'hE0;
    parameter BREAK_CODE = 8'hF0; // Indicates that a key was released
    
    //When you press LEFT arrow keyboard sends E0 6B
    //When you release LEFT arrow keyboard sends E0 F0 6B

    // State machine
    parameter WAIT_CODE = 2'b00;
    parameter WAIT_EXTENDED = 2'b01; //Just saw an E0
    parameter WAIT_BREAK = 2'b10; // Just saw an F0 (release code)
    
    reg [1:0] decode_state;
    reg waiting_for_break_after_extended;
    
    always @(posedge clk) begin
        if (reset) begin
            decode_state <= WAIT_CODE;
            waiting_for_break_after_extended <= 0;
            left_arrow <= 0;
            right_arrow <= 0;
        end
        else if (ps2_valid) //whenever a complete byte has been received
        begin
            case (decode_state)
                WAIT_CODE: 
                begin
                    if (ps2_data == EXTENDED_CODE) 
                    begin
                        decode_state <= WAIT_EXTENDED;
                    end
                    else if (ps2_data == BREAK_CODE) 
                    begin
                        decode_state <= WAIT_BREAK;
                    end
                end
                WAIT_EXTENDED: 
                begin
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
                WAIT_BREAK: 
                begin
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




//taken from demo
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