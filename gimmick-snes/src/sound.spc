; The sound driver, on the SNES's SPC700. It plays what the game writes to the NES's APU
; and the Sunsoft 5B: the runtime sends register values over the ports, and this keeps
; the NES's sequencer going, at 240 Hz, for length, envelope, sweep and the linear counter.
; One DSP voice for each NES one: pulse, pulse, triangle, noise, DPCM, 5B A, B, C.

port0 = $F4
port1 = $F5
port2 = $F6
dspa  = $F2
dspd  = $F3
ctrl  = $F1
timer0 = $FA
tout0 = $FD

regs   = $20         ; $4000-$4017, then the 5B's 16 at +$20
sb     = $40
len    = $50         ; length counters: pulse, pulse, triangle, noise
env    = $54         ; envelope volume: pulse, pulse, -, noise
envd   = $58         ; envelope divider
sweepd = $5C         ; sweep divider: 2 bytes for 2 pulses
linc   = $5E         ; triangle's linear counter
linr   = $5F         ; its reload flag
seq    = $60
last   = $61
ptr    = $62         ; 2 bytes
tmp    = $64
tmp2   = $65
vidx   = $66
bank   = $67         ; the NES's $C000 bank, for DPCM
envs   = $68         ; start flags

start:
        mov x,#$EF
        mov sp,x
        mov $F0,#$0A        ; the normal test state
        mov ctrl,#$30       ; the ports start from zero
        mov last,#0
        call dsp_init
        mov timer0,#33      ; 8 kHz / 33 = 242 Hz
        mov ctrl,#$01
main:
        mov a,port0
        cmp a,last
        beq no_msg
        mov last,a
        mov x,port1
        mov a,port2
        mov port0,last      ; acknowledge
        call msg
no_msg:
        mov a,tout0
        beq main
        call tick
        bra main

; A register in x, its value in a. $00-$17 the APU, $20-$2F the 5B, $18-$1B a new note
; on channel x-$18, $1C DPCM started, $1D the $C000 bank.
msg:
        cmp x,#$18
        bcs msg_special
        mov regs+x,a
        ret
msg_special:
        cmp x,#$20
        bcc msg_kick
        mov regs+x,a
        ret
msg_kick:
        cmp x,#$1C
        bcs msg_dpcm
        ; New note: x-$18. Length from the value's top 5 bits, envelope restarts.
        mov tmp,x
        mov a,x
        clc
        adc a,#256-$18
        mov x,a
        mov a,#1
        mov envs+x,a
        mov a,!regs_len_hi+x
        call set_len
        cmp x,#2
        bne msg_done
        mov linr,#1
msg_done:
        ret
msg_dpcm:
        cmp x,#$1D
        beq msg_bank
        jmp dpcm_start
msg_bank:
        mov bank,a
        ret

regs_len_hi:
        .byte regs+3, regs+7, regs+$B, regs+$F

; Channel in x; the register's number in a.
set_len:
        push x
        mov x,a
        mov a,$00+x
        lsr a
        lsr a
        lsr a
        mov y,a
        mov a,!len_table+y
        pop x
        mov len+x,a
        ret

len_table:
        .byte 10,254,20,2,40,4,80,6,160,8,60,10,14,12,26,14
        .byte 12,16,24,18,48,20,96,22,192,24,72,26,16,28,32,30

dsp_init:
        mov x,#0
di_loop:
        mov a,!dsp_table+x
        beq di_voices
        mov dspa,a
        mov a,!dsp_table+1+x
        mov dspd,a
        inc x
        inc x
        bra di_loop
di_voices:
        mov x,#0            ; voice number * 16
        mov y,#0
