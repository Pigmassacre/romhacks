; Yumetaro's star: charge, throw, bounce, kill enemies, ride

STAR_TILE	= $29
SPARKLE_TILE	= $2B
STAR_PAL	= SPR_PAL3

Star_BBoxY:	.byte $18, $18, $28, $18, $18, $18, $18, $18, $18, $18, $20, $18, $18, $28, $18, $18
Star_BBoxX:	.byte $18, $18, $18, $18, $18, $18, $18, $18, $18, $18, $18, $18, $18, $20, $18, $18

Gim_Star:
	LDA #$00
	STA Gim_Animated
	JSR Gim_DropEndCard
	JSR Gim_RideRotate
	LDA Level_PipeMove
	BEQ Gim_StarNoPipe
	LDA #$00
	STA Star_State
	STA Star_Ridden
Gim_StarNoPipe:
	LDA <Player_HaltGame
	ORA Player_HaltTick
	ORA Player_IsDying
	ORA Level_PipeMove
	BEQ Gim_StarActive
	JMP Gim_StarDraw

	; Every level spawns the goal card at row $15, too high for Yumetaro's jump
Gim_DropEndCard:
	LDX #$07
Gim_DropEndCardLoop:
	LDA Level_ObjectID,X
	CMP #OBJ_ENDLEVELCARD
	BNE Gim_DropEndCardNext
	LDA <Objects_DetStat,X
	BNE Gim_DropEndCardNext
	LDA <Objects_YHi,X
	CMP #$01
	BNE Gim_DropEndCardNext
	LDA <Objects_Y,X
	CMP #$50
	BNE Gim_DropEndCardNext
	ADD #GIM_CARDDROP
	STA <Objects_Y,X
Gim_DropEndCardNext:
	DEX
	BPL Gim_DropEndCardLoop
	RTS

Gim_StarActive:
	JSR Gim_StarInput

	LDA Star_State
	BEQ Gim_StarLogicDone
	CMP #$01
	BEQ Gim_StarIsThrown
	CMP #$D0
	BGE Gim_StarVanishing

	JSR Gim_StarFollowPlayer
	JMP Gim_StarLogicDone

Gim_StarVanishing:
	INC Star_State
	LDA Star_State
	CMP #$E0
	BNE Gim_StarLogicDone
	LDA #$00
	STA Star_State
	BEQ Gim_StarLogicDone

Gim_StarIsThrown:
	JSR Gim_StarThrown
	LDA Star_State
	CMP #$01
	BNE Gim_StarLogicDone
	JSR Gim_StarCalcScreen
	JSR Gim_StarHitEnemies
	JSR Gim_StarRide

Gim_StarLogicDone:
	JSR Gim_RideSprites
	JMP Gim_StarDraw

	; Yumetaro is drawn before objects and the star move and snap him; shift his sprites to where he ended up
Gim_RideSprites:
	LDA <Player_Y
	SUB Level_VertScroll
	TAY
	SUB <Player_SpriteY
	STA <Temp_Var1
	STY <Player_SpriteY
	LDA <Player_X
	SUB <Horz_Scroll
	TAY
	SUB <Player_SpriteX
	STA <Temp_Var2
	STY <Player_SpriteX
	ORA <Temp_Var1
	BEQ Gim_RideSpritesRTS

	LDX Player_SprOff
	LDY #6
Gim_RideSpritesLoop:
	LDA Sprite_RAM+$00,X
	CMP #$F0
	BGE Gim_RideSpritesNext
	ADD <Temp_Var1
	STA Sprite_RAM+$00,X
	LDA Sprite_RAM+$03,X
	ADD <Temp_Var2
	STA Sprite_RAM+$03,X
	LDA <Temp_Var2
	BMI Gim_RideSpritesLeft
	BCC Gim_RideSpritesNext
	BCS Gim_RideSpritesHide
Gim_RideSpritesLeft:
	BCS Gim_RideSpritesNext
Gim_RideSpritesHide:
	LDA #$F8
	STA Sprite_RAM+$00,X
Gim_RideSpritesNext:
	INX
	INX
	INX
	INX
	DEY
	BNE Gim_RideSpritesLoop
Gim_RideSpritesRTS:
	RTS


