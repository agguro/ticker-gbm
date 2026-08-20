# ==============================================================================
# Project:     Bare-metal GBM Monte Carlo Engine
# File:        fetch-ticker.s
# Author:      agguro
# Date:        August 19, 2026 
# Description: Self-Contained SSL Yahoo JSON Extractor & Packed Binary Writer.
#              Downloads market data over HTTPS using OpenSSL BIO layers, 
#              allocates dynamic memory via mmap for massive JSON payloads (100y+),
#              smart-routes 'max' requests to period1=0 for absolute IPO history,
#              parses arrays synchronously with forward-fill safety, and dumps binary structs.
#              Struct Layout: [8-byte uint64_t epoch timestamp] [8-byte double]
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
    # --------------------------------------------------------------------------
    # NETWORK CONSTANTS & HTTP TEMPLATES
    # --------------------------------------------------------------------------
    host:        .asciz "query2.finance.yahoo.com:443"
    
    # Standard range-based request template (e.g. 10y, 1d)
    req_fmt_range: .asciz "GET /v8/finance/chart/%s?range=%s&interval=%s HTTP/1.1\r\nHost: query2.finance.yahoo.com\r\nUser-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
    
    # Absolute epoch-based request template for 'max' (period1=0 forces absolute IPO history)
    req_fmt_epoch: .asciz "GET /v8/finance/chart/%s?period1=0&period2=9999999999&interval=%s HTTP/1.1\r\nHost: query2.finance.yahoo.com\r\nUser-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36\r\nAccept: application/json\r\nConnection: close\r\n\r\n"
    
    # Magic comparison string to detect 'max' argument
    str_max_arg:    .asciz "max"
    
    ext_bin:        .asciz ".ticker"
    
    # --------------------------------------------------------------------------
    # OUTPUT MESSAGES
    # --------------------------------------------------------------------------
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

    # --------------------------------------------------------------------------
    # PARSING NEEDLES (Substrings to search for in the JSON payload)
    # --------------------------------------------------------------------------
    sig_http_ok:   .asciz "HTTP/1.1 200"
    sig_error:     .asciz "\"result\":null"
    sig_desc:      .asciz "\"description\":\""
    sig_timestamp: .asciz "\"timestamp\":["
    sig_close:     .asciz "\"close\":["
    str_null:      .asciz "null"

    # OpenSSL BIO Control Macros
    BIO_C_SET_CONNECT = 100
    BIO_C_DO_STATE_MACHINE = 101

.section .data
    # --------------------------------------------------------------------------
    # GLOBAL POINTERS & STATE VARIABLES
    # --------------------------------------------------------------------------
    .align 8
    ctx:                  .quad 0     # OpenSSL context pointer
    bio:                  .quad 0     # OpenSSL BIO pointer
    file_fd:              .quad 0     # File descriptor for binary output
    total_read:           .quad 0     # Counter for bytes read from network
    
    # Dynamic mmap allocation pointers and sizes
    stream_buf_ptr:       .quad 0     # Pointer to mmap'd JSON stream buffer (64 MB)
    ts_pool_ptr:          .quad 0     # Pointer to mmap'd timestamp pool (4 MB)
    price_pool_ptr:       .quad 0     # Pointer to mmap'd price pool (4 MB)

.section .bss
    # --------------------------------------------------------------------------
    # SMALL UNINITIALIZED BUFFERS
    # --------------------------------------------------------------------------
    .align 16
    filename:   .skip 64              # Output filename buffer (e.g. "AAPL.ticker")
    request:    .skip 2048            # Formatted HTTP GET request buffer

.section .text
.globl _start

