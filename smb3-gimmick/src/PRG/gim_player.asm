; Yumetaro (Gimmick!) player and star logic, mapped at $A000 through Gim_Call

GIMCALL_GNDMOV		= 0
GIMCALL_LEVELINIT	= 1
GIMCALL_STAR		= 2
GIMCALL_STANDENEMY	= 3
GIMCALL_POWERUP		= 4
GIMCALL_ANIMATE		= 5
GIMCALL_SLOPE		= 6
GIMCALL_CANNONBALL	= 7

Gim_Dispatch:
	LDA Gim_EntryL,Y
	STA Gim_Vector
	LDA Gim_EntryH,Y
	STA Gim_Vector+1
	JMP [Gim_Vector]

Gim_EntryL:	.byte LOW(Gim_GndMov), LOW(Gim_LevelInit), LOW(Gim_Star), LOW(Gim_StandOnEnemy), LOW(Gim_PowerUp), LOW(Gim_Animate), LOW(Gim_Slope), LOW(Gim_Cannonball)
Gim_EntryH:	.byte HIGH(Gim_GndMov), HIGH(Gim_LevelInit), HIGH(Gim_Star), HIGH(Gim_StandOnEnemy), HIGH(Gim_PowerUp), HIGH(Gim_Animate), HIGH(Gim_Slope), HIGH(Gim_Cannonball)

	; Temp_Var1 = queued suit + 1; Yumetaro stays small, power-ups become health instead
Gim_PowerUp:
	LDA #PLAYERSUIT_SMALL
	STA <Player_Suit

	LDA <Temp_Var1
	AND #$0F
	CMP #PLAYERSUIT_BIG+1
	BLT Gim_PowerUpRTS
	BEQ Gim_PowerUpHeal

	LDX Player_Current
	LDA Gim_MaxHealth,X
	CMP #GIM_HEALTHCAP
	BGE Gim_PowerUpFull
	INC Gim_MaxHealth,X
Gim_PowerUpFull:
	LDA Gim_MaxHealth,X
	STA Gim_Health
	RTS

Gim_PowerUpHeal:
	LDX Player_Current
	LDA Gim_Health
	CMP Gim_MaxHealth,X
	BGE Gim_PowerUpRTS
	INC Gim_Health
Gim_PowerUpRTS:
	RTS

	; X = object Yumetaro landed on / keeps standing on
Gim_StandOnEnemy:
	LDA <Objects_Y,X
	SUB #31
	STA <Player_Y
	LDA <Objects_YHi,X
	SBC #0
	STA <Player_YHi
	LDA #$00
	STA <Player_YVel
	STA <Player_InAir

	INX
	TXA
	DEX
	STA Gim_RideSlotNew
	CMP Gim_RideSlot
	BNE Gim_StandStore

	LDA <Objects_X,X
	SUB Gim_RideX
	STA <Temp_Var1
	LDA <Objects_XHi,X
	SBC Gim_RideXHi
	STA <Temp_Var2
	LDA <Player_X
	ADD <Temp_Var1
	STA <Player_X
	LDA <Player_XHi
	ADC <Temp_Var2
	STA <Player_XHi
	LDA <Temp_Var2
	JSR Gim_RideClamp

Gim_StandStore:
	LDA <Objects_X,X
	STA Gim_RideX
	LDA <Objects_XHi,X
	STA Gim_RideXHi
	RTS

	; A = high byte of how far a ride just carried Yumetaro. Walking stops at 16 from the left of the screen and
	; 232 from its right, but only when walking that way: a ride past them would count as crushed off the screen
Gim_RideClamp:
	BMI Gim_RideClampLeft
	LDA <Player_X
	SUB <Horz_Scroll
	STA <Temp_Var1
	LDA <Player_XHi
	SBC <Horz_Scroll_Hi
	BMI Gim_RideClampRTS
	BNE Gim_RideClampRight
	LDA <Temp_Var1
	CMP #233
	BLT Gim_RideClampRTS
Gim_RideClampRight:
	LDA #232
	BNE Gim_RideClampSet
Gim_RideClampLeft:
	LDA <Player_X
	SUB <Horz_Scroll
	STA <Temp_Var1
	LDA <Player_XHi
	SBC <Horz_Scroll_Hi
	BMI Gim_RideClampLow
	BNE Gim_RideClampRTS
	LDA <Temp_Var1
	CMP #16
	BGE Gim_RideClampRTS
Gim_RideClampLow:
	LDA #16
Gim_RideClampSet:
	ADD <Horz_Scroll
	STA <Player_X
	LDA <Horz_Scroll_Hi
	ADC #0
	STA <Player_XHi
Gim_RideClampRTS:
	RTS

