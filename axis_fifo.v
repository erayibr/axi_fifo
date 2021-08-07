// Module description: simple FIFO module with AXI Stream Interface, sync reset and single clock

`timescale 1ns / 1ps

module axis_fifo

	#(parameter DEPTH = 8, WIDTH = 32)
	(

	input wire aclk, 	
	input wire areset_n,

	//AXIS Slave Interface
	output wire s_axis_tready,
    input wire s_axis_tvalid,
    input wire [(WIDTH - 1):0] s_axis_tdata,
    input wire [(WIDTH/8 - 1): 0] s_axis_tkeep,
    input wire s_axis_tlast,

    //AXIS Master Interface
	input wire m_axis_tready,
    output wire m_axis_tvalid,
    output wire [(WIDTH - 1):0] m_axis_tdata,
    output reg [(WIDTH/8 - 1): 0] m_axis_tkeep,
    output reg m_axis_tlast

    );

	// define internal signals
    reg [(WIDTH - 1):0] data_out; 
	reg flag_full = 0;
	reg flag_empty = 1;
	wire write_enable;
	wire read_enable;
	wire [(WIDTH - 1):0] data_in; 

	// Define memory
	reg [(WIDTH - 1) : 	0] memory [(DEPTH - 1) : 0];

	// Declare head & tail pointers
	reg [($clog2(DEPTH) - 1):0] ptr_head = 0;
	reg [($clog2(DEPTH) - 1):0] ptr_tail = 0;

	// Declare counter to count number of r/w operations
	reg [($clog2(DEPTH) - 1):0] counter = 0;

	// AXI Last registers
	reg axi_last_stream [(DEPTH - 1):0];

	// AXI Keep registers
	reg [(WIDTH/8 - 1 ): 0] axi_keep_stream [(DEPTH - 1):0];

	//AXI input assignments
	assign write_enable = s_axis_tvalid & s_axis_tready;
	assign read_enable = m_axis_tready & m_axis_tvalid;
	assign data_in = s_axis_tdata;

	//AXI output assignments
	assign m_axis_tvalid = ~flag_empty;
	assign m_axis_tdata = data_out;

	always @(posedge aclk) begin
		
		//areset_n
		if(~areset_n) begin 
			ptr_head <= 0;
			ptr_tail <= 0;
			flag_full <= 0;
			flag_empty <= 1;
			counter <= 0;
			s_axis_tready <= 0;
		end

		// write & read with non-empty fifo
		else if (write_enable & read_enable & ~flag_empty) begin 
					memory[ptr_tail] <= data_in;
					ptr_tail <= (ptr_tail + 1);
					data_out <= memory[ptr_head];
					ptr_head <= (ptr_head + 1);
					s_axis_tready <= 1;
		end

		// only write into non-full fifo
		else if (write_enable & ~flag_full) begin
			memory[ptr_tail] <= data_in;
			ptr_tail <= (ptr_tail + 1);
			counter <= counter + 1;
			flag_empty <= 0;
			s_axis_tready <= (counter == (DEPTH - 1)) ? 0 : 1;
			if(counter == (DEPTH - 1))
				flag_full <= 1;
		end

		// only read from non-empty fifo
		else if (read_enable & ~flag_empty) begin 
				data_out <= memory[ptr_head];
				ptr_head <= (ptr_head + 1);
				counter <= counter - 1;
				flag_full <= 0;
				s_axis_tready <= 1;
				if(counter == 1)
					flag_empty <= 1;
		end

		// register axi last & keep signals
		if(write_enable & ~flag_full) begin
			axi_last_stream[ptr_tail] <= s_axis_tlast;
			axi_keep_stream[ptr_tail] <= s_axis_tkeep;
		end

		// send out axi last & keep signals	
		if(read_enable & ~flag_empty) begin
			m_axis_tkeep <= axi_keep_stream[ptr_head];
			m_axis_tlast <= axi_last_stream[ptr_head];	
		end
			
	end

	`ifdef FORMAL
		`include "axis_fifo_formal.svh"
	`endif
	
endmodule
