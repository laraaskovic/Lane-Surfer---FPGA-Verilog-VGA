/*
 * Lane Runner - LED ONLY VERSION (No VGA)
 * 
 * This shows the player's lane position using LEDs
 * - 5 lanes total (LEDR[4:0])
 * - Start at lane 2 (middle LED lit)
 * - LEFT arrow key or KEY[1] = move left
 * - RIGHT arrow key or KEY[0] = move right
 * - KEY[3] = reset
 * 
 * LED Display:
 * LEDR[0] = Lane 0 (leftmost)
 * LEDR[1] = Lane 1
 * LEDR[2] = Lane 2 (middle, starting position)
 * LEDR[3] = Lane 3
 * LEDR[4] = Lane 4 (rightmost)
 * 
 * Debug LEDs:
 * LEDR[7] = Left arrow key pressed
 * LEDR[8] = Right arrow key pressed
 * LEDR[9] = Any key detected from keyboard
 */

`default_nettype none

module lane_runner_top(
    input wire CLOCK_50,
    input wire [3:0] KEY,
    inout wire PS2_CLK,
    inout wire PS2_DAT,
    output wire [9:0] LEDR
);

    wire Resetn;
    wire move_left_key, move_right_key;  // From buttons
    wire move_left_kb, move_right_kb;    // From keyboard
    wire move_left, move_right;          // Combined
    wire [2:0] player_lane;              // Current lane (0-4)
    
    // PS/2 signals
    wire [7:0] ps2_key_data;
    wire ps2_key_pressed;
    
    assign Resetn = KEY[3];
    
    // Synchronize button inputs
    sync left_sync (~KEY[1], Resetn, CLOCK_50, move_left_key);
    sync right_sync (~KEY[0], Resetn, CLOCK_50, move_right_key);
    
    // Combine keyboard and button inputs (either can move player)
    assign move_left = move_left_key | move_left_kb;
    assign move_right = move_right_key | move_right_kb;
    
    // PS/2 Keyboard Controller
    PS2_Controller PS2 (
        .CLOCK_50(CLOCK_50),
        .reset(~Resetn),
        .PS2_CLK(PS2_CLK),
        .PS2_DAT(PS2_DAT),
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
    
    // Player lane controller
    player_lane_fsm PLAYER (
        .clk(CLOCK_50),
        .reset(~Resetn),
        .move_left(move_left),
        .move_right(move_right),
        .current_lane(player_lane)
    );
    
    // LED Display - Show which lane player is in
    // Only ONE LED should be lit at a time
    assign LEDR[0] = (player_lane == 3'd0);  // Lane 0
    assign LEDR[1] = (player_lane == 3'd1);  // Lane 1
    assign LEDR[2] = (player_lane == 3'd2);  // Lane 2 (middle, start)
    assign LEDR[3] = (player_lane == 3'd3);  // Lane 3
    assign LEDR[4] = (player_lane == 3'd4);  // Lane 4
    assign LEDR[5] = 1'b0;
    assign LEDR[6] = 1'b0;
    
    // Debug LEDs - show keyboard status
    assign LEDR[7] = move_left_kb;   // Left arrow pressed
    assign LEDR[8] = move_right_kb;  // Right arrow pressed

endmodule


// PLAYER LANE FSM - Simple FSM to track lane position
// States:
// - IDLE: waiting for input
// - MOVING: processing a move
// - WAIT_RELEASE: waiting for button/key release before accepting next move
module player_lane_fsm(
    input wire clk,
    input wire reset,
    input wire move_left,
    input wire move_right,
    output reg [2:0] current_lane
);

    parameter NUM_LANES = 5;
    
    // FSM States
    parameter IDLE = 2'b00;
    parameter MOVING = 2'b01;
    parameter WAIT_RELEASE = 2'b10;
    
    reg [1:0] state;
    reg [2:0] next_lane;
    
    always @(posedge clk) begin
        if (reset) begin
            // Reset to middle lane (lane 2)
            current_lane <= 3'd2;
            state <= IDLE;
            next_lane <= 3'd2;
        end
        else begin
            case (state)
                // IDLE: Wait for movement command
                IDLE: begin
                    if (move_left && current_lane > 0) begin
                        // Move left (decrease lane number)
                        next_lane <= current_lane - 1;
                        state <= MOVING;
                    end
                    else if (move_right && current_lane < NUM_LANES - 1) begin
                        // Move right (increase lane number)
                        next_lane <= current_lane + 1;
                        state <= MOVING;
                    end
                    // If at boundary, stay in IDLE and ignore input
                end
                
                // MOVING: Update lane position
                MOVING: begin
                    current_lane <= next_lane;
                    state <= WAIT_RELEASE;
                end
                
                // WAIT_RELEASE: Wait for all buttons/keys released
                WAIT_RELEASE: begin
                    if (!move_left && !move_right) begin
                        // All inputs released, ready for next move
                        state <= IDLE;
                    end
                    // Stay in this state until buttons released
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule


// KEYBOARD DECODER - Detects LEFT and RIGHT arrow keys
// PS/2 Arrow Key Sequences:
// LEFT arrow press:  E0 6B
// LEFT arrow release: E0 F0 6B
// RIGHT arrow press:  E0 74
// RIGHT arrow release: E0 F0 74
// =========================================================================
module keyboard_decoder(
    input wire clk,
    input wire reset,
    input wire [7:0] ps2_data,
    input wire ps2_valid,
    output reg left_arrow,
    output reg right_arrow
);

    // Scan codes from PS/2 documentation
    parameter LEFT_ARROW_CODE = 8'h6B;
    parameter RIGHT_ARROW_CODE = 8'h74;
    parameter EXTENDED_CODE = 8'hE0;  // Prefix for arrow keys
    parameter BREAK_CODE = 8'hF0;     // Prefix for key release
    
    // State machine for decoding multi-byte sequences
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
                // ==========================================
                // WAIT_CODE: Waiting for first byte
                // ==========================================
                WAIT_CODE: begin
                    if (ps2_data == EXTENDED_CODE) begin
                        // Extended key coming (arrow keys)
                        decode_state <= WAIT_EXTENDED;
                    end
                    else if (ps2_data == BREAK_CODE) begin
                        // Break code for non-extended key (ignore)
                        decode_state <= WAIT_BREAK;
                    end
                    // Ignore other codes
                end
                
                // ==========================================
                // WAIT_EXTENDED: Got E0, waiting for arrow code
                // ==========================================
                WAIT_EXTENDED: begin
                    if (ps2_data == BREAK_CODE) begin
                        // E0 F0 sequence - key release coming
                        waiting_for_break_after_extended <= 1;
                        decode_state <= WAIT_BREAK;
                    end
                    else if (ps2_data == LEFT_ARROW_CODE) begin
                        // E0 6B - LEFT arrow pressed
                        left_arrow <= 1;
                        decode_state <= WAIT_CODE;
                    end
                    else if (ps2_data == RIGHT_ARROW_CODE) begin
                        // E0 74 - RIGHT arrow pressed
                        right_arrow <= 1;
                        decode_state <= WAIT_CODE;
                    end
                    else begin
                        // Unknown extended key
                        decode_state <= WAIT_CODE;
                    end
                end
                
                // ==========================================
                // WAIT_BREAK: Got F0, waiting for key code
                // ==========================================
                WAIT_BREAK: begin
                    if (waiting_for_break_after_extended) begin
                        // E0 F0 XX sequence - extended key released
                        if (ps2_data == LEFT_ARROW_CODE) begin
                            left_arrow <= 0;
                        end
                        else if (ps2_data == RIGHT_ARROW_CODE) begin
                            right_arrow <= 0;
                        end
                        waiting_for_break_after_extended <= 0;
                    end
                    // Ignore non-extended break codes
                    decode_state <= WAIT_CODE;
                end
                
                default: decode_state <= WAIT_CODE;
            endcase
        end
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

