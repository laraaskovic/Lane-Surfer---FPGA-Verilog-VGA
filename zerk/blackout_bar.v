`default_nettype none

/*
 * BLACKOUT_BAR.V
 * 
 * Draws a black bar at the top of the screen to hide obstacle spawning glitches
 * Continuously redraws to cover any visual artifacts
 */

module blackout_bar(
    input wire Resetn,
    input wire Clock,
    input wire enable,              // Enable drawing (should be high during gameplay)
    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output wire [8:0] VGA_color,
    output wire VGA_write
);

    parameter XSCREEN = 640;
    parameter BAR_HEIGHT = 80;      // Height of black bar (covers spawn zone)
    parameter BLACK = 9'b000_000_000;
    
    parameter LANE_START_X = 120;
    parameter LANE_END_X = 520;     // 5 lanes * 80px = 400px wide
    
    parameter IDLE = 1'd0;
    parameter DRAWING = 1'd1;
    
    reg state;
    reg [9:0] draw_x;
    reg [6:0] draw_y;               // 0-79 for bar height
    reg [22:0] refresh_counter;     // Refresh every ~0.1 seconds
    parameter REFRESH_INTERVAL = 23'd5_000_000;  // Redraw frequently
    
    reg [9:0] vga_x_reg;
    reg [8:0] vga_y_reg;
    reg [8:0] vga_color_reg;
    reg vga_write_reg;
    
    always @(posedge Clock) begin
        if (!Resetn) begin
            state <= IDLE;
            draw_x <= LANE_START_X;
            draw_y <= 0;
            refresh_counter <= 0;
            vga_write_reg <= 0;
        end
        else if (enable) begin
            case (state)
                IDLE: begin
                    vga_write_reg <= 0;
                    
                    // Refresh timer - constantly redraw to cover glitches
                    if (refresh_counter < REFRESH_INTERVAL) begin
                        refresh_counter <= refresh_counter + 1;
                    end
                    else begin
                        refresh_counter <= 0;
                        draw_x <= LANE_START_X;
                        draw_y <= 0;
                        state <= DRAWING;
                    end
                end
                
                DRAWING: begin
                    // Draw black pixel
                    vga_x_reg <= draw_x;
                    vga_y_reg <= {2'b00, draw_y};  // Extend to 9 bits
                    vga_color_reg <= BLACK;
                    vga_write_reg <= 1;
                    
                    // Scan across lane area
                    if (draw_x < LANE_END_X) begin
                        draw_x <= draw_x + 1;
                    end
                    else begin
                        draw_x <= LANE_START_X;
                        
                        // Move to next row
                        if (draw_y < BAR_HEIGHT - 1) begin
                            draw_y <= draw_y + 1;
                        end
                        else begin
                            // Finished drawing bar
                            draw_y <= 0;
                            vga_write_reg <= 0;
                            state <= IDLE;
                        end
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
        else begin
            vga_write_reg <= 0;
            state <= IDLE;
        end
    end
    
    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;

endmodule