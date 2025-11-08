onerror {resume}
quietly WaveActivateNextPane {} 0

add wave -label clk /testbench/clk
add wave -label reset /testbench/reset
add wave -label left /testbench/left
add wave -label right /testbench/right
add wave -label lane /testbench/U1/lane
add wave -label led_pos /testbench/U1/led_pos
add wave -label state /testbench/U1/state
add wave -label next_state /testbench/U1/next_state
add wave -divider "Edge Detection"
add wave -label left_edge /testbench/U1/left_edge
add wave -label right_edge /testbench/U1/right_edge

TreeUpdate [SetDefaultTree]
update
WaveRestoreZoom {0 ns} {300 ns}
