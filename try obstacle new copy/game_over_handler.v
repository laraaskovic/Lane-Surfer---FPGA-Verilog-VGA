`default_nettype none

module game_over_handler(
    input wire Resetn,
    input wire Clock,
    input wire collision,      // From obstacle manager
    output reg game_over       // To top module (freezes everything)
);

    always @(posedge Clock) begin
        if (!Resetn) begin
            // Reset pressed - clear game over
            game_over <= 0;
        end
        else if (collision) begin
            // Collision detected - set game over flag
            game_over <= 1;
            // Stays 1 until reset (KEY[3]) pressed
        end
    end

endmodule
