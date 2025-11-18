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

    // ... (keep all your parameters the same)
    
    // Colors
    parameter ERASE_COLOR  = 9'b111_111_111;  // White (erases)
    
    // FSM states
    parameter INIT = 3'd0;
    parameter DRAW_INITIAL = 3'd1;
    parameter IDLE = 3'd2;
    parameter ERASE = 3'd3;
    parameter DRAW = 3'd4;

    // ... (keep all your reg declarations)
    
    // ============================================
    // ROM INSTANTIATION FOR PLAYER IMAGE
    // ============================================
    wire [11:0] rom_address;  // 60x60 = 3600 pixels needs 12 bits
    wire [8:0] rom_color;     // Color from ROM
    
    // Calculate ROM address: address = pixel_y * WIDTH + pixel_x
    assign rom_address = (pixel_y * PLAYER_WIDTH) + pixel_x;
    
    // Instantiate your ROM (replace 'player_image_rom' with your actual module name)
    player_image_rom PLAYER_ROM (
        .address(rom_address),
        .clock(Clock),
        .q(rom_color)
    );
    // ============================================

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
            vga_color_reg <= 9'b0;  // Changed from PLAYER_COLOR
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
                    vga_color_reg <= rom_color;  // USE ROM COLOR
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
                    vga_color_reg <= ERASE_COLOR;  // Still use white to erase
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
                    vga_color_reg <= rom_color;  // USE ROM COLOR
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

                default: state <= INIT;
            endcase
        end
    end

    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;

endmodule