# ==============================================================================
# Project:     Bare-metal GBM Monte Carlo Engine
# File:        ticker-gbm.s
# Author:      agguro
# Date:        August 19, 2026 
# Description: x86_64 host orchestrator for GBM directional price forecasting.
#              Safe RBP-based Argument Parsing & Full CUDA Device Initialization.
# Architecture: x86_64 | Linux SysV ABI | AT&T Syntax
#
# Copyright 2026 agguro
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================

.section .rodata
    .align 16
    kernel_bin:     .incbin "gbm_monte_carlo.cubin"
    kernel_name:    .asciz  "gbm_monte_carlo"

    msg_dash:       .asciz "------------------------------------------------------------\n"
    msg_header:     .asciz "SIMULATION DIRECTIONAL FORECAST (%s)\n"
    fmt_stats:      .asciz "Historical Drift    : %.6f\nHistorical Vol      : %.6f\n"
    fmt_forecast:   .ascii "Forecast Horizon    : %ld Days\n"
                    .asciz "Simulated Paths     : %ld\n\n"
    
    fmt_prices:     .asciz "Current Price       : %.4f\nTarget Price        : %.4f\nExpected Average    : %.4f\n\n"
    
    .align 8
    fmt_prob:       .ascii "DIRECTIONAL ANALYSIS:\n"
                    .ascii ">> Probability (Terminal Price > Target): %.2f%%\n"
                    .asciz ">> Likelihood  (Terminal Price < Target): %.2f%%\n"

    msg_warning:    .ascii "\n[!] WARNING: GBM forecasts are highly sensitive to historical volatility.\n"
                    .asciz "    Interpret these directional probabilities with caution.\n\n"

    err_args:       .asciz "Usage: ./ticker-gbm <data.ticker> <target_price> <iters> <horizon>\n"
    err_file:       .asciz "\n[ERROR] Ticker data file not found or empty.\n"
    err_cuda:       .asciz "CUDA ERROR: %ld\n"

    .align 8
    .L_hundred:     .double 100.0
    .L_zero:        .double 0.0

.section .data
    .align 8
    p_drift:        .double 0.0
    p_vol:          .double 0.0
    p_target:       .double 0.0
    p_start:        .double 0.0
    p_iters:        .quad   0
    p_horizon:      .quad   0

    filename_ptr:   .quad 0
    total_records:  .quad 0
    host_input_ptr: .quad 0
    actual_paths:   .quad 0
    total_hits_acc: .quad 0

    .align 16
    kernel_params:
        .quad 0
        .quad 0
        .quad 0

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
    h_hits_buf:     .skip 4096

.section .text
.global _start

_start:
    # =========================================================================
    # 1. ARGUMENT PARSING (Safe RBP-based offsets, preserving stack integrity)
    # =========================================================================
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp

    # Check argc (located at 8(%rbp) in standard SysV ABI entry)
    movq    8(%rbp), %rax
    cmpq    $5, %rax
    jl      .L_fail_args
    
    # argv[1] -> Ticker filename pointer
    movq    24(%rbp), %rax
    movq    %rax, filename_ptr(%rip)

    # argv[2] -> Target Price (parsed via strtod)
    movq    32(%rbp), %rdi
    xorl    %esi, %esi
    call    strtod@PLT
    movsd   %xmm0, p_target(%rip)

    # argv[3] -> Simulation iterations (parsed via atoll)
    movq    40(%rbp), %rdi
    call    atoll@PLT
    shrq    $18, %rax
    cmpq    $1, %rax
    jge     .L_iters_ok
    movq    $1, %rax
