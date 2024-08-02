;;
;; Gramado MBR - 
;; Esse é o MBR que é montado no VHD na hora de sua criação.
;; Será o primeiro setor do disco.
;; Essa rotina carrega o BM.BIN na memória e passa o comando para ele. 
;; Além de passar argumentos.
;; É um VHD de 32MB. 
;; A primeira partição é a partição do sistema e está formatada
;; em fat16 com 512 bytes por cluster.
;; Obs: 
;; Não mudar os endereços de segmento e offset usados 
;; para não arrumar problemas.
;; History:
;;     2005 - Created.
;;     It is the first file created for the project.
;; Partition table:
;; See:
;;     https://thestarman.pcministry.com/asm/mbr/PartTables.htm
;; org = 0
;; See: main.asm 

;       +--------+
;       |   ...  |
;       |--------|
;       |   FAT  |
;       |--------| 0x17C0:0x0200
;       |        |
;       |--------|
;       |        |
;       | BM.BIN |
;       |        |
;       |--------| 0x0000:0x8000
;       |        |
;       |--------|
;       | ROOT   |
;       | DIR    |
;       |--------| 0x07C0:0x0200
;       |BOOT SEC| 
;       |ORIGIN  | 
;  >>>  |--------| 0x07C0:0x0000 :)
;       |        |
;       |--------| 0x0000:0x6000
;       |INITIAL | Initial stack address.
;       |STACK   | It goes down.
;       |--------| 
;       |        |
;       +--------+


;; 16bit. Esse é o MBR do VHD.
[bits 16]

; Jump to the real start routine.
stage1_main:
    jmp GRAMADOINIT

    %include "s1data.inc"
    %include "s1lib.inc"

; =============================================
; GRAMADOINIT:  (Real start)
; Start here 0x07C0:0.
; Stack here 0:6000h.
; Root dir in 0x07C0:0x0200.
; Load the FAT in es:bx 0x17C0:0x0200.
; Load image in 0:8000h.
; #todo
; BootSegment   equ 0x07C0
; BootOffset    equ 0
; StackSegment  equ 0
; StackOffset   equ 0x6000
; RootSegment   equ 0x07C0
; RootOffset    equ 0x0200
; FATSegment    equ 0x17C0
; FATOffset     equ 0x0200
; ImageSegment  equ 0
; ImageOffset   equ 0x8000

GRAMADOINIT:

; Step1:
; Code located at 0x7C00, 
; adjust segment registers to 0x07C0:0.
; Create stack.   0:6000h
    cli
    mov ax, 0x07C0
    mov ds, ax
    mov es, ax
    mov ax, 0x0000
    mov ss, ax
    mov sp, 0x6000
    sti

Step2:
    mov byte [DriveNumber], byte dl 
    ;cmp dl, byte 0x80
    ;jne FAILURE

Step3:
; Clear the Screen.
    mov ax, 02h
    int 010h

; Step4:
; #todo: Certificar que int 13h é suportada.

; Step5:
; #todo: Reset driver.

; Step6:
; As informações sobre disco 
; serão pegadas no BM.BIN.
; O STEP6 FOI RETIRADO E AGORA ESTÁ NO PARA O BM.BIN
; DESSE MODO NÃO PRECISAMOS MAIS PASSAR ARGUMENTOS PARA O BM.BIN 
; PASSAREMOS SOMENTE O 'DRIVE NUMBER'

; Step7:
; Carregamentos...
; Load root, fat and image.
; Carregar o ROOT.
; #todo: 
; Cuidadosamente rever os cálculos feitos aqui para permitir que
; que carreguemos o sistema usando discos de vários tamanhos. 
; Por enquanto estamos predeterminando as diretrizes de carregamento. 
;  559 (root)
; ( MBR + Reserved Sectors + VBR + Hidden Sectors + TotalFATs * SectorsPerFAT )
; (  1  +      62          +  1  +    3           +    2      *     246)
; =================================================================
;   1 - mbr (*hidden) 
;  62 - Reserved sectors.
;   1 - vbr (*hidden) (VBR da primeira partição)
; 246 - fat1
; 246 - fat2
;   3 - Hidden sectors. (*hidden)
;  32 - root. (512 entradas)
; xxx - data area.

LOADROOT:

; ## data area location ## 
; Calcula o início da área de dados.
; Compute size of root directory and store in "cx".

    xor  cx, cx
    mov  ax, 32                   ; 32 byte. Tamanho de uma entrada de diretório.
    mul  WORD [MaxRootEntries]    ; 512. Tamanho total do diretório dado em bytes. (32*512) bytes.
    div  WORD [BytesPerSector]    ; ((32*512)/512) O número total de bytes no diretório, dividido pela quantidade de bytes por setor.
    mov  WORD [ROOTDIRSIZE], ax
    mov cx, ax                    ; Coloca o resultado em cx. (Quantidade de setores no diretório raiz.)

