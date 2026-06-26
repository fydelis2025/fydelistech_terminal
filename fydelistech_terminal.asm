section .data
    ; Chamadas de sistema (Syscalls Linux x86_64)
    SYS_READ            equ 0
    SYS_WRITE           equ 1
    SYS_OPEN            equ 2
    SYS_CLOSE           equ 3
    SYS_EXECVE          equ 59
    SYS_EXIT            equ 60
    SYS_IOCTL           equ 16
    SYS_SETSID          equ 112
    SYS_FORK            equ 57     
    SYS_SELECT          equ 23

    ; Constantes de IOCTL para PTY (x86_64)
    TIOCGPTN            equ 0x80045430
    TIOCSPTLCK          equ 0x40045431
    TIOCSCTTY           equ 0x540E

    O_RDWR              equ 2
    STDIN               equ 0
    STDOUT              equ 1

    ptmx_path           db "/dev/ptmx", 0
    ptmx_alt_path       db "/dev/pts/ptmx", 0 
    pts_base            db "/dev/pts/", 0
    sh_path             db "/bin/sh", 0

    msg_erro            db "Erro na inicializacao do PTY.", 0xA
    tam_erro            equ $ - msg_erro
    msg_etapa           db "Etapa: ", 0
    tam_etapa           equ $ - msg_etapa
    msg_status          db " | Erro: ", 0
    tam_status          equ $ - msg_status

section .bss
    fd_mestre           resq 1     
    fd_escravo          resq 1
    pty_num             resd 1     
    pts_path            resb 64
    buffer              resb 4096
    fd_set_read         resq 16    
    envp_ptr            resq 1     ; Variável para armazenar o ponteiro do ambiente do sistema

section .text
    global _start

_start:
    ; --- CAPTURA DAS VARIÁVEIS DE AMBIENTE (ENVP) DA PILHA ---
    ; Na entrada de _start:
    ; RSP indica argc. [RSP + 8] é argv[0].
    ; O envp fica logo após o fim de argv (que termina com um ponteiro NULL).
    mov rcx, [rsp]          ; RCX = argc
    lea rsi, [rsp + 8 + rcx*8 + 8] ; Pula argc, a lista de argv e o NULL final. 
    mov [envp_ptr], rsi     ; Salva o ponteiro de envp para usar no execve do filho

    ; 1. Abrir /dev/ptmx
    mov r12, 1              
    mov rax, SYS_OPEN
    mov rdi, ptmx_path
    mov rsi, O_RDWR
    xor rdx, rdx
    syscall
    cmp rax, 0
    jge .sucesso_ptmx

    mov rax, SYS_OPEN
    mov rdi, ptmx_alt_path
    mov rsi, O_RDWR
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl erro_geral

.sucesso_ptmx:
    mov [fd_mestre], rax

    ; 2. Destravar o PTY Escravo (TIOCSPTLCK)
    mov r12, 2              
    mov rax, SYS_IOCTL
    mov rdi, [fd_mestre]
    mov rsi, TIOCSPTLCK
    xor r8, r8
    push r8                 
    mov rdx, rsp            
    syscall
    pop r8                  
    cmp rax, 0
    jl erro_geral

    ; 3. Obter o número do PTY
    mov r12, 3              
    mov rax, SYS_IOCTL
    mov rdi, [fd_mestre]
    mov rsi, TIOCGPTN
    mov rdx, pty_num
    syscall
    cmp rax, 0
    jl erro_geral

    ; 4. Construir string do caminho
    mov r12, 4              
    call construir_caminho_escravo

    ; 5. Abrir o PTY Escravo
    mov r12, 5              
    mov rax, SYS_OPEN
    mov rdi, pts_path
    mov rsi, O_RDWR
    xor rdx, rdx
    syscall
    cmp rax, 0
    jl erro_geral
    mov [fd_escravo], rax

    ; 6. Fork
    mov r12, 6              
    mov rax, SYS_FORK
    syscall
    cmp rax, 0
    jl erro_geral
    je processo_filho

; =========================================================================
; PROCESSO PAI
; =========================================================================
processo_pai:
    mov rax, SYS_CLOSE
    mov rdi, [fd_escravo]
    syscall