di_v:
        mov a,x
        mov dspa,a          ; VOLL
        mov dspd,#0
        or a,#$01
        mov dspa,a
        mov dspd,#0
        mov a,x
        or a,#$05
        mov dspa,a          ; ADSR1: off, so GAIN applies
        mov dspd,#0
        mov a,x
        or a,#$07
        mov dspa,a
        mov dspd,#$7F       ; full, directly
        mov a,x
        or a,#$04
        mov dspa,a
        mov a,!voice_src+y
        mov dspd,a
        mov a,x
        clc
        adc a,#$10
        mov x,a
        inc y
        cmp y,#8
        bne di_v
        ; Everything but DPCM runs all the time, at no volume when silent.
        mov dspa,#$5C
        mov dspd,#0
        mov dspa,#$4C
        mov dspd,#$EF
        ret

voice_src:
        .byte SRC_DUTY+2, SRC_DUTY+2, SRC_TRI, SRC_DUTY+2, SRC_DUTY+2, SRC_DUTY+2, SRC_DUTY+2, SRC_DUTY+2

dsp_table:
        .byte $6C,$20       ; echo off, noise clock 0
        .byte $0C,$60, $1C,$60, $2C,$00, $3C,$00
        .byte $5D,DIR_PAGE
        .byte $3D,$08       ; voice 3 is noise
        .byte $2D,$00, $0D,$00, $4D,$00
        .byte 0

; 240 Hz: the sequencer, then the voices.
tick:
        inc seq
        call tick_env
        mov a,seq
        and a,#1
        bne t_no120
        call tick_len
        call tick_sweep
t_no120:
        call update
        ret

tick_env:
        ; pulse, pulse, noise
        mov x,#0
        call env1
        mov x,#1
        call env1
        mov x,#3
        call env1
        ; triangle's linear counter
        mov a,linr
        beq te_dec
        mov a,regs+8
        and a,#$7F
        mov linc,a
        bra te_c
te_dec:
        mov a,linc
        beq te_c
        dec linc
te_c:
        mov a,regs+8
        bmi te_out
        mov linr,#0
te_out:
        ret

; Envelope for channel x. Its register is at regs + x*4.
env1:
        mov a,x
        asl a
        asl a
        mov y,a
        mov a,!regs+y
        and a,#$0F
        mov tmp,a           ; the period, or constant volume
        mov a,envs+x
        beq e_run
        mov a,#0
        mov envs+x,a
        mov a,#15
        mov env+x,a
        mov a,tmp
        mov envd+x,a
        ret
e_run:
        mov a,envd+x
        beq e_clock
        dec a
        mov envd+x,a
        ret
e_clock:
        mov a,tmp
        mov envd+x,a
        mov a,env+x
        beq e_zero
        dec a
        mov env+x,a
        ret
e_zero:
        mov a,!regs+y
        and a,#$20          ; loop
        beq e_out
        mov a,#15
        mov env+x,a
e_out:
        ret

tick_len:
        mov x,#3
tl_loop:
        ; halt: bit 5 of the channel's first register (bit 7 for the triangle)
        mov a,x
        asl a
        asl a
        mov y,a
        mov a,!regs+y
        cmp x,#2
        bne tl_not_tri
        lsr a
        lsr a
tl_not_tri:
        and a,#$20
        bne tl_next
        mov a,len+x
        beq tl_next
        dec a
        mov len+x,a
tl_next:
        dec x
        bpl tl_loop
        ret

tick_sweep:
        mov x,#0
        call sweep1
        mov x,#1
        call sweep1
        ret

; The pulse channel's period moves by itself shifted right, up or down.
sweep1:
        mov a,x
        asl a
        asl a
        mov y,a             ; y = 0 or 4
        mov a,!regs+1+y
        bpl sw_out          ; off
        mov tmp,a
        mov a,sweepd+x
        beq sw_clock
        dec a
        mov sweepd+x,a
sw_out:
        ret
sw_clock:
        mov a,tmp
        lsr a
        lsr a
        lsr a
        lsr a
        and a,#7
        mov sweepd+x,a
        mov a,tmp
        and a,#7
        beq sw_out
        mov tmp2,a          ; shift
        mov a,!regs+2+y
        mov ptr,a
        mov a,!regs+3+y
        and a,#7
        mov ptr+1,a
