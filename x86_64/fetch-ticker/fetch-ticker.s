/*
 * ============================================================================
 * Architecture : x86_64 | Linux SysV ABI | AT&T Syntax
 * Description  : Self-Contained SSL Yahoo JSON Extractor & Packed Binary Writer
 * Struct Layout: [8-byte uint64_t epoch timestamp] [8-byte double price]
 * ============================================================================
 */

.section .rodata
    host:       .asciz "query2.finance.yahoo.com:443"
    req_fmt:    .asciz "GET /v8/finance/chart/%s?range=%s&interval=%s HTTP/1.1\r\nHost: query2.finance.yahoo.com\r\nUser-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
    ext_bin:    .asciz ".ticker"
    
    # Output Strings & Dynamic Lengths
    err_args:   .asciz "Usage: ./fetch_ticker <TICKER> <RANGE> <INTERVAL>\n"
    .set ERR_ARGS_LEN, . - err_args

    msg_conn:   .asciz "Connecting to Yahoo Finance Secure API...\n"
    msg_done:   .asciz "Binary stream safely structured and dumped to: %s (%lu records)\n"
    
    err_prefix: .asciz "\n[YAHOO API ERROR] Response Failed: "
    .set ERR_PREFIX_LEN, . - err_prefix

    err_http:   .asciz "\n[NETWORK ERROR] HTTP Layer Rejected. Remote Status: "
    .set ERR_HTTP_LEN, . - err_http

    err_empty:  .asciz "\n[ERROR] Yahoo API returned no data records. Check parameters.\n"
    .set ERR_EMPTY_LEN, . - err_empty

    err_newline:.asciz "\n"

    # Extraction Needle Signatures
    sig_http_ok:   .asciz "HTTP/1.1 200"
    sig_error:     .asciz "\"result\":null"
    sig_desc:      .asciz "\"description\":\""
    sig_timestamp: .asciz "\"timestamp\":["
    sig_close:     .asciz "\"close\":["
    str_null:      .asciz "null"

    BIO_C_SET_CONNECT = 100
    BIO_C_DO_STATE_MACHINE = 101

.section .data
    .align 8
    ctx:        .quad 0
    bio:        .quad 0
    file_fd:    .quad 0
    total_read: .quad 0

.section .bss
    .align 16
    filename:   .skip 64
    request:    .skip 2048
    
    # Accumulation Frame - 512KB stable data heap buffer
    .align 4096
    big_stream_buf: .skip 524288  

    # Internal parallel record structures
    .align 16
    ts_pool:    .skip 65536     # Up to 8192 records (8-bytes each)
    price_pool: .skip 65536     # Up to 8192 records (8-bytes double each)

.section .text
.globl _start

_start:
    movq    %rsp, %rbp
    andq    $-16, %rsp         # Tight 16-byte stack boundary rule
    
    # Reserve 16 bytes of local frame space to pass address pointers safely to libc
    subq    $16, %rsp          
    
    movq    (%rbp), %rdi       # argc
    cmpq    $4, %rdi
    jne     .L_arg_error
    
    movq    16(%rbp), %r12     # argv[1] (Ticker)
    movq    24(%rbp), %r13     # argv[2] (Range)
    movq    32(%rbp), %r14     # argv[3] (Interval)

    # --- Build Target Output Filename ---
    leaq    filename(%rip), %rdi
    movq    %r12, %rsi
    call    strcpy@PLT
    leaq    filename(%rip), %rdi
    leaq    ext_bin(%rip), %rsi
    call    strcat@PLT

    # --- Format HTTP Request ---
    leaq    request(%rip), %rdi
    leaq    req_fmt(%rip), %rsi
    movq    %r12, %rdx
    movq    %r13, %rcx
    movq    %r14, %r8
    xorq    %rax, %rax         
    call    sprintf@PLT

    leaq    msg_conn(%rip), %rdi
    xorq    %rax, %rax
    call    printf@PLT

    # --- Initialize OpenSSL Subsystem ---
    xorq    %rdi, %rdi
    xorq    %rsi, %rsi
    call    OPENSSL_init_ssl@PLT
    call    TLS_client_method@PLT
    movq    %rax, %rdi
    call    SSL_CTX_new@PLT
    movq    %rax, ctx(%rip)

    movq    ctx(%rip), %rdi
    call    BIO_new_ssl_connect@PLT
    movq    %rax, bio(%rip)

    movq    bio(%rip), %rdi
    movq    $BIO_C_SET_CONNECT, %rsi
    xorq    %rdx, %rdx
    leaq    host(%rip), %rcx
    call    BIO_ctrl@PLT

    movq    bio(%rip), %rdi
    movq    $BIO_C_DO_STATE_MACHINE, %rsi
    xorq    %rdx, %rdx
    xorq    %rcx, %rcx
    call    BIO_ctrl@PLT
    testq   %rax, %rax
    jle     .L_exit_err

    # --- Send Encrypted Headers ---
    leaq    request(%rip), %rdi
    call    strlen@PLT
    movq    %rax, %rdx
    movq    bio(%rip), %rdi
    leaq    request(%rip), %rsi
    call    BIO_write@PLT

    # --- Read/Accumulate Stream Subsystem Loop ---
    movq    $0, total_read(%rip)

