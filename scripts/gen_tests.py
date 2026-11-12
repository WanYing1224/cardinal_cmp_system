#!/usr/bin/env python3
import os

os.makedirs("tests", exist_ok=True)

# ---------------------------------------------------------------------------
# Cardinal ISA Assembler Helpers (matching control_decoder.v)
# ---------------------------------------------------------------------------
def vnop():
    return 0xF0000000

def vend():
    return 0x00000000

def vld(rD, imm):
    return (0b100000 << 26) | ((rD & 0x1F) << 21) | (imm & 0xFFFF)

def vsd(rD, imm):
    return (0b100001 << 26) | ((rD & 0x1F) << 21) | (imm & 0xFFFF)

def vbez(rD, byte_addr):
    return (0b100010 << 26) | ((rD & 0x1F) << 21) | (byte_addr & 0xFFFF)

def vbnez(rD, byte_addr):
    return (0b100011 << 26) | ((rD & 0x1F) << 21) | (byte_addr & 0xFFFF)

def rtype(func, rD, rA, rB=0, ppp=0, ww=3):
    return ((0b101010 << 26) |
            ((rD & 0x1F) << 21) |
            ((rA & 0x1F) << 16) |
            ((rB & 0x1F) << 11) |
            ((ppp & 0x7) << 8) |
            ((ww & 0x3) << 6) |
            (func & 0x3F))

# Function codes from control_decoder.v
F_VAND   = 0b000001
F_VOR    = 0b000010
F_VXOR   = 0b000011
F_VNOT   = 0b000100
F_VMOV   = 0b000101
F_VADD   = 0b000110
F_VSUB   = 0b000111
F_VMULEU = 0b001000
F_VDIV   = 0b001110
F_VMOD   = 0b001111
F_VSQRT  = 0b010010

def write_node_files(prefix, node, imem_words, dmem_dict, exp_dict, asm_text=None):
    if asm_text is not None and node == 0:
        with open(f"tests/{prefix}.asm", "w") as f:
            f.write(asm_text)

    with open(f"tests/{prefix}.imem.{node}.fill", "w") as f:
        for w in imem_words:
            f.write(f"{w:08x}\n")

    with open(f"tests/{prefix}.dmem.{node}.fill", "w") as f:
        for addr in range(32):
            val = dmem_dict.get(addr, 0)
            f.write(f"{val:016x}\n")

    with open(f"tests/{prefix}.expected.{node}.dump", "w") as f:
        for addr in range(32):
            val = exp_dict.get(addr, 0)
            if isinstance(val, str):
                f.write(f"Memory location # {addr:3d} : {val} \n")
            else:
                f.write(f"Memory location # {addr:3d} : {val:016x} \n")

def make_packet(vc, dst_x, dst_y, hops, src, payload, res1=0, res67=0):
    # Bits [0:63] big-endian:
    # bit 0: vc
    # bit 1: res1
    # bits 2-3: dst_x
    # bits 4-5: dst_y
    # bits 6-7: res67
    # bits 8-15: unary hops = (1 << hops) - 1
    # bits 16-31: src
    # bits 32-63: payload
    unary = ((1 << hops) - 1) & 0xFF
    pkt = (((vc & 1) << 63) |
           ((res1 & 1) << 62) |
           ((dst_x & 3) << 60) |
           ((dst_y & 3) << 58) |
           ((res67 & 3) << 56) |
           (unary << 48) |
           ((src & 0xFFFF) << 32) |
           (payload & 0xFFFFFFFF))
    return pkt