_start:
    # ==========================================================================
    # 1. INIT & ARGUMENT PARSING
    # ==========================================================================
    movq    %rsp, %rbp                # Save base stack pointer
    andq    $-16, %rsp                # Align stack to 16-byte boundary (SysV ABI rule)
    
    # Reserve 16 bytes of local stack space to safely pass pointers to libc later
    subq    $16, %rsp          
    
    # Validate argument count (argc)
    movq    (%rbp), %rdi              # Load argc from original stack
    cmpq    $4, %rdi                  # Expecting 4 args: [prog] [TICKER] [RANGE] [INTERVAL]
    jne     .L_arg_error              # If not 4, jump to error handler
    
    # Load argument strings into persistent registers
    movq    16(%rbp), %r12            # argv[1] -> Ticker symbol (e.g. "AAPL")
    movq    24(%rbp), %r13            # argv[2] -> Time range (e.g. "max" or "100y")
    movq    32(%rbp), %r14            # argv[3] -> Interval (e.g. "1d")

    # ==========================================================================
    # 2. DYNAMIC MEMORY ALLOCATION (MMAP)
    # ==========================================================================
    # Allocate 64 MB for incoming JSON stream
    movq    $9, %rax                  # Syscall: mmap
    xorq    %rdi, %rdi                # addr = NULL
    movq    $67108864, %rsi           # length = 64 MB
    movl    $3, %edx                  # prot = PROT_READ | PROT_WRITE
    movl    $34, %r10d                # flags = MAP_PRIVATE | MAP_ANONYMOUS
    movq    $-1, %r8                  # fd = -1
    xorq    %r9, %r9                  # offset = 0
    syscall
    testq   %rax, %rax                # Check if mmap failed
    js      .L_exit_err
    movq    %rax, stream_buf_ptr(%rip)

    # Allocate 4 MB for timestamp pool (~524,000 timestamps)
    movq    $9, %rax
    xorq    %rdi, %rdi
    movq    $4194304, %rsi            # length = 4 MB
    movl    $3, %edx
    movl    $34, %r10d
    movq    $-1, %r8
    xorq    %r9, %r9
    syscall
    testq   %rax, %rax
    js      .L_exit_err
    movq    %rax, ts_pool_ptr(%rip)

    # Allocate 4 MB for price pool (~524,000 double prices)
    movq    $9, %rax
    xorq    %rdi, %rdi
    movq    $4194304, %rsi            # length = 4 MB
    movl    $3, %edx
    movl    $34, %r10d
    movq    $-1, %r8
    xorq    %r9, %r9
    syscall
    testq   %rax, %rax
    js      .L_exit_err
    movq    %rax, price_pool_ptr(%rip)

    # ==========================================================================
    # 3. PREPARE STRINGS (Filename and Smart HTTP Request Routing)
    # ==========================================================================
    # strcpy(filename, argv[1])
    leaq    filename(%rip), %rdi      # Dest: filename buffer
    movq    %r12, %rsi                # Src: Ticker string
    call    strcpy@PLT
    
    # strcat(filename, ".ticker")
    leaq    filename(%rip), %rdi      # Dest: filename buffer
    leaq    ext_bin(%rip), %rsi       # Src: ".ticker" extension
    call    strcat@PLT

    # Check if argv[2] equals "max" to apply epoch bypass
    movq    %r13, %rdi                # Arg 1: argv[2] (range string)
    leaq    str_max_arg(%rip), %rsi   # Arg 2: "max"
    call    strcmp@PLT
    testq   %rax, %rax                # If strcmp == 0, user requested 'max'
    jz      .L_format_epoch_request

    # --- Standard Range Format (e.g. 10y, 1d) ---
    leaq    request(%rip), %rdi       # Arg 1: Target buffer
    leaq    req_fmt_range(%rip), %rsi # Arg 2: Range format string
    movq    %r12, %rdx                # Arg 3: %s -> Ticker
    movq    %r13, %rcx                # Arg 4: %s -> Range
    movq    %r14, %r8                 # Arg 5: %s -> Interval
    xorq    %rax, %rax                # 0 floating point arguments
    jmp     .L_do_sprintf

.L_format_epoch_request:
    # --- Absolute Epoch Format for 'max' (period1=0 bypasses Yahoo range limits) ---
    leaq    request(%rip), %rdi       # Arg 1: Target buffer
    leaq    req_fmt_epoch(%rip), %rsi # Arg 2: Epoch format string
    movq    %r12, %rdx                # Arg 3: %s -> Ticker
    movq    %r14, %rcx                # Arg 4: %s -> Interval (takes RCX place in 2-arg format)
    xorq    %rax, %rax                # 0 floating point arguments

