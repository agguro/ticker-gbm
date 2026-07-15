/*
 * ============================================================================
 * TICKER GBM ENGINE — X86_64 HOST ORCHESTRATOR
 * EMBEDDED CUBIN + CORRECT CUDA DRIVER ABI
 * ============================================================================
 */

.section .rodata
    .align 16
    kernel_bin:     .incbin "ticker-gbm.cubin"     # Embedded cubin
    kernel_name:    .asciz  "ticker_gbm"           # PTX entry name

    msg_dash:       .asciz "------------------------------------------------------------\n"
    msg_header:     .asciz "SIMULATION DIRECTIONAL FORECAST (%s)\n"
    fmt_stats:      .asciz "Historical Drift    : %.6f\nHistorical Vol      : %.6f\n"
    fmt_forecast:   .ascii "Forecast Horizon    : %ld Days\n"
                    .asciz "Simulated Paths     : %ld\n\n"
    fmt_prices:     .asciz "Current Price       : %.4f\nExpected Average    : %.4f\n\n"
    .align 8
    fmt_prob:       .ascii "DIRECTIONAL ANALYSIS:\n"
                    .ascii ">> Probability of Net RISE  (S_T > S_0): %.2f%%\n"
                    .asciz ">> Likelihood of Net DROP   (S_T < S_0): %.2f%%\n"
    err_args:       .asciz "Usage: ./ticker-gbm <data.ticker> 0 <iters> <horizon>\n"
    err_cuda:       .asciz "CUDA ERROR: %ld\n"

cuda_msg_init:          .asciz "cuda cuInit passed\n"
cuda_msg_devget:        .asciz "cuda cuDeviceGet passed\n"
cuda_msg_ctxcreate:     .asciz "cuda cuCtxCreate_v2 passed\n"
cuda_msg_modload:       .asciz "cuda cuModuleLoadData passed\n"
cuda_msg_getfunc:       .asciz "cuda cuModuleGetFunction passed\n"
cuda_msg_alloc_sums:    .asciz "cuda cuMemAlloc_v2 (sums) passed\n"
cuda_msg_alloc_hits:    .asciz "cuda cuMemAlloc_v2 (hits) passed\n"
cuda_msg_alloc_cfg:     .asciz "cuda cuMemAlloc_v2 (config) passed\n"
cuda_msg_htod:          .asciz "cuda cuMemcpyHtoD_v2 passed\n"
cuda_msg_launch:        .asciz "cuda cuLaunchKernel passed\n"
cuda_msg_sync:          .asciz "cuda cuCtxSynchronize passed\n"
cuda_msg_dtoh:          .asciz "cuda cuMemcpyDtoH_v2 passed\n"
cuda_msg_free_sums:     .asciz "cuda cuMemFree_v2 (sums) passed\n"
cuda_msg_free_hits:     .asciz "cuda cuMemFree_v2 (hits) passed\n"
cuda_msg_free_cfg:      .asciz "cuda cuMemFree_v2 (config) passed\n"
cuda_msg_ctxdestroy:    .asciz "cuda cuCtxDestroy_v2 passed\n"

    .align 8
    .L_hundred:     .double 100.0
    .L_one:         .double 1.0

.section .data
    # =========================================================================
    # CONFIG STRUCT (48 bytes) — MUST MATCH PTX OFFSETS EXACTLY
    # =========================================================================
    .align 8
    p_drift:        .double 0.000150   # +0
    p_vol:          .double 0.012500   # +8
    p_target:       .double 0.0        # +16
    p_start:        .double 0.0        # +24
    p_iters:        .quad   0          # +32
    p_horizon:      .quad   0          # +40

    # Runtime state
    filename_ptr:   .quad 0
    total_records:  .quad 0
    host_input_ptr: .quad 0
    requested_paths:.quad 0
    actual_paths:   .quad 0
    total_hits_acc: .quad 0

    # =========================================================================
    # KERNEL PARAMETER ARRAY (CRITICAL)
    # CUDA expects: void** kernelParams = { &d_sums_ptr, &d_hits_ptr, &d_config_ptr }
    # =========================================================================
    .align 16
    kernel_params:
        .quad 0     # d_sums_ptr (waarde van de pointer)
        .quad 0     # d_hits_ptr
        .quad 0     # d_config_ptr

    file_stat:      .skip 144

