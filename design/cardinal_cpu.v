////////////////////////////////////////////////////////////////////////////
// Cardinal processor - top-level module (EE577B Phase 3)
//
// Start from your Phase 2 processor and add the NIC interface described in
// the NIC specification ("Interfacing with Processor"). Keep the module
// name and the port list below as provided: the Phase 2 ports plus the
// five NIC ports (Figure 1 of the handout). They are what the cardinal_cmp
// template connects.
//
// NIC address decoding (memAddr = {16'b0, immediate} = addr_out):
//   * memAddr[16] and memAddr[17] both 1 (immediate[0:1] == 2'b11): the
//     load or store accesses the NIC. memAddr[30:31] (immediate[14:15])
//     selects the NIC register (addr_nic). Assert nicEn, and nicWrEn for a
//     store; memEn and memWrEn must stay 0.
//   * Otherwise it is a data memory access, as in Phase 2 (only
//     memAddr[24:31] are used by the memory model); nicEn stays 0.
//
// NIC timing (same as the data memory): addr_nic, din_nic, nicEn and
// nicWrEn are sampled at a rising clock edge; a store is written at that
// edge, and the register selected by a load appears on dout_nic after that
// edge, during the following cycle. A load from the NIC therefore takes
// its data from dout_nic where a load from the data memory takes d_in.
// ==========================================================================
// Description: Top-Level 64-bit 4-Stage Pipelined Cardinal Processor Core
//              - Stages: IF, ID, EX/MEM, WB
//              - Synchronous active-high reset
//              - Integrated Hazard Management Unit (Flushes & Stalls)
//              - Immediate-address Memory Interface (asynch IMEM, synch DMEM)
//              - Phase 3 Memory-Mapped NIC Interface Integration
//              - Big-Endian indexing convention [0:31] and [0:63]
////////////////////////////////////////////////////////////////////////////

module cardinal_cpu (
    input         clk,        // rising-edge clock
    input         reset,      // synchronous, active high
    input  [0:31] inst_in,    // instruction from the instruction memory
    input  [0:63] d_in,       // load data from the data memory
    output [0:31] pc_out,     // instruction memory address (byte address)
    output [0:31] addr_out,   // data memory address (64-bit word address)
    output        memEn,      // data memory enable (load or store)
    output        memWrEn,    // data memory write enable (store)
    output [0:63] d_out,      // store data to the data memory

    // NIC Interface
    output [0:1]  addr_nic,   // NIC register address (memAddr[30:31])
    output [0:63] din_nic,    // store data to the NIC (NIC port d_in)
    input  [0:63] dout_nic,   // load data from the NIC (NIC port d_out)
    output        nicEn,      // NIC enable (load or store to a NIC address)
    output        nicWrEn     // NIC write enable (store to a NIC address)
);

// =====================================================================
// Forward Declarations & Inter-Stage Wires
// =====================================================================
wire        branch_taken;
wire [0:31] branch_target;

// ID Stage Decoded Signals
wire [0:4]  id_rD_addr;
wire [0:4]  id_rA_addr;
wire [0:4]  id_rB_addr;
wire [0:15] id_imm;
wire [0:2]  id_ppp;
wire [0:1]  id_ww;
wire [0:5]  id_opcode;
wire [0:5]  id_func_code;

wire        id_rf_wr_en;
wire [0:7]  id_rf_byte_wr_en;
wire        id_dmem_read;
wire        id_dmem_write;
wire        id_wb_src_sel;
wire        id_alu_or_sfu_sel;
wire [0:4]  id_alu_op;
wire        id_is_branch;
wire        id_branch_type;
wire        id_is_nop;
wire        id_is_illegal;
wire        id_rA_used;
wire        id_rB_used;
wire        id_rD_as_src;

// ID/EX Pipeline Registers
reg        id_ex_rf_wr_en;
reg [0:7]  id_ex_rf_byte_wr_en;
reg        id_ex_dmem_read;
reg        id_ex_dmem_write;
reg        id_ex_wb_src_sel;
reg        id_ex_alu_or_sfu_sel;
reg [0:4]  id_ex_alu_op;
reg [0:1]  id_ex_ww;
reg [0:4]  id_ex_rD_addr;
reg [0:15] id_ex_imm;
reg [0:63] id_ex_rA_data;
reg [0:63] id_ex_rB_data;
reg [0:63] id_ex_store_data;

// EX/WB Pipeline Registers
reg        ex_wb_rf_wr_en;
reg [0:7]  ex_wb_rf_byte_wr_en;
reg        ex_wb_wb_src_sel;
reg [0:4]  ex_wb_rD_addr;
reg [0:63] ex_wb_calc_result;
reg        ex_wb_is_nic;

