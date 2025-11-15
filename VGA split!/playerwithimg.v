/*
 * PLAYER_OBJECT.V - Simple addition of car MIF with transparency
 * 
 * Only changes:
 * 1. Added car ROM to read car.mif
 * 2. Changed PLAYER_COLOR to read from ROM instead of solid cyan
 * 3. Added transparency check (skip writing transparent pixels)
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
    
    // NEW: Transparency color
    // Whatever color you use in car.mif for "empty" areas
    parameter TRANSPARENT_COLOR = 9'b111_000_111;  // Magenta - change to match your car.mif
    
    parameter ERASE_COLOR  = 9'b111_111_111;  // White (erases)
    
    // FSM States (UNCHANGED)
    parameter INIT = 3'd0;
    parameter DRAW_INITIAL = 3'd1;
    parameter IDLE = 3'd2;
    parameter ERASE = 3'd3;
    parameter DRAW = 3'd4;

    reg [2:0] state;
    reg [2:0] target_lane;
    reg [nX-1:0] player_x_pos;
    reg [nX-1:0] prev_x_pos;
   
    reg [5:0] pixel_x;
    reg [5:0] pixel_y;
    
    reg [nX-1:0] vga_x_reg;
    reg [nY-1:0] vga_y_reg;
    reg [COLOR_DEPTH-1:0] vga_color_reg;
    reg vga_write_reg;
    
    reg input_handled;
    
    // NEW: ROM signals for car image
    wire [11:0] car_address;           // Address into car ROM (60x60 = 3600 pixels)
    wire [COLOR_DEPTH-1:0] car_pixel;  // Color read from car ROM
    
    // NEW: Calculate address into car ROM
    // For a 60x60 image: address = row * 60 + column
    assign car_address = pixel_y * PLAYER_WIDTH + pixel_x;
    
    // NEW: Instantiate ROM for car sprite
    car_rom CAR_ROM (
        .address(car_address),
        .clock(Clock),
        .q(car_pixel)
    );

    function [nX-1:0] lane_to_x;
        input [2:0] lane;
        begin
            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) + ((LANE_WIDTH - PLAYER_WIDTH) / 2);
        end
    endfunction

    // FSM (mostly UNCHANGED, just modified color assignments)
    always @(posedge Clock) begin
        if (!Resetn) begin
            state <= INIT;
            player_lane <= 3'd2;
            player_x_pos <= lane_to_x(3'd2);
            prev_x_pos <= lane_to_x(3'd2);
            pixel_x <= 0;
            pixel_y <= 0;
            vga_write_reg <= 0;
            vga_color_reg <= ERASE_COLOR;
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
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= car_pixel;  // CHANGED: Use ROM color instead of solid cyan
                    
                    // CHANGED: Only write if NOT transparent
                    vga_write_reg <= (car_pixel != TRANSPARENT_COLOR);
                    
                    if (pixel_x < PLAYER_WIDTH - 1)
                        pixel_x <= pixel_x + 1;
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1)
                            pixel_y <= pixel_y + 1;
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
                    vga_x_reg <= prev_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= ERASE_COLOR;  // Still white for now
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
                
                DRAW: begin
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= car_pixel;  // CHANGED: Use ROM color
                    
                    // CHANGED: Only write if NOT transparent
                    vga_write_reg <= (car_pixel != TRANSPARENT_COLOR);
                    
                    if (pixel_x < PLAYER_WIDTH - 1)
                        pixel_x <= pixel_x + 1;
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1)
                            pixel_y <= pixel_y + 1;
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


// NEW MODULE: ROM for car sprite (60x60 pixels)
module car_rom(
    input wire [11:0] address,   // 12 bits for 3600 pixels
    input wire clock,
    output reg [8:0] q           // 9-bit color
);

    reg [8:0] memory [0:3599];   // 60 * 60 = 3600 pixels
    
    initial begin
        $readmemh("car.mif", memory);
    end
    
    always @(posedge clock) begin
        q <= memory[address];
    end

endmodule