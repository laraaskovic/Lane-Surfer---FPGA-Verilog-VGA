`default_nettype none

/*
 Sets game_over flag when collision is detected.
 Game stays frozen until reset. 
 FIXXXXXX LATER MAKE IT RESET OR SOMETHING
*/

module game_over_handler(
    input wire Resetn,
    input wire Clock,
    input wire collision,
    output reg game_over
);

    always @(posedge Clock) begin
        if (!Resetn) begin
            game_over <= 0;
        end
        else if (collision) begin
            game_over <= 1;  // Set and stay set until reset
        end
    end

endmodule
