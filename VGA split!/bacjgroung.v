/*
 * PLAYER_OBJECT.V - With Car Sprite and Background Restoration
 * 
 * ============ WHAT CHANGED ============
 * 
 * 1. CAR SPRITE (instead of solid cyan):
 *    - Added car_rom module that reads car.mif (60x60 image)
 *    - car_pixel gives us the color at each (pixel_x, pixel_y)
 * 
 * 2. TRANSPARENCY:
 *    - Pixels matching TRANSPARENT_COLOR are not drawn
 *    - Background shows through these pixels
 *    - Set to magenta (111_000_111) by default
 * 
 * 3. BACKGROUND RESTORATION:
 *    - Added background_rom that reads image.colour.mif
 *    - During ERASE, we read the actual background color
 *    - Draw that instead of white → clean erase!
 * 
 * 4. FIXED ROM TIMING:
 *    - ROM has 1-cycle delay: address set on cycle N, data ready on cycle N+1
 *    - Added one extra pixel to each drawing loop
 *    - This "primes" the ROM before we start using data
 * 
 * ============ HOW IT WORKS ============
 * 
 * Drawing sequence:
 * Cycle 1: Set address (0,0)
 * Cycle 2: ROM outputs color for (0,0), we draw it, set address (0,1)  
 * Cycle 3: ROM outputs color for (0,1), we draw it, set address (0,2)
 * ...and so on
 */

