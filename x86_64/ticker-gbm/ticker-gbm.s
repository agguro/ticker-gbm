/*
 * ============================================================================
 * TICKER GBM ENGINE: X86_64 HOST ORCHESTRATOR (DYNAMIC TAIL EXTRACTION)
 * ============================================================================
 */

.section .rodata
    msg_dash:       .asciz "------------------------------------------------------------\n"
    msg_header:     .asciz "SIMULATION DIRECTIONAL FORECAST (%s)\n"
    fmt_stats:      .asciz "Historical Drift    : %.6f\nHistorical Vol      : %.6f\n"
    fmt_forecast:   .ascii "Forecast Horizon    : %ld Days\n"
                    .asciz "Simulated Paths     : %ld\n\n"
    fmt_prices:     .asciz "Current Price       : %.4f\nExpected Average    : %.4f\n\n"
    fmt_prob:       .ascii "DIRECTIONAL ANALYSIS:\n"
                    .ascii ">> Probability of Net RISE  (S_T > S_0): %.2f%%\n"
                    .asciz ">> Likelihood of Net DROP   (S_T < S_0): %.2f%%\n"
    err_args:       .asciz "Usage: ./ticker-gbm <data.ticker> <target_price> <iters> <horizon>\n"
    
    # Resolved via the assembler include path (-I) matching the $(NAME) standard
    cubin_path:     .asciz "ticker_gbm.cubin"
    kernel_name:    .asciz "ticker_gbm"

    .align 8
    .L_hundred:     .double 100.0
    .L_one:         .double 1.0

.section .data
    # 48-Byte Contiguous Structural Parameter Matrix
    .align 8
    p_drift:        .double 0.000150   # Offset 0
    .align 8
    p_vol:          .double 0.012500   # Offset 8
    .align 8
    p_target:       .double 0.0        # Offset 16
    .align 8
    p_start:        .double 0.0        # Offset 24 (Populated dynamically from file tail)
    .align 8
    p_iters:        .quad 0            # Offset 32
    .align 8
    p_horizon:      .quad 0            # Offset 40
    
    # Internal variables
    .align 8
    filename_ptr:   .quad 0
    total_records:  .quad 0
    host_input_ptr: .quad 0
    target_val:     .double 0.0
    requested_paths:.quad 0            
    actual_paths:   .quad 0            
    total_sum_acc:  .double 0.0
    total_hits_acc: .quad 0
    
    .align 16
    gpu_launch_matrix:
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
    h_hits_buf:     .skip 32768        

.section .text
.global _start

_start:
    # --- 1. SETUP ---
    pushq   %rbp
    movq    %rsp, %rbp
    andq    $-16, %rsp              

    # --- 2. CLI ARGUMENT PARSING ---
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
    jge     .L_save_scaled_iters
    movq    $1, %rax                    