.section .bss
    .align 8
    cu_device:      .skip 4
    cu_context:     .skip 8
    cu_module:      .skip 8
    cu_function:    .skip 8

    d_sums_ptr:     .skip 8
    d_hits_ptr:     .skip 8
    d_config_ptr:   .skip 8

    h_hits_buf:     .skip 4096         # 1024 * 4 bytes

.section .text
.global _start

_start:
    # =========================================================================
    # 1. STACK + ARGUMENTS
    # =========================================================================
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp

    movq    8(%rbp), %rax
    cmpq    $5, %rax
    jl      .L_fail_args

    movq    24(%rbp), %rax
    movq    %rax, filename_ptr(%rip)

    movq    32(%rbp), %rdi
    xorl    %esi, %esi
    call    strtod@PLT
    movsd   %xmm0, p_target(%rip)

    movq    40(%rbp), %rdi
    call    atoll@PLT
    movq    %rax, requested_paths(%rip)

    shrq    $18, %rax
    cmpq    $1, %rax
    jge     1f
    movq    $1, %rax
1:
    movq    %rax, p_iters(%rip)
    shlq    $18, %rax
    movq    %rax, actual_paths(%rip)

    movq    48(%rbp), %rdi
    call    atoll@PLT
    movq    %rax, p_horizon(%rip)

    # =========================================================================
    # 2. MMAP INPUT FILE + LOAD LAST PRICE
    # =========================================================================

    movq    $2, %rax
    movq    filename_ptr(%rip), %rdi
    xorq    %rsi, %rsi
    syscall
    movq    %rax, %r12
     

    movq    $5, %rax
    movq    %r12, %rdi
    leaq    file_stat(%rip), %rsi
    syscall
    

    movq    48+file_stat(%rip), %r13
    movq    %r13, %rax
    shrq    $4, %rax
    movq    %rax, total_records(%rip)

    movq    $9, %rax
    xorq    %rdi, %rdi
    movq    %r13, %rsi
    movl    $1, %edx
    movl    $2, %r10d
    movq    %r12, %r8
    xorq    %r9, %r9
    syscall
    movq    %rax, host_input_ptr(%rip)
    # todo: check for ERROR 

    movq    total_records(%rip), %rcx
    decq    %rcx
    shlq    $4, %rcx
    addq    %rax, %rcx

    movsd   8(%rcx), %xmm0
    movsd   %xmm0, p_start(%rip)


    # =========================================================================
    # 3. CUDA INIT
    # =========================================================================
    xorl    %edi, %edi
    call    cuInit@PLT

    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_init(%rip), %rdi
    call    .L_cuda_ok

    leaq    cu_device(%rip), %rdi
    xorl    %esi, %esi
    call    cuDeviceGet@PLT

    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_devget(%rip), %rdi
    call    .L_cuda_ok
    
    leaq    cu_context(%rip), %rdi
    xorl    %esi, %esi
    movl    cu_device(%rip), %edx
    call    cuCtxCreate_v2@PLT

    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_ctxcreate(%rip), %rdi
    call    .L_cuda_ok

    # =========================================================================
    # 4. LOAD EMBEDDED CUBIN
    # =========================================================================
    leaq    cu_module(%rip), %rdi
    leaq    kernel_bin(%rip), %rsi
    call    cuModuleLoadData@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_modload(%rip), %rdi
    call    .L_cuda_ok

    leaq    cu_function(%rip), %rdi
    movq    cu_module(%rip), %rsi
    leaq    kernel_name(%rip), %rdx
    call    cuModuleGetFunction@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_getfunc(%rip), %rdi
    call    .L_cuda_ok

    # =========================================================================
    # 5. VRAM ALLOC
    # =========================================================================
    leaq    d_sums_ptr(%rip), %rdi
    movq    $8192, %rsi
    call    cuMemAlloc_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_alloc_sums(%rip), %rdi
    call    .L_cuda_ok

    leaq    d_hits_ptr(%rip), %rdi
    movq    $4096, %rsi
    call    cuMemAlloc_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_alloc_hits(%rip), %rdi
    call    .L_cuda_ok

    leaq    d_config_ptr(%rip), %rdi
    movq    $48, %rsi
    call    cuMemAlloc_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_alloc_cfg(%rip), %rdi
    call    .L_cuda_ok

    # =========================================================================
    # 6. COPY CONFIG STRUCT TO DEVICE
    # =========================================================================
    movq    d_config_ptr(%rip), %rdi
    leaq    p_drift(%rip), %rsi
    movq    $48, %rdx
    call    cuMemcpyHtoD_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_htod(%rip), %rdi
    call    .L_cuda_ok

    # =========================================================================
    # 7. BUILD CORRECT kernelParams ARRAY
    # =========================================================================

