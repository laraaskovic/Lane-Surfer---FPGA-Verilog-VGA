/*
 * Lane Runner - VGA Version with Moving Player
 * 
 * This displays a player block on VGA that can move between 5 lanes
 * Controls:
 * - LEFT arrow key or KEY[1] = move LEFT (lane decreases)
 * - RIGHT arrow key or KEY[0] = move RIGHT (lane increases)
 * - KEY[3] = reset to middle lane
 * 
 * VGA Display:
 * - 5 lanes in center 2/3 of screen
 * - Player block at bottom of screen
 * - Background road image
 * 
 * LED Display (for debugging):
 * LEDR[2:0] = Current lane (0-4)
 * LEDR[7] = Left arrow key pressed
 * LEDR[8] = Right arrow key pressed
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

    // VGA Parameters
    parameter nX = 9;           // 9 bits for X (320 pixels)
    parameter nY = 8;           // 8 bits for Y (240 pixels)
    parameter COLOR_DEPTH = 9;  // 9-bit color
    
    // Reset and control signals
    wire Resetn;
    wire move_left_key, move_right_key;  // From buttons
    wire move_left_kb, move_right_kb;    // From keyboard
    wire move_left, move_right;          // Combined inputs
    
    // Player signals
    wire [2:0] player_lane;              // Current lane (0-4)
    wire [nX-1:0] player_x;              // Player VGA X coordinate
    wire [nY-1:0] player_y;              // Player VGA Y coordinate
    wire [COLOR_DEPTH-1:0] player_color; // Player pixel color
    wire player_write;                   // VGA write enable
    
    // PS/2 signals
    wire [7:0] ps2_key_data;
    wire ps2_key_pressed;
    
    // Reset is active LOW on KEY[3]
    assign Resetn = KEY[3];
    
    // Synchronize button inputs (note: KEYs are active LOW)
    sync left_sync (~KEY[1], Resetn, CLOCK_50, move_left_key);
    sync right_sync (~KEY[0], Resetn, CLOCK_50, move_right_key);
    
    // Combine keyboard and button inputs
    assign move_left = move_left_key | move_left_kb;
    assign move_right = move_right_key | move_right_kb;
    
    // PS/2 Keyboard Controller
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
    
    // Keyboard decoder - detects arrow keys
    keyboard_decoder KB_DEC (
        .clk(CLOCK_50),
        .reset(~Resetn),
        .ps2_data(ps2_key_data),
        .ps2_valid(ps2_key_pressed),
        .left_arrow(move_left_kb),
        .right_arrow(move_right_kb)
    );
    
    // Player object - handles movement and VGA drawing
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
    
    // VGA adapter - displays pixels on monitor
    vga_adapter VGA (
        .resetn(Resetn),
        .clock(CLOCK_50),
        .colour(player_color),
        .x(player_x),
        .y(player_y),
        .plot(player_write),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_CLK(VGA_CLK)
    );
        defparam VGA.RESOLUTION = "320x240";
        defparam VGA.BACKGROUND_IMAGE = "image.colour.mif";
    
    // LED Display - show current lane for debugging
    assign LEDR[2:0] = player_lane;
    assign LEDR[6:3] = 4'b0;
    assign LEDR[7] = move_left_kb;      // Left arrow indicator
    assign LEDR[8] = move_right_kb;     // Right arrow indicator
    assign LEDR[9] = ps2_key_pressed;   // PS/2 activity
    
    // HEX display - show last PS/2 scan code
    hex7seg H0 (ps2_key_data[3:0], HEX0);
    hex7seg H1 (ps2_key_data[7:4], HEX1);

endmodule


// =========================================================================
// PLAYER OBJECT MODULE
// Handles player movement between lanes and VGA drawing
// =========================================================================
module player_object(
    input wire Resetn,
    input wire Clock,
    input wire move_left,
    input wire move_right,
    output reg [2:0] player_lane,       // Current lane (0-4)
    output wire [nX-1:0] VGA_x,         // VGA pixel X coordinate
    output wire [nY-1:0] VGA_y,         // VGA pixel Y coordinate
    output wire [COLOR_DEPTH-1:0] VGA_color,  // VGA pixel color
    output wire VGA_write               // VGA write enable
);

    // VGA parameters
    parameter nX = 9;
    parameter nY = 8;
    parameter COLOR_DEPTH = 9;
    
    // Screen dimensions
    parameter XSCREEN = 320;
    parameter YSCREEN = 240;
    
    // Lane configuration - 5 lanes in center 2/3 of screen
    parameter NUM_LANES = 5;
    parameter LANE_WIDTH = 40;          // Each lane is 40 pixels wide
    parameter LANE_START_X = 60;        // Lanes start at X=60
    // Total lane area: 5 lanes * 40 pixels = 200 pixels (60 to 260)
    
    // Player dimensions
    parameter PLAYER_WIDTH = 30;        // 30 pixels wide
    parameter PLAYER_HEIGHT = 30;       // 30 pixels tall (square)
    parameter PLAYER_Y_POS = 180;       // Y position (fixed, near bottom)
    
    // Colors
    parameter PLAYER_COLOR = 9'b000_111_111;  // Cyan
    parameter ERASE_COLOR = 9'b000_000_000;   // Black (will hide background)
    // NOTE: To show background when erasing, you'd need to read from VGA memory
    // For now, black erase means player leaves black trail over background
    
    // FSM States
    parameter INIT = 3'd0;              // Initialize
    parameter DRAW_INITIAL = 3'd1;      // Draw at starting position
    parameter IDLE = 3'd2;              // Wait for input
    parameter ERASE = 3'd3;             // Erase player at old position
    parameter MOVE = 3'd4;              // Update lane position
    parameter DRAW = 3'd5;              // Draw player at new position
    parameter WAIT_RELEASE = 3'd6;      // Wait for key release
    
    reg [2:0] state;                    // Current FSM state
    reg [2:0] target_lane;              // Lane to move to
    reg [nX-1:0] player_x_pos;          // Top-left X coordinate
    reg [4:0] pixel_x;                  // Pixel counter X (0-29)
    reg [4:0] pixel_y;                  // Pixel counter Y (0-29)
    reg [nX-1:0] vga_x_reg;             // Registered VGA X output
    reg [nY-1:0] vga_y_reg;             // Registered VGA Y output
    reg [COLOR_DEPTH-1:0] vga_color_reg; // Registered VGA color
    reg vga_write_reg;                  // Registered VGA write
    reg is_erasing;                     // 1=erasing, 0=drawing
    
    // Function: Convert lane number to X coordinate
    // Centers the player within each lane
    function [nX-1:0] lane_to_x;
        input [2:0] lane;
        begin
            // Formula: X = LANE_START + (lane * LANE_WIDTH) + centering_offset
            // Centering offset = (LANE_WIDTH - PLAYER_WIDTH) / 2
            // Lane 0: 60 + (0*40) + 5 = 65
            // Lane 1: 60 + (1*40) + 5 = 105
            // Lane 2: 60 + (2*40) + 5 = 145 (middle)
            // Lane 3: 60 + (3*40) + 5 = 185
            // Lane 4: 60 + (4*40) + 5 = 225
            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) + 
                       ((LANE_WIDTH - PLAYER_WIDTH) / 2);
        end
    endfunction
    
    // =====================================================
    // Main FSM - Handles movement and drawing
    // =====================================================
    always @(posedge Clock) begin
        if (!Resetn) begin
            // Reset to middle lane (lane 2)
            state <= INIT;
            player_lane <= 3'd2;
            player_x_pos <= lane_to_x(3'd2);
            target_lane <= 3'd2;
            pixel_x <= 0;
            pixel_y <= 0;
            vga_x_reg <= 0;
            vga_y_reg <= 0;
            vga_color_reg <= ERASE_COLOR;
            vga_write_reg <= 0;
            is_erasing <= 0;
        end
        else begin
            case (state)
                // ==========================================
                // INIT: Setup initial state
                // ==========================================
                INIT: begin
                    pixel_x <= 0;
                    pixel_y <= 0;
                    vga_write_reg <= 0;
                    is_erasing <= 0;
                    state <= DRAW_INITIAL;
                end
                
                // ==========================================
                // DRAW_INITIAL: Draw player at starting position
                // ==========================================
                DRAW_INITIAL: begin
                    // Output current pixel position and color
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= PLAYER_COLOR;
                    vga_write_reg <= 1;
                    
                    // Scan through all pixels (30x30)
                    if (pixel_x < PLAYER_WIDTH - 1) begin
                        pixel_x <= pixel_x + 1;
                    end
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1) begin
                            pixel_y <= pixel_y + 1;
                        end
                        else begin
                            // Done drawing initial block
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= IDLE;
                        end
                    end
                end
                
                // ==========================================
                // IDLE: Wait for movement input
                // ==========================================
                IDLE: begin
                    vga_write_reg <= 0;
                    
                    // Check for left movement
                    if (move_left && player_lane > 0) begin
                        target_lane <= player_lane - 1;
                        pixel_x <= 0;
                        pixel_y <= 0;
                        state <= ERASE;
                    end
                    // Check for right movement
                    else if (move_right && player_lane < NUM_LANES - 1) begin
                        target_lane <= player_lane + 1;
                        pixel_x <= 0;
                        pixel_y <= 0;
                        state <= ERASE;
                    end
                end
                
                // ==========================================
                // ERASE: Just skip erasing - VGA will show background
                // ==========================================
                ERASE: begin
                    // Don't actually erase - VGA framebuffer keeps background
                    // Just move directly to updating position
                    vga_write_reg <= 0;
                    pixel_x <= 0;
                    pixel_y <= 0;
                    state <= MOVE;
                end
                
                // ==========================================
                // MOVE: Update position to new lane
                // ==========================================
                MOVE: begin
                    player_lane <= target_lane;
                    player_x_pos <= lane_to_x(target_lane);
                    pixel_x <= 0;
                    pixel_y <= 0;
                    is_erasing <= 0;
                    vga_write_reg <= 0;
                    state <= DRAW;
                end
                
                // ==========================================
                // DRAW: Draw player at new position
                // ==========================================
                DRAW: begin
                    // Output colored pixels at new position
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= PLAYER_COLOR;
                    vga_write_reg <= 1;
                    
                    // Scan through all pixels
                    if (pixel_x < PLAYER_WIDTH - 1) begin
                        pixel_x <= pixel_x + 1;
                    end
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1) begin
                            pixel_y <= pixel_y + 1;
                        end
                        else begin
                            // Done drawing
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= WAIT_RELEASE;
                        end
                    end
                end
                
                // ==========================================
                // WAIT_RELEASE: Wait for key/button release
                // ==========================================
                WAIT_RELEASE: begin
                    vga_write_reg <= 0;
                    if (!move_left && !move_right) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= INIT;
            endcase
        end
    end
    
    // Assign registered outputs to VGA
    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;

endmodule


// =========================================================================
// KEYBOARD DECODER - Detects arrow keys from PS/2
// =========================================================================
module keyboard_decoder(
    input wire clk,
    input wire reset,
    input wire [7:0] ps2_data,
    input wire ps2_valid,
    output reg left_arrow,
    output reg right_arrow
);

    // PS/2 scan codes
    parameter LEFT_ARROW_CODE = 8'h6B;   // LEFT arrow
    parameter RIGHT_ARROW_CODE = 8'h74;  // RIGHT arrow
    parameter EXTENDED_CODE = 8'hE0;     // Extended key prefix
    parameter BREAK_CODE = 8'hF0;        // Key release prefix
    
    // State machine states
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


// =========================================================================
// HEX 7-SEGMENT DECODER
// =========================================================================
module hex7seg(
    input wire [3:0] hex,
    output reg [6:0] display
);
    always @(*) begin
        case (hex)
            4'h0: display = 7'b1000000;
            4'h1: display = 7'b1111001;
            4'h2: display = 7'b0100100;
            4'h3: display = 7'b0110000;
            4'h4: display = 7'b0011001;
            4'h5: display = 7'b0010010;
            4'h6: display = 7'b0000010;
            4'h7: display = 7'b1111000;
            4'h8: display = 7'b0000000;
            4'h9: display = 7'b0010000;
            4'hA: display = 7'b0001000;
            4'hB: display = 7'b0000011;
            4'hC: display = 7'b1000110;
            4'hD: display = 7'b0100001;
            4'hE: display = 7'b0000110;
            4'hF: display = 7'b0001110;
            default: display = 7'b1111111;
        endcase
    end
endmodule


// =========================================================================
// SYNCHRONIZER - Prevents metastability
// =========================================================================
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