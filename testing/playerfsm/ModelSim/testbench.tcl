# stop any simulation that is currently running
quit -sim

# create the default "work" library
vlib work;

# compile the Verilog source code
vlog playerfsm.v
vlog testbench.v

# start the Simulator
vsim work.testbench

# load waveforms
do wave.do

# run simulation
run 300 ns