sw_shift:
        lsr ptr+1
        ror ptr
        dec tmp2
        bne sw_shift
        mov a,tmp
        and a,#8
        bne sw_down
        mov a,!regs+2+y
        clc
        adc a,ptr
        mov !regs+2+y,a
        mov a,!regs+3+y
        and a,#7
        adc a,ptr+1
        cmp a,#8
        bcs sw_out          ; over 11 bits: the NES mutes it and stops
        mov tmp2,a
        mov a,!regs+3+y
        and a,#$F8
        or a,tmp2
        mov !regs+3+y,a
        ret
sw_down:
        mov a,!regs+2+y
        setc
        sbc a,ptr
        mov !regs+2+y,a
        mov a,!regs+3+y
        and a,#7
        sbc a,ptr+1
        bcc sw_out
        mov tmp2,a
        mov a,!regs+3+y
        and a,#$F8
        or a,tmp2
        mov !regs+3+y,a
        ret

; The voices' volume, pitch and sample, from the registers.
update:
        ; pulse 1, pulse 2
        mov x,#0
        call pulse
        mov x,#1
        call pulse
        call triangle
        call noise
        mov x,#0
        call fiveb
        mov x,#1
        call fiveb
        mov x,#2
        call fiveb
        ret

; Pitch of DSP voice (a*16) from the period in ptr (up to 12 bits).
set_pitch:
        mov tmp,a
        mov a,ptr
        asl a
        mov y,a
        mov a,ptr+1
        rol a
        clc
        adc a,#PITCH_HI
        mov ptr+1,a
        mov ptr,#0
        mov a,[ptr]+y
        mov tmp2,a
        mov a,tmp
        or a,#2
        mov dspa,a
        mov dspd,tmp2
        inc y
        mov a,[ptr]+y
        mov tmp2,a
        mov a,tmp
        or a,#3
        mov dspa,a
        mov dspd,tmp2
        ret

; Volume of DSP voice x*16 from a.
set_vol:
        mov tmp2,a
        mov a,x
        asl a
        asl a
        asl a
        asl a
        mov dspa,a
        mov dspd,tmp2
        or a,#1
        mov dspa,a
        mov dspd,tmp2
        ret

pulse:
        mov a,x
        asl a
        asl a
        mov y,a
        mov a,!regs+2+y
        mov ptr,a
        mov a,!regs+3+y
        and a,#7
        mov ptr+1,a
        ; off if disabled, length out, or too short a period
        mov a,x
        beq p_bit0
        mov a,regs+$15
        and a,#2
        bra p_bit
p_bit0: mov a,regs+$15
        and a,#1
p_bit:  beq p_quiet
        mov a,len+x
        beq p_quiet
        mov a,ptr+1
        bne p_on
        mov a,ptr
        cmp a,#8
        bcc p_quiet
p_on:   ; duty picks the sample
        mov a,!regs+y
        and a,#$C0
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc a,#SRC_DUTY
        mov tmp,a
        mov a,x
        asl a
        asl a
        asl a
        asl a
        or a,#4
        mov dspa,a
        mov dspd,tmp
        mov a,x
        asl a
        asl a
        asl a
        asl a
        call set_pitch
        ; constant volume or the envelope's
        mov a,x
        asl a
        asl a
        mov y,a
        mov a,!regs+y
        and a,#$10
        beq p_env
        mov a,!regs+y
        and a,#$0F
        bra p_vol
p_env:  mov a,env+x
p_vol:  mov y,a
        mov a,!pulse_vol+y
        jmp set_vol
p_quiet:
        mov a,#0
        jmp set_vol

pulse_vol:
        .byte 0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45