Gim_StarInput:
	LDA Star_State
	CMP #$01
	BEQ Gim_StarInputRTS
	CMP #$D0
	BGE Gim_StarInputRTS

	LDA Player_FlashInv
	CMP #GIM_STUNTIME
	BGE Gim_StarReleased

	LDA <Pad_Holding
	AND #PAD_B
	BEQ Gim_StarReleased

	LDA Star_State
	BNE Gim_StarCharge
	LDA #GIMSND_CHARGE
	STA Gim_SndQ
	LDA #$7F
	STA Star_State
	JSR Gim_StarFollowPlayer
Gim_StarCharge:
	CMP #$A9
	BEQ Gim_StarInputRTS
	INC Star_State
Gim_StarInputRTS:
	RTS

Gim_StarReleased:
	LDA Star_State
	CMP #$A0
	BGE Gim_StarThrow
	LDA #$00
	STA Star_State
	RTS

Gim_StarThrow:
	LDA #$01
	STA Star_State
	LDA #$00
	STA Star_XFrac
	STA Star_YFrac
	STA Star_StillCnt
	STA Star_Wall
	STA Star_Floor
	STA Star_PrevFloor
	STA Star_Standable
	STA Star_Ridden

	JSR Gim_StarFollowPlayer

	LDA <Player_YVel
	CMP #$80
	ROR A
	CLC
	ADC #$30
	BVC Gim_StarThrowYVel
	LDA #$7F
Gim_StarThrowYVel:
	STA Star_YVel
	STA Star_SavedYVel

	LDY #$28
	LDA <Player_FlipBits
	AND #SPR_HFLIP
	BNE Gim_StarThrowRight
	LDY #-$28
Gim_StarThrowRight:
	STY <Temp_Var1
	LDA <Player_XVel
	CMP #$80
	ROR A
	CLC
	ADC <Temp_Var1
	STA Star_XVel
	STA Star_SavedXVel

	LDA #GIMSND_THROW
	STA Gim_SndQ
	RTS


Gim_StarFollowPlayer:
	LDA <Player_X
	STA Star_X
	LDA <Player_XHi
	STA Star_XHi
	LDA <Player_Y
	STA Star_Y
	LDA <Player_YHi
	STA Star_YHi
	LDA Star_State
	RTS


Gim_StarVanish:
	LDA #$D0
	STA Star_State
	LDA #$00
	STA Star_Ridden
	RTS


Gim_StarThrown:
	LDA Star_Wall
	BEQ Gim_StarNoWall
	LDA Star_SavedXVel
	NEG
	STA Star_XVel
	LDA #$01
	STA Star_Standable
Gim_StarNoWall:
	LDA Star_XVel
	STA Star_SavedXVel

	LDA #8
	STA <Temp_Var1
	STA <Temp_Var2
	JSR Gim_StarSetPoint
	JSR Gim_TileSolidAll
	BCS Gim_StarVanish

	LDA Star_XVel
	ORA Star_YVel
	BNE Gim_StarMoving
	INC Star_StillCnt
	LDA Star_StillCnt
	CMP #8
	BGE Gim_StarVanish
Gim_StarMoving:

	LDA Star_Floor
	BEQ Gim_StarNoFloor
	LDA Star_PrevFloor
	BNE Gim_StarBounce
	LDA #GIMSND_BOUNCE
	STA Gim_SndQ
Gim_StarBounce:
	LDA #8
	SUB Star_SavedYVel
	STA Star_YVel
	LDA #$01
	STA Star_Standable
Gim_StarNoFloor:
	LDA Star_YVel
	STA Star_SavedYVel
	LDA Star_Floor
	STA Star_PrevFloor

	LDA Star_X
	STA Star_PrevX
	LDA Star_XHi
	STA Star_PrevXHi

	LDA Star_Floor
	BEQ Gim_StarFrictionDone
	LDA Star_OnSlope
	BNE Gim_StarFrictionDone
	LDA Player_Slippery
	BEQ Gim_StarFriction
	LDA <Counter_1
	AND #$07
	BNE Gim_StarFrictionDone
Gim_StarFriction:
	LDA Star_XVel
	BEQ Gim_StarFrictionDone
	BMI Gim_StarFrictionNeg
	DEC Star_XVel
	JMP Gim_StarFrictionDone