`default_nettype none

module player_object(
    input wire Resetn,
    input wire Clock,
    input wire move_left,
    input wire move_right,
    output reg [2:0] player_lane,
    output wire [nX-1:0] VGA_x,
    output wire [nY-1:0] VGA_y,
    output wire [COLOR_DEPTH-1:0] VGA_color,
    output wire VGA_write
);

    parameter nX = 10;
    parameter nY = 9;
    parameter COLOR_DEPTH = 9;

    parameter XSCREEN = 640;
    parameter YSCREEN = 480;
    
    parameter NUM_LANES = 5;
    parameter LANE_WIDTH = 80;
    parameter LANE_START_X = 120;

    parameter PLAYER_WIDTH = 60;
    parameter PLAYER_HEIGHT = 60;
    parameter PLAYER_Y_POS = 360;
    
    // Transparent color: any pixel in car.mif with this color won't be drawn
    parameter TRANSPARENT_COLOR = 9'b111_000_111;  // Magenta
    
    // FSM States (same as before)
    parameter INIT = 3'd0;
    parameter DRAW_INITIAL = 3'd1;
    parameter IDLE = 3'd2;
    parameter ERASE = 3'd3;
    parameter DRAW = 3'd4;

    reg [2:0] state;
    reg [2:0] target_lane;
    reg [nX-1:0] player_x_pos;
    reg [nX-1:0] prev_x_pos;
   
    // Counter goes one extra to handle ROM delay
    reg [6:0] pixel_x;  // Changed to 7 bits to go up to 61
    reg [6:0] pixel_y;  // Changed to 7 bits to go up to 61
    
    reg [nX-1:0] vga_x_reg;
    reg [nY-1:0] vga_y_reg;
    reg [COLOR_DEPTH-1:0] vga_color_reg;
    reg vga_write_reg;
    
    reg input_handled;
    
    // ===== CAR SPRITE ROM =====
    wire [11:0] car_address;
    wire [COLOR_DEPTH-1:0] car_pixel;
    
    // Address is based on CURRENT pixel_x, pixel_y
    assign car_address = (pixel_y >= PLAYER_HEIGHT) ? 12'd0 : 
                         (pixel_x >= PLAYER_WIDTH) ? 12'd0 :
                         (pixel_y * PLAYER_WIDTH + pixel_x);
    
    car_rom CAR_ROM (
        .address(car_address),
        .clock(Clock),
        .q(car_pixel)
    );
    
    // ===== BACKGROUND ROM =====
    wire [18:0] bg_address;
    wire [COLOR_DEPTH-1:0] bg_pixel;
    
    // During ERASE: read from old position
    // Otherwise: read from current position
    wire [nX-1:0] bg_x = (state == ERASE) ? prev_x_pos : player_x_pos;
    wire [6:0] safe_pixel_x = (pixel_x >= PLAYER_WIDTH) ? 7'd0 : pixel_x;
    wire [6:0] safe_pixel_y = (pixel_y >= PLAYER_HEIGHT) ? 7'd0 : pixel_y;
    
    assign bg_address = ((PLAYER_Y_POS + safe_pixel_y) * XSCREEN) + (bg_x + safe_pixel_x);
    
    background_rom BG_ROM (
        .address(bg_address),
        .clock(Clock),
        .q(bg_pixel)
    );

    function [nX-1:0] lane_to_x;
        input [2:0] lane;
        begin
            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) + ((LANE_WIDTH - PLAYER_WIDTH) / 2);
        end
    endfunction

    // FSM
    always @(posedge Clock) begin
        if (!Resetn) begin
            state <= INIT;
            player_lane <= 3'd2;
            player_x_pos <= lane_to_x(3'd2);
            prev_x_pos <= lane_to_x(3'd2);
            pixel_x <= 0;
            pixel_y <= 0;
            vga_write_reg <= 0;
            vga_color_reg <= 9'b0;
            input_handled <= 0;
        end
        else begin
            case (state)
                INIT: begin
                    pixel_x <= 0;
                    pixel_y <= 0;
                    vga_write_reg <= 0;
                    state <= DRAW_INITIAL;
                end
                
                DRAW_INITIAL: begin
                    // ROM TIMING EXPLANATION:
                    // pixel_x=0: ROM reads address 0, but output not ready yet
                    // pixel_x=1: ROM output for address 0 is ready, we write pixel (0,0)
                    //            ROM reads address 1
                    // pixel_x=2: ROM output for address 1 is ready, we write pixel (0,1)
                    //            ...and so on
                    
                    if (pixel_x > 0 && pixel_x <= PLAYER_WIDTH && pixel_y < PLAYER_HEIGHT) begin
                        // Write the previous pixel (ROM has caught up)
                        vga_x_reg <= player_x_pos + pixel_x - 1;
                        vga_y_reg <= PLAYER_Y_POS + pixel_y;
                        vga_color_reg <= car_pixel;
                        
                        // TRANSPARENCY: don't write if color is transparent
                        vga_write_reg <= (car_pixel != TRANSPARENT_COLOR);
                    end
                    else begin
                        vga_write_reg <= 0;
                    end
                    
                    // Increment counters (go one extra to finish last pixel)
                    if (pixel_x < PLAYER_WIDTH) begin
                        pixel_x <= pixel_x + 1;
                    end
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1) begin
                            pixel_y <= pixel_y + 1;
                        end
                        else begin
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= IDLE;
                        end
                    end
                end
                
                IDLE: begin
                    vga_write_reg <= 0;
                    
                    if (!input_handled) begin
                        if (move_left && player_lane > 0) begin
                            prev_x_pos <= player_x_pos;
                            player_lane <= player_lane - 1;
                            player_x_pos <= lane_to_x(player_lane - 1);
                            pixel_x <= 0;
                            pixel_y <= 0;
                            input_handled <= 1;
                            state <= ERASE;
                        end
                        else if (move_right && player_lane < NUM_LANES - 1) begin
                            prev_x_pos <= player_x_pos;
                            player_lane <= player_lane + 1;
                            player_x_pos <= lane_to_x(player_lane + 1);
                            pixel_x <= 0;
                            pixel_y <= 0;
                            input_handled <= 1;
                            state <= ERASE;
                        end
                    end
                    
                    if (!move_left && !move_right)
                        input_handled <= 0;
                end
                
                ERASE: begin
                    // BACKGROUND RESTORATION:
                    // Read actual background color from ROM and draw it
                    // This erases the player by restoring what was underneath
                    
                    if (pixel_x < PLAYER_WIDTH && pixel_y < PLAYER_HEIGHT) begin
                        vga_x_reg <= prev_x_pos + pixel_x;
                        vga_y_reg <= PLAYER_Y_POS + pixel_y;
                        vga_color_reg <= bg_pixel;  // Use background, not white!
                        vga_write_reg <= 1;
                    end
                    else begin
                        vga_write_reg <= 0;
                    end
                    
                    if (pixel_x < PLAYER_WIDTH - 1) begin
                        pixel_x <= pixel_x + 1;
                    end
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1) begin
                            pixel_y <= pixel_y + 1;
                        end
                        else begin
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= DRAW;
                        end
                    end
                end
                
                DRAW: begin
                    // Same as DRAW_INITIAL
                    if (pixel_x > 0 && pixel_x <= PLAYER_WIDTH && pixel_y < PLAYER_HEIGHT) begin
                        vga_x_reg <= player_x_pos + pixel_x - 1;
                        vga_y_reg <= PLAYER_Y_POS + pixel_y;
                        vga_color_reg <= car_pixel;
                        vga_write_reg <= (car_pixel != TRANSPARENT_COLOR);
                    end
                    else begin
                        vga_write_reg <= 0;
                    end
                    
                    if (pixel_x < PLAYER_WIDTH) begin
                        pixel_x <= pixel_x + 1;
                    end
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1) begin
                            pixel_y <= pixel_y + 1;
                        end
                        else begin
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

    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;

endmodule


// ============================================
// CAR SPRITE ROM
// ============================================
// Loads car.mif (60x60 pixels = 3600 total)
// Each pixel is 9 bits: RRR_GGG_BBB
// 
// To create car.mif:
// 1. Make 60x60 BMP with your car
// 2. Use magenta (255,0,255) for transparent areas
// 3. Convert with bmp_to_mif (set COLS=60, ROWS=60)
// 4. Rename to car.mif
module car_rom(
    input wire [11:0] address,
    input wire clock,
    output reg [8:0] q
);

    reg [8:0] memory [0:3599];
    
    initial begin
        $readmemh("car.mif", memory);
    end
    
    always @(posedge clock) begin
        q <= memory[address];
    end

endmodule


// ============================================
// BACKGROUND ROM
// ============================================
// Loads image.colour.mif (640x480 = 307200 pixels)
// This is THE SAME FILE that VGA adapter displays
// 
// Why we need this:
// - VGA adapter shows background automatically
// - But when we draw player, we overwrite background pixels
// - When player moves, we need to restore those pixels
// - This ROM lets us read what the background should be
// - We draw those colors = clean erase!
module background_rom(
    input wire [18:0] address,
    input wire clock,
    output reg [8:0] q
);

    reg [8:0] memory [0:307199];
    
    initial begin
        $readmemh("image.colour.mif", memory);
    end
    
    always @(posedge clock) begin
        q <= memory[address];
    end

endmodule