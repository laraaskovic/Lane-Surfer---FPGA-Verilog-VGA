/*
 * GAME_CONTROLLER.V
 * 
 * Save this as: game_controller.v
 * 
 * Manages overall game state, lives, score, and game logic
 * 
 * FEATURES:
 * - 3 lives system
 * - Score tracking (points for time survived)
 * - Game states: START → PLAYING → HIT → GAME_OVER
 * - Collision handling (lose life, brief invincibility)
 * - Reset on game over
 * - Outputs for HEX display and LEDs
 * 
 * GAME FLOW:
 * 1. START: Press any movement key to begin
 * 2. PLAYING: Avoid obstacles, score increases
 * 3. HIT: Collision detected, lose 1 life, brief pause
 * 4. GAME_OVER: Lives = 0, display final score
 * 5. Press reset (KEY[3]) to restart
 */

`default_nettype none

module game_controller(
    input wire Resetn,
    input wire Clock,
    input wire collision_in,           // From obstacle_manager
    input wire move_left,              // Player trying to move
    input wire move_right,
    output reg game_active,            // High when game is running
    output reg enable_player_move,     // Allow player movement
    output reg enable_obstacles,       // Allow obstacles to spawn/move
    output reg [3:0] lives,            // Current lives (0-3)
    output reg [15:0] score,           // Current score
    output wire [6:0] hex0_out,        // HEX display outputs
    output wire [6:0] hex1_out,
    output wire [6:0] hex2_out,
    output wire [6:0] hex3_out
);

    // Game States
    parameter START = 3'd0;            // Waiting to start
    parameter PLAYING = 3'd1;          // Active gameplay
    parameter HIT = 3'd2;              // Just got hit, brief pause
    parameter INVINCIBLE = 3'd3;       // Brief invincibility after hit
    parameter GAME_OVER = 3'd4;        // No lives left
    
    reg [2:0] state;
    
    // Timers
    parameter HIT_PAUSE_TIME = 25000000;      // 0.5 seconds at 50MHz
    parameter INVINCIBLE_TIME = 100000000;    // 2 seconds invincibility
    parameter SCORE_INCREMENT_TIME = 50000000; // Score +1 every second
    
    reg [31:0] state_timer;
    reg [31:0] score_timer;
    
    // Collision edge detection (only trigger once per collision)
    reg collision_prev;
    wire collision_rising_edge;
    assign collision_rising_edge = collision_in && !collision_prev;
    
    // HEX display values
    reg [3:0] hex0_val, hex1_val, hex2_val, hex3_val;
    
    // Instantiate HEX decoders
    hex_decoder HEX0 (.in(hex0_val), .out(hex0_out));
    hex_decoder HEX1 (.in(hex1_val), .out(hex1_out));
    hex_decoder HEX2 (.in(hex2_val), .out(hex2_out));
    hex_decoder HEX3 (.in(hex3_val), .out(hex3_out));
    
    // Main FSM
    always @(posedge Clock) begin
        if (!Resetn) begin
            state <= START;
            lives <= 4'd3;               // Start with 3 lives
            score <= 16'd0;
            state_timer <= 0;
            score_timer <= 0;
            collision_prev <= 0;
            game_active <= 0;
            enable_player_move <= 0;
            enable_obstacles <= 0;
            
            // Display "0" on HEX
            hex0_val <= 4'd0;
            hex1_val <= 4'd0;
            hex2_val <= 4'd0;
            hex3_val <= 4'd0;
        end
        else begin
            // Update collision edge detection
            collision_prev <= collision_in;
            
            // Increment timers
            state_timer <= state_timer + 1;
            score_timer <= score_timer + 1;
            
            case (state)
                START: begin
                    game_active <= 0;
                    enable_player_move <= 1;     // Can move in menu
                    enable_obstacles <= 0;       // No obstacles yet
                    lives <= 4'd3;
                    score <= 16'd0;
                    
                    // Display "---" or lives on HEX
                    hex0_val <= 4'd0;
                    hex1_val <= 4'd0;
                    hex2_val <= 4'd0;
                    hex3_val <= lives;           // Show starting lives
                    
                    // Start game when player presses movement key
                    if (move_left || move_right) begin
                        state <= PLAYING;
                        score_timer <= 0;
                        game_active <= 1;
                        enable_obstacles <= 1;
                    end
                end
                
                PLAYING: begin
                    game_active <= 1;
                    enable_player_move <= 1;
                    enable_obstacles <= 1;
                    
                    // Increment score over time
                    if (score_timer >= SCORE_INCREMENT_TIME) begin
                        score_timer <= 0;
                        if (score < 16'd9999)    // Max score 9999
                            score <= score + 1;
                    end
                    
                    // Display score on HEX (4 digits)
                    hex0_val <= score % 10;                    // Ones
                    hex1_val <= (score / 10) % 10;             // Tens
                    hex2_val <= (score / 100) % 10;            // Hundreds
                    hex3_val <= (score / 1000) % 10;           // Thousands
                    
                    // Check for collision
                    if (collision_rising_edge) begin
                        lives <= lives - 1;
                        
                        if (lives == 4'd1) begin
                            // Last life lost - game over
                            state <= GAME_OVER;
                            game_active <= 0;
                            enable_obstacles <= 0;
                        end
                        else begin
                            // Still have lives - brief pause then invincible
                            state <= HIT;
                            state_timer <= 0;
                            enable_obstacles <= 0;  // Pause obstacles during hit
                        end
                    end
                end
                
                HIT: begin
                    // Brief pause after getting hit
                    game_active <= 1;
                    enable_player_move <= 1;
                    enable_obstacles <= 0;       // Freeze obstacles
                    
                    // Flash lives on HEX (visual feedback)
                    if (state_timer[23])         // Blink using timer bit
                        hex3_val <= lives;
                    else
                        hex3_val <= 4'd15;       // Blank (off)
                    
                    // Resume after pause
                    if (state_timer >= HIT_PAUSE_TIME) begin
                        state <= INVINCIBLE;
                        state_timer <= 0;
                        enable_obstacles <= 1;   // Resume obstacles
                    end
                end
                
                INVINCIBLE: begin
                    // Temporary invincibility after hit
                    game_active <= 1;
                    enable_player_move <= 1;
                    enable_obstacles <= 1;
                    
                    // Continue scoring
                    if (score_timer >= SCORE_INCREMENT_TIME) begin
                        score_timer <= 0;
                        if (score < 16'd9999)
                            score <= score + 1;
                    end
                    
                    // Display score normally
                    hex0_val <= score % 10;
                    hex1_val <= (score / 10) % 10;
                    hex2_val <= (score / 100) % 10;
                    hex3_val <= (score / 1000) % 10;
                    
                    // End invincibility after timer
                    if (state_timer >= INVINCIBLE_TIME) begin
                        state <= PLAYING;
                        state_timer <= 0;
                    end
                    
                    // Note: Ignore collisions during invincibility
                end
                
                GAME_OVER: begin
                    game_active <= 0;
                    enable_player_move <= 0;
                    enable_obstacles <= 0;
                    
                    // Display final score (frozen)
                    hex0_val <= score % 10;
                    hex1_val <= (score / 10) % 10;
                    hex2_val <= (score / 100) % 10;
                    hex3_val <= (score / 1000) % 10;
                    
                    // Stay in game over until reset
                    // Could add: press key to return to START
                end
                
                default: state <= START;
            endcase
        end
    end

endmodule


// ===== HEX DECODER =====
// Converts 4-bit value to 7-segment display
module hex_decoder(
    input wire [3:0] in,
    output reg [6:0] out
);

    always @(*) begin
        case (in)
            4'h0: out = 7'b1000000;  // 0
            4'h1: out = 7'b1111001;  // 1
            4'h2: out = 7'b0100100;  // 2
            4'h3: out = 7'b0110000;  // 3
            4'h4: out = 7'b0011001;  // 4
            4'h5: out = 7'b0010010;  // 5
            4'h6: out = 7'b0000010;  // 6
            4'h7: out = 7'b1111000;  // 7
            4'h8: out = 7'b0000000;  // 8
            4'h9: out = 7'b0010000;  // 9
            4'hA: out = 7'b0001000;  // A
            4'hB: out = 7'b0000011;  // B
            4'hC: out = 7'b1000110;  // C
            4'hD: out = 7'b0100001;  // D
            4'hE: out = 7'b0000110;  // E
            4'hF: out = 7'b1111111;  // Blank (off)
            default: out = 7'b1111111;
        endcase
    end

endmodule