Gim_StarFrictionNeg:
	INC Star_XVel
Gim_StarFrictionDone:

	LDA Star_YVel
	CLC
	ADC #GIM_GRAVITY
	BVC Gim_StarGravity
	LDA #$7F
Gim_StarGravity:
	STA Star_YVel

	LDA #$00
	STA Star_Wall
	STA Star_Floor

	LDA Star_XVel
	JSR Gim_VelSplit
	ADD Star_XFrac
	STA Star_XFrac
	LDA <Temp_Var3
	ADC Star_X
	STA Star_X
	LDA <Temp_Var4
	ADC Star_XHi
	STA Star_XHi

	JSR Gim_StarWalls

	LDA Star_YVel
	JSR Gim_VelSplit
	ADD Star_YFrac
	STA Star_YFrac
	LDA <Temp_Var3
	ADC Star_Y
	STA Star_Y
	LDA <Temp_Var4
	ADC Star_YHi
	STA Star_YHi

	JSR Gim_StarFloors

	LDA Star_YHi
	BMI Gim_StarYOK
	BEQ Gim_StarYOK
	LDA Level_7Vertical
	BNE Gim_StarYOK
	LDA Star_Y
	CMP #$C0
	BLT Gim_StarYOK
	LDA #$00
	STA Star_State
	RTS
Gim_StarYOK:

	LDA Star_X
	SUB <Horz_Scroll
	LDA Star_XHi
	SBC <Horz_Scroll_Hi
	BEQ Gim_StarXOK
	LDA #$00
	STA Star_State
Gim_StarXOK:
	RTS


	; Splits 4.4 velocity A into fraction (A, carry cleared) and sign extended whole part (Temp_Var3/4)
Gim_VelSplit:
	PHA
	LDY #$00
	LSR A
	LSR A
	LSR A
	LSR A
	CMP #$08
	BLT Gim_VelSplitPos
	ORA #$F0
	DEY
Gim_VelSplitPos:
	STA <Temp_Var3
	STY <Temp_Var4
	PLA
	ASL A
	ASL A
	ASL A
	ASL A
	CLC
	RTS


Gim_StarWalls:
	LDA Star_XVel
	BEQ Gim_StarWallsRTS
	BMI Gim_StarWallLeft

	LDA #15
	STA <Temp_Var1
	JSR Gim_StarWallProbe
	BCC Gim_StarWallsRTS
	PHA
	LDA <Temp_Var16
	AND #$F0
	SUB #16
	STA Star_X
	LDA <Temp_Var15
	SBC #0
	STA Star_XHi
	JMP Gim_StarHitWall

Gim_StarWallLeft:
	LDA #0
	STA <Temp_Var1
	JSR Gim_StarWallProbe
	BCC Gim_StarWallsRTS
	PHA
	LDA <Temp_Var16
	AND #$F0
	ADD #16
	STA Star_X
	LDA <Temp_Var15
	ADC #0
	STA Star_XHi

Gim_StarHitWall:
	PLA
	JSR Gim_StarBump
	LDA #$00
	STA Star_XVel
	STA Star_XFrac
	LDA #$01
	STA Star_Wall
Gim_StarWallsRTS:
	RTS

	; Carry set if either side probe at X offset Temp_Var1 is solid; leaves Temp_Var15/16 at the probe X
Gim_StarWallProbe:
	LDA #4
	STA <Temp_Var2
	JSR Gim_StarSetPoint
	JSR Gim_TileSolidAll
	BCS Gim_StarWallProbeRTS
	LDA #11
	STA <Temp_Var2
	JSR Gim_StarSetPoint
	JSR Gim_TileSolidAll
Gim_StarWallProbeRTS:
	RTS


Gim_StarFloors:
	LDA Star_OnSlope
	STA <Temp_Var10
	LDA #$00
	STA Star_OnSlope
	LDA Star_YVel
	BPL Gim_StarFloorsDown
	JMP Gim_StarCeiling
