module playerfsm (
    input clk,
    input reset,
    input left,
    input right,
    output reg [2:0] lane, // 0–3 or 0–4
    output reg [4:0] led_pos
);

    // Define states
    parameter IDLE = 2'b00,
              MOVE_LEFT = 2'b01,
              MOVE_RIGHT = 2'b10;

    reg [1:0] state, next_state;

    // Edge detection (to make 1-move per press)
    reg left_d, right_d;
    wire left_edge = left & ~left_d;
    wire right_edge = right & ~right_d;

    always @(posedge clk) begin
        left_d <= left;
        right_d <= right;
    end

    // State register
    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (left_edge && lane > 0)
                    next_state = MOVE_LEFT;
                else if (right_edge && lane < 4)
                    next_state = MOVE_RIGHT;
            end
            MOVE_LEFT,
            MOVE_RIGHT: next_state = IDLE;
        endcase
    end

    // Lane position update
    always @(posedge clk or posedge reset) begin
        if (reset)
            lane <= 3'd2;
        else if (state == MOVE_LEFT && lane > 0)
            lane <= lane - 1;
        else if (state == MOVE_RIGHT && lane < 4)
            lane <= lane + 1;
    end

    // LED output
    always @(*) begin
        led_pos = 5'b00001 << lane;
    end

endmodule