.L_iters_ok:
    movq    %rax, p_iters(%rip)
    shlq    $18, %rax
    movq    %rax, actual_paths(%rip)

    # argv[4] -> Forecast horizon in days
    movq    48(%rbp), %rdi
    call    atoll@PLT
    movq    %rax, p_horizon(%rip)

    # =========================================================================
    # 2. FILE IO & MMAP
    # =========================================================================
    movq    $2, %rax                      # sys_open
    movq    filename_ptr(%rip), %rdi
    xorq    %rsi, %rsi
    syscall
    testq   %rax, %rax
    js      .L_fail_file
    movq    %rax, %r12

    movq    $5, %rax                      # sys_fstat
    movq    %r12, %rdi
    leaq    file_stat(%rip), %rsi
    syscall
    
    movq    48+file_stat(%rip), %r13
    testq   %r13, %r13
    jz      .L_fail_file

    movq    %r13, %rax
    shrq    $4, %rax
    movq    %rax, total_records(%rip)

    movq    $9, %rax                      # sys_mmap
    xorq    %rdi, %rdi
    movq    %r13, %rsi
    movl    $1, %edx
    movl    $2, %r10d
    movq    %r12, %r8
    xorq    %r9, %r9
    syscall
    cmpq    $-1, %rax
    je      .L_fail_file
    movq    %rax, host_input_ptr(%rip)

    # Fetch Start Price (Last record in 16-byte struct array)
    movq    total_records(%rip), %rcx
    decq    %rcx
    shlq    $4, %rcx
    addq    %rax, %rcx
    movsd   8(%rcx), %xmm0
    movsd   %xmm0, p_start(%rip)

    # =========================================================================
    # 3. STATISTICAL ENGINE (DRIFT & VOLATILITY WITH SANITY CHECKS)
    # =========================================================================
    movq    host_input_ptr(%rip), %rbx
    movq    total_records(%rip), %r13
    decq    %r13
    cmpq    $1, %r13
    jle     .L_skip_stats

    pxor    %xmm14, %xmm14
    pxor    %xmm15, %xmm15
    xorq    %r8, %r8
    movq    %r13, %r14

.L_stats_loop:
    movsd   8(%rbx), %xmm0
    movsd   24(%rbx), %xmm1
    
    pxor    %xmm2, %xmm2
    ucomisd %xmm2, %xmm0
    jbe     .L_stats_skip_item
    ucomisd %xmm2, %xmm1
    jbe     .L_stats_skip_item

    divsd   %xmm0, %xmm1
    
    subq    $8, %rsp
    movsd   %xmm1, (%rsp)
    fldln2
    fldl    (%rsp)
    fyl2x
    fstpl   (%rsp)
    movsd   (%rsp), %xmm1
    addq    $8, %rsp
    
    addsd   %xmm1, %xmm14
    movsd   %xmm1, %xmm2
    mulsd   %xmm1, %xmm2
    addsd   %xmm2, %xmm15
    incq    %r8

.L_stats_skip_item:
    addq    $16, %rbx
    decq    %r14
    jnz     .L_stats_loop

    cmpq    $2, %r8
    jl      .L_skip_stats

    cvtsi2sd %r8, %xmm13
    movsd   %xmm14, %xmm0
    divsd   %xmm13, %xmm0
    movsd   %xmm0, p_drift(%rip)
    
    movsd   %xmm14, %xmm1
    mulsd   %xmm14, %xmm1
    divsd   %xmm13, %xmm1
    movsd   %xmm15, %xmm2
    subsd   %xmm1, %xmm2
    
    movq    %r8, %rax
    decq    %rax
    cvtsi2sd %rax, %xmm12
    divsd   %xmm12, %xmm2
    sqrtsd  %xmm2, %xmm2
    movsd   %xmm2, p_vol(%rip)

.L_skip_stats:

    # Ensure Target is not 0.0 (Fallback to start price if user passed 0)
    movsd   p_target(%rip), %xmm0
    movsd   .L_zero(%rip), %xmm1
    comisd  %xmm1, %xmm0
    jne     .L_skip_target_fix
    movsd   p_start(%rip), %xmm0
    movsd   %xmm0, p_target(%rip)
