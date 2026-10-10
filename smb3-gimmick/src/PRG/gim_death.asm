; Gimmick! death jingle player, mapped at $C000 by GimDeath_Update in the sound engine

	; Carry set: the jingle wrote the APU this frame. Clear during the leading silence, so the music stop gets processed
GimDeath_Play:
	LDA Gim_DeathDelay
	BEQ GimDeath_Frame
	DEC Gim_DeathDelay
	CLC
	RTS

GimDeath_Frame:
	LDY #$00
GimDeath_Write:
	LDA [Gim_DeathPtrL],Y
	BMI GimDeath_FrameEnd
	TAX
	INY
	LDA [Gim_DeathPtrL],Y
	STA PAPU_CTL1,X
	INY
	BNE GimDeath_Write

GimDeath_FrameEnd:
	CMP #$FF
	BNE GimDeath_End
	INY
	TYA
	ADD <Gim_DeathPtrL
	STA <Gim_DeathPtrL
	BCC GimDeath_Played
	INC <Gim_DeathPtrH
GimDeath_Played:
	SEC
	RTS

GimDeath_End:
	LDA #$00
	STA <Gim_DeathPtrH
	SEC
	RTS

	.include "PRG/gim_deathdata.asm"
