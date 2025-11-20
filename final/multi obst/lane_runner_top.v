
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
    output wire [6:0] HEX2,
    output wire [6:0] HEX5,
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
    parameter nX = 10;
    parameter nY = 9;
    parameter COLOR_DEPTH = 9;
    
    wire Resetn;
    wire move_left_key, move_right_key;
    wire move_left_kb, move_right_kb;
    wire move_left, move_right;
    wire start_game_key;
    
    assign Resetn = SW[9];  // Changed: Use SW[9] for reset
    assign start_game_key = ~KEY[3];  // KEY[3] to start game
    assign move_left = move_left_key | move_left_kb;
    assign move_right = move_right_key | move_right_kb;
    
    // Player Signals
    wire [2:0] player_lane;
    wire [nX-1:0] player_x;
    wire [nY-1:0] player_y;
    wire [COLOR_DEPTH-1:0] player_color;
    wire player_write;
    
    // Obstacle Signals
    wire [nX-1:0] obs_x;
    wire [nY-1:0] obs_y;
    wire [COLOR_DEPTH-1:0] obs_color;
    wire obs_write;
    wire collision;
    wire game_over;
    wire [1:0] lives;
    wire score_increment;
    
    // Score Signals
    wire [9:0] score;
    
    // Title Screen Signals
    wire showing_title;
    wire title_complete;
    wire [nX-1:0] title_x;
    wire [nY-1:0] title_y;
    wire [COLOR_DEPTH-1:0] title_color;
    wire title_write;
    
    // PS/2 Signals
    wire [7:0] ps2_key_data;
    wire ps2_key_pressed;
    
    // Screen Eraser Signals
    wire erase_active;
    wire [nX-1:0] erase_x;
    wire [nY-1:0] erase_y;
    wire [COLOR_DEPTH-1:0] erase_color;
    wire erase_write;
    
    // Player state signals for priority detection
    wire player_is_erasing;
    wire player_is_drawing;
    wire player_is_collision_mode;  // NEW: High when player is red (collision)
    
    // Obstacle state signals for priority detection
    wire obs_is_erasing;
    wire obs_is_drawing;
    
    // VGA Arbiter with Updated Priority System:
    // 1. Title screen (highest - when showing_title is active)
    // 2. Screen eraser
    // 3. Player in collision mode - draws RED on top of everything
    // 4. Player erase
    // 5. Obstacle draw
    // 6. Player draw (normal)
    // 7. Obstacle erase (lowest)
    wire [nX-1:0] vga_x;
    wire [nY-1:0] vga_y;
    wire [COLOR_DEPTH-1:0] vga_color;
    wire vga_write;
    
    // Game is active only after title is complete
    wire game_active;
    assign game_active = title_complete & ~game_over;
    
    // Determine who gets VGA bus access based on priority
    assign vga_x = showing_title ? title_x :
                   erase_active ? erase_x :
                   (player_is_collision_mode && player_is_drawing) ? player_x :
                   player_is_erasing ? player_x :
                   obs_is_drawing ? obs_x :
                   player_is_drawing ? player_x :
                   obs_x;
    
    assign vga_y = showing_title ? title_y :
                   erase_active ? erase_y :
                   (player_is_collision_mode && player_is_drawing) ? player_y :
                   player_is_erasing ? player_y :
                   obs_is_drawing ? obs_y :
                   player_is_drawing ? player_y :
                   obs_y;
    
    assign vga_color = showing_title ? title_color :
                       erase_active ? erase_color :
                       (player_is_collision_mode && player_is_drawing) ? player_color :
                       player_is_erasing ? player_color :
                       obs_is_drawing ? obs_color :
                       player_is_drawing ? player_color :
                       obs_color;
    
    assign vga_write = title_write | erase_write | player_write | obs_write;
    
    // Title Screen - Shows at startup
    title_screen TITLE (
        .Resetn(Resetn),
        .Clock(CLOCK_50),
        .start_key(start_game_key),
        .showing_title(showing_title),
        .title_complete(title_complete),
        .VGA_x(title_x),
        .VGA_y(title_y),
        .VGA_color(title_color),
        .VGA_write(title_write)
    );
    
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
    
    // Screen Eraser - Clears entire game area on reset (only after title)
    screen_eraser ERASER (
        .Resetn(Resetn & title_complete),
        .Clock(CLOCK_50),
        .erase_active(erase_active),
        .erase_x(erase_x),
        .erase_y(erase_y),
        .erase_color(erase_color),
        .erase_write(erase_write)
    );
    
    // Player Object - NOW WITH COLLISION INPUT AND PRIORITY OUTPUT
    player_object PLAYER (
        .Resetn(Resetn & ~game_over & ~erase_active & title_complete),
        .Clock(CLOCK_50),
        .move_left(move_left & game_active),
        .move_right(move_right & game_active),
        .collision(collision),
        .player_lane(player_lane),
        .VGA_x(player_x),
        .VGA_y(player_y),
        .VGA_color(player_color),
        .VGA_write(player_write),
        .is_erasing(player_is_erasing),
        .is_drawing(player_is_drawing),
        .is_collision_mode(player_is_collision_mode)
    );
    
    // Obstacle Manager with Scoring
    multi_obstacle OBSTACLES (
        .Resetn(Resetn & ~game_over & ~erase_active & title_complete),
        .Clock(CLOCK_50),
        .player_lane(player_lane),
        .player_is_collision_mode(player_is_collision_mode),
        .VGA_x(obs_x),
        .VGA_y(obs_y),
        .VGA_color(obs_color),
        .VGA_write(obs_write),
        .collision(collision),
        .score_increment(score_increment),
        .is_erasing(obs_is_erasing),
        .is_drawing(obs_is_drawing)
    );
    
    // Game Over Handler with Lives System
    game_over_handler GAME_OVER (
        .Resetn(Resetn & title_complete),
        .Clock(CLOCK_50),
        .collision(collision),
        .game_over(game_over),
        .lives(lives),
        .HEX_display(HEX5)
    );
    
    // Score Counter - Displays on HEX0, HEX1, HEX2
    score_counter SCORE (
        .Resetn(Resetn & title_complete),
        .Clock(CLOCK_50),
        .score_increment(score_increment),
        .score(score),
        .HEX0(HEX0),
        .HEX1(HEX1),
        .HEX2(HEX2)
    );
    
    // VGA Adapter
    vga_adapter VGA (
        .resetn(Resetn),
        .clock(CLOCK_50),
        .color(vga_color),
        .x(vga_x),
        .y(vga_y),
        .write(vga_write),
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
    assign LEDR[3] = collision;
    assign LEDR[4] = game_over;
    assign LEDR[6:5] = lives;
    assign LEDR[7] = showing_title;        // Shows when title screen is active
    assign LEDR[8] = score_increment;      // Shows when score increases
    assign LEDR[9] = player_is_collision_mode;  // Shows when player is RED
    
endmodule

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