; Root location
; Compute location(LBA) of root directory and store in "ax".

    xor ax, ax
    mov  al, BYTE [TotalFATs]    ; 2. Number of FATs.
    mul  WORD [SectorsPerFAT]    ; 246. Sectors used by FATs.

; +62. Adiciona os setores reservados. 
; +5.  Adiciona os setores escondidos. (1+1+3) 
; 5 = ( 1 MBR + 1 VBR + 3 hidden sectors )

    add  ax, WORD [ReservedSectors]  
    add  ax, WORD [HiddenSectors]    

; >>> Nesse momento ax contém o setor inicial do root dir.
; vamos adicionar o tamanho do diretório raiz dado em setores. 
; [ROOTDIRSIZE]
; Dessa forma ex contém o setor onde inicia a área de dados.

    mov word [ROOTDIRSTART], ax
    add  ax, cx

    mov  WORD [datasector], ax

; SIMULANDO o data area para testes.
    ;; mov  WORD [datasector], 591

; Obs: 
; A variável 'datasector' precisa ser inicializada aqui, 
; pois é usada mais à frente na rotina de conversão.
; Obtivemos com o cálculo:
    ;; cx           = Tamanho do diretório raiz, dado em número de setores.
    ;; [datasector] = Início da área de dados.
;; >> Carregar o diretório raiz em es:bx 0x07C0:0x0200.
;; Obs: 
;; Me parece seguro permitirmos que carregue o diretório raiz inteiro,
;; Porém desnecessário ainda.
;; 559 (root)
;; ( MBR + Reserved Sectors + VBR + Hidden Sectors + TotalFATs * SectorsPerFAT )
;; (  1  +      62          +  1  +    3           +    2      *     246)
;;==============================
;;   1 - mbr (*hidden) 
;;  62 - Reserved sectors.
;;   1 - vbr (*hidden) (VBR da primeira partição)  	
;; 246 - fat1
;; 246 - fat2
;;   3 - Hidden sectors. (*hidden)
;;  32 - root. (512 entradas)
;; xxx - data area.

.loadRoot:

; 559 - Início do diretório raiz.
; 32  - Quantos setores carregar. Tamanho do diretório raiz.
; 0x0200 - Offset para encontrarmos o endereço onde devemos 
; carregar o root na memória. (seg:off) 

    mov  ax, word [ROOTDIRSTART]
    mov  cx, word [ROOTDIRSIZE]
    mov  bx, 0x0200
    call  ReadSectors

; Uma mensagem de espaçamento.

    ;pusha
    ;mov  si, msgCRLF
    ;call  DisplayMessage
    ;popa

; Procurando o arquivo BM.BIN no diretório raiz.
; Browse root directory for binary image.
.searchFile:
    mov  cx, WORD [MaxRootEntries]  ; Load loop counter.
    mov  di, 0x0200                 ; Determinando o offset do início do diretório.
.LOOP:
    push  cx
    mov  cx, 0x000B       ; Eleven character name.
    mov  si, ImageName    ; Image name to find.
    ; It prints the image name while comparing each entry.
    ; Debug purpose.
    pusha
    call  DisplayMessage
    popa
    push  di
    rep  cmpsb            ; Test for entry match.
    pop  di
    je  LOADFAT     ; Se o arquivo foi encontrado.
    pop  cx
    add  di, 0x0020       ; Queue next directory entry.
    loop  .LOOP
    jmp  FAILURE

; Load the FAT in es:bx 0x17C0:0200.
; #bugbug Size?

LOADFAT:

    ;pusha
    ;mov  si, msgFAT
    ;call  DisplayMessage
    ;popa

; dx = Cluster inicial do arquivo a ser carregado.
; Save starting cluster of boot image.
; Salvamos o número do cluster inicial da Imagem. 
; Isso foi obtido na entrada do diretório.
; File's first cluster.

    mov dx, WORD [di + 0x001A]
    mov WORD [cluster], dx 

; Efetuando o carregamento da fat no buffer es:bx. 
; 0x17C0:0x0200.

;===================================
; #bugbug: 
; SE CARREGAR A FAT INTEIRA DÁ PROBLEMA. !!!! 
; (246/2)
; Estamos carregando apenas metade da fat.
; ?? Por que ?? Qual é o problema ??
;===================================
; Read FAT into memory (17C0:0200).
; Obs: Confiar no cáculo do início da LBA é perigoso, apesar de necessário.
; Por enquanto vamos determiná-lo.
; Obs: É possível confiarmos no cálculo do tamanho da fat, mesmo assim, vamos
; por enquanto, determiná-lo.
; Obs: Não estamos carregando a FAT inteira. Isso pode ser arriscado, mas 
; por enquanto, como temos poucos arquivos, vamos carrega apenas metade da FAT.

.loadFAT:

    mov ax, 0x17C0
    mov es, ax   

; Compute location of FAT and store in "ax".
; Calculado qual é a LBA inicial da FAT e salvando em 'ax'.

    mov ax, WORD [HiddenSectors]      ; 5 setores escondidos.
    add ax, WORD [ReservedSectors]    ; 62 setores reservados.