Gim_RideRotate:
	LDA Gim_RideSlotNew
	BNE Gim_RideRotateDone
	LDX Gim_RideSlot
	BEQ Gim_RideRotateDone
	BMI Gim_RideRotateDone
	DEX

	LDA <Player_HaltGame
	ORA Player_IsDying
	ORA Level_PipeMove
	BNE Gim_RideRotateDone
	LDA <Player_YVel
	BMI Gim_RideRotateDone

	LDA Objects_State,X
	CMP #OBJSTATE_NORMAL
	BEQ Gim_RideStateOK
	CMP #OBJSTATE_SHELLED
	BEQ Gim_RideStateOK
	CMP #OBJSTATE_KICKED
	BNE Gim_RideRotateDone
Gim_RideStateOK:

	LDA <Player_X
	ADD #12
	STA <Temp_Var1
	LDA <Player_XHi
	ADC #0
	STA <Temp_Var2
	LDA <Temp_Var1
	SUB <Objects_X,X
	STA <Temp_Var1
	LDA <Temp_Var2
	SBC <Objects_XHi,X
	BNE Gim_RideRotateDone
	LDA <Temp_Var1
	CMP #25
	BGE Gim_RideRotateDone

	LDA <Player_Y
	ADD #31+8
	STA <Temp_Var1
	LDA <Player_YHi
	ADC #0
	STA <Temp_Var2
	LDA <Temp_Var1
	SUB <Objects_Y,X
	STA <Temp_Var1
	LDA <Temp_Var2
	SBC <Objects_YHi,X
	BNE Gim_RideRotateDone
	LDA <Temp_Var1
	CMP #17
	BGE Gim_RideRotateDone

	JSR Gim_StandOnEnemy

Gim_RideRotateDone:
	LDA Gim_RideSlotNew
	STA Gim_RideSlot
	LDA #$00
	STA Gim_RideSlotNew
	RTS

	; X = special object slot of a live cannonball. Ridden special objects are Gim_RideSlot $80 | slot.
	; Temp_Var1 -> 0 = nothing, 1 = knocked out by the star, $FF = hurts Yumetaro
Gim_Cannonball:
	LDA #$00
	STA <Temp_Var1

	LDA Star_State
	CMP #$01
	BNE Gim_CannonPlayer
	LDA Star_X
	ADD #12
	SUB SpecialObj_XLo,X
	CMP #24
	BGE Gim_CannonPlayer
	LDA Star_Y
	ADD #12
	STA <Temp_Var2
	LDA Star_YHi
	ADC #0
	STA <Temp_Var3
	LDA <Temp_Var2
	SUB SpecialObj_YLo,X
	STA <Temp_Var2
	LDA <Temp_Var3
	SBC SpecialObj_YHi,X
	BNE Gim_CannonPlayer
	LDA <Temp_Var2
	CMP #24
	BGE Gim_CannonPlayer

	LDA #$01
	STA SpecialObj_Data,X
	STA <Temp_Var1
	LDA #-$30
	STA SpecialObj_YVel,X
	LDA #$0C
	LDY Star_XVel
	BPL Gim_CannonKillXVel
	LDA #-$0C
Gim_CannonKillXVel:
	STA SpecialObj_XVel,X
	LDA Sound_QPlayer
	ORA #SND_PLAYERKICK
	STA Sound_QPlayer
	RTS

Gim_CannonPlayer:
	LDA Player_IsDying
	ORA Player_OffScreen
	BNE Gim_CannonPlayerRTS

	LDA <Player_X
	ADD #12
	SUB SpecialObj_XLo,X
	STA <Temp_Var3
	CMP #25
	BGE Gim_CannonPlayerRTS

	LDA SpecialObj_YLo,X
	SUB <Player_Y
	STA <Temp_Var2

	TXA
	ORA #$80
	CMP Gim_RideSlot
	BNE Gim_CannonNotRiding
	LDA <Player_YVel
	BMI Gim_CannonPlayerRTS
	LDA <Temp_Var2
	SUB #16
	CMP #24
	BLT Gim_CannonStand
Gim_CannonPlayerRTS:
	RTS

Gim_CannonNotRiding:
	LDA <Temp_Var2
	SUB #16
	CMP #16
	BGE Gim_CannonRTS
	LDA <Temp_Var2
	CMP #19
	BLT Gim_CannonSide
	LDA Player_StarInv
	BNE Gim_CannonSide
	LDA <Player_YVel
	BMI Gim_CannonRTS

Gim_CannonStand:
	LDA SpecialObj_YLo,X
	SUB #31
	STA <Player_Y
	LDA SpecialObj_YHi,X
	SBC #0
	STA <Player_YHi
	LDA #$00
	STA <Player_YVel
	STA <Player_InAir

	; Cannonballs fly through terrain; once the ground reaches Yumetaro's feet he steps off onto it
	TXA
	PHA
	LDA #$08
	STA <Temp_Var1
	LDA #$1F
	STA <Temp_Var2
	JSR Gim_PlayerSetPoint
	JSR Gim_RiderFloor
	PLA
	TAX
	LDA #$00
	STA <Temp_Var1
	BCC Gim_CannonRide
	LDA <Temp_Var14
	AND #$F0
	SUB #32
	STA <Player_Y
	LDA <Temp_Var13
	SBC #0
	STA <Player_YHi
	RTS