loop_pai:
    mov rcx, 16
    mov rdi, fd_set_read
    xor rax, rax
    rep stosq

    mov rbx, 1
    shl rbx, STDIN
    or [fd_set_read], rbx

    mov rcx, [fd_mestre]
    mov rbx, 1
    shl rbx, cl
    or [fd_set_read], rbx

    mov rdi, [fd_mestre]
    inc rdi                 
    mov rsi, fd_set_read    
    xor rdx, rdx            
    xor r10, r10            
    xor r8, r8              
    mov rax, SYS_SELECT
    syscall
    cmp rax, 0
    jl erro_geral

    mov rcx, STDIN
    mov rbx, 1
    shl rbx, cl
    test [fd_set_read], rbx
    jz verificar_mestre

    mov rax, SYS_READ
    mov rdi, STDIN
    mov rsi, buffer
    mov rdx, 4096
    syscall
    cmp rax, 0
    jle loop_pai

    mov rdx, rax
    mov rax, SYS_WRITE
    mov rdi, [fd_mestre]
    mov rsi, buffer
    syscall

verificar_mestre:
    mov rcx, [fd_mestre]
    mov rbx, 1
    shl rbx, cl
    test [fd_set_read], rbx
    jz loop_pai

    mov rax, SYS_READ
    mov rdi, [fd_mestre]
    mov rsi, buffer
    mov rdx, 4096
    syscall
    cmp rax, 0
    jle sair_pai

    mov rdx, rax
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, buffer
    syscall
    jmp loop_pai

sair_pai:
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

; =========================================================================
; PROCESSO FILHO
; =========================================================================
processo_filho:
    mov rax, SYS_CLOSE
    mov rdi, [fd_mestre]
    syscall

    mov rax, SYS_SETSID
    syscall

    mov rax, SYS_IOCTL
    mov rdi, [fd_escravo]
    mov rsi, TIOCSCTTY
    xor rdx, rdx
    syscall

    mov rcx, 0
.loop_dup:
    mov rax, 33             
    mov rdi, [fd_escravo]
    mov rsi, rcx
    syscall
    inc rcx
    cmp rcx, 3
    jl .loop_dup

    ; Executar /bin/sh passando o ambiente herdado do sistema
    xor rbx, rbx
    push rbx                
    mov rax, sh_path
    push rax
    mov rsi, rsp            ; argv = ["/bin/sh", NULL]
    mov rdx, [envp_ptr]     ; rdx = Mudado de 'xor rdx,rdx' para o envp real capturado!
    mov rdi, sh_path        ; filename
    mov rax, SYS_EXECVE
    syscall

    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

; =========================================================================
; AUXILIARES
; =========================================================================
construir_caminho_escravo:
    mov rcx, 8
    mov rdi, pts_path
    xor rax, rax
    rep stosq

    mov rsi, pts_base
    mov rdi, pts_path
.copia_base:
    lodsb
    test al, al
    jz .converte_num
    stosb
    jmp .copia_base

.converte_num:
    mov eax, [pty_num]
    mov ecx, 10
    xor rbx, rbx
    push rbx                

.loop_div:
    xor edx, edx
    div ecx
    movzx rdx, dl           
    add rdx, '0'            
    push rdx                
    test eax, eax
    jnz .loop_div

.desempilha:
    pop rax                 
    test rax, rax           
    jz .fim_caminho
    stosb                   
    jmp .desempilha

.fim_caminho:
    mov byte [rdi], 0       
    ret

erro_geral:
    push rax                 
    
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_erro
    mov rdx, tam_erro
    syscall

    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_etapa
    mov rdx, tam_etapa
    syscall

    mov rax, r12
    call pr_num

    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, msg_status
    mov rdx, tam_status
    syscall

    pop rax
    neg rax
    call pr_num

    push 0x0A
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, rsp
    mov rdx, 1
    syscall
    pop rax

    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

pr_num:
    mov ecx, 10
    push 0xFFFF             
.loop:
    xor rdx, rdx
    div rcx
    add dl, '0'
    push rdx
    test rax, rax
    jnz .loop
.print:
    pop rdx
    cmp rdx, 0xFFFF
    je .fim
    mov [buffer], dl
    push rcx
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, buffer
    mov rdx, 1
    syscall
    pop rcx
    jmp .print
.fim:
    ret
