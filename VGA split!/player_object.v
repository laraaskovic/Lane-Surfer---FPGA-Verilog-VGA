/*
 * PLAYER_OBJECT.V
 * 
 * Save this as: player_object.v
 * 
 * 640x480 VGA Resolution Version
 * - Player moves between 5 lanes
 * - NO BLACK ERASING (background shows through naturally)
 * - Just draws player at new position when moving
 */

`default_nettype none

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

    // VGA parameters - 640x480 Resolution
    parameter nX = 10;          // 10 bits for 640 pixels
    parameter nY = 9;           // 9 bits for 480 pixels
    parameter COLOR_DEPTH = 9;
    
    // Screen dimensions
    parameter XSCREEN = 640;
    parameter YSCREEN = 480;
    
    // Lane configuration - 5 lanes in center 2/3 of screen
    parameter NUM_LANES = 5;
    parameter LANE_WIDTH = 80;          // Each lane is 80 pixels wide (640*2/3 / 5)
    parameter LANE_START_X = 120;       // Lanes start at X=120 (1/6 of 640)
    // Total lane area: 5 lanes * 80 pixels = 400 pixels (120 to 520)
    
    // Player dimensions - scaled up for 640x480
    parameter PLAYER_WIDTH = 60;        // 60 pixels wide
    parameter PLAYER_HEIGHT = 60;       // 60 pixels tall (square)
    parameter PLAYER_Y_POS = 360;       // Y position (fixed, near bottom)
    
    // Colors
    parameter PLAYER_COLOR = 9'b000_111_111;  // Cyan
    
    // FSM States - SIMPLIFIED (no erasing!)
    parameter INIT = 2'd0;              // Initialize
    parameter DRAW_INITIAL = 2'd1;      // Draw at starting position
    parameter IDLE = 2'd2;              // Wait for input
    parameter DRAW = 2'd3;              // Draw player at new position
    
    reg [1:0] state;                    // Current FSM state
    reg [2:0] target_lane;              // Lane to move to
    reg [nX-1:0] player_x_pos;          // Top-left X coordinate
    reg [5:0] pixel_x;                  // Pixel counter X (0-59)
    reg [5:0] pixel_y;                  // Pixel counter Y (0-59)
    reg [nX-1:0] vga_x_reg;             // Registered VGA X output
    reg [nY-1:0] vga_y_reg;             // Registered VGA Y output
    reg [COLOR_DEPTH-1:0] vga_color_reg; // Registered VGA color
    reg vga_write_reg;                  // Registered VGA write
    reg input_handled;                  // Flag to prevent multiple moves per press
    
    // Function: Convert lane number to X coordinate
    // Centers the player within each lane
    function [nX-1:0] lane_to_x;
        input [2:0] lane;
        begin
            // Formula: X = LANE_START + (lane * LANE_WIDTH) + centering_offset
            // Centering offset = (LANE_WIDTH - PLAYER_WIDTH) / 2 = 10
            // Lane 0: 120 + (0*80) + 10 = 130
            // Lane 1: 120 + (1*80) + 10 = 210
            // Lane 2: 120 + (2*80) + 10 = 290 (middle)
            // Lane 3: 120 + (3*80) + 10 = 370
            // Lane 4: 120 + (4*80) + 10 = 450
            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) + 
                       ((LANE_WIDTH - PLAYER_WIDTH) / 2);
        end
    endfunction
    
    // =====================================================
    // Main FSM - Simplified (no erasing needed!)
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
            vga_color_reg <= PLAYER_COLOR;
            vga_write_reg <= 0;
            input_handled <= 0;
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
                    input_handled <= 0;
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
                    
                    // Scan through all pixels (60x60)
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
                    
                    // Check for movement and update position
                    if (!input_handled) begin
                        if (move_left && player_lane > 0) begin
                            player_lane <= player_lane - 1;
                            player_x_pos <= lane_to_x(player_lane - 1);
                            pixel_x <= 0;
                            pixel_y <= 0;
                            input_handled <= 1;
                            state <= DRAW;
                        end
                        else if (move_right && player_lane < NUM_LANES - 1) begin
                            player_lane <= player_lane + 1;
                            player_x_pos <= lane_to_x(player_lane + 1);
                            pixel_x <= 0;
                            pixel_y <= 0;
                            input_handled <= 1;
                            state <= DRAW;
                        end
                    end
                    
                    // Reset input_handled when keys released
                    if (!move_left && !move_right) begin
                        input_handled <= 0;
                    end
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
                    
                    // Scan through all pixels (60x60)
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
                            state <= IDLE;
                        end
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