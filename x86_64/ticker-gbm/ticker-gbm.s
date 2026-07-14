/*
 * ============================================================================
 * TICKER-GBM ENGINE: FINAL ABI-COMPLIANT X86_64 HOST ORCHESTRATOR
 * ============================================================================
 */

.section .rodata
    .align 16
    kernel_bin:     .incbin "ticker-gbm.cubin"
    kernel_name:    .asciz  "ticker_gbm"
    msg_dash:       .asciz  "------------------------------------------------------------\n"
    msg_header:     .asciz  "SIMULATION DIRECTIONAL FORECAST (%s)\n"
    fmt_stats:      .asciz  "Historical Drift    : %.6f\nHistorical Vol      : %.6f\n"
    fmt_forecast:   .ascii  "Forecast Horizon    : %ld Days\n"
                    .asciz  "Simulated Paths     : %ld\n\n"
    fmt_prices:     .asciz  "Current Price       : %.4f\nExpected Average    : %.4f\n\n"
    err_args:       .asciz  "Usage: ./ticker_gbm <data.ticker> 0 <iters> <horizon>\n"
    .align 8
    .L_hundred:     .double 100.0

.section .data
    .align 8
    h_module:       .quad 0
    h_func:         .quad 0
    p_drift:        .double 0.000150
    p_vol:          .double 0.012500
    p_config:       .quad p_drift, p_vol, 0, 0, 0, 0  # Packed config for kernel
    d_sums_ptr:     .quad 0
    d_hits_ptr:     .quad 0
    d_config_ptr:   .quad 0
    gpu_launch_matrix: .quad 0, 0, 0                  # d_sums, d_hits, d_config

.section .bss
    .align 8
    h_hits_buf:     .skip 32768

.section .text
.global _start

_start:
    # 1. ABI Stack Alignment
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp
    
    # 2. CUDA Initialization
    xorl    %edi, %edi
    call    cuInit@PLT
    
    subq    $128, %rsp
    leaq    64(%rsp), %rdi
    xorl    %esi, %esi
    call    cuDeviceGet@PLT
    
    leaq    64(%rsp), %rdi
    xorl    %esi, %esi
    movl    64(%rsp), %edx
    call    cuCtxCreate_v2@PLT
    
    # 3. Module Load
    leaq    h_module(%rip), %rdi
    leaq    kernel_bin(%rip), %rsi
    call    cuModuleLoadData@PLT
    
    leaq    h_func(%rip), %rdi
    movq    h_module(%rip), %rsi
    leaq    kernel_name(%rip), %rdx
    call    cuModuleGetFunction@PLT

    # 4. Memory Allocations
    # d_sums (8192 bytes)
    leaq    d_sums_ptr(%rip), %rdi
    movq    $8192, %rsi
    call    cuMemAlloc_v2@PLT

    # d_hits (4096 bytes)
    leaq    d_hits_ptr(%rip), %rdi
    movq    $4096, %rsi
    call    cuMemAlloc_v2@PLT

    # d_config (48 bytes)
    leaq    d_config_ptr(%rip), %rdi
    movq    $48, %rsi
    call    cuMemAlloc_v2@PLT

    # 5. PCIe Copy (HtoD)
    movq    d_config_ptr(%rip), %rdi
    leaq    p_config(%rip), %rsi
    movq    $48, %rdx
    call    cuMemcpyHtoD_v2@PLT

    # 6. Bind Launch Matrix
    movq    d_sums_ptr(%rip), %rax
    movq    %rax, gpu_launch_matrix+0(%rip)
    movq    d_hits_ptr(%rip), %rax
    movq    %rax, gpu_launch_matrix+8(%rip)
    movq    d_config_ptr(%rip), %rax
    movq    %rax, gpu_launch_matrix+16(%rip)

    # 7. Kernel Execution
    leaq    gpu_launch_matrix(%rip), %r11
    subq    $48, %rsp
    movq    $1, 0(%rsp)
    movq    $0, 8(%rsp)
    movq    $0, 16(%rsp)
    movq    %r11, 24(%rsp)
    movq    $0, 32(%rsp)
    movq    $0, 40(%rsp)

    movq    h_func(%rip), %rdi
    movl    $1024, %esi
    movl    $1, %edx
    movl    $1, %ecx
    movl    $256, %r8d
    movl    $1, %r9d
    call    cuLaunchKernel@PLT
    addq    $48, %rsp
    
    call    cuCtxSynchronize@PLT

    # 8. Cleanup & Exit (Standard ABI)
    addq    $128, %rsp
    movq    %rbp, %rsp
    popq    %rbp
    movq    $60, %rax
    xorl    %edi, %edi
    syscall