## Sectie 7: Vullen met de VRAM adressen direct
    leaq    kernel_params(%rip), %r10
    
    movq    d_sums_ptr(%rip), %rax
    movq    %rax, 0(%r10)   # Array[0] = VRAM adres van sums
    
    movq    d_hits_ptr(%rip), %rax
    movq    %rax, 8(%r10)   # Array[1] = VRAM adres van hits
    
    movq    d_config_ptr(%rip), %rax
    movq    %rax, 16(%r10)  # Array[2] = VRAM adres van config

    # =========================================================================
    # 8. KERNEL LAUNCH — CORRECT SysV ABI STACK LAYOUT
    # =========================================================================
 # 8. KERNEL LAUNCH
    subq    $48, %rsp
    movq    $1, 0(%rsp)        # 7: blockDimZ (Moet 8 bytes zijn, geen 4!)
    movq    $1, 8(%rsp)        # 8: sharedMemBytes (8 bytes)
    movq    $0, 16(%rsp)       # 9: hStream
    
    leaq    kernel_params(%rip), %rax
    movq    %rax, 24(%rsp)     # 10: kernelParams
    
    movq    $0, 32(%rsp)       # 11: extra
    # Let op: de 40(%rsp) hoeft hier niet te worden ingesteld als je subq $48 doet
    
    # Roep aan
    # Zorg dat RDI, RSI, RDX, RCX, R8, R9 correct zijn
    movq    cu_function(%rip), %rdi
    movl    $1024, %esi        # gridDimX
    movl    $1, %edx           # gridDimY
    movl    $1, %ecx           # gridDimZ
    movl    $256, %r8d         # blockDimX
    movl    $1, %r9d           # blockDimY
    
    call    cuLaunchKernel@PLT
    addq    $48, %rsp
    
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_launch(%rip), %rdi
    call    .L_cuda_ok

    addq    $40, %rsp
    call    cuCtxSynchronize@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_sync(%rip), %rdi
    call    .L_cuda_ok

    # =========================================================================
    # 9. COPY BACK RESULTS
    # =========================================================================
    leaq    h_hits_buf(%rip), %rdi
    movq    d_hits_ptr(%rip), %rsi
    movq    $4096, %rdx
    call    cuMemcpyDtoH_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_dtoh(%rip), %rdi
    call    .L_cuda_ok

    xorq    %rax, %rax
    xorq    %rcx, %rcx
    leaq    h_hits_buf(%rip), %rdx
1:
    cmpq    $1024, %rax
    jge     2f
    movl    (%rdx,%rax,4), %esi
    addq    %rsi, %rcx
    incq    %rax
    jmp     1b