.L_accumulation_loop:
    leaq    big_stream_buf(%rip), %rsi
    addq    total_read(%rip), %rsi      
    
    movq    bio(%rip), %rdi
    movq    $4096, %rdx                 
    call    BIO_read@PLT
    testq   %rax, %rax
    jle     .L_extraction_parsing_gate   

    addq    %rax, total_read(%rip)
    jmp     .L_accumulation_loop

.L_extraction_parsing_gate:
    leaq    big_stream_buf(%rip), %rax
    addq    total_read(%rip), %rax
    movb    $0, (%rax)

    # 1. Inspect HTTP response code
    leaq    big_stream_buf(%rip), %rdi
    leaq    sig_http_ok(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax
    jz      .L_handle_http_gate_error   

    # 2. Check for application level JSON errors
    leaq    big_stream_buf(%rip), %rdi
    leaq    sig_error(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax
    jnz     .L_handle_yahoo_error 

    # === CORE TEXT PARSING ENGINE ===
    leaq    big_stream_buf(%rip), %rdi
    leaq    sig_timestamp(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax
    jz      .L_handle_empty_payload
    addq    $13, %rax                   
    movq    %rax, %r12                  # %r12 = Timestamp text cursor

    xorq    %r14, %r14                  # %r14 = records counter
.L_parse_ts_loop:
    cmpb    $93, (%r12)                 # ']' End of Array
    je      .L_locate_prices
    cmpb    $0, (%r12)
    je      .L_locate_prices

    # FIX: Store pointer on stack to safely pass a valid pointer address to strtoull
    movq    %r12, (%rsp)
    movq    %rsp, %rsi                  # Pass address of stack storage to %rsi
    movq    (%rsp), %rdi                # Pass data pointer value to %rdi
    movq    $10, %rdx
    call    strtoull@PLT                
    movq    (%rsp), %r12                # Retrieve updated updated cursor position from stack
    
    leaq    ts_pool(%rip), %rcx
    movq    %rax, (%rcx,%r14,8)         
    incq    %r14

    cmpb    $44, (%r12)                 # ',' Delimiter check
    jne     .L_parse_ts_loop
    incq    %r12                        
    jmp     .L_parse_ts_loop

.L_locate_prices:
    leaq    big_stream_buf(%rip), %rdi
    leaq    sig_close(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax
    jz      .L_handle_empty_payload
    addq    $9, %rax                    
    movq    %rax, %r12                  # %r12 = Prices text cursor

    xorq    %r15, %r15                  
.L_parse_prices_loop:
    cmpq    %r14, %r15                  
    jge     .L_serialize_output
    cmpb    $0, (%r12)
    je      .L_serialize_output

    movq    %r12, %rdi
    leaq    str_null(%rip), %rsi
    movq    $4, %rdx
    call    strncmp@PLT
    testq   %rax, %rax
    jnz     .L_extract_valid_double

    pxor    %xmm0, %xmm0
    addq    $4, %r12                    
    jmp     .L_store_double

.L_extract_valid_double:
    # FIX: Use explicit stack frame pointer address configuration to invoke strtod safely
    movq    %r12, (%rsp)
    movq    %rsp, %rsi                  
    movq    (%rsp), %rdi                
    call    strtod@PLT                  
    movq    (%rsp), %r12                # Recover updated text scanner bounds pointer

.L_store_double:
    leaq    price_pool(%rip), %rcx
    movq    %xmm0, (%rcx,%r15,8)        
    incq    %r15

    cmpb    $44, (%r12)                 
    jne     .L_parse_prices_loop
    incq    %r12
    jmp     .L_parse_prices_loop

# === SERIALIZATION & STORAGE WRITEBACK ===
.L_serialize_output:
    testq   %r14, %r14
    jz      .L_handle_empty_payload

    movq    $2, %rax                    
    leaq    filename(%rip), %rdi
    movq    $0x241, %rsi                
    movq    $0644, %rdx
    syscall
    movq    %rax, file_fd(%rip)

    xorq    %r15, %r15
.L_write_records:
    cmpq    %r14, %r15
    jge     .L_finish_binary

    leaq    ts_pool(%rip), %rax
    movq    (%rax,%r15,8), %r12      

    leaq    price_pool(%rip), %rax
    movq    (%rax,%r15,8), %r13      

    subq    $16, %rsp
    movq    %r12, (%rsp)
    movq    %r13, 8(%rsp)

    movq    $1, %rax                    
    movq    file_fd(%rip), %rdi
    movq    %rsp, %rsi               
    movq    $16, %rdx                
    syscall
    
    addq    $16, %rsp                
    incq    %r15
    jmp     .L_write_records

.L_finish_binary:
    movq    file_fd(%rip), %rdi
    movq    $3, %rax                    
    syscall

    leaq    msg_done(%rip), %rdi
    leaq    filename(%rip), %rsi
    movq    %r14, %rdx
    xorq    %rax, %rax
    call    printf@PLT
    jmp     .L_shutdown_crypto_success

# === DIAGNOSTIC EXITS & RUNTIME ERROR TRAWLS ===
.L_handle_http_gate_error:
    movq    $1, %rax            
    movq    $2, %rdi            
    leaq    err_http(%rip), %rsi
    movq    $ERR_HTTP_LEN, %rdx           
    syscall

    movq    $1, %rax
    movq    $2, %rdi
    leaq    big_stream_buf(%rip), %rsi
    movq    $32, %rdx
    syscall
    
    leaq    err_newline(%rip), %rsi
    movq    $1, %rdx
    movq    $1, %rax
    syscall
    jmp     .L_shutdown_crypto_err

.L_handle_yahoo_error:
    leaq    big_stream_buf(%rip), %rdi
    leaq    sig_desc(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax
    jz      .L_shutdown_crypto_err
    addq    $15, %rax
    movq    %rax, %r12          

    movq    $1, %rax            
    movq    $2, %rdi            
    leaq    err_prefix(%rip), %rsi
    movq    $ERR_PREFIX_LEN, %rdx           
    syscall

    movq    %r12, %r13          
.L_print_err_char:
    cmpb    $0, (%r13)
    je      .L_error_done
    cmpb    $34, (%r13)         
    je      .L_error_done
    movq    $1, %rax            
    movq    $2, %rdi            
    movq    %r13, %rsi          
    movq    $1, %rdx            
    syscall
    incq    %r13
    jmp     .L_print_err_char

.L_error_done:
    leaq    err_newline(%rip), %rsi
    movq    $1, %rdx
    movq    $1, %rax
    syscall
    jmp     .L_shutdown_crypto_err

.L_handle_empty_payload:
    movq    $1, %rax                 
    movq    $2, %rdi                 
    leaq    err_empty(%rip), %rsi
    movq    $ERR_EMPTY_LEN, %rdx                
    syscall
    jmp     .L_shutdown_crypto_err

.L_shutdown_crypto_success:
    movq    bio(%rip), %rdi
    call    BIO_free_all@PLT
    movq    ctx(%rip), %rdi
    call    SSL_CTX_free@PLT
    addq    $16, %rsp                  # Re-align original stack allocation parameters
    movq    $60, %rax            
    xorq    %rdi, %rdi               
    syscall

.L_shutdown_crypto_err:
    movq    bio(%rip), %rdi
    call    BIO_free_all@PLT
    movq    ctx(%rip), %rdi
    call    SSL_CTX_free@PLT
    addq    $16, %rsp                  
    movq    $60, %rax            
    movq    $1, %rdi                 
    syscall

.L_arg_error:
    movq    $1, %rax                 
    movq    $2, %rdi                 
    leaq    err_args(%rip), %rsi
    movq    $ERR_ARGS_LEN, %rdx
    syscall
    addq    $16, %rsp                  
    movq    $60, %rax            
    movq    $1, %rdi                 
    syscall

.L_exit_err:
    addq    $16, %rsp                  
    movq    $60, %rax            
    movq    $1, %rdi                 
    syscall

.size _start, . - _start
.section .note.GNU-stack,"",@progbits