triangle:
        mov x,#2
        mov a,regs+$15
        and a,#4
        beq t_quiet
        mov a,len+2
        beq t_quiet
        mov a,linc
        beq t_quiet
        mov a,regs+$A
        mov ptr,a
        mov a,regs+$B
        and a,#7
        mov ptr+1,a
        mov a,#$20
        call set_pitch
        mov x,#2
        mov a,#TRI_VOL
        jmp set_vol
t_quiet:
        ; The NES's triangle holds its level; a sudden stop clicks a little less like this.
        mov a,#0
        jmp set_vol

noise:
        mov x,#3
        mov a,regs+$15
        and a,#8
        beq n_quiet
        mov a,len+3
        beq n_quiet
        mov a,regs+$E
        and a,#$0F
        mov y,a
        mov a,!noise_clock+y
        or a,#$20
        mov dspa,#$6C
        mov dspd,a
        mov a,regs+$C
        and a,#$10
        beq n_env
        mov a,regs+$C
        and a,#$0F
        bra n_vol
n_env:  mov a,env+3
n_vol:  mov y,a
        mov a,!noise_vol+y
        jmp set_vol
n_quiet:
        mov a,#0
        jmp set_vol

noise_vol:
        .byte 0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30

; A 5B voice (x = 0-2) on DSP voice 5+x.
fiveb:
        mov a,x
        asl a
        mov y,a             ; y = register of the fine period
        mov a,!sb+y
        mov ptr,a
        mov a,!sb+1+y
        and a,#$0F
        mov ptr+1,a
        ; The 5B divides by the period itself, the table by period + 1.
        mov a,ptr
        bne fb_dec
        mov a,ptr+1
        beq fb_ok
        dec ptr+1
fb_dec: dec ptr
fb_ok:
        mov a,x
        clc
        adc a,#5
        asl a
        asl a
        asl a
        asl a
        call set_pitch
        ; tone enabled? the mixer's bits 0-2, low for on
        mov a,x
        mov y,a
        mov a,!tone_bit+y
        and a,sb+7
        bne fb_quiet
        mov a,!sb+8+y
        and a,#$0F
        mov y,a
        mov a,!sb_vol+y
        bra fb_vol
fb_quiet:
        mov a,#0
fb_vol: mov tmp,a
        mov a,x
        clc
        adc a,#5
        mov tmp2,a
        push x
        mov x,tmp2
        mov a,tmp
        call set_vol
        pop x
        ret

tone_bit:
        .byte 1,2,4
sb_vol:
        .byte 0,1,2,3,4,6,9,13,18,26,37,52,73,100,110,120

; DPCM: a has $4015's value. Stop it, and start the sample if bit 4 is set.
dpcm_start:
        mov dspa,#$5C
        mov dspd,#$10
        mov tmp,a
        and a,#$10
        beq dp_off
        ; find (bank, $4012, $4013) in the list
        mov y,#0
dp_find:
        mov a,!dpcm_list+y
        cmp a,#$FF
        beq dp_off
        cmp a,bank
        bne dp_next
        mov a,!dpcm_list+1+y
        cmp a,regs+$12
        bne dp_next
        mov a,!dpcm_list+2+y
        cmp a,regs+$13
        bne dp_next
        mov a,!dpcm_list+3+y
        mov tmp2,a
        mov dspa,#$44
        mov dspd,tmp2
        ; pitch from the rate
        mov a,regs+$10
        and a,#$0F
        asl a
        mov y,a
        mov dspa,#$42
        mov a,!dpcm_pitch+y
        mov dspd,a
        mov dspa,#$43
        mov a,!dpcm_pitch+1+y
        mov dspd,a
        mov x,#4
        mov a,#DPCM_VOL
        call set_vol
        mov dspa,#$5C
        mov dspd,#0
        mov dspa,#$4C
        mov dspd,#$10
        ret
dp_next:
        mov a,y
        clc
        adc a,#4
        mov y,a
        bra dp_find
dp_off:
        mov dspa,#$5C
        mov dspd,#0
        ret