Gim_StarFloorsDown:

	LDA Level_SlopeEn
	BEQ Gim_StarFloorsFlat
	LDA #8
	STA <Temp_Var1
	LDA #16
	STA <Temp_Var2
	JSR Gim_StarSetPoint
	JSR Gim_StarSlopeAt
	BCS Gim_StarSlopeLand
	LDA <Temp_Var11
	BNE Gim_StarSlopeIn
	JSR Gim_StarSlopeOver
	BCS Gim_StarSlopeLand
	LDA <Temp_Var10
	BEQ Gim_StarFloorsFlat
	BNE Gim_StarSlopeBelow
Gim_StarSlopeIn:
	LDA <Temp_Var10
	BEQ Gim_StarFloorsFlat
	LDA <Temp_Var14
	AND #$0F
	ADD #GIM_STARSLOPESTICK
	CMP <Temp_Var12
	BLT Gim_StarFloorsFlat
	LDA <Temp_Var12
	JMP Gim_StarSlopeLand
Gim_StarSlopeBelow:
	LDA #16 + GIM_STARSLOPESTICK
	STA <Temp_Var2
	JSR Gim_StarSetPoint
	JSR Gim_StarSlopeAt
	BCS Gim_StarSlopeLand

Gim_StarFloorsFlat:
	LDA #16
	STA <Temp_Var2
	LDA #4
	STA <Temp_Var1
	JSR Gim_StarSetPoint
	JSR Gim_StarFlatTop
	BCS Gim_StarFloorHit
	LDA #11
	STA <Temp_Var1
	JSR Gim_StarSetPoint
	JSR Gim_StarFlatTop
	BCC Gim_StarFloorsRTS
Gim_StarFloorHit:
	LDA <Temp_Var14
	AND #$0F
	CMP #8
	BGE Gim_StarFloorsRTS
	LDA <Temp_Var14
	AND #$F0
	SUB #16
	STA Star_Y
	LDA <Temp_Var13
	SBC #0
	STA Star_YHi
	LDA #$00
	STA Star_YVel
	STA Star_YFrac
	LDA #$01
	STA Star_Floor
Gim_StarFloorsRTS:
	RTS

	; A = surface height within the tile at Temp_Var13/14
Gim_StarSlopeLand:
	STA <Temp_Var12
	LDA <Temp_Var14
	AND #$F0
	ORA <Temp_Var12
	SUB #16
	STA Star_Y
	LDA <Temp_Var13
	SBC #0
	STA Star_YHi
	LDA #$00
	STA Star_YVel
	STA Star_YFrac
	LDA #$01
	STA Star_Floor
	LDX <Temp_Var11
	STX Star_OnSlope
	LDA Star_XVel
	JSR Gim_SlopeVel
	STA Star_XVel
	RTS

	; Carry set if the point Temp_Var13-16 is on or below the surface of a slope tile:
	; A = Temp_Var12 = surface height within the tile, Temp_Var11 = slope effect (0 if not a slope tile)
Gim_StarSlopeAt:
	JSR Gim_TileAt
	JSR Gim_TileShape
	TAY
	LDA Slope_PlayerVel_Effect,Y
	BEQ Gim_StarSlopeAtNo
	STA <Temp_Var11
	TYA
	ASL A
	ASL A
	ASL A
	ASL A
	STA <Temp_Var12
	LDA <Temp_Var16
	AND #$0F
	ORA <Temp_Var12
	TAY
	LDA Slope_LUT,Y
	AND #$0F
	STA <Temp_Var12
	LDA <Temp_Var14
	AND #$0F
	CMP <Temp_Var12
	LDA <Temp_Var12
	RTS
Gim_StarSlopeAtNo:
	STA <Temp_Var11
	CLC
	RTS

	; Point Temp_Var13-16 in a solid non-slope tile under a slope tile: the star is below that slope's surface.
	; Carry set with A = surface height, Temp_Var13/14 moved up into the slope tile
Gim_StarSlopeOver:
	JSR Gim_TileAt
	CMP Tile_AttrTable,Y
	BCC Gim_StarSlopeOverRTS
	LDA <Temp_Var2
	SUB #16
	STA <Temp_Var2
	JSR Gim_StarSetPoint
	JSR Gim_StarSlopeAt
	LDA <Temp_Var11
	BEQ Gim_StarSlopeOverNo
	LDA <Temp_Var12
	SEC
	RTS
Gim_StarSlopeOverNo:
	CLC