Gim_CannonRide:
	TXA
	ORA #$80
	STA Gim_RideSlotNew
	CMP Gim_RideSlot
	BNE Gim_CannonStore

	LDA SpecialObj_XLo,X
	SUB Gim_RideX
	STA <Temp_Var2
	LDY #$00
	LDA <Temp_Var2
	BPL Gim_CannonCarry
	DEY
Gim_CannonCarry:
	ADD <Player_X
	STA <Player_X
	TYA
	ADC <Player_XHi
	STA <Player_XHi
	TYA
	JSR Gim_RideClamp

Gim_CannonStore:
	LDA SpecialObj_XLo,X
	STA Gim_RideX
Gim_CannonRTS:
	RTS

Gim_CannonSide:
	LDA <Temp_Var3
	SUB #1
	CMP #20
	BGE Gim_CannonRTS
	LDA #$FF
	STA <Temp_Var1
	RTS

Gim_LevelInit:
	LDA #$00
	STA Gim_Frame
	STA Gim_AnimCnt
	STA Gim_JumpHold
	STA Gim_RideSlot
	STA Gim_RideSlotNew
	STA Star_State
	LDX Player_Current
	LDA Gim_MaxHealth,X
	STA Gim_Health
	RTS

Gim_Slope:
	STX Gim_OnSlope
	LDA <Player_XVel
	JSR Gim_SlopeVel
	STA <Player_XVel
	RTS

	; A = X velocity, X = slope effect (Slope_PlayerVel_Effect) -> A = X velocity pulled downhill
Gim_SlopeVel:
	STA <Temp_Var1
	TXA
	BEQ Gim_SlopeVelNone
	BMI Gim_SlopeVelLeft
	CMP #$03
	BLT Gim_SlopeVelGentleR
	LDA <Counter_1
	AND #$01
	ORA #$02
	ADD <Temp_Var1
	CMP #GIM_SLOPESTEEPMAX
	BMI Gim_SlopeVelRTS
	LDA #GIM_SLOPESTEEPMAX
	RTS
Gim_SlopeVelGentleR:
	LDA <Temp_Var1
	CMP #GIM_SLOPEGENTLEMAX
	BPL Gim_SlopeVelRTS
	ADD #1
	RTS
Gim_SlopeVelLeft:
	CMP #-$02
	BGE Gim_SlopeVelGentleL
	LDA <Counter_1
	AND #$01
	ORA #$02
	STA <Temp_Var2
	LDA <Temp_Var1
	SUB <Temp_Var2
	CMP #-GIM_SLOPESTEEPMAX
	BPL Gim_SlopeVelRTS
	LDA #-GIM_SLOPESTEEPMAX
	RTS
Gim_SlopeVelGentleL:
	LDA <Temp_Var1
	CMP #-GIM_SLOPEGENTLEMAX
	BMI Gim_SlopeVelRTS
	SUB #1
	RTS
Gim_SlopeVelNone:
	LDA <Temp_Var1
Gim_SlopeVelRTS:
	RTS

Gim_WalkFrames:
	.byte 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4
	.byte 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7
GIM_WALKCYCLE = 61

Gim_GndMov:
	LDA Sound_QLevel2
	AND #~SND_LEVELSKID
	STA Sound_QLevel2

	LDA #$02
	LDY Player_Slippery
	BEQ Gim_SetStep
	LDA <Counter_1
	AND #$01
Gim_SetStep:
	STA <Temp_Var1

	LDA Player_FlashInv
	CMP #GIM_STUNTIME
	BGE Gim_HDone

	LDA <Pad_Holding
	AND #PAD_RIGHT
	BEQ Gim_NotRight
	LDA <Player_XVel
	BMI Gim_AddStep
	CMP #GIM_WALKMAX
	BGE Gim_HDone
Gim_AddStep:
	ADD <Temp_Var1
	STA <Player_XVel
	JMP Gim_HDone

Gim_NotRight:
	LDA <Pad_Holding
	AND #PAD_LEFT
	BEQ Gim_HDone
	LDA <Player_XVel
	BPL Gim_SubStep
	CMP #-GIM_WALKMAX
	BLT Gim_HDone
Gim_SubStep:
	SUB <Temp_Var1
	STA <Player_XVel

Gim_HDone:
	LDY Gim_OnSlope
	LDA #$00
	STA Gim_OnSlope
	LDA <Player_InAir
	BNE Gim_FrictionDone
	TYA
	BNE Gim_FrictionDone
	LDA Player_Slippery
	BEQ Gim_Friction
	LDA <Counter_1
	AND #$07
	BNE Gim_FrictionDone