# ===========================================================================
# Test R2(e) [A2]: Processor ALU, SFU, PPP, and Hazard Stress on all 16 Nodes
# ===========================================================================
def gen_r2e_cpu():
    asm = """; R2(e) / A2: Comprehensive ALU, SFU, PPP, and Hazard Test across all 16 cores
        vnop
        vld   r1, 0             ; r1 = {a, a} (32-bit lanes)
        vld   r2, 1             ; r2 = {b, b} (32-bit lanes)
        vadd  r3, r1, r2, 0, 2  ; r3 = {a+b, a+b} (32-bit SIMD add, RAW hazard on r1, r2)
        vsub  r4, r1, r2, 0, 2  ; r4 = {a-b, a-b} (32-bit SIMD sub)
        vmuleu r5, r1, r2, 0, 2 ; r5 = a * b (64-bit product of even 32-bit lane [0:31])
        vdiv  r6, r1, r2, 0, 2  ; r6 = {a/b, a/b} (32-bit SIMD div)
        vmod  r7, r3, r2, 0, 2  ; r7 = {(a+b)%b, (a+b)%b} (32-bit SIMD mod)
        vsqrt r8, r1, 0, 0, 2   ; r8 = {sqrt(a), sqrt(a)} (32-bit SIMD sqrt)
        vand  r9, r1, r2, 0, 3  ; r9 = r1 & r2
        vor   r10, r1, r2, 0, 3 ; r10 = r1 | r2
        vxor  r11, r1, r2, 0, 3 ; r11 = r1 ^ r2
        vnot  r12, r1, 0, 1, 2  ; r12 upper 32 bits inverted (ppp=1 -> upper 32-bit lane)
        vsd   r3, 2
        vsd   r4, 3
        vsd   r5, 4
        vsd   r6, 5
        vsd   r7, 6
        vsd   r8, 7
        vsd   r9, 8
        vsd   r10, 9
        vsd   r11, 10
        vsd   r12, 11
        end
"""
    imem = [
        vnop(),
        vld(1, 0),
        vld(2, 1),
        rtype(F_VADD,   3, 1, 2, ppp=0, ww=2),
        rtype(F_VSUB,   4, 1, 2, ppp=0, ww=2),
        rtype(F_VMULEU, 5, 1, 2, ppp=0, ww=2),
        rtype(F_VDIV,   6, 1, 2, ppp=0, ww=2),
        rtype(F_VMOD,   7, 3, 2, ppp=0, ww=2),
        rtype(F_VSQRT,  8, 1, 0, ppp=0, ww=2),
        rtype(F_VAND,   9, 1, 2, ppp=0, ww=3),
        rtype(F_VOR,   10, 1, 2, ppp=0, ww=3),
        rtype(F_VXOR,  11, 1, 2, ppp=0, ww=3),
        rtype(F_VNOT,  12, 1, 0, ppp=1, ww=2),
        vsd(3, 2),
        vsd(4, 3),
        vsd(5, 4),
        vsd(6, 5),
        vsd(7, 6),
        vsd(8, 7),
        vsd(9, 8),
        vsd(10, 9),
        vsd(11, 10),
        vsd(12, 11),
        vend()
    ]
    for n in range(16):
        a = 100 + n * 4
        b = 25
        a_vec = (a << 32) | a
        b_vec = (b << 32) | b
        dmem = {0: a_vec, 1: b_vec}
        exp = dict(dmem)
        exp[2]  = ((a + b) << 32) | (a + b)
        exp[3]  = ((a - b) << 32) | (a - b)
        exp[4]  = a * b
        exp[5]  = ((a // b) << 32) | (a // b)
        exp[6]  = (((a + b) % b) << 32) | ((a + b) % b)
        exp[7]  = (int(a ** 0.5) << 32) | int(a ** 0.5)
        exp[8]  = a_vec & b_vec
        exp[9]  = a_vec | b_vec
        exp[10] = a_vec ^ b_vec
        exp[11] = ((~a) & 0xFFFFFFFF) << 32
        write_node_files("test_r2e_cpu", n, imem, dmem, exp, asm)

# ===========================================================================
# Test R2(f) [A3]: Full Mesh Communication (1..6 hops, dual VC, reserved bits)
# ===========================================================================
def gen_r2f_comm():
    # Each node sends 15 packets (one to every other node 0..15, covering 1..6 hops)
    # Interleaved send and receive (1 send, 1 receive per iteration) to prevent deadlock.
    # Reversed VC polarity vs sample test: cols 0,1 use VC0; cols 2,3 use VC1.
    # Also sets reserved bits (bit 1 = 1, bits 6-7 = 2'b11) to confirm unchanged delivery.
    asm = """; R2(f) / A3: All-to-All Interleaved Communication (15 packets per node, 1..6 hops)
; Sends MEM[0..14] to all 15 peer nodes and stores received packets in MEM[16..30]
"""
    for src in range(16):
        sx, sy = src % 4, src // 4
        vc = 0 if sx < 2 else 1
        dmem = {}
        imem = [vnop()]
        tx_idx = 0
        for dst in range(16):
            if dst == src:
                continue
            dx, dy = dst % 4, dst // 4
            hops = abs(dx - sx) + abs(dy - sy)
            payload = (0xA5000000 | (src << 16) | (dst << 8) | hops)
            pkt = make_packet(vc, dx, dy, hops, (0x8000 | src), payload, res1=1, res67=3)
            dmem[tx_idx] = pkt

            # Load packet from DMEM[tx_idx]
            imem.append(vld(10, tx_idx))
            # Poll Tx status
            tx_poll_addr = len(imem) * 4
            imem.append(vld(1, 0xC003))
            imem.append(vbnez(1, tx_poll_addr))
            imem.append(vsd(10, 0xC002))

            # Poll Rx status
            rx_poll_addr = len(imem) * 4
            imem.append(vld(2, 0xC001))
            imem.append(vbez(2, rx_poll_addr))
            imem.append(vld(5, 0xC000))
            imem.append(vsd(5, 16 + tx_idx))
            tx_idx += 1

        imem.append(vend())

        # Build expected dump (received packets in MEM[16..30] with xx hop nibble)
        exp = dict(dmem)
        rx_idx = 0
        for peer in range(16):
            if peer == src:
                continue
            px, py = peer % 4, peer // 4
            p_vc = 0 if px < 2 else 1
            hops = abs(sx - px) + abs(sy - py)
            payload = (0xA5000000 | (peer << 16) | (src << 8) | hops)
            pkt = make_packet(p_vc, sx, sy, hops, (0x8000 | peer), payload, res1=1, res67=3)
            hex_str = f"{pkt:016x}"
            # Mask hop field (nibbles 2 and 3 in big-endian hex string) as 'xx'
            masked_hex = hex_str[:2] + "xx" + hex_str[4:]
            exp[16 + rx_idx] = masked_hex
            rx_idx += 1

        write_node_files("test_r2f_comm", src, imem, dmem, exp, asm)

# ===========================================================================
# Test R2(g) [A4]: NIC Address Map & Read-Only Protection
# ===========================================================================
def gen_r2g_addrmap():
    # Verifies:
    # 1. Both NIC status registers read 0 after reset (stored to MEM[10], MEM[11])
    # 2. Distinctive values in MEM[0..3] are untouched by NIC loads/stores
    # 3. Addresses with bits [16:17] = 01 (0x4004) and 10 (0x8005) access DMEM
    # 4. Addresses with bits [16:17] = 11 (e.g. 0xF001, 0xF003) reach NIC
    # 5. Stores to read-only NIC registers (0xC000, 0xC001, 0xC003) change nothing
    asm = """; R2(g) / A4: NIC Address Map & Read-Only Register Protection
        vnop
        vld   r1, 0xC001        ; input status after reset -> 0
        vld   r2, 0xC003        ; output status after reset -> 0
        vsd   r1, 10            ; MEM[10] = 0
        vsd   r2, 11            ; MEM[11] = 0
        vld   r3, 0             ; r3 = distinctive value from MEM[0]
        vsd   r3, 0xC000        ; illegal store to read-only input buffer (ignored)
        vsd   r3, 0xC001        ; illegal store to read-only input status (ignored)
        vsd   r3, 0xC003        ; illegal store to read-only output status (ignored)
        vld   r4, 0xF001        ; read input status via alias 0xF001 (bits 16:17 = 11) -> still 0
        vld   r5, 0xF003        ; read output status via alias 0xF003 (bits 16:17 = 11) -> still 0
        vsd   r4, 12            ; MEM[12] = 0
        vsd   r5, 13            ; MEM[13] = 0
        vsd   r3, 0x4004        ; addr[16:17]=01 -> reaches DMEM[4]
        vld   r6, 1             ; r6 = distinctive value from MEM[1]
        vsd   r6, 0x8005        ; addr[16:17]=10 -> reaches DMEM[5]
        end
"""
    imem = [
        vnop(),
        vld(1, 0xC001),
        vld(2, 0xC003),
        vsd(1, 10),
        vsd(2, 11),
        vld(3, 0),
        vsd(3, 0xC000),
        vsd(3, 0xC001),
        vsd(3, 0xC003),
        vld(4, 0xF001),
        vld(5, 0xF003),
        vsd(4, 12),
        vsd(5, 13),
        vsd(3, 0x4004),
        vld(6, 1),
        vsd(6, 0x8005),
        vend()
    ]
    for n in range(16):
        dmem = {
            0: 0x1111222233334444,
            1: 0x5555666677778888,
            2: 0x9999AAAABBBBCCCC,
            3: 0xDDDDEEEEFFFF0000
        }
        exp = dict(dmem)
        exp[4]  = 0x1111222233334444
        exp[5]  = 0x5555666677778888
        exp[10] = 0
        exp[11] = 0
        exp[12] = 0
        exp[13] = 0
        write_node_files("test_r2g_addrmap", n, imem, dmem, exp, asm)

# ===========================================================================
# Test R2(h) [A5]: Network Blocking & Backpressure (10-packet burst)
# ===========================================================================
def gen_r2h_blocking():
    # Node 0 bursts 10 packets to Node 1 while Node 1 executes 80 VNOP delay cycles
    # before reading any packets. Induces router & NIC backpressure (net_ro = 0)
    # and verifies all 10 packets arrive in order without loss.
    asm = """; R2(h) / A5: 10-packet burst from Node 0 to Node 1 with receiver delay"""

    # Node 0: Send 10 packets from MEM[0..9] to Node 1
    imem0 = [vnop()]
    dmem0 = {}
    exp0  = {}
    for idx in range(10):
        pkt = make_packet(vc=1, dst_x=1, dst_y=0, hops=1, src=0, payload=(0xB0000000 + idx))
        dmem0[idx] = pkt
        exp0[idx]  = pkt
        imem0.append(vld(10, idx))
        poll_addr = len(imem0) * 4
        imem0.append(vld(1, 0xC003))
        imem0.append(vbnez(1, poll_addr))
        imem0.append(vsd(10, 0xC002))
    imem0.append(vend())
    write_node_files("test_r2h_blocking", 0, imem0, dmem0, exp0, asm)

    # Node 1: 80-cycle VNOP delay, then read all 10 packets into MEM[10..19]
    imem1 = [vnop() for _ in range(80)]
    dmem1 = {}
    exp1  = {}
    for idx in range(10):
        rx_poll = len(imem1) * 4
        imem1.append(vld(2, 0xC001))
        imem1.append(vbez(2, rx_poll))
        imem1.append(vld(5, 0xC000))
        imem1.append(vsd(5, 10 + idx))
        exp1[10 + idx] = f"9001xx00{(0xB0000000 + idx):08x}"
    imem1.append(vend())
    write_node_files("test_r2h_blocking", 1, imem1, dmem1, exp1)

    # Nodes 2..15: Idle (immediate end)
    for n in range(2, 16):
        write_node_files("test_r2h_blocking", n, [vnop(), vend()], {}, {})

# ===========================================================================
# Test R2(i) [A6]: Tight Polling Loops (Zero VNOPs, irregular send/receive)
# ===========================================================================
def gen_r2i_tight():
    # Node 0 and Node 2 exchange packets with zero VNOPs between VLD and VBEZ/VBNEZ,
    # testing back-to-back load-use stalls and branch forwarding in irregular order.
    asm = """; R2(i) / A6: Tight Polling Loops with Zero VNOPs and Irregular Send/Receive"""

    # Node 0: Sends 2 packets to Node 2, then receives 2 from Node 2
    p0_a = make_packet(vc=1, dst_x=2, dst_y=0, hops=2, src=0, payload=0xC0010001)
    p0_b = make_packet(vc=1, dst_x=2, dst_y=0, hops=2, src=0, payload=0xC0010002)
    p2_a = make_packet(vc=0, dst_x=0, dst_y=0, hops=2, src=2, payload=0xC0020001)
    p2_b = make_packet(vc=0, dst_x=0, dst_y=0, hops=2, src=2, payload=0xC0020002)

    imem0 = [
        vld(10, 0),
        vld(11, 1),
        # Tight Tx 1 (no VNOP)
        vld(1, 0xC003),
        vbnez(1, 8),
        vsd(10, 0xC002),
        # Tight Tx 2 (no VNOP)
        vld(1, 0xC003),
        vbnez(1, 20),
        vsd(11, 0xC002),
        # Tight Rx 1 (no VNOP)
        vld(2, 0xC001),
        vbez(2, 32),
        vld(5, 0xC000),
        # Tight Rx 2 (no VNOP)
        vld(2, 0xC001),
        vbez(2, 44),
        vld(6, 0xC000),
        vsd(5, 4),
        vsd(6, 5),
        vend()
    ]
    dmem0 = {0: p0_a, 1: p0_b}
    exp0  = {
        0: p0_a, 1: p0_b,
        4: f"00xx0002{0xC0020001:08x}",
        5: f"00xx0002{0xC0020002:08x}"
    }
    write_node_files("test_r2i_tight", 0, imem0, dmem0, exp0, asm)

    # Node 2: Receives 1, Sends 2, Receives 1 (irregular order, tight loops)
    imem2 = [
        vld(10, 0),
        vld(11, 1),
        # Tight Rx 1
        vld(2, 0xC001),
        vbez(2, 8),
        vld(5, 0xC000),
        # Tight Tx 1
        vld(1, 0xC003),
        vbnez(1, 20),
        vsd(10, 0xC002),
        # Tight Tx 2
        vld(1, 0xC003),
        vbnez(1, 32),
        vsd(11, 0xC002),
        # Tight Rx 2
        vld(2, 0xC001),
        vbez(2, 44),
        vld(6, 0xC000),
        vsd(5, 4),
        vsd(6, 5),
        vend()
    ]
    dmem2 = {0: p2_a, 1: p2_b}
    exp2  = {
        0: p2_a, 1: p2_b,
        4: f"a0xx0000{0xC0010001:08x}",
        5: f"a0xx0000{0xC0010002:08x}"
    }
    write_node_files("test_r2i_tight", 2, imem2, dmem2, exp2)

    # Other nodes idle
    for n in range(16):
        if n not in (0, 2):
            write_node_files("test_r2i_tight", n, [vnop(), vend()], {}, {})

if __name__ == "__main__":
    gen_r2e_cpu()
    gen_r2f_comm()
    gen_r2g_addrmap()
    gen_r2h_blocking()
    gen_r2i_tight()
    print("Generated all R2(e)-(i) test suites in tests/ successfully.")