Gim_StarSlopeOverRTS:
	RTS

	; Like Gim_TileSolidTop, but slope tiles only count through Gim_StarSlopeAt
Gim_StarFlatTop:
	JSR Gim_TileAt
	CMP Tile_AttrTable,Y
	BCC Gim_StarFlatTopRTS
	JSR Gim_TileShape
	TAY
	LDA Slope_PlayerVel_Effect,Y
	CMP #$01
	LDA #$00
	BCC Gim_StarFlatTopSolid
	CLC
	RTS
Gim_StarFlatTopSolid:
	SEC
Gim_StarFlatTopRTS:
	RTS

	; A = tile, Y = quadrant (from Gim_TileAt) -> A = slope shape (0 outside sloped levels or below the solid tiles)
Gim_TileShape:
	LDX Level_SlopeEn
	BEQ Gim_TileShapeNone
	CMP Tile_AttrTable,Y
	BLT Gim_TileShapeNone
	SUB Tile_AttrTable,Y
	STA <Temp_Var12
	TYA
	ASL A
	TAX
	LDA Level_SlopeSetByQuad,X
	STA <Temp_Var3
	LDA Level_SlopeSetByQuad+1,X
	STA <Temp_Var4
	LDY <Temp_Var12
	LDA [Temp_Var3],Y
	RTS
Gim_TileShapeNone:
	LDA #$00
	RTS

Gim_StarCeiling:
	LDA #0
	STA <Temp_Var2
	LDA #4
	STA <Temp_Var1
	JSR Gim_StarSetPoint
	JSR Gim_TileSolidAll
	BCS Gim_StarCeilingHit
	LDA #11
	STA <Temp_Var1
	JSR Gim_StarSetPoint
	JSR Gim_TileSolidAll
	BCS Gim_StarCeilingHit
	RTS
Gim_StarCeilingHit:
	PHA
	LDA <Temp_Var14
	AND #$F0
	ADD #16
	STA Star_Y
	LDA <Temp_Var13
	ADC #0
	STA Star_YHi
	LDA #$00
	STA Star_YVel
	STA Star_YFrac
	PLA

	; A = tile hit, Temp_Var13-16 = point; bump ? blocks and bricks like a kicked shell
Gim_StarBump:
	LDX <Temp_Var13
	STX ObjTile_DetYHi
	LDX <Temp_Var14
	STX ObjTile_DetYLo
	LDX <Temp_Var15
	STX ObjTile_DetXHi
	LDX <Temp_Var16
	STX ObjTile_DetXLo
	JMP Object_BumpBlocks


	; Temp_Var13/14 = Star Y + Temp_Var2, Temp_Var15/16 = Star X + Temp_Var1
Gim_StarSetPoint:
	LDA Star_Y
	ADD <Temp_Var2
	STA <Temp_Var14
	LDA Star_YHi
	ADC #0
	STA <Temp_Var13
	LDA Star_X
	ADD <Temp_Var1
	STA <Temp_Var16
	LDA Star_XHi
	ADC #0
	STA <Temp_Var15
	RTS

Gim_TileSolidAll:
	JSR Gim_TileAt
	CMP Tile_AttrTable+4,Y
	RTS

Gim_TileSolidTop:
	JSR Gim_TileAt
	CMP Tile_AttrTable,Y
	RTS

	; Tile at Temp_Var13/14 (Y), Temp_Var15/16 (X) -> A, quadrant -> Y
Gim_TileAt:
	LDA <Temp_Var13
	BMI Gim_TileAir
	LDA Level_7Vertical
	BNE Gim_TileVert

	LDA <Temp_Var13
	BEQ Gim_TileRowOK
	CMP #$01
	BNE Gim_TileAir
	LDA <Temp_Var14
	CMP #$B0
	BGE Gim_TileAir
Gim_TileRowOK:
	LDA <Temp_Var15
	AND #$0F
	ASL A
	TAX
	LDA Tile_Mem_Addr,X
	STA <Map_Tile_AddrL
	LDA Tile_Mem_Addr+1,X
	ADC <Temp_Var13
	STA <Map_Tile_AddrH
	LDA <Temp_Var16
	LSR A
	LSR A
	LSR A
	LSR A
	STA <Temp_Var12
	LDA <Temp_Var14
	AND #$F0
	ORA <Temp_Var12
	TAY
	LDA [Map_Tile_AddrL],Y
	JMP Gim_TileQuad

