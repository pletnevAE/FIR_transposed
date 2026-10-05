//=====================================================================================
// 		Transposed FIR
//
//			Parameters:
//				N_COEFFS - number of coefficients
//				IN_WIDTH - input word length
//				COEFF_WIDTH - coefficients word length
//				MULT_WIDTH - product word length
//				MULT_FRACTION - product fraction length
//				ACC_WIDTH - accumulator word length
//				OUT_WIDTH - output word length
//				OUT_FRACTION - output fraction length
//
//			Control Signals:
//				clk - clock signal
//				rst_n – reset (Active-Low)
//				valid_in - input data valid
//				valid_out - output data valid
//
//			Data:
//				data_in - input data
//				data_out - output data
//=====================================================================================

`include "fir_params.vh"

module FIR
#(
	parameter N_COEFFS = N_TAPS, // Number of coefficients
	parameter IN_WIDTH = INPUT_WL, // Input word length
	parameter COEFF_WIDTH = COEFF_WL, // Coefficients word length
	parameter MULT_WIDTH = MULT_WL, // Product word length
	parameter MULT_FRACTION = MULT_FL, // Product fraction length
	parameter ACC_WIDTH = ACC_WL, // Accumulator word length
	parameter OUT_WIDTH = OUT_WL, // Output word length
	parameter OUT_FRACTION = OUT_FL // Output fraction length
)
(
	input clk, // Clock
	input rst_n, // Reset
	input valid_in, // Input data valid
	input signed [IN_WIDTH - 1:0] data_in, // Input data
	output logic valid_out, // Output data valid
	output logic signed [OUT_WIDTH - 1:0] data_out // Output data
);

localparam NUM_UNIQUE_COEFFS = (N_COEFFS + 1) / 2; // Number of unique coefficients
localparam DROP_BITS = MULT_FRACTION - OUT_FRACTION; // Truncation of the fractional part
localparam TOTAL_LATENCY = 3; // Total pipeline delay

logic signed [COEFF_WIDTH - 1:0] h [0:NUM_UNIQUE_COEFFS - 1]; // Coefficients
logic [TOTAL_LATENCY - 1:0] valid_pipe; // Pipeline for valid signal
(* multstyle = "dsp" *) logic signed [MULT_WIDTH - 1:0] mult_reg [0:NUM_UNIQUE_COEFFS - 1]; // Multipliers registers
logic signed [MULT_WIDTH - 1:0] mult_full [0:N_COEFFS - 1]; // Accumulators input
genvar i;

//=====================================================================================
// Accumulators bit depth calculation function for each tap
//=====================================================================================
function automatic int get_acc_width(int tap_idx);
	if (N_COEFFS <= 1) begin
		return ACC_WIDTH;
	end
	else begin
//-------------------------------------------------------------------------------------
// Linear narrowing from ACC_WIDTH (at tap 0) to MULT_WIDTH (at tap N_COEEFS - 1)
		return ACC_WIDTH - ((ACC_WIDTH - MULT_WIDTH) * tap_idx) / (N_COEFFS - 1);
	end
endfunction

//=====================================================================================
// Initialization of Coefficients
//=====================================================================================
initial begin
	$readmemh("fir_coeffs.txt", h);
end

//=====================================================================================
// Multipliers with output registers
//=====================================================================================
always_ff @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		for (int i = 0; i < NUM_UNIQUE_COEFFS; i++) begin
			mult_reg[i] <= {MULT_WIDTH{1'b0}};
		end
	end
	else begin
		if (valid_in) begin
			for (int i = 0; i < NUM_UNIQUE_COEFFS; i++) begin
				mult_reg[i] <= data_in * h[i];
			end
		end
	end
end

//=====================================================================================
// Formation of the accumulators inputs
//=====================================================================================
always_comb begin
	for (int i = 0; i < N_COEFFS; i++) begin
		if (i < NUM_UNIQUE_COEFFS) begin
			mult_full[i] = mult_reg[i];
		end
		else begin
			mult_full[i] = mult_reg[N_COEFFS - 1 - i];
		end
	end
end

//=====================================================================================
// Accumulators with individual bit depth
//=====================================================================================
generate
	for (i = 0; i < N_COEFFS; i++) begin : g_acc
		localparam CURR_WIDTH = get_acc_width(i); // Current accumulator bit depth
		logic signed [CURR_WIDTH - 1:0] acc_reg; // Accumulators registers
		
		if (i == N_COEFFS - 1) begin : g_last
//-------------------------------------------------------------------------------------
// The last tap
			always_ff @ (posedge clk, negedge rst_n) begin
				if (!rst_n) begin
					acc_reg <= {CURR_WIDTH{1'b0}};
				end
				else begin
					if (valid_in) begin
						acc_reg <= mult_full[i][MULT_WIDTH - 1 -:CURR_WIDTH];
					end
				end
			end
		end
		else begin : g_chain
//-------------------------------------------------------------------------------------
// Intermediate taps
			always_ff @ (posedge clk, negedge rst_n) begin
				if (!rst_n) begin
					acc_reg <= {CURR_WIDTH{1'b0}};
				end
				else begin
					if (valid_in) begin
						acc_reg <= $signed(mult_full[i]) + $signed(g_acc[i + 1].acc_reg);
					end
				end
			end
		end
	end
endgenerate

//=====================================================================================
// Output register with LSB cutoff
//=====================================================================================
always_ff @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		data_out <= {OUT_WIDTH{1'b0}};
	end
	else begin
		if (valid_in) begin
			data_out <= g_acc[0].acc_reg[DROP_BITS + OUT_WIDTH - 1:DROP_BITS];
		end
	end
end

//=====================================================================================
// Output valid delay and syncronization with valid_in
//=====================================================================================
always_ff @ (posedge clk, negedge rst_n) begin
	if (!rst_n) begin
		valid_pipe <= {TOTAL_LATENCY{1'b0}};
	end
	else begin
		if (valid_in) begin
			valid_pipe <= {valid_pipe[TOTAL_LATENCY - 2:0], 1'b1};
		end
	end
end

assign valid_out = valid_in & valid_pipe[TOTAL_LATENCY - 1];

endmodule