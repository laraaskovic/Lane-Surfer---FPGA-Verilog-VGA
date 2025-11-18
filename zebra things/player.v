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
    parameter PLAYER_COLOR = 9'b000_111_111;
    parameter ERASE_COLOR = 9'b111_111_111;
    
    // FSM States - ADDED CLEAR_ON_RESET
    parameter CLEAR_ON_RESET = 3'd5;  // NEW: Clear old player
    parameter INIT = 3'd0;
    parameter DRAW_INITIAL = 3'd1;
    parameter IDLE = 3'd2;
    parameter ERASE = 3'd3;
    parameter DRAW = 3'd4;

    reg [2:0] state = CLEAR_ON_RESET;
    reg [nX-1:0] player_x_pos = 10'd290;
    reg [nX-1:0] prev_x_pos = 10'd290;
    reg [5:0] pixel_x = 0;
    reg [5:0] pixel_y = 0;
    reg [nX-1:0] vga_x_reg = 0;
    reg [nY-1:0] vga_y_reg = 0;
    reg [COLOR_DEPTH-1:0] vga_color_reg = 9'b0;
    reg vga_write_reg = 0;
    reg input_handled = 0;
    
    // Track last position for clearing
    reg [nX-1:0] last_x = 10'd290;
    reg [2:0] last_lane = 3'd2;

    function [nX-1:0] lane_to_x;
        input [2:0] lane;
        begin
            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) + ((LANE_WIDTH - PLAYER_WIDTH) / 2);
        end
    endfunction

    always @(posedge Clock) begin
        if (!Resetn) begin
            // Save current position for clearing
            last_x <= player_x_pos;
            last_lane <= player_lane;
            
            // Start clearing sequence
            state <= CLEAR_ON_RESET;
            pixel_x <= 0;
            pixel_y <= 0;
            vga_write_reg <= 0;
            input_handled <= 0;
        end
        else begin
            case (state)
                // ================================================
                // CLEAR_ON_RESET - Erase player at old position
                // ================================================
                CLEAR_ON_RESET: begin
                    vga_x_reg <= last_x + pixel_x;
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
                            // Done clearing, initialize to middle
                            pixel_x <= 0;
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            
                            player_lane <= 3'd2;
                            player_x_pos <= lane_to_x(3'd2);
                            prev_x_pos <= lane_to_x(3'd2);
                            
                            state <= INIT;
                        end
                    end
                end
                
                INIT: begin
                    pixel_x <= 0;
                    pixel_y <= 0;
                    vga_write_reg <= 0;
                    state <= DRAW_INITIAL;
                end
                
                DRAW_INITIAL: begin
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= PLAYER_COLOR;
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
                            state <= IDLE;
                        end
                    end
                end
                
                IDLE: begin
                    vga_write_reg <= 0;
                    
                    // Update last position continuously
                    last_x <= player_x_pos;
                    last_lane <= player_lane;
                    
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
                
                DRAW: begin
                    vga_x_reg <= player_x_pos + pixel_x;
                    vga_y_reg <= PLAYER_Y_POS + pixel_y;
                    vga_color_reg <= PLAYER_COLOR;
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
                            state <= IDLE;
                        end
                    end
                end

                default: state <= CLEAR_ON_RESET;
            endcase
        end
    end

    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;

endmodule