; R2(g) / A4: NIC Address Map & Read-Only Register Protection
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
