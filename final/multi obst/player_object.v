/*
 * PLAYER_OBJECT.V
 *
 * 640x480 VGA Resolution Version
 * - Player moves between 5 lanes
 * - Erases old position (black)
 * - Draws player at new position
 * - Turns solid RED for 2 seconds on collision (movement still enabled)
 * - CONTINUOUSLY REDRAWS during collision to maintain priority over obstacles
 */

`default_nettype none

module player_object(
    input wire Resetn,
    input wire Clock,
    input wire move_left,
    input wire move_right,
    input wire collision,               // Collision signal from obstacle module
    output reg [2:0] player_lane,       // Current lane (0-4)
    output wire [nX-1:0] VGA_x,         // VGA pixel X coordinate
    output wire [nY-1:0] VGA_y,         // VGA pixel Y coordinate
    output wire [COLOR_DEPTH-1:0] VGA_color,  // VGA pixel color
    output wire VGA_write,              // VGA write enable
    output wire is_erasing,             // High when in ERASE state
    output wire is_drawing,             // High when in DRAW or DRAW_INITIAL state
    output wire is_collision_mode       // High when player is in collision mode (red)
);

    // VGA parameters - 640x480 Resolution
    parameter nX = 10;          // 10 bits for 640 pixels
    parameter nY = 9;           // 9 bits for 480 pixels
    parameter COLOR_DEPTH = 9;
   
    // Screen dimensions
    parameter XSCREEN = 640;
    parameter YSCREEN = 480;
   
    // Lane configuration
    parameter NUM_LANES = 5;
    parameter LANE_WIDTH = 80;
    parameter LANE_START_X = 120;
   
    // Player dimensions
    parameter PLAYER_WIDTH = 60;
    parameter PLAYER_HEIGHT = 60;
    parameter PLAYER_Y_POS = 360;
   
    // Colors
    parameter PLAYER_COLOR_NORMAL = 9'b000_111_111;  // Cyan (normal)
    parameter PLAYER_COLOR_COLLISION = 9'b111_000_000;  // Red (collision)
    parameter ERASE_COLOR  = 9'b000_000_000;  // Black (erases)
   
    // Collision timer - 2 seconds at 50MHz = 100,000,000 cycles
    parameter COLLISION_DURATION = 27'd100_000_000;
    
    // Redraw interval during collision - match obstacle update cycle
    // This ensures player redraws as frequently as obstacles
    parameter REDRAW_INTERVAL = 23'd500_000;  // ~100Hz redraw rate
   
    // FSM States
    parameter INIT = 3'd0;
    parameter DRAW_INITIAL = 3'd1;
    parameter IDLE = 3'd2;
    parameter ERASE = 3'd3;
    parameter DRAW = 3'd4;
    parameter COLLISION_REDRAW = 3'd5;  // NEW: Continuous redraw state
   
    reg [2:0] state;
    reg [2:0] next_state_after_draw;  // Remember where to return after drawing
    reg [nX-1:0] player_x_pos;
    reg [nX-1:0] prev_x_pos;
    reg [5:0] pixel_x;
    reg [5:0] pixel_y;
   
    reg [nX-1:0] vga_x_reg;
    reg [nY-1:0] vga_y_reg;
    reg [COLOR_DEPTH-1:0] vga_color_reg;
    reg vga_write_reg;
   
    reg input_handled;
    
    // Collision state tracking
    reg collision_prev;            // For edge detection
    reg in_collision_mode;         // Currently in collision mode (red)
    reg [26:0] collision_timer;    // Timer for 2-second red duration
    
    // Redraw timing during collision
    reg [22:0] redraw_counter;     // Counter for redraw intervals
   
    // Convert lane number to X coordinate
    function [nX-1:0] lane_to_x;
        input [2:0] lane;
        begin
            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) +
                       ((LANE_WIDTH - PLAYER_WIDTH) / 2);
        end
    endfunction
    
    // Determine current player color based on collision state
    wire [COLOR_DEPTH-1:0] current_player_color;
    assign current_player_color = in_collision_mode ? PLAYER_COLOR_COLLISION : PLAYER_COLOR_NORMAL;

    // FSM
    always @(posedge Clock) begin
        if (!Resetn) begin
            state <= INIT;
            next_state_after_draw <= IDLE;
            player_lane <= 3'd2;
            player_x_pos <= 10'd0;  // Will be set in INIT state
            prev_x_pos <= 10'd0;
            pixel_x <= 0;
            pixel_y <= 0;
            vga_x_reg <= 10'd0;
            vga_y_reg <= 9'd0;
            vga_write_reg <= 0;
            vga_color_reg <= PLAYER_COLOR_NORMAL;
            input_handled <= 0;
            collision_prev <= 0;
            in_collision_mode <= 0;
            collision_timer <= 0;
            redraw_counter <= 0;
        end
        else begin
            // Collision edge detection - start timer on rising edge of collision
            collision_prev <= collision;
            if (collision && !collision_prev) begin
                in_collision_mode <= 1;
                collision_timer <= 0;
                redraw_counter <= 0;
            end
            
            // Update collision timer when in collision mode
            if (in_collision_mode) begin
                if (collision_timer < COLLISION_DURATION) begin
                    collision_timer <= collision_timer + 1;
                end else begin
                    // Timer expired - exit collision mode
                    in_collision_mode <= 0;
                    collision_timer <= 0;
                end
            end
            
            case (state)
                // --------------------------------------------------
                INIT: begin
                    // Calculate the initial position for lane 2
                    player_x_pos <= lane_to_x(player_lane);
                    prev_x_pos <= lane_to_x(player_lane);
                    pixel_x <= 0;
                    pixel_y <= 0;
                    vga_write_reg <= 0;
                    next_state_after_draw <= IDLE;
                    state <= DRAW_INITIAL;
                end

                // --------------------------------------------------
                DRAW_INITIAL: begin
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= current_player_color;
                    vga_write_reg <= 1;
                   
                    if (pixel_x < PLAYER_WIDTH - 1)
                        pixel_x <= pixel_x + 1;
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1)
                            pixel_y <= pixel_y + 1;
                        else begin
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= next_state_after_draw;
                        end
                    end
                end

                // --------------------------------------------------
                IDLE: begin
                    vga_write_reg <= 0;
                    
                    // Check if we need to continuously redraw during collision
                    if (in_collision_mode) begin
                        redraw_counter <= redraw_counter + 1;
                        if (redraw_counter >= REDRAW_INTERVAL) begin
                            redraw_counter <= 0;
                            pixel_x <= 0;
                            pixel_y <= 0;
                            next_state_after_draw <= IDLE;
                            state <= COLLISION_REDRAW;
                        end
                    end
                    
                    // Movement is ALWAYS allowed, regardless of collision state
                    if (!input_handled) begin
                        if (move_left && player_lane > 0) begin
                            prev_x_pos <= player_x_pos;
                            player_lane <= player_lane - 1;
                            player_x_pos <= lane_to_x(player_lane - 1);
                            pixel_x <= 0;
                            pixel_y <= 0;
                            input_handled <= 1;
                            next_state_after_draw <= IDLE;
                            state <= ERASE;
                        end
                        else if (move_right && player_lane < NUM_LANES - 1) begin
                            prev_x_pos <= player_x_pos;
                            player_lane <= player_lane + 1;
                            player_x_pos <= lane_to_x(player_lane + 1);
                            pixel_x <= 0;
                            pixel_y <= 0;
                            input_handled <= 1;
                            next_state_after_draw <= IDLE;
                            state <= ERASE;
                        end
                    end
                   
                    if (!move_left && !move_right)
                        input_handled <= 0;
                end

                // --------------------------------------------------
                ERASE: begin
                    vga_x_reg <= prev_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= ERASE_COLOR;
                    vga_write_reg <= 1;
                   
                    if (pixel_x < PLAYER_WIDTH - 1)
                        pixel_x <= pixel_x + 1;
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1)
                            pixel_y <= pixel_y + 1;
                        else begin
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= DRAW;
                        end
                    end
                end

                // --------------------------------------------------
                DRAW: begin
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= current_player_color;  // Will be red if in collision mode
                    vga_write_reg <= 1;
                   
                    if (pixel_x < PLAYER_WIDTH - 1)
                        pixel_x <= pixel_x + 1;
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1)
                            pixel_y <= pixel_y + 1;
                        else begin
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= next_state_after_draw;
                        end
                    end
                end

                // --------------------------------------------------
                COLLISION_REDRAW: begin
                    // Continuously redraw player in red to stay on top of obstacles
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= current_player_color;  // Red during collision
                    vga_write_reg <= 1;
                   
                    if (pixel_x < PLAYER_WIDTH - 1)
                        pixel_x <= pixel_x + 1;
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1)
                            pixel_y <= pixel_y + 1;
                        else begin
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= next_state_after_draw;
                        end
                    end
                end

                default: state <= INIT;
            endcase
        end
    end

    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;
    
    // State detection for arbiter priority
    assign is_erasing = (state == ERASE);
    assign is_drawing = (state == DRAW) || (state == DRAW_INITIAL) || (state == COLLISION_REDRAW);
    assign is_collision_mode = in_collision_mode;  // Signal for priority arbiter

endmodule