// Hazard Control Signals
wire stall_pc;
wire stall_if_id;
wire flush_if_id;
wire bubble_id_ex;

// =====================================================================
// Hazard Detection Unit Instantiation
// =====================================================================
hazard_unit u_hazard (
    .id_rA_addr      (id_rA_addr),
    .id_rB_addr      (id_rB_addr),
    .id_rD_addr      (id_rD_addr),
    .id_rA_used      (id_rA_used),
    .id_rB_used      (id_rB_used),
    .id_rD_as_src    (id_rD_as_src),
    .branch_taken    (branch_taken),
    .id_ex_rD_addr   (id_ex_rD_addr),
    .id_ex_rf_wr_en  (id_ex_rf_wr_en),
    .id_ex_dmem_read (id_ex_dmem_read),
    .ex_wb_rD_addr   (ex_wb_rD_addr),
    .ex_wb_rf_wr_en  (ex_wb_rf_wr_en),
    .stall_pc        (stall_pc),
    .stall_if_id     (stall_if_id),
    .flush_if_id     (flush_if_id),
    .bubble_id_ex    (bubble_id_ex)
);

// =====================================================================
// IF Stage
// =====================================================================
reg [0:31] pc;
wire [0:31] next_pc;

assign pc_out = pc;

// Branch takes precedence over normal increment
assign next_pc = branch_taken ? branch_target : (pc + 32'd4);

always @(posedge clk) begin
    if (reset) begin
        pc <= 32'h0000_0000;
    end 
    else if (!stall_pc) begin
        pc <= next_pc;
    end
end

// =====================================================================
// IF / ID Pipeline Register
// =====================================================================
reg [0:31] if_id_instr;
reg [0:31] if_id_pc;

always @(posedge clk) begin
    if (reset || flush_if_id) begin
        // Flush to bubble (VNOP: opcode 6'b111100)
        if_id_instr <= 32'hF000_0000;
        if_id_pc    <= 32'h0000_0000;
    end 
    else if (!stall_if_id) begin
        if_id_instr <= inst_in;
        if_id_pc    <= pc;
    end
end

// =====================================================================
// ID Stage
// =====================================================================
control_decoder u_decoder (
    .instr          (if_id_instr),
    .rD_addr        (id_rD_addr),
    .rA_addr        (id_rA_addr),
    .rB_addr        (id_rB_addr),
    .imm            (id_imm),
    .ppp            (id_ppp),
    .ww             (id_ww),
    .opcode         (id_opcode),
    .func_code      (id_func_code),
    .rf_wr_en       (id_rf_wr_en),
    .rf_byte_wr_en  (id_rf_byte_wr_en),
    .dmem_read      (id_dmem_read),
    .dmem_write     (id_dmem_write),
    .wb_src_sel     (id_wb_src_sel),
    .alu_or_sfu_sel (id_alu_or_sfu_sel),
    .alu_op         (id_alu_op),
    .is_branch      (id_is_branch),
    .branch_type    (id_branch_type),
    .is_nop         (id_is_nop),
    .is_illegal     (id_is_illegal),
    .rA_used        (id_rA_used),
    .rB_used        (id_rB_used),
    .rD_as_src      (id_rD_as_src)
);

// Register File Connections
wire [0:4]  rf_rd_addr1 = id_rD_as_src ? id_rD_addr : id_rB_addr;
wire [0:63] rf_rd_data0;
wire [0:63] rf_rd_data1;

wire        wb_rf_wr_en;
wire [0:4]  wb_rf_wr_addr;
wire [0:63] wb_rf_wr_data;
wire [0:7]  wb_rf_byte_wr_en;

register_file u_regfile (
    .clk      (clk),
    .reset    (reset),
    .wrEn     (wb_rf_wr_en),
    .wrAddr   (wb_rf_wr_addr),
    .wrData   (wb_rf_wr_data),
    .wrByteEn (wb_rf_byte_wr_en),
    .rdAddr0  (id_rA_addr),
    .rdData0  (rf_rd_data0),
    .rdAddr1  (rf_rd_addr1),
    .rdData1  (rf_rd_data1)
);

// Early Branch Resolution (evaluated directly in ID)
wire branch_cond_met = (id_branch_type == 1'b0) ? (rf_rd_data1 == 64'd0) : (rf_rd_data1 != 64'd0);
assign branch_taken  = id_is_branch && branch_cond_met;
assign branch_target = {16'h0000, id_imm};

// =====================================================================
// ID / EX Pipeline Register
// =====================================================================
always @(posedge clk) begin
    if (reset || bubble_id_ex) begin
        id_ex_rf_wr_en       <= 1'b0;
        id_ex_rf_byte_wr_en  <= 8'h00;
        id_ex_dmem_read      <= 1'b0;
        id_ex_dmem_write     <= 1'b0;
        id_ex_wb_src_sel     <= 1'b0;
        id_ex_alu_or_sfu_sel <= 1'b0;
        id_ex_alu_op         <= 5'd0;
        id_ex_ww             <= 2'b00;
        id_ex_rD_addr        <= 5'd0;
        id_ex_imm            <= 16'd0;
        id_ex_rA_data        <= 64'd0;
        id_ex_rB_data        <= 64'd0;
        id_ex_store_data     <= 64'd0;
    end 
    else begin
        id_ex_rf_wr_en       <= id_rf_wr_en;
        id_ex_rf_byte_wr_en  <= id_rf_byte_wr_en;
        id_ex_dmem_read      <= id_dmem_read;
        id_ex_dmem_write     <= id_dmem_write;
        id_ex_wb_src_sel     <= id_wb_src_sel;
        id_ex_alu_or_sfu_sel <= id_alu_or_sfu_sel;
        id_ex_alu_op         <= id_alu_op;
        id_ex_ww             <= id_ww;
        id_ex_rD_addr        <= id_rD_addr;
        id_ex_imm            <= id_imm;
        id_ex_rA_data        <= rf_rd_data0;
        id_ex_rB_data        <= rf_rd_data1;
        id_ex_store_data     <= rf_rd_data1;
    end
end

// =====================================================================
// EX / MEM Access Stage
// =====================================================================
wire [0:63] ex_alu_out;
wire [0:63] ex_sfu_out;

alu u_alu (
    .alu_op  (id_ex_alu_op),
    .ww      (id_ex_ww),
    .rA_data (id_ex_rA_data),
    .rB_data (id_ex_rB_data),
    .alu_out (ex_alu_out)
);

sfu u_sfu (
    .alu_op  (id_ex_alu_op),
    .ww      (id_ex_ww),
    .rA_data (id_ex_rA_data),
    .rB_data (id_ex_rB_data),
    .sfu_out (ex_sfu_out)
);

wire [0:63] ex_calc_result = id_ex_alu_or_sfu_sel ? ex_sfu_out : ex_alu_out;

// Memory & NIC Address and Data Signals
assign addr_out = {16'h0000, id_ex_imm};
assign d_out    = id_ex_store_data;

// Phase 3 Address Decoding:
// If addr_out[16:17] == 2'b11, access refers to the NIC; otherwise Data Memory
wire is_nic_access = (addr_out[16:17] == 2'b11);

// Data Memory Enable Signals
assign memEn    = (id_ex_dmem_read | id_ex_dmem_write) && (!is_nic_access);
assign memWrEn  = id_ex_dmem_write && (!is_nic_access);

// NIC Interface Enable Signals & Data
assign nicEn    = (id_ex_dmem_read | id_ex_dmem_write) && is_nic_access;
assign nicWrEn  = id_ex_dmem_write && is_nic_access;
assign addr_nic = addr_out[30:31];
assign din_nic  = id_ex_store_data;

// =====================================================================
// EX / WB Pipeline Register
// =====================================================================
always @(posedge clk) begin
    if (reset) begin
        ex_wb_rf_wr_en      <= 1'b0;
        ex_wb_rf_byte_wr_en <= 8'h00;
        ex_wb_wb_src_sel    <= 1'b0;
        ex_wb_rD_addr       <= 5'd0;
        ex_wb_calc_result   <= 64'd0;
        ex_wb_is_nic        <= 1'b0;
    end 
    else begin
        ex_wb_rf_wr_en      <= id_ex_rf_wr_en;
        ex_wb_rf_byte_wr_en <= id_ex_rf_byte_wr_en;
        ex_wb_wb_src_sel    <= id_ex_wb_src_sel;
        ex_wb_rD_addr       <= id_ex_rD_addr;
        ex_wb_calc_result   <= ex_calc_result;
        ex_wb_is_nic        <= is_nic_access;
    end
end

// =====================================================================
// WB Stage
// =====================================================================
assign wb_rf_wr_en      = ex_wb_rf_wr_en;
assign wb_rf_wr_addr    = ex_wb_rD_addr;
assign wb_rf_byte_wr_en = ex_wb_rf_byte_wr_en;

// Multiplex load data between Data Memory (d_in) and NIC (dout_nic)
wire [0:63] load_data   = ex_wb_is_nic ? dout_nic : d_in;
assign wb_rf_wr_data    = ex_wb_wb_src_sel ? load_data : ex_wb_calc_result;

endmodule
