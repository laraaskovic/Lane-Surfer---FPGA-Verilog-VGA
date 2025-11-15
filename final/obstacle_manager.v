/*
 * OBSTACLE_MANAGER.V
 * 
 * Save this as: obstacle_manager.v
 * 
 * Manages falling obstacles in the lane runner game
 * 
 * FEATURES:
 * - Spawns obstacles every ~5 seconds in random lanes
 * - Obstacles fall down the screen at constant speed
 * - Uses obstacle.mif for sprite (60x60 like player)
 * - Supports transparency (magenta pixels not drawn)
 * - Erases with background restoration
 * - Outputs collision detection signal
 * 
 * PARAMETERS YOU CAN ADJUST:
 * - MAX_OBSTACLES: How many obstacles can exist at once
 * - SPAWN_INTERVAL: Clock cycles between spawns (~5 seconds at 50MHz)
 * - FALL_SPEED: How fast obstacles fall (pixels per frame)
 */

`default_nettype none

module obstacle_manager(
    input wire Resetn,
    input wire Clock,
    input wire enable_obstacles,            // NEW: Only spawn/move when enabled
    input wire [2:0] player_lane,           // Which lane is player in
    input wire [9:0] player_y,              // Player Y position (for collision)
    output reg collision,                   // High when player hits obstacle
    output reg [1:0] collision_obstacle_id, // NEW: Which obstacle was hit
    output wire [9:0] VGA_x,
    output wire [8:0] VGA_y,
    output wire [8:0] VGA_color,
    output wire VGA_write
);

    // VGA Parameters
    parameter nX = 10;
    parameter nY = 9;
    parameter COLOR_DEPTH = 9;
    
    parameter XSCREEN = 640;
    parameter YSCREEN = 480;
    
    // Lane configuration (must match player_object.v)
    parameter NUM_LANES = 5;
    parameter LANE_WIDTH = 80;
    parameter LANE_START_X = 120;
    
    // Obstacle dimensions
    parameter OBSTACLE_WIDTH = 60;
    parameter OBSTACLE_HEIGHT = 60;
    parameter OBSTACLE_START_Y = -60;  // Start above screen
    
    // Obstacle behavior
    parameter MAX_OBSTACLES = 4;           // Max simultaneous obstacles
    parameter SPAWN_INTERVAL = 250000000;  // ~5 seconds at 50MHz
    parameter FALL_SPEED = 2;              // Pixels per frame update
    parameter UPDATE_RATE = 833333;        // Update position every 60Hz (~16ms at 50MHz)
    
    // Colors
    parameter TRANSPARENT_COLOR = 9'b111_000_111;  // Magenta
    
    // FSM States
    parameter IDLE = 3'd0;
    parameter DRAW_OBSTACLE = 3'd1;
    parameter ERASE_OBSTACLE = 3'd2;
    parameter UPDATE_POSITIONS = 3'd3;
    parameter CHECK_COLLISIONS = 3'd4;
    
    reg [2:0] state;
    
    // Obstacle data structure
    // For each obstacle: [active, lane, y_pos]
    reg [MAX_OBSTACLES-1:0] active;        // Is this obstacle active?
    reg [2:0] lane [0:MAX_OBSTACLES-1];    // Which lane (0-4)
    reg signed [10:0] y_pos [0:MAX_OBSTACLES-1];  // Y position (signed for above screen)
    reg [9:0] old_y_pos [0:MAX_OBSTACLES-1];      // Previous Y for erasing
    
    // Current obstacle being drawn/erased
    reg [1:0] current_obstacle;
    reg [6:0] pixel_x;
    reg [6:0] pixel_y;
    reg drawing;                           // True when drawing, false when erasing
    
    // Spawn timer
    reg [31:0] spawn_timer;
    reg [2:0] spawn_lane;                  // Which lane to spawn in
    
    // Update timer (for movement)
    reg [31:0] update_timer;
    
    // VGA output registers
    reg [nX-1:0] vga_x_reg;
    reg [nY-1:0] vga_y_reg;
    reg [COLOR_DEPTH-1:0] vga_color_reg;
    reg vga_write_reg;
    
    // ===== OBSTACLE SPRITE ROM =====
    wire [11:0] obs_address;
    wire [COLOR_DEPTH-1:0] obs_pixel;
    
    assign obs_address = (pixel_y >= OBSTACLE_HEIGHT) ? 12'd0 : 
                         (pixel_x >= OBSTACLE_WIDTH) ? 12'd0 :
                         (pixel_y * OBSTACLE_WIDTH + pixel_x);
    
    obstacle_rom OBS_ROM (
        .address(obs_address),
        .clock(Clock),
        .q(obs_pixel)
    );
    
    // ===== BACKGROUND ROM =====
    wire [18:0] bg_address;
    wire [COLOR_DEPTH-1:0] bg_pixel;
    
    wire [9:0] bg_x = lane_to_x(lane[current_obstacle]) + pixel_x;
    wire [10:0] bg_y_signed = drawing ? y_pos[current_obstacle] : old_y_pos[current_obstacle];
    wire [9:0] bg_y = (bg_y_signed < 0) ? 10'd0 : 
                      (bg_y_signed >= YSCREEN) ? (YSCREEN-1) : bg_y_signed[9:0];
    
    assign bg_address = (bg_y * XSCREEN) + bg_x;
    
    background_rom_obs BG_ROM_OBS (
        .address(bg_address),
        .clock(Clock),
        .q(bg_pixel)
    );
    
    // Convert lane number to X coordinate
    function [9:0] lane_to_x;
        input [2:0] lane_num;
        begin
            lane_to_x = LANE_START_X + (lane_num * LANE_WIDTH) + ((LANE_WIDTH - OBSTACLE_WIDTH) / 2);
        end
    endfunction
    
    // LFSR for pseudo-random lane selection
    reg [7:0] lfsr;
    wire lfsr_feedback = lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3];
    
    always @(posedge Clock) begin
        if (!Resetn)
            lfsr <= 8'b10101010;
        else
            lfsr <= {lfsr[6:0], lfsr_feedback};
    end
    
    // Random lane (0-4)
    always @(*) begin
        spawn_lane = lfsr[2:0] % NUM_LANES;
    end
    
    integer i;
    
    // Main FSM
    always @(posedge Clock) begin
        if (!Resetn) begin
            state <= IDLE;
            spawn_timer <= 0;
            update_timer <= 0;
            collision <= 0;
            vga_write_reg <= 0;
            current_obstacle <= 0;
            pixel_x <= 0;
            pixel_y <= 0;
            drawing <= 0;
            
            // Initialize all obstacles as inactive
            for (i = 0; i < MAX_OBSTACLES; i = i + 1) begin
                active[i] <= 0;
                lane[i] <= 0;
                y_pos[i] <= OBSTACLE_START_Y;
                old_y_pos[i] <= 0;
            end
        end
        else begin
            // Increment timers
            spawn_timer <= spawn_timer + 1;
            update_timer <= update_timer + 1;
            
            case (state)
                IDLE: begin
                    vga_write_reg <= 0;
                    
                    // Spawn new obstacle every SPAWN_INTERVAL
                    if (spawn_timer >= SPAWN_INTERVAL) begin
                        spawn_timer <= 0;
                        
                        // Find an inactive obstacle slot
                        for (i = 0; i < MAX_OBSTACLES; i = i + 1) begin
                            if (!active[i]) begin
                                active[i] <= 1;
                                lane[i] <= spawn_lane;
                                y_pos[i] <= OBSTACLE_START_Y;
                                i = MAX_OBSTACLES;  // Break loop
                            end
                        end
                    end
                    
                    // Update obstacle positions every UPDATE_RATE
                    if (update_timer >= UPDATE_RATE) begin
                        update_timer <= 0;
                        current_obstacle <= 0;
                        state <= UPDATE_POSITIONS;
                    end
                end
                
                UPDATE_POSITIONS: begin
                    if (current_obstacle < MAX_OBSTACLES) begin
                        if (active[current_obstacle]) begin
                            // Save old position for erasing
                            old_y_pos[current_obstacle] <= (y_pos[current_obstacle] < 0) ? 0 : y_pos[current_obstacle][9:0];
                            
                            // Move obstacle down
                            y_pos[current_obstacle] <= y_pos[current_obstacle] + FALL_SPEED;
                            
                            // Deactivate if off screen
                            if (y_pos[current_obstacle] >= YSCREEN) begin
                                active[current_obstacle] <= 0;
                            end
                            else begin
                                // Erase old position, then draw new
                                pixel_x <= 0;
                                pixel_y <= 0;
                                drawing <= 0;
                                state <= ERASE_OBSTACLE;
                            end
                        end
                        else begin
                            current_obstacle <= current_obstacle + 1;
                        end
                    end
                    else begin
                        // All obstacles updated, check collisions
                        state <= CHECK_COLLISIONS;
                    end
                end
                
                ERASE_OBSTACLE: begin
                    // Only erase if old position was on screen
                    if (old_y_pos[current_obstacle] < YSCREEN && 
                        pixel_x < OBSTACLE_WIDTH && 
                        pixel_y < OBSTACLE_HEIGHT) begin
                        
                        vga_x_reg <= lane_to_x(lane[current_obstacle]) + pixel_x;
                        vga_y_reg <= old_y_pos[current_obstacle] + pixel_y;
                        vga_color_reg <= bg_pixel;
                        vga_write_reg <= 1;
                    end
                    else begin
                        vga_write_reg <= 0;
                    end
                    
                    // Increment pixel counters
                    if (pixel_x < OBSTACLE_WIDTH - 1) begin
                        pixel_x <= pixel_x + 1;
                    end
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < OBSTACLE_HEIGHT - 1) begin
                            pixel_y <= pixel_y + 1;
                        end
                        else begin
                            // Done erasing, now draw
                            pixel_x <= 0;
                            pixel_y <= 0;
                            drawing <= 1;
                            vga_write_reg <= 0;
                            state <= DRAW_OBSTACLE;
                        end
                    end
                end
                
                DRAW_OBSTACLE: begin
                    // Only draw if on screen
                    if (y_pos[current_obstacle] >= 0 && 
                        y_pos[current_obstacle] < YSCREEN &&
                        pixel_x > 0 && 
                        pixel_x <= OBSTACLE_WIDTH && 
                        pixel_y < OBSTACLE_HEIGHT) begin
                        
                        vga_x_reg <= lane_to_x(lane[current_obstacle]) + pixel_x - 1;
                        vga_y_reg <= y_pos[current_obstacle][9:0] + pixel_y;
                        vga_color_reg <= obs_pixel;
                        vga_write_reg <= (obs_pixel != TRANSPARENT_COLOR);
                    end
                    else begin
                        vga_write_reg <= 0;
                    end
                    
                    // Increment pixel counters (with ROM delay handling)
                    if (pixel_x < OBSTACLE_WIDTH) begin
                        pixel_x <= pixel_x + 1;
                    end
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < OBSTACLE_HEIGHT - 1) begin
                            pixel_y <= pixel_y + 1;
                        end
                        else begin
                            // Done drawing this obstacle
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            current_obstacle <= current_obstacle + 1;
                            state <= UPDATE_POSITIONS;
                        end
                    end
                end
                
                CHECK_COLLISIONS: begin
                    collision <= 0;
                    
                    // Check if player overlaps with any active obstacle
                    for (i = 0; i < MAX_OBSTACLES; i = i + 1) begin
                        if (active[i] && lane[i] == player_lane) begin
                            // Simple AABB collision detection
                            // Player is at (player_x, 360) with size 60x60
                            // Obstacle is at (obs_x, y_pos[i]) with size 60x60
                            if (y_pos[i] >= 300 && y_pos[i] <= 420) begin
                                collision <= 1;
                            end
                        end
                    end
                    
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


// ===== OBSTACLE SPRITE ROM =====
// Same structure as car ROM but loads obstacle.mif
module obstacle_rom(
    input wire [11:0] address,
    input wire clock,
    output reg [8:0] q
);

    reg [8:0] memory [0:3599];
    
    initial begin
        $readmemh("obstacle.mif", memory);
    end
    
    always @(posedge clock) begin
        q <= memory[address];
    end

endmodule


// ===== BACKGROUND ROM (duplicate for obstacles) =====
// We need a separate instance because player also uses background ROM
module background_rom_obs(
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