2:
    movq    %rcx, total_hits_acc(%rip)

    # =========================================================================
    # 10. UI OUTPUT
    # =========================================================================
    leaq    msg_dash(%rip), %rdi
    xorl    %eax, %eax
    call    printf@PLT

    leaq    msg_header(%rip), %rdi
    movq    filename_ptr(%rip), %rsi
    xorl    %eax, %eax
    call    printf@PLT

    leaq    fmt_stats(%rip), %rdi
    movsd   p_drift(%rip), %xmm0
    movsd   p_vol(%rip), %xmm1
    movb    $2, %al
    call    printf@PLT
        xorl    %eax, %eax

    leaq    fmt_forecast(%rip), %rdi
    movq    p_horizon(%rip), %rsi
    movq    actual_paths(%rip), %rdx
    xorl    %eax, %eax
    call    printf@PLT
        xorl    %eax, %eax

    leaq    fmt_prices(%rip), %rdi
    movsd   p_start(%rip), %xmm0

    movsd   p_drift(%rip), %xmm1
    cvtsi2sd p_horizon(%rip), %xmm3
    mulsd   %xmm3, %xmm1
    mulsd   %xmm0, %xmm1
    addsd   %xmm0, %xmm1
    movb    $2, %al
    call    printf@PLT
        xorl    %eax, %eax

    cvtsi2sd total_hits_acc(%rip), %xmm0
    cvtsi2sd actual_paths(%rip), %xmm9
    divsd   %xmm9, %xmm0
    mulsd   .L_hundred(%rip), %xmm0

    movsd   .L_hundred(%rip), %xmm1
    minsd   %xmm1, %xmm0
    subsd   %xmm0, %xmm1

    leaq    fmt_prob(%rip), %rdi
    movb    $2, %al
    call    printf@PLT
        xorl    %eax, %eax
        
    # =========================================================================
    # 11. CLEANUP
    # =========================================================================
    movq    d_sums_ptr(%rip), %rdi
    call    cuMemFree_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_free_sums(%rip), %rdi
    call    .L_cuda_ok

    movq    d_hits_ptr(%rip), %rdi
    call    cuMemFree_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_free_hits(%rip), %rdi
    call    .L_cuda_ok

    movq    d_config_ptr(%rip), %rdi
    call    cuMemFree_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_free_cfg(%rip), %rdi
    call    .L_cuda_ok

    movq    cu_context(%rip), %rdi
    call    cuCtxDestroy_v2@PLT
    testq %rax, %rax
    jnz .L_cuda_error
    leaq     cuda_msg_ctxdestroy(%rip), %rdi
    call    .L_cuda_ok

    movq    $231, %rax
    xorq    %rdi, %rdi
    syscall

.L_fail_args:
    leaq    err_args(%rip), %rdi
    xorl    %eax, %eax
    call    printf@PLT
    movq    $231, %rax
    movq    $1, %rdi
    syscall

# --- CUDA error handler ---
# Input:  %rax = CUDA error code
# Clobbers: %rdi, %rsi, %rax
.L_cuda_error:
    # 1. Format string in RDI (1e argument)
    leaq    err_cuda(%rip), %rdi   

    # 2. Error code in RSI (2e argument voor %ld)
    # Let op: Omdat je in RDI de string had geladen, moet je 
    # de error code (die in RAX staat) nu in RSI verplaatsen.
    movq    %rax, %rsi             

    # 3. Printf aanroep
    xorl    %eax, %eax             # AL = 0, want er zijn geen XMM argumenten
    call    printf@PLT

    # 4. Exit
    movq    $231, %rax
    movq    $1, %rdi
    syscall

# --- General CUDA OK message printer ---
# Input: %rsi = pointer to message string
# Clobbers: %rdi, %rax
.L_cuda_ok:
    pushq   %rax
    pushq   %rdx
    pushq   %rsi
    pushq   %rdi
    
    # RDI bevat al het adres van de string (gezet voor de call)
    xorl    %eax, %eax
    call    printf@PLT
    
    popq    %rdi
    popq    %rsi
    popq    %rdx
    popq    %rax
    ret

.size _start, . - _start
.section .note.GNU-stack,"",@progbits