Gim_Friction:
	LDA <Player_XVel
	BEQ Gim_FrictionDone
	BMI Gim_FrictionNeg
	DEC <Player_XVel
	JMP Gim_FrictionDone
Gim_FrictionNeg:
	INC <Player_XVel
Gim_FrictionDone:

	; Bolt lifts, parabeetles and rotating platforms carry him through the air, and say he may jump from them
	LDY Player_AllowAirJump
	BEQ Gim_JumpOnGround
	DEC Player_AllowAirJump
	BNE Gim_JumpAllowed
Gim_JumpOnGround:
	LDA <Player_InAir
	BNE Gim_NoJump
Gim_JumpAllowed:
	LDA Player_FlashInv
	CMP #GIM_STUNTIME
	BGE Gim_NoJump
	LDA <Pad_Input
	AND #PAD_A
	BEQ Gim_NoJump
	LDA #GIM_JUMPVEL
	STA <Player_YVel
	LDA #$01
	STA <Player_InAir
	STA Gim_JumpHold
	LDA #$00
	STA Player_AllowAirJump
	LDA #GIMSND_JUMP
	STA Gim_SndQ
Gim_NoJump:

	LDA Gim_JumpHold
	BEQ Gim_JumpCutDone
	LDA <Pad_Holding
	AND #PAD_A
	BNE Gim_JumpCutDone
	LDA <Player_YVel
	BPL Gim_JumpCutClear
	CMP #GIM_JUMPCUT
	BGE Gim_JumpCutClear
	LDA #GIM_JUMPCUT
	STA <Player_YVel
Gim_JumpCutClear:
	LDA #$00
	STA Gim_JumpHold
Gim_JumpCutDone:

	LDA <Player_InAir
	BEQ Gim_GravityDone
	; Vertical levels scroll down at most 4 pixels a frame; falling faster drops him off the screen, which kills
	LDY #GIM_FALLMAX
	LDA Level_7Vertical
	BEQ Gim_GravityAdd
	LDY #GIM_FALLMAXVERT
Gim_GravityAdd:
	STY <Temp_Var1
	LDA <Player_YVel
	ADD #GIM_GRAVITY
	BVS Gim_GravityMax
	BMI Gim_GravitySet
	CMP <Temp_Var1
	BLT Gim_GravitySet
Gim_GravityMax:
	LDA <Temp_Var1
Gim_GravitySet:
	STA <Player_YVel
Gim_GravityDone:

	JMP Gim_Animate


Gim_Animate:
	LDA #$01
	STA Gim_Animated
	LDX #$00
	LDA <Counter_1
	AND #$DC
	BNE Gim_NoBlink
	INX
Gim_NoBlink:
	STX Gim_Frame

	LDA Player_Slippery
	BEQ Gim_AnimBySpeed
	LDA <Pad_Holding
	AND #(PAD_LEFT | PAD_RIGHT)
	BEQ Gim_AnimAir
	LDA #$00
	BEQ Gim_AnimStep

Gim_AnimBySpeed:
	LDA <Player_XVel
	BPL Gim_AnimAbs
	NEG
Gim_AnimAbs:
	CMP #$02
	BGE Gim_AnimStep
	LDX #$04
	STX Gim_AnimCnt
	LDA <Pad_Holding
	AND #(PAD_LEFT | PAD_RIGHT)
	BEQ Gim_AnimAir

Gim_AnimStep:
	LSR A
	LSR A
	LSR A
	LSR A
	SEC
	ADC Gim_AnimCnt
	CMP #GIM_WALKCYCLE
	BLT Gim_AnimNoWrap
	SBC #GIM_WALKCYCLE
Gim_AnimNoWrap:
	STA Gim_AnimCnt
	TAX
	LDA Gim_WalkFrames,X
	STA Gim_Frame

Gim_AnimAir:
	LDA <Player_InAir
	BEQ Gim_AnimHurt
	LDA #GIMF_JUMP
	STA Gim_Frame
	LDA #$3B
	STA Gim_AnimCnt
Gim_AnimHurt:
	LDA Player_FlashInv
	SUB #GIM_STUNTIME
	BCC Gim_AnimDone
	TAX
	LDA Gim_HurtFrames,X
	STA Gim_Frame
Gim_AnimDone:
	RTS

	; Indexed by Player_FlashInv - GIM_STUNTIME: squash, then dizzy stars
Gim_HurtFrames:
	.byte $14, $14, $13, $13, $12, $12, $11, $11, $10, $10, $0F, $0F, $0E
	.byte $0E, $0D, $0D, $0C, $0C, $0C, $0C, $0A, $0A, $0C, $0C, $0C, $0C