Gim_TileVert:
	LDA <Temp_Var15
	PHA
	JSR Player_GetTileV
	PLA
	STA <Temp_Var15
	LDA <Level_Tile

Gim_TileQuad:
	PHA
	ASL A
	ROL A
	ROL A
	AND #$03
	TAY
	PLA
	RTS

Gim_TileAir:
	LDA #$00
	TAY
	RTS


	; Star_SprX/Y = screen position, Star_SprVis = visible halves
Gim_StarCalcScreen:
	LDA #$00
	STA Star_SprVis

	LDA Star_Y
	SUB Level_VertScroll
	STA Star_SprY
	LDA Star_YHi
	SBC Level_VertScrollH
	BNE Gim_StarCalcRTS
	LDA Star_SprY
	CMP #$D0
	BGE Gim_StarCalcRTS

	LDA Star_X
	SUB <Horz_Scroll
	STA Star_SprX
	LDA Star_XHi
	SBC <Horz_Scroll_Hi
	STA <Temp_Var1
	BNE Gim_StarCalcLeftOff
	LDA #$01
	STA Star_SprVis
Gim_StarCalcLeftOff:
	LDA Star_SprX
	ADD #8
	LDA <Temp_Var1
	ADC #0
	BNE Gim_StarCalcRTS
	LDA Star_SprVis
	ORA #$02
	STA Star_SprVis
Gim_StarCalcRTS:
	RTS


Gim_StarHitEnemies:
	LDA Star_SprVis
	CMP #$03
	BNE Gim_StarHitRTS

	LDY #$04
Gim_StarHitLoop:
	LDA Objects_SprHVis,Y
	ORA Objects_SprVVis,Y
	BNE Gim_StarHitNext

	LDX Objects_State,Y
	LDA Obj2Obj_EnByState,X
	BNE Gim_StarHitNext

	LDX Level_ObjectID,Y
	LDA Object_AttrFlags,X
	STA <Temp_Var1
	AND #OAT_WEAPONIMMUNITY
	BNE Gim_StarHitNext

	LDA <Temp_Var1
	AND #OAT_BOUNDBOXMASK
	TAX

	LDA Star_SprY
	ADD #12
	SUB Objects_SpriteY,Y
	CMP Star_BBoxY,X
	BGE Gim_StarHitNext

	LDA Star_SprX
	ADD #12
	SUB Objects_SpriteX,Y
	CMP Star_BBoxX,X
	BGE Gim_StarHitNext

	JSR Gim_StarHitObject
	LDA Star_State
	CMP #$01
	BNE Gim_StarHitRTS

Gim_StarHitNext:
	DEY
	BPL Gim_StarHitLoop
Gim_StarHitRTS:
	RTS

Gim_StarHitObject:
	LDA <Temp_Var1
	AND #(OAT_HITNOTKILL | OAT_FIREIMMUNITY)
	CMP #(OAT_HITNOTKILL | OAT_FIREIMMUNITY)
	BEQ Gim_StarHitObjRTS

	LDA Sound_QPlayer
	ORA #SND_PLAYERKICK
	STA Sound_QPlayer

	LDA Objects_HitCount,Y
	BEQ Gim_StarKill
	SUB #$01
	STA Objects_HitCount,Y
	JMP Gim_StarVanish

Gim_StarKill:
	LDA #-$34
	STA Objects_YVel,Y
	LDA #$0C
	LDX Star_XVel
	BPL Gim_StarKillXVel
	LDA #-$0C
Gim_StarKillXVel:
	STA Objects_XVel,Y

	TYA
	PHA
	TAX
	LDA #$05
	JSR Score_PopUp
	PLA
	TAY

	LDA #OBJSTATE_KILLED
	STA Objects_State,Y
Gim_StarHitObjRTS:
	RTS


Gim_StarRide:
	LDA Star_Ridden
	STA <Temp_Var5
	LDA #$00
	STA Star_Ridden

	LDA Star_Standable
	BEQ Gim_StarRideNo
	LDA <Player_YVel
	BPL Gim_StarRideCheck
