`default_nettype none

module multi_obstacle(
    input wire Resetn,
    input wire Clock,
    input wire [2:0] player_lane,      // For collision detection
    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output wire [8:0] VGA_color,
    output wire VGA_write,
    output reg collision               // High when any obstacle hits player
);

    // Screen parameters
    parameter XSCREEN = 640;
    parameter YSCREEN = 480;

    // Lane configuration
    parameter NUM_LANES = 5;
    parameter LANE_WIDTH = 80;
    parameter LANE_START_X = 120;

    // Obstacle size
    parameter OBS_WIDTH = 60;
    parameter OBS_HEIGHT = 60;
    parameter MAX_OBSTACLES = 4;

    // Player position (for collision)
    parameter PLAYER_Y_POS = 360;
    parameter PLAYER_HEIGHT = 60;

    // Colors
    parameter OBS_COLOR = 9'b111_000_111;    // Magenta obstacles
    parameter ERASE_COLOR = 9'b111_111_111;  // White erase

    // FSM States
    parameter IDLE = 3'd0;
    parameter ERASE_OBS = 3'd1;
    parameter MOVE_OBS = 3'd2;
    parameter DRAW_OBS = 3'd3;
    parameter CHECK_COLLISION = 3'd4;

    // Obstacle data (separate variables for each obstacle)
    reg active0, active1, active2, active3;
    reg [2:0] obs_lane0, obs_lane1, obs_lane2, obs_lane3;
    reg signed [9:0] obs_y0, obs_y1, obs_y2, obs_y3;
    reg [9:0] obs_x0, obs_x1, obs_x2, obs_x3;

    // Current obstacle being processed
    reg [1:0] current_obs;

    // Drawing counters
    reg [5:0] pixel_x;
    reg [5:0] pixel_y;

    // FSM state
    reg [2:0] state;

    // Speed control - how fast obstacles move
    reg [22:0] speed_counter;
    parameter SPEED_LIMIT = 23'd1_000_000;  // ~20ms updates

    // Spawn control - how often new obstacles appear
    reg [26:0] spawn_counter;
    parameter SPAWN_INTERVAL = 27'd100_000_000;  // ~2 seconds

    // Lane selection (round-robin: 0,1,2,3,4,0,1...)
    reg [2:0] next_spawn_lane;

    // VGA output registers
    reg [9:0] vga_x_reg;
    reg [8:0] vga_y_reg;
    reg [8:0] vga_color_reg;
    reg vga_write_reg;

    // Convert lane number to X position
    function [9:0] lane_to_x;
        input [2:0] lane;
        begin
            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) + ((LANE_WIDTH - OBS_WIDTH) / 2);
        end
    endfunction

    // Main FSM
    always @(posedge Clock) begin
        if (!Resetn) begin
            // RESET: Clear everything
            state <= IDLE;
            current_obs <= 0;
            pixel_x <= 0;
            pixel_y <= 0;
            speed_counter <= 0;
            spawn_counter <= 0;
            next_spawn_lane <= 0;
            vga_write_reg <= 0;
            collision <= 0;

            // Deactivate all obstacles
            active0 <= 0; obs_lane0 <= 0; obs_y0 <= -60; obs_x0 <= 0;
            active1 <= 0; obs_lane1 <= 0; obs_y1 <= -60; obs_x1 <= 0;
            active2 <= 0; obs_lane2 <= 0; obs_y2 <= -60; obs_x2 <= 0;
            active3 <= 0; obs_lane3 <= 0; obs_y3 <= -60; obs_x3 <= 0;
        end
        else begin
            // ===== SPAWN TIMER =====
            spawn_counter <= spawn_counter + 1;
            if (spawn_counter >= SPAWN_INTERVAL) begin
                spawn_counter <= 0;

                // Find first inactive slot and spawn there
                if (!active0) begin
                    active0 <= 1;
                    obs_lane0 <= next_spawn_lane;
                    obs_x0 <= lane_to_x(next_spawn_lane);
                    obs_y0 <= -60;  // Start above screen
                end
                else if (!active1) begin
                    active1 <= 1;
                    obs_lane1 <= next_spawn_lane;
                    obs_x1 <= lane_to_x(next_spawn_lane);
                    obs_y1 <= -60;
                end
                else if (!active2) begin
                    active2 <= 1;
                    obs_lane2 <= next_spawn_lane;
                    obs_x2 <= lane_to_x(next_spawn_lane);
                    obs_y2 <= -60;
                end
                else if (!active3) begin
                    active3 <= 1;
                    obs_lane3 <= next_spawn_lane;
                    obs_x3 <= lane_to_x(next_spawn_lane);
                    obs_y3 <= -60;
                end

                // Update lane for next spawn (round-robin)
                if (next_spawn_lane == 4)
                    next_spawn_lane <= 0;
                else
                    next_spawn_lane <= next_spawn_lane + 1;
            end

            // ===== MAIN STATE MACHINE =====
            case (state)
                // ------------------------------------------------
                IDLE: begin
                    vga_write_reg <= 0;

                    // Wait for speed timer
                    if (speed_counter < SPEED_LIMIT)
                        speed_counter <= speed_counter + 1;
                    else begin
                        speed_counter <= 0;
                        current_obs <= 0;
                        state <= ERASE_OBS;
                    end
                end

                // ------------------------------------------------
                ERASE_OBS: begin
                    // Erase obstacle 0
                    if (current_obs == 0) begin
                        if (active0 && obs_y0 >= 0) begin
                            vga_x_reg <= obs_x0 + pixel_x;
                            vga_y_reg <= obs_y0[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;

                            if (pixel_x < OBS_WIDTH - 1)
                                pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1)
                                    pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0;
                                    vga_write_reg <= 0;
                                    current_obs <= 1;
                                end
                            end
                        end
                        else current_obs <= 1;
                    end

                    // Erase obstacle 1
                    else if (current_obs == 1) begin
                        if (active1 && obs_y1 >= 0) begin
                            vga_x_reg <= obs_x1 + pixel_x;
                            vga_y_reg <= obs_y1[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;

                            if (pixel_x < OBS_WIDTH - 1)
                                pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1)
                                    pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0;
                                    vga_write_reg <= 0;
                                    current_obs <= 2;
                                end
                            end
                        end
                        else current_obs <= 2;
                    end

                    // Erase obstacle 2
                    else if (current_obs == 2) begin
                        if (active2 && obs_y2 >= 0) begin
                            vga_x_reg <= obs_x2 + pixel_x;
                            vga_y_reg <= obs_y2[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;

                            if (pixel_x < OBS_WIDTH - 1)
                                pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1)
                                    pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0;
                                    vga_write_reg <= 0;
                                    current_obs <= 3;
                                end
                            end
                        end
                        else current_obs <= 3;
                    end

                    // Erase obstacle 3
                    else if (current_obs == 3) begin
                        if (active3 && obs_y3 >= 0) begin
                            vga_x_reg <= obs_x3 + pixel_x;
                            vga_y_reg <= obs_y3[8:0] + pixel_y;
                            vga_color_reg <= ERASE_COLOR;
                            vga_write_reg <= 1;

                            if (pixel_x < OBS_WIDTH - 1)
                                pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1)
                                    pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0;
                                    vga_write_reg <= 0;
                                    state <= MOVE_OBS;
                                    current_obs <= 0;
                                end
                            end
                        end
                        else begin
                            state <= MOVE_OBS;
                            current_obs <= 0;
                        end
                    end
                end

                // ------------------------------------------------
                MOVE_OBS: begin
                    vga_write_reg <= 0;

                    // Move obstacle 0
                    if (current_obs == 0) begin
                        if (active0) begin
                            if (obs_y0 >= YSCREEN)
                                active0 <= 0;  // Off screen - deactivate
                            else
                                obs_y0 <= obs_y0 + 2;  // Move down
                        end
                        current_obs <= 1;
                    end

                    // Move obstacle 1
                    else if (current_obs == 1) begin
                        if (active1) begin
                            if (obs_y1 >= YSCREEN)
                                active1 <= 0;
                            else
                                obs_y1 <= obs_y1 + 2;
                        end
                        current_obs <= 2;
                    end

                    // Move obstacle 2
                    else if (current_obs == 2) begin
                        if (active2) begin
                            if (obs_y2 >= YSCREEN)
                                active2 <= 0;
                            else
                                obs_y2 <= obs_y2 + 2;
                        end
                        current_obs <= 3;
                    end

                    // Move obstacle 3
                    else if (current_obs == 3) begin
                        if (active3) begin
                            if (obs_y3 >= YSCREEN)
                                active3 <= 0;
                            else
                                obs_y3 <= obs_y3 + 2;
                        end
                        current_obs <= 0;
                        state <= DRAW_OBS;
                    end
                end

                // ------------------------------------------------
                DRAW_OBS: begin
                    // Draw obstacle 0
                    if (current_obs == 0) begin
                        if (active0 && obs_y0 >= 0 && obs_y0 < YSCREEN) begin
                            vga_x_reg <= obs_x0 + pixel_x;
                            vga_y_reg <= obs_y0[8:0] + pixel_y;
                            vga_color_reg <= OBS_COLOR;
                            vga_write_reg <= 1;

                            if (pixel_x < OBS_WIDTH - 1)
                                pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1)
                                    pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0;
                                    vga_write_reg <= 0;
                                    current_obs <= 1;
                                end
                            end
                        end
                        else current_obs <= 1;
                    end

                    // Draw obstacle 1
                    else if (current_obs == 1) begin
                        if (active1 && obs_y1 >= 0 && obs_y1 < YSCREEN) begin
                            vga_x_reg <= obs_x1 + pixel_x;
                            vga_y_reg <= obs_y1[8:0] + pixel_y;
                            vga_color_reg <= OBS_COLOR;
                            vga_write_reg <= 1;

                            if (pixel_x < OBS_WIDTH - 1)
                                pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1)
                                    pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0;
                                    vga_write_reg <= 0;
                                    current_obs <= 2;
                                end
                            end
                        end
                        else current_obs <= 2;
                    end

                    // Draw obstacle 2
                    else if (current_obs == 2) begin
                        if (active2 && obs_y2 >= 0 && obs_y2 < YSCREEN) begin
                            vga_x_reg <= obs_x2 + pixel_x;
                            vga_y_reg <= obs_y2[8:0] + pixel_y;
                            vga_color_reg <= OBS_COLOR;
                            vga_write_reg <= 1;

                            if (pixel_x < OBS_WIDTH - 1)
                                pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1)
                                    pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0;
                                    vga_write_reg <= 0;
                                    current_obs <= 3;
                                end
                            end
                        end
                        else current_obs <= 3;
                    end

                    // Draw obstacle 3
                    else if (current_obs == 3) begin
                        if (active3 && obs_y3 >= 0 && obs_y3 < YSCREEN) begin
                            vga_x_reg <= obs_x3 + pixel_x;
                            vga_y_reg <= obs_y3[8:0] + pixel_y;
                            vga_color_reg <= OBS_COLOR;
                            vga_write_reg <= 1;

                            if (pixel_x < OBS_WIDTH - 1)
                                pixel_x <= pixel_x + 1;
                            else begin
                                pixel_x <= 0;
                                if (pixel_y < OBS_HEIGHT - 1)
                                    pixel_y <= pixel_y + 1;
                                else begin
                                    pixel_y <= 0;
                                    vga_write_reg <= 0;
                                    state <= CHECK_COLLISION;
                                end
                            end
                        end
                        else state <= CHECK_COLLISION;
                    end
                end

                // ------------------------------------------------
                CHECK_COLLISION: begin
                    // Check all obstacles for collision with player
                    collision <= 0;  // Default: no collision

                    // Check obstacle 0
                    if (active0 && obs_lane0 == player_lane &&
                        obs_y0 >= (PLAYER_Y_POS - OBS_HEIGHT) &&
                        obs_y0 <= (PLAYER_Y_POS + PLAYER_HEIGHT))
                        collision <= 1;

                    // Check obstacle 1
                    if (active1 && obs_lane1 == player_lane &&
                        obs_y1 >= (PLAYER_Y_POS - OBS_HEIGHT) &&
                        obs_y1 <= (PLAYER_Y_POS + PLAYER_HEIGHT))
                        collision <= 1;

                    // Check obstacle 2
                    if (active2 && obs_lane2 == player_lane &&
                        obs_y2 >= (PLAYER_Y_POS - OBS_HEIGHT) &&
                        obs_y2 <= (PLAYER_Y_POS + PLAYER_HEIGHT))
                        collision <= 1;

                    // Check obstacle 3
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

    // Connect to output ports
    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;

endmodule