.L_do_sprintf:
    call    sprintf@PLT

    # Print connection message
    leaq    msg_conn(%rip), %rdi      # Arg 1: Message string
    xorq    %rax, %rax                # 0 floating point arguments
    call    printf@PLT

    # ==========================================================================
    # 4. OPENSSL NETWORK CONNECTION
    # ==========================================================================
    xorq    %rdi, %rdi                # Arg 1: NULL
    xorq    %rsi, %rsi                # Arg 2: NULL
    call    OPENSSL_init_ssl@PLT      # Initialize OpenSSL library
    
    call    TLS_client_method@PLT     # Setup TLS client
    
    movq    %rax, %rdi                # Move method to Arg 1
    call    SSL_CTX_new@PLT           # Create new context
    movq    %rax, ctx(%rip)           # Save context pointer to memory

    movq    ctx(%rip), %rdi           # Arg 1: Context pointer
    call    BIO_new_ssl_connect@PLT   # Create secure BIO connection object
    movq    %rax, bio(%rip)           # Save BIO pointer to memory

    # Tell BIO to connect to Yahoo Finance
    movq    bio(%rip), %rdi           # Arg 1: BIO pointer
    movq    $BIO_C_SET_CONNECT, %rsi  # Arg 2: Command (Set connect)
    xorq    %rdx, %rdx                # Arg 3: 0
    leaq    host(%rip), %rcx          # Arg 4: Hostname ("query2.finance.yahoo.com:443")
    call    BIO_ctrl@PLT              # Execute control command

    # Execute State Machine to establish connection and perform SSL handshake
    movq    bio(%rip), %rdi           # Arg 1: BIO pointer
    movq    $BIO_C_DO_STATE_MACHINE, %rsi # Arg 2: Command (Do state machine)
    xorq    %rdx, %rdx                # Arg 3: 0
    xorq    %rcx, %rcx                # Arg 4: 0
    call    BIO_ctrl@PLT              # Execute connection
    testq   %rax, %rax                # Check if connection was successful
    jle     .L_exit_err               # If <= 0, network error

    # ==========================================================================
    # 5. SEND HTTP REQUEST & RECEIVE RESPONSE
    # ==========================================================================
    # Get length of request string
    leaq    request(%rip), %rdi
    call    strlen@PLT
    movq    %rax, %rdx                # Arg 3: Length of request
    
    # Write request to network
    movq    bio(%rip), %rdi           # Arg 1: BIO pointer
    leaq    request(%rip), %rsi       # Arg 2: Pointer to request buffer
    call    BIO_write@PLT

    # Reset total bytes read counter
    movq    $0, total_read(%rip)

.L_accumulation_loop:
    # Calculate offset in dynamic stream buffer: stream_buf_ptr + total_read
    movq    stream_buf_ptr(%rip), %rsi
    addq    total_read(%rip), %rsi    # RSI points to end of current data chunk
    
    movq    bio(%rip), %rdi           # Arg 1: BIO pointer
    movq    $4096, %rdx               # Arg 3: Read up to 4096 bytes per chunk
    call    BIO_read@PLT              # Read from network
    
    testq   %rax, %rax                # Check bytes read
    jle     .L_extraction_parsing_gate # If <= 0, stream is finished

    # Accumulate bytes read and loop
    addq    %rax, total_read(%rip)
    jmp     .L_accumulation_loop

