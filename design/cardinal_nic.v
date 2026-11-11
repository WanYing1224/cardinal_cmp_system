////////////////////////////////////////////////////////////////////////////
// Cardinal Network Interface Component - top-level module (EE577B Phase 3)
//
// DO NOT CHANGE THE MODULE NAME OR THE PORT LIST BELOW.
// The NIC grading testbench instantiates cardinal_nic by these exact port
// names (Figure 2 and Table 1 of the corrected NIC specification). The
// write enable is named nicWrEn, as in the corrected specification and in
// the Phase 3 handout; if your Project 1 NIC uses nicEnWr,
// rename the port.
//
// Register map (Table 2), selected by addr[0:1]:
//   00  input channel buffer        read only; a read empties the buffer
//   01  input channel status        read only
//   10  output channel buffer       write only
//   11  output channel status       read only
// Unsupported accesses are ignored. A store to an occupied output buffer is
// ignored. A status read returns the bit on d_out[63], d_out[0:62] = 0.
//
// Timing:
//   * Processor side: addr, d_in, nicEn and nicWrEn are sampled at the
//     rising clock edge; the selected register appears on d_out after that
//     edge (like the data memory). d_out is 0 after an edge at which nicEn
//     was 0.
//   * Network input channel: when net_si is 1 at a rising edge, net_di is
//     latched into the input buffer and net_ri (buffer empty) drops.
//   * Network output channel: the router samples net_so and net_do at
//     rising edges. A packet is taken at an edge where net_so = 1; at that
//     edge net_ro must be 1 and net_polarity must be ~vc (vc = bit 0 of
//     the packet; specification Figure 3, the phase in which the mesh
//     transfers that VC). This is the opposite of the Project 1 NIC
//     testbench rule. net_so may be registered (decided at the previous
//     edge, where the sampled polarity equals vc) or combinational.
//     Release the buffer only at an edge where net_so and net_ro are both
//     1 (the router accepted the packet); otherwise keep it and offer it
//     again.
//   * Reset (synchronous, active high): both buffers empty, both status
//     registers 0, net_so = 0, net_ri = 1, d_out = 0.
//
// Bit numbering: Phase 3 uses the Phase 2 processor convention, [0:63]
// with bit 0 the MSB (vc bit) and bit 63 the LSB (status bit on d_out).
// Project 1 declared the same ports as [63:0]. You may keep [63:0] and
// [1:0] declarations in this module: ports connect by name, MSB to MSB,
// so your Project 1 code (d_in[63] = vc, addr[1] = high address bit)
// stays right. Do not mix: a module declared [0:63] must use d_in[0] for
// the vc bit and addr[0] for the high address bit.
//
// Description: Cardinal Network Interface Component (NIC)
//              Provides memory-mapped register interface between CPU and Router.
////////////////////////////////////////////////////////////////////////////

module cardinal_nic (
    input         clk,          // rising-edge clock
    input         reset,        // synchronous, active high
    // processor side
    input  [0:1]  addr,         // register select (Table 2)
    input  [0:63] d_in,         // packet from the processor
    output [0:63] d_out,        // register content to the processor
    input         nicEn,        // NIC enable
    input         nicWrEn,      // NIC write enable
    // router side, network input channel (router -> processor)
    input         net_si,       // router sends a packet
    output        net_ri,       // input channel buffer is empty
    input  [0:63] net_di,       // packet from the router
    // router side, network output channel (processor -> router)
    output        net_so,       // NIC sends a packet
    input         net_ro,       // router can accept a packet
    output [0:63] net_do,       // packet to the router
    input         net_polarity  // polarity of the connected router
);

wire clk, reset;
wire [0:1] addr;
wire [0:63] d_in;        
reg [0:63] d_out;
wire nicEn, nicWrEn;
wire net_si, net_ri;      
wire [0:63] net_di;
wire net_so, net_ro, net_polarity;
wire [0:63] net_do;

/*=============================================
    Internal Buffers & Status Registers
==============================================*/
reg [0:63] input_buf, output_buf;
reg input_status, output_status;    // 1'b1 = occupied/full, 1'b0 = empty

/*=============================================
    Network Rx Handshake (Router -> NIC)
==============================================*/
// Ready when input buffer is empty
assign net_ri = ~input_status;      

// Detect if processor is reading and popping the input buffer this cycle
wire proc_pop_rx = nicEn && (!nicWrEn) && (addr == 2'b00);      

// RX Latch & Status Update
always @(posedge clk) begin
    if (reset) begin
        input_buf <= 64'h0;
        input_status <= 64'h0;
    end
    else begin
        if (net_si && ~input_status) begin
            // Latch incoming packet from router
            input_buf <= net_di;
            input_status <= 1'b1;
        end
        else if (proc_pop_rx && input_status) begin
            input_status <= 1'b0;    // Processor reads and clears the input buffer
        end
    end
end

/*=============================================
    Network Tx Handshake (Router -> NIC)
==============================================*/
// Packet VC is bit 0 of output_buf:
// vc = 0 (even virtual channel) -> injected when net_polarity == 1
// vc = 1 (odd virtual channel)  -> injected when net_polarity == 0
wire target_polarity = ~output_buf[0];

// Assert net_so only when packet exists, router has space, and polarity matches
assign net_so = output_status && net_ro && (net_polarity == target_polarity);
assign net_do = output_buf;

// Handshake completion on output channel
wire net_tx_done = net_so && net_ro;

/*=============================================
Processor Tx Latch & Output Buffer Management
==============================================*/
// Processor store condition: enabled, write-enabled, addr == 2'b10, and buffer free
wire proc_push_tx = nicEn && nicWrEn && (addr == 2'b10) && (~output_status);

always @(posedge clk) begin
    if (reset) begin
        output_buf    <= 64'h0;
        output_status <= 1'b0;
    end 
    else begin
        if (proc_push_tx) begin
            output_buf <= d_in;
            output_status <= 1'b1;
        end 
        else if (net_tx_done) begin
            output_status <= 1'b0;    // Router accepted packet; free buffer
        end
    end
end

/*=============================================
Processor Load Data Path (Registered 1-Cycle Output)
==============================================*/
always @(posedge clk) begin
    if (reset) begin
        d_out <= 64'h0;
    end 
    else if (!nicEn) begin
        d_out <= 64'h0;
    end 
    else if (!nicWrEn) begin
        case (addr)
            2'b00:   d_out <= input_buf;
            2'b01:   d_out <= {63'b0, input_status};
            2'b10:   d_out <= 64'h0;    // Read from write-only output buffer is undefined
            2'b11:   d_out <= {63'b0, output_status};
            default: d_out <= 64'h0;
        endcase
    end 
    else begin
        d_out <= 64'h0;    // During writes, d_out is idle
    end
end

endmodule
