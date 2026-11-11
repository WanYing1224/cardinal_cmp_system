/////////////////////////////////////////////////////////////////////////////
// Filename    : tb_cardinal_nic.v
// Description : Basic testbench for the Cardinal NIC (Phase 3)
//
// A starting point for your own NIC testbench (handout item 3). It drives
// the processor side and the router side of one cardinal_nic and checks a
// few basic operations:
//   1. reset values: net_so = 0, net_ri = 1, both status registers 0
//   2. a processor store to the output channel buffer (addr 10), the
//      output status (addr 11), and the send to the router: net_so must
//      be 1, with the packet on net_do, at exactly one rising edge, an
//      edge where net_ro = 1 and net_polarity = ~vc (the phase in which
//      the mesh router transfers that VC). net_so may be a registered or
//      a combinational output; the router (and this testbench) only looks
//      at it at the rising edge
//   3. a packet from the router (net_si) into the input channel buffer:
//      net_ri drops, the input status (addr 01) reads 1, a load from
//      addr 00 returns the packet and empties the buffer
// It does not test blocking (net_ro = 0 for a while), a store to a full
// output buffer, a second packet while the first waits, sending and
// receiving in the same cycle, or both VC polarities. Add those cases.
//
// The polarity is generated as the mesh router does it: 0 during reset,
// toggling at every rising edge afterwards. Processor inputs change at
// falling edges so that they are stable at the rising edge.
//
// The TA testbench instantiates cardinal_nic by the port names below.
//===========================================================================
// Description : Extended testbench for the Cardinal NIC (Phase 3)
//               Built on top of the TA-provided starting framework.
//               Covers all Report R1 cases (a through i) and outputs
//               results to both the console and out/tb_cardinal_nic.out
/////////////////////////////////////////////////////////////////////////////

`timescale 1ns/10ps

`define CYCLE_TIME 4

module tb_cardinal_nic;

reg         clk, reset;
reg  [0:1]  addr;
reg  [0:63] d_in;
wire [0:63] d_out;
reg         nicEn, nicWrEn;
reg         net_si, net_ro, net_polarity;
reg  [0:63] net_di;
wire        net_ri, net_so;
wire [0:63] net_do;

reg  [0:63] packet;
integer     errors, sends, k;
integer     out_file;

cardinal_nic NIC (
	.clk(clk), .reset(reset),
	.addr(addr), .d_in(d_in), .d_out(d_out), .nicEn(nicEn), .nicWrEn(nicWrEn),
	.net_si(net_si), .net_ri(net_ri), .net_di(net_di),
	.net_so(net_so), .net_ro(net_ro), .net_do(net_do), .net_polarity(net_polarity)
	);

always #(`CYCLE_TIME / 2.0) clk = ~clk;

// Polarity of the connected router: 0 during reset, toggles every rising edge
always @(posedge clk) begin
	if (reset) net_polarity <= 1'b0;
	else       net_polarity <= ~net_polarity;
end

