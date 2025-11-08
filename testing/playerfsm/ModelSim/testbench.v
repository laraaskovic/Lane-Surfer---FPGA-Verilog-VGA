`timescale 1ns/1ps
module testbench;

    reg clk;
    reg reset;
    reg left;
    reg right;
    wire [2:0] lane;
    wire [4:0] led_pos;

    playerfsm U1 (
        .clk(clk),
        .reset(reset),
        .left(left),
        .right(right),
        .lane(lane),
        .led_pos(led_pos)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10 ns period
    end

    // Stimulus
    initial begin
        reset = 1; left = 0; right = 0;
        #15 reset = 0;
        #20;
        right = 1; #10; right = 0; #40;
        right = 1; #10; right = 0; #40;
        left = 1; #10; left = 0; #40;
        #100;
        $stop;
    end
endmodule
