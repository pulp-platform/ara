

module ara_ring_buffer #(
	    parameter int            unsigned ID_WIDTH = 8,
	    parameter int unsigned DEPTH = 1, // Make sure that there are never more ids stored then the depth of the buffer
	    parameter type dtype = logic,
	    // DO NOT OVERWRITE THIS PARAMETER
	    parameter int unsigned ADDR_DEPTH   = (DEPTH > 1) ? $clog2(DEPTH) : 1
	) (
		// Clock and Reset
		input logic clk_i,
		input logic rst_ni,
		// State information
		output logic full_o,
		output logic empty_o,
		// Control information
		input logic push_i,
		input logic commit_i,
		input logic flush_i,
		output logic valid_o,
		input logic ready_i,
		// Data
		input logic [ID_WIDTH-1:0] commit_id_i,
		input logic [ID_WIDTH-1:0] id_i,
		input dtype data_i,
		output dtype data_o
	);
	// Clock gating control
	logic gate_clock;
	// Memory
	dtype [DEPTH-1:0] mem_d, mem_q;
	logic [DEPTH-1:0][ID_WIDTH-1:0] id_mem_d, id_mem_q;
	// Pointer to indicate head and tail
	logic [ADDR_DEPTH-1:0] head_d, head_q;
	logic [ADDR_DEPTH-1:0] tail_d, tail_q;
	// Pointer to indicate the commitable instructions
	logic [ADDR_DEPTH-1:0] commit_d, commit_q;

	assign full_o 	= (tail_q+1'b1 == head_q) ? 1'b1 : 1'b0;
	assign empty_o 	= (tail_q == head_q) ? 1'b1 : 1'b0;

	assign valid_o = !(head_q == commit_q && head_q == commit_d);

	// Read and write logic
	always_comb begin
		// Default assignment
		mem_d 		= mem_q;
		id_mem_d 	= id_mem_q;
		head_d 		= head_q;
		tail_d 		= tail_q;
		commit_d 	= commit_q;
		data_o 		= mem_q[head_q];
		gate_clock 	= 1'b1;
		
		// Write
		if (push_i && ~full_o) begin
			// Un-gate the clock
			gate_clock = 1'b0;
			// Write to mem
			mem_d[tail_q] = data_i;
			// Link the tail id to id_i
			id_mem_d[id_i] = tail_q;
			// Push the tail by one
			tail_d = tail_q + 1'b1;
		end

		// Commit
		if (commit_i && ~empty_o) begin
			// Push the commit pointer to the 
			commit_d = id_mem_q[commit_id_i] + 1'b1;
		end

		// Read
		if (valid_o && ~empty_o && ready_i) begin
			// Pop the head by one
			head_d = head_q + 1'b1;
		end

		// Flush
		if (flush_i && !empty_o) begin
			// When we flush the buffer we take an id and flush all values that where pushed after that id including the id
			tail_d = id_mem_q[commit_id_i];
		end
	end


	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(~rst_ni) begin
			head_q 		<= '0;
			tail_q 		<= '0;
			commit_q 	<= '0;
		end else begin
			head_q 		<= head_d;
			tail_q 		<= tail_d;
			commit_q 	<= commit_d;
		end
	end

	always_ff @(posedge clk_i or negedge rst_ni) begin
		if(~rst_ni) begin
			mem_q 		<= '0;
			id_mem_q 	<= '0;
		end else if (!gate_clock) begin
			mem_q 		<= mem_d;
			id_mem_q 	<= id_mem_d;
		end
	end

	full_write : assert property(
        @(posedge clk_i) disable iff (~rst_ni) (full_o |-> ~push_i))
        else $fatal (1, "Trying to push new data although the BUFFER is full.");

    empty_read : assert property(
        @(posedge clk_i) disable iff (~rst_ni) (empty_o |-> ~(valid_o && ready_i)))
        else $fatal (1, "Trying to pop data although the BUFFER is empty.");

endmodule : ara_ring_buffer