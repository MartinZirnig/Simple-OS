; === Includes ===
%Include '../Constants.inc'
%Include '../ReservedMemory.inc'

; === Local Constants ===
%define EXPECTED_RAM_SIZE 0x280

%define CODE32    0x08
%define DATA32    0x10
%define CODE64    0x18
%define DATA64    0x20

; === Starting bootloader format ===
ORG 0x7C00                      ; move stack to correct memory address
BITS 16                         ; indicate safe (16bit) CPU mode

; === Stack and registers initializetion ===
CLI             
MOV AX, 0
MOV DS, AX
MOV ES, AX
MOV SS, AX
MOV SP, 0x7C00  
STI

; === Allocate Data ===
shutdown_msg                DB  'Shutting down', LINE_START, NEXT_LINE, NULL_TERMINATOR
apm_error_msg               DB  'APM Shutdown Failed', LINE_START, NEXT_LINE, NULL_TERMINATOR
acpi_error_msg              DB  'ACPI Shutdown Failed', LINE_START, NEXT_LINE, NULL_TERMINATOR
qemu_error_msg              DB  'QEMU Shutdown Failed', LINE_START, NEXT_LINE, NULL_TERMINATOR
port0XB004_error_msg        DB  'port 0XB004 Shutdown Failed', LINE_START, NEXT_LINE, NULL_TERMINATOR
port0X604_error_msg         DB  'port 0X604 Shutdown Failed', LINE_START, NEXT_LINE, NULL_TERMINATOR
shutdown_failed_msg         DB  'software shutdown failed, turn off manually', LINE_START, NEXT_LINE, NULL_TERMINATOR

start_msg                   DB  'starting boot process', LINE_START, NEXT_LINE, NULL_TERMINATOR
fail_msg                    DB  'booting failed, shutdown immenet', LINE_START, NEXT_LINE, NULL_TERMINATOR

UNAVAILABLE_LONG_MODE_MSG   DB  'your PC doesn't support 64 bit OS', LINE_START, NEXT_LINE, NULL_TERMINATOR


; === Reserve data ===


; === Define structures ===
JMP END_STRUCTURES ; jump to the end of structure definition

; --- GDT ---
GDT_DESCRIPTOR:
    DW GDT_END - GDT - 1   ; Size of GDT
    DD GDT                 ; GDT address
GDT:
    DQ NULL ; requared Null segment 
    ; Code segment (64bit, exexecute)
    DQ 0x00209A0000000000
    ; Data segment (64bit, read/write)
    DQ 0x0000920000000000
GDT_END: ; end structure definition position

; --- Paging ---
ALIGN 8
PML4_TABLE:
    DQ PDPT_TABLE | 0b11  ; První záznam PML4 (směřuje na PDPT)

ALIGN 8
PDPT_TABLE:
    DQ PD_TABLE | 0b11  ; První záznam PDPT (směřuje na Page Directory)

ALIGN 8
PD_TABLE:
    DQ 0x00000003        ; Identicky mapovaná první 2MB stránka (RW, Present)


END_STRUCTURES:


; === Protected (32bit) mode transition ===
CLI                        ; ban interrupts
LGDT [GDT_DESCRIPTOR]      ; load GDT

; Set flag bites
MOV EAX, CR0
OR EAX, 1                 
MOV CR0, EAX
; jump to protected mode
JMP CODE32:.protected_mode  

BITS 32
.protected_mode:
; set segmentation registers
MOV AX, DATA32            
MOV DS, AX
MOV ES, AX
MOV FS, AX
MOV GS, AX
MOV SS, AX
; Now in protected mode


; === Long (64bit) mode transition
; Check long mode support
MOV EAX, 0x80000000
CPUID
CMP EAX, 0x80000001
JB no_long_mode
MOV EAX, 0x80000001
CPUID
TEST EDX, (1 << 29)  
JZ no_long_mode

; Allow PAE (Physical Address Extension)
MOV EAX, CR4
OR EAX, (1 << 5)     
MOV CR4, EAX

; Set paging tables (PML4, PDPT, PDT)
MOV EAX, PML4_TABLE
MOV CR3, EAX         

; Allow LongMode in MSR
MOV ECX, 0xC0000080  
RDMSR
OR EAX, (1 << 8)     
WRMSR

; Activate paging
MOV EAX, CR0
OR EAX, (1 << 31) | (1 << 0) 
MOV CR0, EAX

; Jump to 
JMP CODE64:.long_mode

; Unavailable long mode handling
no_long_mode:
    MOV ESI, UNAVAILABLE_LONG_MODE_MSG
    CALL print_string
    JMP fail



BITS 64
.long_mode:
MOV AX, DATA64
MOV DS, AX
MOV ES, AX
MOV FS, AX
MOV GS, AX
MOV SS, AX
; Now in long mode

    



; === Code ===









; > string pointer in si
; < void
; print message on screan
print_string:
        MOV AH, 0x0E  
    .loop:
        LODSB           ; Načte znak do AL a posune SI
        OR AL, AL      
        JZ .done        ; Pokud AL == 0, konec řetězce

        INT 0x10        ; Vypíše znak
        JMP .loop
    .done:
        RET

; > void
; < key in AL
wait_key:
    MOV AH, 0
    INT 16H   
    RET

; > void
; < void
; handle error by shutting PC down
fail:
    MOV SI, fail_msg
    CALL print_string

    CALL wait_key
    JMP shutdown
    

; > void
; < void
; try shutdown PC
shutdown:
    ; print msg
    MOV SI, shutdown_msg
    CALL print_string

    CALL wait_key
    ; try each shutdown type
    CALL .apm_shutdown
    CALL wait_key

    CALL .acpi_shutdown
    CALL wait_key

    CALL .port0x604_shutdown
    CALL wait_key

    CALL .qemu_shutdown
    CALL wait_key

    ; handle shutdown fail
    MOV SI, shutdown_failed_msg
    CALL print_string
    HLT
    JMP $

    .apm_shutdown:
        ; check if apm is available
        MOV AX, 0X5301      
        XOR BX, BX          
        INT 0X15           
        JC .apm_error      

        ; send apm shutdown command
        MOV AX, 0X5307      
        MOV BX, 0X0001      
        MOV CX, 0X0003      
        INT 0X15           
        JC .apm_error    

        HLT

    .apm_error:
        MOV SI, apm_error_msg   
        CALL print_string
        RET

    .acpi_shutdown:
        ; acpi reset control 
        MOV DX, 0XCF9
        MOV AL, 0X02  ; hard power off
        OUT DX, AL    
        HLT

    .port0x604_shutdown:
        ; some bios versions accept this
        MOV DX, 0X604
        MOV AL, 0X02  ; power off
        OUT DX, AL
        HLT

    .qemu_shutdown: ; for virtualization
        ; qemu specific shutdown
        MOV DX, 0X604
        MOV AX, 0X2001
        OUT DX, AX
        HLT








; === Finishing bootloader format ===
TIMES 510 - ($ - $$) DB 0       ; fills file into selected size
DW 0xAA55                       ; Boot sektor signature