Gim_StarRideNo:
	RTS
Gim_StarRideCheck:

	LDA <Player_X
	ADD #12
	STA <Temp_Var1
	LDA <Player_XHi
	ADC #0
	STA <Temp_Var2
	LDA <Temp_Var1
	SUB Star_X
	STA <Temp_Var1
	LDA <Temp_Var2
	SBC Star_XHi
	BNE Gim_StarRideRTS
	LDA <Temp_Var1
	CMP #25
	BGE Gim_StarRideRTS

	LDA <Player_Y
	ADD #32+16
	STA <Temp_Var1
	LDA <Player_YHi
	ADC #0
	STA <Temp_Var2
	LDA <Temp_Var1
	SUB Star_Y
	STA <Temp_Var1
	LDA <Temp_Var2
	SBC Star_YHi
	BNE Gim_StarRideRTS

	LDA <Temp_Var1
	LDX <Temp_Var5
	BNE Gim_StarRideWasOn
	LDX <Player_InAir
	BEQ Gim_StarRideRTS
	CMP #16
	BLT Gim_StarRideRTS
	CMP #16+16
	BGE Gim_StarRideRTS
	JMP Gim_StarRideSnap
Gim_StarRideWasOn:
	CMP #16+17
	BLT Gim_StarRideSnap
Gim_StarRideRTS:
	RTS

Gim_StarRideSnap:
	LDA Star_Y
	SUB #32
	STA <Player_Y
	LDA Star_YHi
	SBC #0
	STA <Player_YHi
	LDA #$00
	STA <Player_YVel
	STA <Player_InAir

	; The star only probes its own box; Yumetaro's head is 16px above it, so a ceiling there stops them both
	LDA #$08
	STA <Temp_Var1
	LDA #$10
	STA <Temp_Var2
	JSR Gim_PlayerSetPoint
	JSR Gim_RiderSolid
	BCC Gim_StarRideCarry
	PHA
	LDA <Temp_Var14
	AND #$F0
	STA <Player_Y
	ADD #32
	STA Star_Y
	LDA <Temp_Var13
	STA <Player_YHi
	ADC #0
	STA Star_YHi
	LDA #$00
	STA Star_YVel
	STA Star_YFrac
	PLA
	JSR Gim_StarBump

Gim_StarRideCarry:
	LDA Star_X
	SUB Star_PrevX
	STA <Temp_Var5
	LDA Star_XHi
	SBC Star_PrevXHi
	STA <Temp_Var6
	ORA <Temp_Var5
	BEQ Gim_StarRideOn

	LDA <Player_X
	STA <Temp_Var7
	ADD <Temp_Var5
	STA <Player_X
	LDA <Player_XHi
	STA <Temp_Var8
	ADC <Temp_Var6
	STA <Player_XHi

	LDY #$0D
	LDA <Temp_Var6
	BPL Gim_StarRideFront
	LDY #$02
Gim_StarRideFront:
	STY <Temp_Var1
	LDA #$14
	STA <Temp_Var2
	JSR Gim_PlayerSetPoint
	JSR Gim_RiderSolid
	BCS Gim_StarRideBlocked
	LDA #$1B
	STA <Temp_Var2
	JSR Gim_PlayerSetPoint
	JSR Gim_RiderSolid
	BCC Gim_StarRideOn
Gim_StarRideBlocked:
	LDA <Temp_Var7
	STA <Player_X
	LDA <Temp_Var8
	STA <Player_XHi

Gim_StarRideOn:
	LDA #$01
	STA Star_Ridden
	RTS

	; Temp_Var13/14 = Player Y + Temp_Var2, Temp_Var15/16 = Player X + Temp_Var1
Gim_PlayerSetPoint:
	LDA <Player_Y
	ADD <Temp_Var2
	STA <Temp_Var14
	LDA <Player_YHi
	ADC #0
	STA <Temp_Var13
	LDA <Player_X
	ADD <Temp_Var1
	STA <Temp_Var16
	LDA <Player_XHi
	ADC #0
	STA <Temp_Var15
	RTS

	; Carry set (A = tile) if the point Temp_Var13-16 is solid from above; floor slope tiles don't count
