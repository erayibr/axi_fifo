// append the following to axis_fifo module (before endmodule keyword)
//
//	`ifdef FORMAL
//		`include "axis_fifo_formal.svh"
//	`endif
//
// 'FORMAL' will be defined by SymbiYosys

logic past_valid;

initial
	past_valid <= 0;

// to be able to call $past there has to be a past (at least one clock period has passed)
always @(posedge aclk)
	past_valid <= 1;

// check initial and reset conditions of tvalid signals
always @(posedge aclk)
	if(!past_valid || (past_valid && $past(!areset_n))) begin // $past(x) returns value of x from the previous cycle, $past(x,2) returns x's value from 2 cycles ago, etc.
		// During reset TVALID must be driven LOW.
		// A master interface must only begin driving TVALID at a rising ACLK edge following a rising edge at which ARESETn is asserted HIGH.
		assert(!m_axis_tvalid);
		assume(!s_axis_tvalid);
	end

always @(posedge aclk)
	if(past_valid && $past(m_axis_tvalid) && $past(areset_n))
		// Once TVALID is asserted it must remain asserted until the handshake occurs.
		// Once the master has asserted TVALID, the data or control information from the master must remain unchanged until the slave drives the TREADY signal HIGH.
		if($past(!m_axis_tready)) begin
			assert($stable(m_axis_tdata)); // $stable(x) is short hand for x == $past(x)
			if(ENABLE_TKEEP)
				assert($stable(m_axis_tkeep));
			if(ENABLE_TLAST)
				assert($stable(m_axis_tlast));
			assert($stable(m_axis_tvalid));
		end

// slave interface must also obey the protocol specification
// since we're not 'checking' but 'constraining' the slave interface 'assume' is used instead of 'assert'
always @(posedge aclk)
	if(past_valid && $past(s_axis_tvalid) && $past(areset_n))
		if($past(!s_axis_tready)) begin
			assume($stable(s_axis_tdata));
			if(ENABLE_TKEEP)
				assume($stable(s_axis_tkeep));
			if(ENABLE_TLAST)
				assume($stable(s_axis_tlast));
			assume($stable(s_axis_tvalid));
		end

// FIFO contract
// any two consecutive data must appear at the output in the order they were received
// select two consecutive locations in the memory

(* anyconst *) logic [DEPTH - 1:0] sample_a_addr; // randomly generate a constant
logic [DEPTH - 1:0] sample_b_addr;

assign sample_b_addr = sample_a_addr + 1;

// complete the specification/description...

// Assumptions for consecutive data write
always @(posedge aclk) begin

	// If fifo tail is now sample_b_addr and data was written in previous cycle; previous data written must be in memory location sample_a_addr
	if(past_valid && $past(areset_n) && (ptr_tail == sample_b_addr) && $past(s_axis_tvalid && s_axis_tready)) begin
		
		//check data 
		assume ($past(s_axis_tdata) == memory[sample_a_addr]);
		
		//check keep and enable signals
		if(ENABLE_TKEEP)
			assume ($past(s_axis_tkeep) == axi_keep_stream[sample_a_addr]);

		if(ENABLE_TLAST)
			assume ($past(s_axis_tlast) == axi_last_stream[sample_a_addr]);
	end
end

// Assertions for consecutive data read
always @(posedge aclk) begin

	// If fifo front is now sample_b_addr and data was read in previous cycle; fifo front must now be previous value of sample_a_addr location in memory
	if(past_valid && $past(areset_n) && (ptr_head == sample_b_addr) && $past(m_axis_tvalid && m_axis_tready)) begin
		
		//check data 
		assert (m_axis_tdata == $past(memory[sample_a_addr]));

		//check keep and enable signals
		if(ENABLE_TKEEP)
			assert(m_axis_tkeep == $past(axi_keep_stream[sample_a_addr]));

		if(ENABLE_TLAST)
			assert(m_axis_tlast == $past(axi_last_stream[sample_a_addr]));
	end
end

// Check if single clock empty-full transitions occur
always @(posedge aclk) begin

	if(DEPTH > 1)

		assume($past(counter) == 0 || $past(counter) == DEPTH);

		// If fifo is empty, it can not be full in the next cycle
		if(past_valid && $past(flag_empty))	
			assert (!flag_full);

		// If fifo is full, it can not be empty in the next cycle
		if(past_valid && $past(areset_n) && $past(flag_full))
			assert (!flag_empty);

end


// Check reading from empty fifo and writing to full fifo cases
always @(posedge aclk) begin

	// Reading from empty fifo
	if(past_valid && $past(areset_n) && $past(flag_empty))
		assert($past(ptr_head) == ptr_head);

	// Writing to full fifo
	if(past_valid && $past(areset_n) && $past(flag_full))
		assert($past(ptr_tail) == ptr_tail);

end


// Check if counter variable works correctly
always @(posedge aclk) begin

	if(flag_empty)
		assert(counter == 0);

	if(flag_full)
		assert(counter == DEPTH);
end

always @(posedge aclk) begin

	if(past_valid && $past(!areset_n))
		assert(flag_empty && 
			   !flag_full && 
			   !m_axis_tvalid && 
			   !s_axis_tready && 
			   (counter == 0) && 
			   (ptr_tail == 0) && 
			   (ptr_head == 0));
end