.L_skip_target_fix:

    # =========================================================================
    # 4. CUDA ORCHESTRATION (Full device initialization sequence)
    # =========================================================================
    xorl    %edi, %edi
    call    cuInit@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    cu_device(%rip), %rdi
    xorl    %esi, %esi
    call    cuDeviceGet@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    cu_context(%rip), %rdi
    xorl    %esi, %esi
    movl    cu_device(%rip), %edx
    call    cuCtxCreate_v2@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    cu_module(%rip), %rdi
    leaq    kernel_bin(%rip), %rsi
    call    cuModuleLoadData@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    cu_function(%rip), %rdi
    movq    cu_module(%rip), %rsi
    leaq    kernel_name(%rip), %rdx
    call    cuModuleGetFunction@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    d_sums_ptr(%rip), %rdi
    movq    $8192, %rsi
    call    cuMemAlloc_v2@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    d_hits_ptr(%rip), %rdi
    movq    $4096, %rsi
    call    cuMemAlloc_v2@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    d_config_ptr(%rip), %rdi
    movq    $48, %rsi
    call    cuMemAlloc_v2@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    movq    d_config_ptr(%rip), %rdi
    leaq    p_drift(%rip), %rsi
    movq    $48, %rdx
    call    cuMemcpyHtoD_v2@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    kernel_params(%rip), %r10
    leaq    d_sums_ptr(%rip), %rax
    movq    %rax, 0(%r10)
    leaq    d_hits_ptr(%rip), %rax
    movq    %rax, 8(%r10)
    leaq    d_config_ptr(%rip), %rax
    movq    %rax, 16(%r10)

    subq    $48, %rsp
    movq    $1, 0(%rsp)
    movq    $1, 8(%rsp)
    movq    $0, 16(%rsp)
    leaq    kernel_params(%rip), %rax
    movq    %rax, 24(%rsp)
    movq    $0, 32(%rsp)
    
    movq    cu_function(%rip), %rdi
    movl    $1024, %esi
    movl    $1, %edx
    movl    $1, %ecx
    movl    $256, %r8d
    movl    $1, %r9d
    call    cuLaunchKernel@PLT
    addq    $48, %rsp
    testq   %rax, %rax
    jnz     .L_cuda_error

    call    cuCtxSynchronize@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    leaq    h_hits_buf(%rip), %rdi
    movq    d_hits_ptr(%rip), %rsi
    movq    $4096, %rdx
    call    cuMemcpyDtoH_v2@PLT
    testq   %rax, %rax
    jnz     .L_cuda_error

    xorq    %rax, %rax
    xorq    %rcx, %rcx
    leaq    h_hits_buf(%rip), %rdx
.L_hits_reduction_loop:
    cmpq    $1024, %rax
    jge     .L_hits_reduction_done
    movl    (%rdx,%rax,4), %esi
    addq    %rsi, %rcx
    incq    %rax
    jmp     .L_hits_reduction_loop
.L_hits_reduction_done:
    movq    %rcx, total_hits_acc(%rip)

    # =========================================================================
    # 5. FINAL REPORTING
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

    leaq    fmt_forecast(%rip), %rdi
    movq    p_horizon(%rip), %rsi
    movq    actual_paths(%rip), %rdx
    xorl    %eax, %eax
    call    printf@PLT

    leaq    fmt_prices(%rip), %rdi
    movsd   p_start(%rip), %xmm0
    movsd   p_target(%rip), %xmm1
    movsd   p_drift(%rip), %xmm2
    cvtsi2sd p_horizon(%rip), %xmm3
    mulsd   %xmm3, %xmm2
    mulsd   %xmm0, %xmm2
    addsd   %xmm0, %xmm2
    movb    $3, %al
    call    printf@PLT

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

    leaq    msg_warning(%rip), %rdi
    xorl    %eax, %eax
    call    printf@PLT

    # =========================================================================
    # 6. CLEANUP & EXIT
    # =========================================================================
    movq    d_sums_ptr(%rip), %rdi
    call    cuMemFree_v2@PLT
    movq    d_hits_ptr(%rip), %rdi
    call    cuMemFree_v2@PLT
    movq    d_config_ptr(%rip), %rdi
    call    cuMemFree_v2@PLT
    movq    cu_context(%rip), %rdi
    call    cuCtxDestroy_v2@PLT
    
    movq    $231, %rax
    xorq    %rdi, %rdi
    syscall

.L_fail_args:
    leaq    err_args(%rip), %rdi
    call    printf@PLT
    movq    $231, %rax
    movq    $1, %rdi
    syscall

.L_fail_file:
    leaq    err_file(%rip), %rdi
    call    printf@PLT
    movq    $231, %rax
    movq    $1, %rdi
    syscall

.L_cuda_error:
    leaq    err_cuda(%rip), %rdi
    movq    %rax, %rsi
    call    printf@PLT
    movq    $231, %rax
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