Gim_RiderFloor:
	JSR Gim_TileAt
	CMP Tile_AttrTable,Y
	JMP Gim_RiderNoSlope

	; Carry set (A = tile) if the point Temp_Var13-16 is solid on all sides; floor slope tiles don't count
Gim_RiderSolid:
	JSR Gim_TileAt
	CMP Tile_AttrTable+4,Y
Gim_RiderNoSlope:
	BCC Gim_RiderSolidRTS
	STA <Temp_Var9
	JSR Gim_TileShape
	TAY
	LDA Slope_PlayerVel_Effect,Y
	CMP #$01
	LDA <Temp_Var9
	BCS Gim_RiderSolidNo
	SEC
	RTS
Gim_RiderSolidNo:
	CLC
Gim_RiderSolidRTS:
	RTS


Gim_StarDraw:
	LDA Star_State
	BNE Gim_StarDrawSome
	RTS

Gim_StarDrawSome:
	JSR Gim_StarCalcScreen

	LDA <Counter_1
	AND #$01
	BEQ Gim_StarDrawPal
	LDA #STAR_PAL
Gim_StarDrawPal:
	LDX Player_Behind
	BEQ Gim_StarDrawFront
	ORA #SPR_BEHINDBG
Gim_StarDrawFront:
	STA <Temp_Var8

	LDA Player_SprOff
	ADD #$10
	TAX

	LDA Star_State
	CMP #$D0
	BGE Gim_StarDrawVanish
	CMP #$01
	BEQ Gim_StarDrawStar
	CMP #$A2
	BGE Gim_StarDrawHeld

	LDA #$A2
	SUB Star_State
	JMP Gim_StarDrawSparkles

Gim_StarDrawVanish:
	SUB #$D0
	ASL A
	JMP Gim_StarDrawSparkles

Gim_StarDrawHeld:
	LDA #$F8
	STA Sprite_RAM-$04,X

Gim_StarDrawStar:
	LDA Star_SprVis
	AND #$01
	BEQ Gim_StarDrawNoLeft
	LDA Star_SprY
	STA Sprite_RAM+$00,X
	LDA #STAR_TILE
	STA Sprite_RAM+$01,X
	LDA <Temp_Var8
	STA Sprite_RAM+$02,X
	LDA Star_SprX
	STA Sprite_RAM+$03,X
Gim_StarDrawNoLeft:
	LDA Star_SprVis
	AND #$02
	BEQ Gim_StarDrawRTS
	LDA Star_SprY
	STA Sprite_RAM+$04,X
	LDA #STAR_TILE
	STA Sprite_RAM+$05,X
	LDA <Temp_Var8
	ORA #SPR_HFLIP
	STA Sprite_RAM+$06,X
	LDA Star_SprX
	ADD #8
	STA Sprite_RAM+$07,X
Gim_StarDrawRTS:
	RTS

	; Two sparkles on a diagonal at radius A around the star centre, diagonal alternating per frame
Gim_StarDrawSparkles:
	STA <Temp_Var1
	LDA Star_SprVis
	CMP #$03
	BNE Gim_StarDrawRTS

	LDA Star_SprY
	SUB <Temp_Var1
	STA Sprite_RAM+$00,X
	LDA Star_SprY
	ADD <Temp_Var1
	STA Sprite_RAM+$04,X

	LDA Star_SprX
	ADD #4
	STA <Temp_Var2
	LDA <Counter_1
	AND #$01
	BEQ Gim_StarSparkleDiag
	LDA <Temp_Var2
	ADD <Temp_Var1
	STA Sprite_RAM+$03,X
	LDA <Temp_Var2
	SUB <Temp_Var1
	STA Sprite_RAM+$07,X
	JMP Gim_StarSparkleTiles
Gim_StarSparkleDiag:
	LDA <Temp_Var2
	SUB <Temp_Var1
	STA Sprite_RAM+$03,X
	LDA <Temp_Var2
	ADD <Temp_Var1
	STA Sprite_RAM+$07,X

Gim_StarSparkleTiles:
	LDA #SPARKLE_TILE
	STA Sprite_RAM+$01,X
	STA Sprite_RAM+$05,X
	LDA <Temp_Var8
	STA Sprite_RAM+$02,X
	STA Sprite_RAM+$06,X
	RTS
