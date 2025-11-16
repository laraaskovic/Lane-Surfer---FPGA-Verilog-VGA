`default_nettype none  // Disables implicit net declarations

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

    // VGA parameters - 640x480 Res

    parameter nX = 10;          // 10 bits for 640 pix
    parameter nY = 9;           // 9 bits for 480 pix
    parameter COLOR_DEPTH = 9; //9 bits for coloru (same as demo)
   //3 bits per RGB

    // Screen dimensions
    parameter XSCREEN = 640;
    parameter YSCREEN = 480;
    
    // Lanes!!!!
    parameter NUM_LANES = 5; //maybe change later
    parameter LANE_WIDTH = 80;
    parameter LANE_START_X = 120; //depicted on drawing

    // Player dimensions
    parameter PLAYER_WIDTH = 60; //make smaller than lane
    parameter PLAYER_HEIGHT = 60;
    parameter PLAYER_Y_POS = 360;
    
    // Colors
    parameter PLAYER_COLOR = 9'b000_111_111;  // Cyan
    parameter ERASE_COLOR  = 9'b111_111_111;  // White (erases) close enough to bkgrd
    //try to make background photo re-appear (ask TA)
    
    // FSM 
    parameter INIT = 3'd0; //initial like on reset
    parameter DRAW_INITIAL = 3'd1;
    parameter IDLE = 3'd2; //wait for left right input
    parameter ERASE = 3'd3; //Clears previous player block (so it doesn’t leave trails)
    parameter DRAW = 3'd4;
    


    reg [2:0] state; //current y_Q
    reg [2:0] target_lane; //move to this
    reg [nX-1:0] player_x_pos; //top left coor

    reg [nX-1:0] prev_x_pos; //do we need this to erase keep for nowwww
   
   //counter for drawing the pixells
    reg [5:0] pixel_x;
    reg [5:0] pixel_y;
    

    //output for the VGA INPUTS TO CONNECT WITH OTher file!
    reg [nX-1:0] vga_x_reg;
    reg [nY-1:0] vga_y_reg;
    reg [COLOR_DEPTH-1:0] vga_color_reg; //the minus one just so its 9 bits lke before!
    reg vga_write_reg; //enable
    
    reg input_handled; //this is to try to remove holding the key
    
    // Convert lane number to X coordinate
    //Converts the lane number (0–4) into the corresponding X pixel coordinate.
    //The centering offset makes sure the player is centered in its lane.

    //following function was found online but calculations were created on own, syntax is new though
    //Explanation:
    /*
    This converts a lane number (0–4) into an actual X pixel coordinate for where the player should be drawn
    - lane * LANE_WIDTH moves you horizontally across the screen.
    - (LANE_WIDTH - PLAYER_WIDTH) / 2 centers the player within the lane.
    - Adding LANE_START_X offsets everything so the first lane starts at pixel 120.
    
    130, 210, 290, 370, 450 (use function instead of hardcoding in case resolution changes (hopefully not again we pray))

    */
    function [nX-1:0] lane_to_x;
        input [2:0] lane; //based on lane its moving to find position
        begin
            //Lane 2 → X = 120 + (2 × 80) + 10 = 290 pixels.

            lane_to_x = LANE_START_X + (lane * LANE_WIDTH) + ((LANE_WIDTH - PLAYER_WIDTH) / 2);
        end
    endfunction


    // FSM
    always @(posedge Clock) begin
        if (!Resetn) begin
            state <= INIT;
            player_lane <= 3'd2; //go to middle
            player_x_pos <= lane_to_x(3'd2); //290 pix
            prev_x_pos <= lane_to_x(3'd2);  //als 290
            pixel_x <= 0; //counters
            pixel_y <= 0;
            vga_write_reg <= 0;
            vga_color_reg <= PLAYER_COLOR;
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
                    vga_color_reg <= PLAYER_COLOR;
                    vga_write_reg <= 1;
                    
                    //kinda like a for loop in c where you go through the x while its in domain
                    //then if not go through y like after each row thing
                    if (pixel_x < PLAYER_WIDTH - 1)
                        pixel_x <= pixel_x + 1;  ///incremenrt
                    else begin
                        pixel_x <= 0;
                        if (pixel_y < PLAYER_HEIGHT - 1)
                            pixel_y <= pixel_y + 1;
                        else begin
                            pixel_y <= 0;
                            vga_write_reg <= 0;
                            state <= IDLE; //return to pause
                        end
                    end
                end
                IDLE: 
                begin
                    vga_write_reg <= 0; //enable
                    
                    if (!input_handled) //input receiveddddddd!!!!!!!! whoooooo yay
                    begin
                        if (move_left && player_lane > 0) begin
                            prev_x_pos <= player_x_pos;
                            player_lane <= player_lane - 1;
                            player_x_pos <= lane_to_x(player_lane - 1);
                            pixel_x <= 0; //reset counters
                            pixel_y <= 0;
                            input_handled <= 1;
                            state <= ERASE; //erase current/previous
                            //check again with demo code what they do for erase
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
                            state <= DRAW; //now dra updated not prev
                        end
                    end
                end
                DRAW:  //same as initial draw
                begin
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

                default: state <= INIT;
            endcase
        end
    end

    //connect internal registers to VGA output ports

    assign VGA_x = vga_x_reg;
    assign VGA_y = vga_y_reg;
    assign VGA_color = vga_color_reg;
    assign VGA_write = vga_write_reg;

endmodule
