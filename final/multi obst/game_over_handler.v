`default_nettype none

module game_over_handler(
    input wire Resetn,
    input wire Clock,
    input wire collision,
    output reg game_over,
    output reg [1:0] lives,          // 0-3 lives
    output wire [6:0] HEX_display    // Display lives on HEX
);

    reg collision_prev;  // Previous collision state to detect edges
    
    always @(posedge Clock) begin
        if (!Resetn) begin
            game_over <= 0;
            lives <= 2'd3;           // Start with 3 lives
            collision_prev <= 0;
        end
        else begin
            collision_prev <= collision;
            
            // Detect rising edge of collision (new collision)
            if (collision && !collision_prev && !game_over) begin
                if (lives > 0) begin
                    lives <= lives - 1;  // Lose a life
                    
                    // Check if this was the last life
                    if (lives == 1) begin
                        game_over <= 1;  // Game over when going from 1 to 0 lives
                    end
                end
            end
        end
    end
    
    // 7-segment decoder for lives display (0-3)
    // Display format: shows the current number of lives remaining
    hex_decoder lives_display(
        .hex_digit(lives),
        .segments(HEX_display)
    );

endmodule

// 7-segment display decoder
module hex_decoder(
    input wire [1:0] hex_digit,
    output reg [6:0] segments
);
    
    // segments encoding: {g, f, e, d, c, b, a}
    // Active low (0 = ON, 1 = OFF)
    
    always @(*) begin
        case (hex_digit)
            2'd0: segments = 7'b1000000;  // Display "0"
            2'd1: segments = 7'b1111001;  // Display "1"
            2'd2: segments = 7'b0100100;  // Display "2"
            2'd3: segments = 7'b0110000;  // Display "3"
            default: segments = 7'b1111111;  // Blank
        endcase
    end
    
endmodule