// Count the edges at which net_so is 1 (sampled like a router does) and
// check the packet on net_do at those edges
always @(posedge clk) begin
	if (!reset && net_so === 1'b1) begin
		sends = sends + 1;
		$display("%0t: net_so = 1 at this edge, net_do = %h, net_polarity = %0d",
			$time, net_do, net_polarity);
		$fdisplay(out_file, "%0t: net_so = 1 at this edge, net_do = %h, net_polarity = %0d",
			$time, net_do, net_polarity);
		if (net_do !== packet) begin
			$display("  ERROR: net_do should be %h", packet);
			$fdisplay(out_file, "  ERROR: net_do should be %h", packet);
			errors = errors + 1;
		end
	end
end

task check;
	input [8*64-1:0] what;
	input [0:63]     got, want;
	begin
		if (got !== want) begin
			$display("%0t: ERROR: %0s is %h, expected %h", $time, what, got, want);
			$fdisplay(out_file, "%0t: ERROR: %0s is %h, expected %h", $time, what, got, want);
			errors = errors + 1;
		end else begin
			$display("%0t: ok: %0s = %h", $time, what, got);
			$fdisplay(out_file, "%0t: ok: %0s = %h", $time, what, got);
		end
	end
endtask

// A processor load: drive the address at a falling edge, the register
// appears on d_out after the next rising edge
task cpu_load;
	input  [0:1]  a;
	output [0:63] value;
	begin
		@(negedge clk);
		nicEn = 1; nicWrEn = 0; addr = a;
		@(posedge clk); #1;
		value = d_out;
		@(negedge clk);
		nicEn = 0;
	end
endtask

task cpu_store;
	input [0:1]  a;
	input [0:63] value;
	begin
		@(negedge clk);
		nicEn = 1; nicWrEn = 1; addr = a; d_in = value;
		@(negedge clk);
		nicEn = 0; nicWrEn = 0;
	end
endtask

reg [0:63] value;

initial begin
	// Open log file in out/
	$system("mkdir -p out");
	out_file = $fopen("out/tb_cardinal_nic.out", "w");
	if (!out_file) begin
		$display("[WARN] Could not create out/tb_cardinal_nic.out, falling back to local file.");
		out_file = $fopen("tb_cardinal_nic.out", "w");
	end

	clk = 0; reset = 1; errors = 0; sends = 0;
	addr = 0; d_in = 0; nicEn = 0; nicWrEn = 0; net_si = 0; net_ro = 0; net_di = 0;
	packet = 64'h9001_0000_0000_0001;	// vc 1, to node 1 (x 1, y 0), 1 hop, source 0, payload 0001

	$display("================================================================");
	$display("Running Full NIC Testbench (Report R1 Cases a through i)");
	$display("================================================================");
	$fdisplay(out_file, "================================================================");
	$fdisplay(out_file, "Running Full NIC Testbench (Report R1 Cases a through i)");
	$fdisplay(out_file, "================================================================");

	// ------------------------------------------------------------------------
	// Case (a): Reset behavior
	// ------------------------------------------------------------------------
	$display("\n--- [R1(a)] Synchronous Reset Test ---");
	$fdisplay(out_file, "\n--- [R1(a)] Synchronous Reset Test ---");
	repeat (3) @(negedge clk);
	check("net_so during reset", net_so, 0);
	check("net_ri during reset", net_ri, 1);
	reset = 0;
	cpu_load(2'b01, value); check("input status after reset", value, 0);
	cpu_load(2'b11, value); check("output status after reset", value, 0);

	// ------------------------------------------------------------------------
	// Case (d): Processor store with output buffer free
	// ------------------------------------------------------------------------
	$display("\n--- [R1(d)] Processor Store with Output Buffer Free ---");
	$fdisplay(out_file, "\n--- [R1(d)] Processor Store with Output Buffer Free ---");
	cpu_store(2'b10, packet);
	cpu_load(2'b11, value); check("output status after store", value, 1);

	// ------------------------------------------------------------------------
	// Case (e): Processor store with output buffer occupied (drop overwrite)
	// ------------------------------------------------------------------------
	$display("\n--- [R1(e)] Processor Store with Output Buffer Occupied ---");
	$fdisplay(out_file, "\n--- [R1(e)] Processor Store with Output Buffer Occupied ---");
	// Attempt to store a different packet into the full buffer
	cpu_store(2'b10, 64'hFFFF_FFFF_FFFF_FFFF);
	cpu_load(2'b11, value); check("output status remains 1", value, 1);
	// packet variable remains 64'h9001_... to verify no corruption on send

	// ------------------------------------------------------------------------
	// Case (c): Router handshake with blocking (net_ro = 0 for a while)
	// ------------------------------------------------------------------------
	$display("\n--- [R1(c)] Router Handshake with Blocking (net_ro = 0) ---");
	$fdisplay(out_file, "\n--- [R1(c)] Router Handshake with Blocking (net_ro = 0) ---");
	net_ro = 0;
	// Wait 6 cycles through several polarity flips; packet must be held
	repeat (6) @(negedge clk);
	check("sends during router blocking", sends, 0);
	cpu_load(2'b11, value); check("output status held during blocking", value, 1);

	// ------------------------------------------------------------------------
	// Case (b): Router handshake without blocking (net_ro = 1)
	// ------------------------------------------------------------------------
	$display("\n--- [R1(b)] Router Handshake without Blocking ---");
	$fdisplay(out_file, "\n--- [R1(b)] Router Handshake without Blocking ---");
	net_ro = 1;
	repeat (4) @(negedge clk);
	check("sends after unblocking (VC1)", sends, 1);
	cpu_load(2'b11, value); check("output status after send", value, 0);
	net_ro = 0;

	// ------------------------------------------------------------------------
	// Case (f): Packet from router into input buffer, then processor reads it
	// ------------------------------------------------------------------------
	$display("\n--- [R1(f)] Router Delivery and Processor Load (Full Buffer) ---");
	$fdisplay(out_file, "\n--- [R1(f)] Router Delivery and Processor Load (Full Buffer) ---");
	@(negedge clk);
	net_si = 1; net_di = 64'h0000_0002_0000_0200;	// vc 0, node 0, hop 0, source 2
	@(negedge clk);
	net_si = 0; net_di = 0;
	check("net_ri with full input buffer", net_ri, 0);
	cpu_load(2'b01, value); check("input status with packet", value, 1);
	cpu_load(2'b00, value); check("input buffer data", value, 64'h0000_0002_0000_0200);
	cpu_load(2'b01, value); check("input status after read", value, 0);
	check("net_ri after read", net_ri, 1);

	// ------------------------------------------------------------------------
	// Case (g): Processor load with input buffer empty
	// ------------------------------------------------------------------------
	$display("\n--- [R1(g)] Processor Load with Input Buffer Empty ---");
	$fdisplay(out_file, "\n--- [R1(g)] Processor Load with Input Buffer Empty ---");
	cpu_load(2'b00, value);
	cpu_load(2'b01, value); check("input status remains 0 after empty read", value, 0);
	check("net_ri remains 1 after empty read", net_ri, 1);

	// ------------------------------------------------------------------------
	// Case (h): Simultaneous send and receive in the same clock cycle
	// ------------------------------------------------------------------------
	$display("\n--- [R1(h)] Simultaneous Send and Receive in Same Clock Cycle ---");
	$fdisplay(out_file, "\n--- [R1(h)] Simultaneous Send and Receive in Same Clock Cycle ---");
	@(negedge clk);
	// CPU stores to output buffer (addr 10)
	nicEn   = 1; nicWrEn = 1; addr = 2'b10; d_in = 64'h0003_0000_1234_5678; // vc 0
	// Router delivers packet into input buffer (net_si = 1)
	net_si  = 1; net_di = 64'h9004_0000_8765_4321; // vc 1
	@(negedge clk);
	nicEn   = 0; nicWrEn = 0; d_in = 0;
	net_si  = 0; net_di = 0;

	// Check both channels accepted packets concurrently
	cpu_load(2'b01, value); check("input status after simultaneous access", value, 1);
	cpu_load(2'b11, value); check("output status after simultaneous access", value, 1);
	check("net_ri dropped after simultaneous access", net_ri, 0);

	// Read and verify the received packet
	cpu_load(2'b00, value); check("simultaneous rx packet read", value, 64'h9004_0000_8765_4321);
	cpu_load(2'b01, value); check("input status cleared", value, 0);
	check("net_ri restored to 1", net_ri, 1);

	// ------------------------------------------------------------------------
	// Case (i): Packets of both VC values under toggling polarity
	// ------------------------------------------------------------------------
	$display("\n--- [R1(i)] Packets of Both VC Values (VC0 then VC1) ---");
	$fdisplay(out_file, "\n--- [R1(i)] Packets of Both VC Values (VC0 then VC1) ---");
	// 1. Drain the VC0 packet currently waiting in the output buffer
	// vc = 0 -> requires net_polarity == 1 (~vc)
	packet = 64'h0003_0000_1234_5678;
	net_ro = 1;
	repeat (4) @(negedge clk);
	check("sends after VC0 packet transfer", sends, 2);
	cpu_load(2'b11, value); check("output status free after VC0 send", value, 0);
	net_ro = 0;

	// 2. Transmit a second packet with VC1
	// vc = 1 -> requires net_polarity == 0 (~vc)
	packet = 64'h9005_0000_AABB_CCDD;
	cpu_store(2'b10, packet);
	cpu_load(2'b11, value); check("output status after second store", value, 1);
	net_ro = 1;
	repeat (4) @(negedge clk);
	check("sends after VC1 packet transfer", sends, 3);
	cpu_load(2'b11, value); check("output status free after VC1 send", value, 0);
	net_ro = 0;

	// ------------------------------------------------------------------------
	// Summary & Final Status
	// ------------------------------------------------------------------------
	repeat (2) @(negedge clk);
	$display("\n================================================================");
	$fdisplay(out_file, "\n================================================================");
	if (errors == 0) begin
		$display("ALL NIC TEST CASES PASSED SUCCESSFULLY (0 errors, %0d sends)", sends);
		$fdisplay(out_file, "ALL NIC TEST CASES PASSED SUCCESSFULLY (0 errors, %0d sends)", sends);
	end else begin
		$display("NIC TEST FAILED: %0d error(s)", errors);
		$fdisplay(out_file, "NIC TEST FAILED: %0d error(s)", errors);
	end
	$display("Simulation output log saved to: out/tb_cardinal_nic.out");
	$display("================================================================");
	$fdisplay(out_file, "================================================================");

	$fclose(out_file);
	$finish;
end

endmodule