.L_extraction_parsing_gate:
    # Null-terminate the entire downloaded JSON string safely inside mmap buffer
    movq    stream_buf_ptr(%rip), %rax
    addq    total_read(%rip), %rax    # Point to the byte after the last read byte
    movb    $0, (%rax)                # Insert null byte '\0'

    # ==========================================================================
    # 6. VALIDATE HTTP RESPONSE & JSON PAYLOAD
    # ==========================================================================
    # Check for "HTTP/1.1 200" to confirm successful network layer
    movq    stream_buf_ptr(%rip), %rdi
    leaq    sig_http_ok(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax                # Did strstr find the substring?
    jz      .L_handle_http_gate_error # If NULL, HTTP failed
    
    # Check if JSON payload contains an API application error ("result":null)
    movq    stream_buf_ptr(%rip), %rdi
    leaq    sig_error(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax                # Did strstr find the error signature?
    jnz     .L_handle_yahoo_error     # If Not NULL, API refused the ticker parameters

    # ==========================================================================
    # 7. EXTRACT TIMESTAMPS & PRICES SYNCHRONOUSLY
    # ==========================================================================
    # Locate '"timestamp":[' array inside the JSON text
    movq    stream_buf_ptr(%rip), %rdi
    leaq    sig_timestamp(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax
    jz      .L_handle_empty_payload
    
    addq    $13, %rax                 # Move pointer past '"timestamp":['
    movq    %rax, %r12                # r12 = Timestamp Text Cursor

    # Locate '"close":[' array inside the JSON text right away
    movq    stream_buf_ptr(%rip), %rdi
    leaq    sig_close(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax
    jz      .L_handle_empty_payload
    
    addq    $9, %rax                  # Move pointer past '"close":['
    movq    %rax, %r13                # r13 = Price Text Cursor

    xorq    %r14, %r14                # r14 = Unified Record Index / Counter

.L_parse_sync_loop:
    # Check if we reached the end of the timestamp array
    cmpb    $93, (%r12)               # ASCII 93 is ']'
    je      .L_serialize_output
    cmpb    $0, (%r12)
    je      .L_serialize_output

    # --- 7A. PARSE TIMESTAMP ---
    movq    %r12, (%rsp)
    movq    %rsp, %rsi
    movq    (%rsp), %rdi
    movq    $10, %rdx
    call    strtoull@PLT
    movq    (%rsp), %r12

    # Store timestamp in dynamic ts_pool
    movq    ts_pool_ptr(%rip), %rcx
    movq    %rax, (%rcx,%r14,8)       # ts_pool[r14] = rax

    # Advance timestamp cursor past comma or closing bracket
.L_skip_ts_comma:
    movb    (%r12), %al
    testb   %al, %al
    jz      .L_serialize_output
    incq    %r12
    cmpb    $44, %al                  # Comma ','
    je      .L_parse_price_item
    cmpb    $93, %al                  # Closing bracket ']'
    je      .L_parse_price_item
    jmp     .L_skip_ts_comma

.L_parse_price_item:
    # --- 7B. PARSE PRICE (WITH FORWARD-FILL SAFETY) ---
    # Check if current price value is literal "null"
    movq    %r13, %rdi
    leaq    str_null(%rip), %rsi
    movq    $4, %rdx
    call    strncmp@PLT
    testq   %rax, %rax
    jnz     .L_extract_price_double

    # It is "null". Forward-fill from previous price index if possible.
    testq   %r14, %r14                # Is this index 0?
    jz      .L_price_fallback_zero  
    
    movq    price_pool_ptr(%rip), %rcx
    movq    -8(%rcx,%r14,8), %rax     # Copy previous price
    movq    %rax, %xmm0
    jmp     .L_advance_price_cursor

.L_price_fallback_zero:
    pxor    %xmm0, %xmm0              # First record fallback to 0.0

.L_advance_price_cursor:
    addq    $4, %r13                  # Skip "null" text
    jmp     .L_store_price_double

.L_extract_price_double:
    movq    %r13, (%rsp)
    movq    %rsp, %rsi
    movq    (%rsp), %rdi
    call    strtod@PLT                # Result in XMM0
    movq    (%rsp), %r13

.L_store_price_double:
    # Store price in dynamic price_pool
    movq    price_pool_ptr(%rip), %rcx
    movsd   %xmm0, (%rcx,%r14,8)      # price_pool[r14] = xmm0
    
    incq    %r14                      # Increment unified record counter

    # Advance price cursor past comma or closing bracket
.L_skip_price_comma:
    movb    (%r13), %al
    testb   %al, %al
    jz      .L_serialize_output
    incq    %r13
    cmpb    $44, %al                  # Comma ','
    je      .L_parse_sync_loop
    cmpb    $93, %al                  # Closing bracket ']'
    je      .L_serialize_output
    jmp     .L_skip_price_comma

# ==============================================================================
# 8. BINARY SERIALIZATION (WRITE TO DISK)
# ==============================================================================
.L_serialize_output:
    # Ensure we actually extracted data
    testq   %r14, %r14
    jz      .L_handle_empty_payload

    # syscall(SYS_open, filename, O_WRONLY | O_CREAT | O_TRUNC, 0644)
    movq    $2, %rax                  # Syscall: open
    leaq    filename(%rip), %rdi      # Arg 1: filename
    movq    $0x241, %rsi              # Arg 2: flags (O_WRONLY=01, O_CREAT=0100, O_TRUNC=01000)
    movq    $0644, %rdx               # Arg 3: mode (rw-r--r--)
    syscall
    movq    %rax, file_fd(%rip)       # Save returned file descriptor

    xorq    %r15, %r15                # Reset loop counter
.L_write_records:
    cmpq    %r14, %r15                # Have we written all records?
    jge     .L_finish_binary

    # Fetch Timestamp
    movq    ts_pool_ptr(%rip), %rax
    movq    (%rax,%r15,8), %r12       # r12 = ts_pool[i]

    # Fetch Price
    movq    price_pool_ptr(%rip), %rax
    movq    (%rax,%r15,8), %r13       # r13 = price_pool[i]

    # Build 16-byte packed struct on stack
    subq    $16, %rsp
    movq    %r12, (%rsp)              # Write 8-byte uint64_t timestamp
    movq    %r13, 8(%rsp)             # Write 8-byte double price

    # syscall(SYS_write, fd, buffer, 16)
    movq    $1, %rax                  # Syscall: write
    movq    file_fd(%rip), %rdi       # Arg 1: file descriptor
    movq    %rsp, %rsi                # Arg 2: buffer (stack pointer)
    movq    $16, %rdx                 # Arg 3: length (16 bytes)
    syscall
    
    addq    $16, %rsp                 # Cleanup stack
    incq    %r15                      # Increment counter
    jmp     .L_write_records          # Loop

.L_finish_binary:
    # syscall(SYS_close, fd)
    movq    file_fd(%rip), %rdi       # Arg 1: file descriptor
    movq    $3, %rax                  # Syscall: close
    syscall

    # Print success message
    leaq    msg_done(%rip), %rdi
    leaq    filename(%rip), %rsi
    movq    %r14, %rdx                # Arg 3: Record count
    xorq    %rax, %rax
    call    printf@PLT
    
    jmp     .L_shutdown_crypto_success

# ==============================================================================
# 9. DIAGNOSTIC EXITS & RUNTIME ERROR TRAWLS
# ==============================================================================
.L_handle_http_gate_error:
    # syscall(SYS_write, stderr, err_http, len)
    movq    $1, %rax                  # Syscall: write
    movq    $2, %rdi                  # Target: stderr
    leaq    err_http(%rip), %rsi
    movq    $ERR_HTTP_LEN, %rdx             
    syscall

    # Print the first 32 bytes of the response to stderr
    movq    $1, %rax
    movq    $2, %rdi
    movq    stream_buf_ptr(%rip), %rsi
    movq    $32, %rdx
    syscall
    
    # Print newline
    leaq    err_newline(%rip), %rsi
    movq    $1, %rdx
    movq    $1, %rax
    syscall
    
    jmp     .L_shutdown_crypto_err

.L_handle_yahoo_error:
    # Search for "description":" string in JSON to find API error details
    movq    stream_buf_ptr(%rip), %rdi
    leaq    sig_desc(%rip), %rsi
    call    strstr@PLT
    testq   %rax, %rax
    jz      .L_shutdown_crypto_err    # Fallback if description is missing
    
    addq    $15, %rax                 # Skip past '"description":"'
    movq    %rax, %r12                

    # Print Error Prefix
    movq    $1, %rax              
    movq    $2, %rdi              
    leaq    err_prefix(%rip), %rsi
    movq    $ERR_PREFIX_LEN, %rdx           
    syscall

    # Character-by-character print until closing quote
    movq    %r12, %r13            
.L_print_err_char:
    cmpb    $0, (%r13)                # End of string?
    je      .L_error_done
    cmpb    $34, (%r13)               # Quote char '"'?
    je      .L_error_done
    
    movq    $1, %rax                  # Syscall: write
    movq    $2, %rdi                  # Target: stderr
    movq    %r13, %rsi                # Character pointer
    movq    $1, %rdx                  # 1 byte
    syscall
    
    incq    %r13                      # Next character
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
    # Free BIO and OpenSSL contexts safely
    movq    bio(%rip), %rdi
    call    BIO_free_all@PLT
    movq    ctx(%rip), %rdi
    call    SSL_CTX_free@PLT
    
    addq    $16, %rsp                 # Cleanup local stack frame pointer space
    
    # syscall(SYS_exit, 0)
    movq    $60, %rax                 # Syscall: exit
    xorq    %rdi, %rdi                # Exit code: 0 (Success)
    syscall

.L_shutdown_crypto_err:
    movq    bio(%rip), %rdi
    call    BIO_free_all@PLT
    movq    ctx(%rip), %rdi
    call    SSL_CTX_free@PLT
    
    addq    $16, %rsp                 # Cleanup stack
    
    # syscall(SYS_exit, 1)
    movq    $60, %rax                 # Syscall: exit
    movq    $1, %rdi                  # Exit code: 1 (Error)
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