; #debug
; SIMULANDO Determinando a LBA inicial da FAT, 
; apezar de termos calculado.

    ; mov  ax, 67                              

; #bugbug
; Estamos carregando apenas metade da fat.
; Falha se tentarmos carregar ela inteira.

    mov  cx,  (246/2) ; WORD [SectorsPerFAT]  ;  Metade da fat.
    mov  bx, 0x0200                           ;  Determinando o offset da FAT.
    call  ReadSectors

; Carregar o arquivo BM.BIN na memória 
; em es:bx, 0:8000h.

; Mensagem de espaçamento.
    ;mov  si, msgCRLF
    ;call  DisplayMessage

; Mensagem avisando que vamos carregar.
    ;mov  si, msgImg
    ;call  DisplayMessage

.setupBuffers:

; Configurando o buffer para o arquivo. (es:bx), 0:8000h.
    mov ax, 0
    mov es, ax        ; Segment.
    mov bx, 0x8000    ; Offset.

; Salvando o offset do buffer do arquivo.
    push  bx

; Nesse momento a FAT já está na memória, precisamos indicar 
; em gs:bx o endereço do buffer onde carregamos a fat.

; Indicando o segmento onde a FAT está carregada.
    mov ax, 0x17C0    ; FAT Segment
    mov gs, ax

; >> Carrega o arquivo na memória 
;    em es:bx, 0:8000h.

__loop_LOAD_IMAGE:

; Em 'bx' está o offset do buffer do arquivo.

; Recuperando o offset do buffer do arquivo.
    pop  bx                                  

; Vamos converter Cluster em LBA.
    mov  ax, WORD [cluster]    ; Cluster inicial do arquivo, obtido na entrada no diretório.
    call  ClusterLBA           ; Convert cluster to LBA.

; Carregamos apenas um cluster de cada vez.
; No nosso caso, um cluster só tem um setor.

.loadImage:

    xor  cx, cx
    mov  cl, BYTE [SectorsPerCluster]    ; 1. Sectors to read.
    call  ReadSectors

.saveThis:

; Vamos savar o offset do próximo setor a ser carregado.
; Onde deve ficar o próximo setor. ??

    push bx

; Agora temos que saber qual será o próximo cluster.
; Vamos calcular o deslocamento dentro da fat para obtermos o 
; o local onde encontraremos o valor do próximo cluster.
; Salvaremos em 'dx'.
; lembrando que a fat está em gs:bx.

    mov ax, WORD [cluster]    ; identify current cluster
    add ax, ax                ; 16 bit(2 byte) FAT entry
    mov bx, 0x0200            ; location of FAT in memory
    add bx, ax                ; index into FAT    
    mov dx, WORD [gs:bx]      ; read two bytes from FAT

; Saving new cluster.
; Em 'dx', está o valor do próximo cluster.

.DONE:
    mov  WORD [cluster], dx 

; Test for end of file.
; Testamos para ver se é o último cluster. 
; 0xFFFF ? or 0xFFF8 ?
; Se esse foi o último cluster então prosseguiremos.
; Caso contrário volta para o loop.

.testEOF: 
    cmp  dx, END_OF_CLUSTER  
    jne  __loop_LOAD_IMAGE

; Done:
; Pass an argument to the next stage.
; Disk Number.
; Passando o comando para o BM.BIN em 0:8000h.

Step8_PARAMETERS:
    mov dl, byte [DriveNumber]
Step9_FLY:
    PUSH WORD  0         ; CS
    PUSH WORD  0x8000    ; Offset 
    RETF


; ======================================================
;  PARTITION TABLE 
; ======================================================
; http://cars.car.coocan.jp/misc/chs2lba.html
; https://en.wikipedia.org/wiki/Partition_type
; bios = limits: h=4, c=3FF, s=A
; vhd = CHS=963/4/17

; Partition table support.
; Colocando a partition table no lugar certo. 
; (0x1BE).
    TIMES 446-($-$$) DB 0 

; 446  16  Partition table entry 1.
; 462  16  Partition table entry 2.
; 478  16  Partition table entry 3.
; 494  16  Partition table entry 4.
; 510  2   0xAA55. Indicates this is a valid MBR.

; Partition 0. 
P0:
.flag:      db  0x80
.startH:    db  0x01
.startC:    db  0x01
.startS:    db  0
.osType:    db  0xEF             ; EFI
.endH:      db  0
.endC:      db  0
.endS:      db  0
.startLBA:       dd  0x3F        ; 63
; #todo
; We gotta send this value to the kernel.
; The file system needs to respect this limit.
.partitionSize:  dd  0x0000FFA7  ; in sectors. almost 32MB

; Partition 1, 2 and 3.
P1: dd 0,0,0,0 
P2: dd 0,0,0,0 
P3: dd 0,0,0,0 

; ----------------------------------------
; Signature.
FREE_SPACE_SIZE EQU  510-($-$$)
MBR_SIG:
    TIMES FREE_SPACE_SIZE DB 0
    DW 0xAA55

;
; End
;