.L_save_scaled_iters:
    movq    %rax, p_iters(%rip)         
    
    shlq    $18, %rax
    movq    %rax, actual_paths(%rip)

    movq    48(%rbp), %rdi
    call    atoll@PLT
    movq    %rax, p_horizon(%rip)

    # --- 3. BINARY MMAP LOADING ---
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
    shrq    $4, %rax                    # Total rows = File size / 16
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

    # --- DYNAMIC TAIL CALCULATOR ---
    # Target Row Offset = (total_records - 1) * 16
    movq    total_records(%rip), %rcx
    decq    %rcx
    shlq    $4, %rcx                    # Multiply by 16 via quick left-shift
    addq    %rax, %rcx                  # Point directly to the final row index
    
    # Skip the 8-byte Unix timestamp chunk, load latest double float price!
    movsd   8(%rcx), %xmm0              
    movsd   %xmm0, p_start(%rip)        

    # --- 4. CUDA HARDWARE ORCHESTRATION ---
    xorl    %edi, %edi
    call    cuInit@PLT
    
    leaq    cu_device(%rip), %rdi
    xorl    %esi, %esi
    call    cuDeviceGet@PLT
    
    leaq    cu_context(%rip), %rdi
    xorl    %esi, %esi
    movl    cu_device(%rip), %edx
    call    cuCtxCreate_v2@PLT
    
    leaq    cu_module(%rip), %rdi
    leaq    cubin_path(%rip), %rsi
    call    cuModuleLoad@PLT
    
    leaq    cu_function(%rip), %rdi
    movq    cu_module(%rip), %rsi
    leaq    kernel_name(%rip), %rdx
    call    cuModuleGetFunction@PLT

    # --- 5. VRAM RESERVATION ---
    leaq    d_sums_ptr(%rip), %rdi              
    movq    $8192, %rsi                 
    call    cuMemAlloc_v2@PLT

    leaq    d_hits_ptr(%rip), %rdi              
    movq    $4096, %rsi                 
    call    cuMemAlloc_v2@PLT

    leaq    d_config_ptr(%rip), %rdi              
    movq    $48, %rsi                   
    call    cuMemAlloc_v2@PLT

    # --- 6. PCIe MEMCOPY ---
    movq    d_config_ptr(%rip), %rdi    
    leaq    p_drift(%rip), %rsi         
    movq    $48, %rdx                   
    call    cuMemcpyHtoD_v2@PLT

    # --- 7. BIND LAUNCH POINTERS ---
    leaq    d_sums_ptr(%rip), %rax
    movq    %rax, gpu_launch_matrix+0(%rip)
    leaq    d_hits_ptr(%rip), %rax
    movq    %rax, gpu_launch_matrix+8(%rip)
    leaq    d_config_ptr(%rip), %rax
    movq    %rax, gpu_launch_matrix+16(%rip)

    leaq    gpu_launch_matrix(%rip), %r11 

    # --- 8. KERNEL EXECUTION ---
    subq    $48, %rsp
    movq    $1, 0(%rsp)                 
    movq    $0, 8(%rsp)                 
    movq    $0, 16(%rsp)                
    movq    %r11, 24(%rsp)              
    movq    $0, 32(%rsp)                
    movq    $0, 40(%rsp)                

    movq    cu_function(%rip), %rdi     
    movl    $1024, %esi                 
    movl    $1, %edx                    
    movl    $1, %ecx                    
    movl    $256, %r8d                  
    movl    $1, %r9d                    
    call    cuLaunchKernel@PLT
    addq    $48, %rsp                   
    
    call    cuCtxSynchronize@PLT

# --- 9. FETCH RESULTS ---
    leaq    h_hits_buf(%rip), %rdi
    movq    d_hits_ptr(%rip), %rsi
    movq    $4096, %rdx
    call    cuMemcpyDtoH_v2@PLT

    # Host Loop Reduction Pass
    xorq    %rax, %rax
    xorq    %rcx, %rcx
    leaq    h_hits_buf(%rip), %rdx
.L_reduction:
    # Reduce only up to 256 blocks (or total blocks launched)
    cmpq    $256, %rax            
    jge     .L_finalize_hits
    movl    (%rdx,%rax,4), %esi   # Read 4-byte atomic results
    addq    %rsi, %rcx            # Accumulate into 64-bit reg
    incq    %rax
    jmp     .L_reduction

.L_finalize_hits:
    movq    %rcx, total_hits_acc(%rip)

    # --- 10. PRESENTATION LAYER (UI FRAME) ---
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
    movsd   p_start(%rip), %xmm0        # Explicitly reload double float price
    
    # Calculate expected price curve path
    movsd   p_drift(%rip), %xmm1        # Temporarily use %xmm1 to store drift
# --- PROBABILITY CALCULATION ---
    # 1. Calculate Rise Percentage in xmm0
    cvtsi2sd total_hits_acc(%rip), %xmm0
    cvtsi2sd actual_paths(%rip), %xmm1
    divsd    %xmm1, %xmm0              # xmm0 = (hits / paths)
    mulsd    .L_hundred(%rip), %xmm0    # xmm0 = Rise %

    # 2. Calculate Drop Percentage in xmm1
    # We need to compute (100.0 - xmm0) and store in xmm1
    movsd    .L_hundred(%rip), %xmm1    # Load 100.0
    subsd    %xmm0, %xmm1               # xmm1 = 100.0 - Rise % = Drop %

    # 3. Print
    leaq     fmt_prob(%rip), %rdi
    movb     $2, %al                    # Tell printf to use xmm0 and xmm1
    call     printf@PLT

    # Destroy hardware allocations
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
    xorl    %eax, %eax
    call    printf@PLT
    movq    $231, %rax
    movq    $1, %rdi
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
