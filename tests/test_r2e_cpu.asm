; R2(e) / A2: Comprehensive ALU, SFU, PPP, and Hazard Test across all 16 cores
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
