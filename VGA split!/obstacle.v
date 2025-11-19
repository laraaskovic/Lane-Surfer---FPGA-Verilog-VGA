`default_nettype none

module multi_obstacle(
    input wire Resetn,
    input wire Clock,
    input wire [2:0] player_lane,
    input wire [9:0] player_x,      // NEW: Player position for masking
    input wire [8:0] player_y,
    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output wire [8:0] VGA_color,
    output wire VGA_write,
    output reg collision
);

    parameter XSCREEN = 640;
    parameter YSCREEN = 480;
    parameter NUM_LANES = 5;
    parameter LANE_WIDTH = 80;
    parameter LANE_START_X = 120;
    parameter OBS_WIDTH = 60;
    parameter OBS_HEIGHT = 60;
    parameter MAX_OBSTACLES = 4;
    parameter PLAYER_Y_POS = 360;
    parameter PLAYER_HEIGHT = 60;
    parameter PLAYER_WIDTH = 60;
    parameter OBS_COLOR = 9'b111_000_111;
    parameter ERASE_COLOR = 9'b000_000_000;

    // FSM States - REMOVED ERASE STATE (only erase when moving/clearing)
    parameter CLEAR_ALL = 3'd5;
    parameter IDLE = 3'd0;
    parameter MOVE_CHECK = 3'd1;      // Check if obstacles need to move
    parameter ERASE_MOVED = 3'd2;     // Only erase obstacles that moved
    parameter DRAW_OBS = 3'd3;
    parameter CHECK_COLLISION = 3'd4;

    reg active0, active1, active2, active3;
    reg [2:0] obs_lane0, obs_lane1, obs_lane2, obs_lane3;
    reg signed [9:0] obs_y0, obs_y1, obs_y2, obs_y3;
    reg [9:0] obs_x0, obs_x1, obs_x2, obs_x3;
    
    // Previous Y positions for selective erasing
    reg signed [9:0] prev_y0, prev_y1, prev_y2, prev_y3;
    
    // Flags for which obstacles moved
    reg moved0, moved1, moved2, moved3;
    
    // Save for clearing
    reg [9:0] clear_x0, clear_x1, clear_x2, clear_x3;
    reg signed [9:0] clear_y0, clear_y1, clear_y2, clear_y3;
    reg clear_active0, clear_active1, clear_active2, clear_active3;

    reg [1:0] current_obs;
    reg [5:0] pixel_x, pixel_y;
    reg [2:0] state;
    reg [22:0] speed_counter;
    parameter SPEED_LIMIT = 23'd2_000_000;  // Slower = smoother
    reg [26:0] spawn_counter;
    parameter SPAWN_INTERVAL = 27'd100_000_000;
    reg [2:0] next_spawn_lane;
    reg [9:0] vga_x_reg;
    reg [8:0] vga_y_reg, vga_color_reg;
    reg vga_write_reg;

    function [9:0] lane_to_x;
        input [2:0] lane;
        begin
            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) + ((LANE_WIDTH - OBS_WIDTH) / 2);
        end
    endfunction
    
    // Check if current pixel overlaps with player
    wire overlaps_player;
    assign overlaps_player = (vga_x_reg >= player_x && vga_x_reg < player_x + PLAYER_WIDTH &&
                              vga_y_reg >= player_y && vga_y_reg < player_y + PLAYER_HEIGHT);

    always @(posedge Clock) begin
        if (!Resetn) begin
            clear_x0 <= obs_x0; clear_y0 <= obs_y0; clear_active0 <= active0;
            clear_x1 <= obs_x1; clear_y1 <= obs_y1; clear_active1 <= active1;
            clear_x2 <= obs_x2; clear_y2 <= obs_y2; clear_active2 <= active2;
            clear_x3 <= obs_x3; clear_y3 <= obs_y3; clear_active3 <= active3;
            
            state <= CLEAR_ALL;
            current_obs <= 0;
            pixel_x <= 0;
            pixel_y <= 0;
            vga_write_reg <= 0;
            collision <= 0;
            speed_counter <= 0;
            spawn_counter <= 0;
            next_spawn_lane <= 0;
            
            active0 <= 0; obs_y0 <= -60; prev_y0 <= -60; moved0 <= 0;
            active1 <= 0; obs_y1 <= -60; prev_y1 <= -60; moved1 <= 0;
            active2 <= 0; obs_y2 <= -60; prev_y2 <= -60; moved2 <= 0;
            active3 <= 0; obs_y3 <= -60; prev_y3 <= -60; moved3 <= 0;
        end
        else begin
            // Spawn only when not clearing
            if (state != CLEAR_ALL) begin
                spawn_counter <= spawn_counter + 1;
                if (spawn_counter >= SPAWN_INTERVAL) begin
                    spawn_counter <= 0;
                    if (!active0) begin
                        active0 <= 1;
                        obs_lane0 <= next_spawn_lane;
                        obs_x0 <= lane_to_x(next_spawn_lane);
                        obs_y0 <= -60;
                        prev_y0 <= -60;
                    end
                    else if (!active1) begin
                        active1 <= 1;
                        obs_lane1 <= next_spawn_lane;
                        obs_x1 <= lane_to_x(next_spawn_lane);
                        obs_y1 <= -60;
                        prev_y1 <= -60;
                    end
                    else if (!active2) begin
                        active2 <= 1;
                        obs_lane2 <= next_spawn_lane;
                        obs_x2 <= lane_to_x(next_spawn_lane);
                        obs_y2 <= -60;
                        prev_y2 <= -60;
                    end
                    else if (!active3) begin
                        active3 <= 1;
                        obs_lane3 <= next_spawn_lane;
                        obs_x3 <= lane_to_x(next_spawn_lane);
                        obs_y3 <= -60;
                        prev_y3 <= -60;
                    end
                    next_spawn_lane <= (next_spawn_lane == 4) ? 0 : next_spawn_lane + 1;
                end
            end

            case (state)
                CLEAR_ALL: begin
                    // [Same clearing code as before - abbreviated for space]
                    if (current_obs == 0) begin
                        if (clear_active0 && clear_y0 >= 0 && clear_y0 < YSCREEN) begin
                            vga_x_reg <= clear_x0 + pixel_x;
                            vga_y_reg <= clear_y0[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 1;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 1;
                        end
                    end
                    else if (current_obs == 1) begin
                        if (clear_active1 && clear_y1 >= 0 && clear_y1 < YSCREEN) begin
                            vga_x_reg <= clear_x1 + pixel_x;
                            vga_y_reg <= clear_y1[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 2;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 2;
                        end
                    end
                    else if (current_obs == 2) begin
                        if (clear_active2 && clear_y2 >= 0 && clear_y2 < YSCREEN) begin
                            vga_x_reg <= clear_x2 + pixel_x;
                            vga_y_reg <= clear_y2[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 3;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 3;
                        end
                    end
                    else if (current_obs == 3) begin
                        if (clear_active3 && clear_y3 >= 0 && clear_y3 < YSCREEN) begin
                            vga_x_reg <= clear_x3 + pixel_x;
                            vga_y_reg <= clear_y3[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0;
                                    current_obs <= 0; state <= IDLE;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0;
                            current_obs <= 0; state <= IDLE;
                        end
                    end
                end

                IDLE: begin
                    vga_write_reg <= 0;
                    if (speed_counter < SPEED_LIMIT)
                        speed_counter <= speed_counter + 1;
                    else begin
                        speed_counter <= 0;
                        state <= MOVE_CHECK;
                    end
                end

                MOVE_CHECK: begin
                    // Move obstacles and check which ones moved
                    vga_write_reg <= 0;
                    
                    // Obstacle 0
                    prev_y0 <= obs_y0;
                    if (active0) begin
                        if (obs_y0 >= YSCREEN) begin
                            active0 <= 0;
                            moved0 <= 1;  // Need to erase
                        end
                        else begin
                            obs_y0 <= obs_y0 + 2;
                            moved0 <= 1;
                        end
                    end
                    else moved0 <= 0;
                    
                    // Obstacle 1
                    prev_y1 <= obs_y1;
                    if (active1) begin
                        if (obs_y1 >= YSCREEN) begin
                            active1 <= 0;
                            moved1 <= 1;
                        end
                        else begin
                            obs_y1 <= obs_y1 + 2;
                            moved1 <= 1;
                        end
                    end
                    else moved1 <= 0;
                    
                    // Obstacle 2
                    prev_y2 <= obs_y2;
                    if (active2) begin
                        if (obs_y2 >= YSCREEN) begin
                            active2 <= 0;
                            moved2 <= 1;
                        end
                        else begin
                            obs_y2 <= obs_y2 + 2;
                            moved2 <= 1;
                        end
                    end
                    else moved2 <= 0;
                    
                    // Obstacle 3
                    prev_y3 <= obs_y3;
                    if (active3) begin
                        if (obs_y3 >= YSCREEN) begin
                            active3 <= 0;
                            moved3 <= 1;
                        end
                        else begin
                            obs_y3 <= obs_y3 + 2;
                            moved3 <= 1;
                        end
                    end
                    else moved3 <= 0;
                    
                    current_obs <= 0;
                    pixel_x <= 0;
                    pixel_y <= 0;
                    state <= ERASE_MOVED;
                end

                ERASE_MOVED: begin
                    // Only erase obstacles that moved
                    if (current_obs == 0) begin
                        if (moved0 && prev_y0 >= 0 && prev_y0 < YSCREEN) begin
                            vga_x_reg <= obs_x0 + pixel_x;
                            vga_y_reg <= prev_y0[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 1;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 1;
                        end
                    end
                    else if (current_obs == 1) begin
                        if (moved1 && prev_y1 >= 0 && prev_y1 < YSCREEN) begin
                            vga_x_reg <= obs_x1 + pixel_x;
                            vga_y_reg <= prev_y1[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 2;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 2;
                        end
                    end
                    else if (current_obs == 2) begin
                        if (moved2 && prev_y2 >= 0 && prev_y2 < YSCREEN) begin
                            vga_x_reg <= obs_x2 + pixel_x;
                            vga_y_reg <= prev_y2[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 3;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 3;
                        end
                    end
                    else if (current_obs == 3) begin
                        if (moved3 && prev_y3 >= 0 && prev_y3 < YSCREEN) begin
                            vga_x_reg <= obs_x3 + pixel_x;
                            vga_y_reg <= prev_y3[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0;
                                    current_obs <= 0; state <= DRAW_OBS;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0;
                            current_obs <= 0; state <= DRAW_OBS;
                        end
                    end
                end

                DRAW_OBS: begin
                    if (current_obs == 0) begin
                        if (active0 && obs_y0 >= 0 && obs_y0 < YSCREEN) begin
                            vga_x_reg <= obs_x0 + pixel_x;
                            vga_y_reg <= obs_y0[8:0] + pixel_y;
                            vga_color_reg <= OBS_COLOR;
                            // Don't write if overlapping player
                            vga_write_reg <= !overlaps_player;
                            
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 1;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 1;
                        end
                    end
                    else if (current_obs == 1) begin
                        if (active1 && obs_y1 >= 0 && obs_y1 < YSCREEN) begin
                            vga_x_reg <= obs_x1 + pixel_x;
                            vga_y_reg <= obs_y1[8:0] + pixel_y;
                            vga_color_reg <= OBS_COLOR;
                            vga_write_reg <= !overlaps_player;
                            
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 2;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 2;
                        end
                    end
                    else if (current_obs == 2) begin
                        if (active2 && obs_y2 >= 0 && obs_y2 < YSCREEN) begin
                            vga_x_reg <= obs_x2 + pixel_x;
                            vga_y_reg <= obs_y2[8:0] + pixel_y;
                            vga_color_reg <= OBS_COLOR;
                            vga_write_reg <= !overlaps_player;
                            
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0; current_obs <= 3;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0; current_obs <= 3;
                        end
                    end
                    else if (current_obs == 3) begin
                        if (active3 && obs_y3 >= 0 && obs_y3 < YSCREEN) begin
                            vga_x_reg <= obs_x3 + pixel_x;
                            vga_y_reg <= obs_y3[8:0] + pixel_y;
                            vga_color_reg <= OBS_COLOR;
                            vga_write_reg <= !overlaps_player;
                            
                            if (pixel_x < OBS_WIDTH - 1) pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1) pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0; pixel_x <= 0;
                                    vga_write_reg <= 0;
                                    state <= CHECK_COLLISION;
                                end
                            end
                        end
                        else begin
                            pixel_x <= 0; pixel_y <= 0;
                            state <= CHECK_COLLISION;
                        end
                    end
                end

                CHECK_COLLISION: begin
                    collision <= 0;
                    if (active0 && obs_lane0 == player_lane &&
                        obs_y0 >= (PLAYER_Y_POS - OBS_HEIGHT) &&
                        obs_y0 <= (PLAYER_Y_POS + PLAYER_HEIGHT))
                        collision <= 1;
                    if (active1 && obs_lane1 == player_lane &&
                        obs_y1 >= (PLAYER_Y_POS - OBS_HEIGHT) &&
                        obs_y1 <= (PLAYER_Y_POS + PLAYER_HEIGHT))
                        collision <= 1;
                    if (active2 && obs_lane2 == player_lane &&
                        obs_y2 >= (PLAYER_Y_POS - OBS_HEIGHT) &&
                        obs_y2 <= (PLAYER_Y_POS + PLAYER_HEIGHT))
                        collision <= 1;
                    if (active3 && obs_lane3 == player_lane &&
                        obs_y3 >= (PLAYER_Y_POS - OBS_HEIGHT) &&
                        obs_y3 <= (PLAYER_Y_POS + PLAYER_HEIGHT))
                        collision <= 1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;

endmodule