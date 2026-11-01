; Metroidvania: addresses in Castlevania, and the hack's own RAM.
;
; Castlevania's objects are arrays of 28 slots ($1C). Slot 0 is Simon (now
; Samus), $14-$16 are the subweapons (now Samus's shots), $04-$13 enemies,
; candles and items. Names follow the Castlevania disassembly in ref/cv1.

; ---- Castlevania: zero page ------------------------------------------------

GameMode        = $18
GameModeAux     = $19
FrameCounter    = $1A
CurrentBank     = $27       ; bank at $8000; the NMI's sound code switches back to it
CurrentStage    = $28
ScrollSub       = $2D
ScrollLo        = $2E       ; level scroll, in pixels: $2F:$2E
ScrollHi        = $2F
MoveDir         = $3C       ; bits 0-1: 1 right, 2 left; bit 2: Simon moves, not the screen
MoveSpeedSub    = $3D       ; speed for the scroll/move routines, 8.8
MoveSpeed       = $3E
SimonY          = $3F
SimonXLo        = $40       ; world x, for collision: $41:$40
SimonXHi        = $41
TimeLo          = $42
TimeHi          = $43
SimonHPShown    = $44
SimonHP         = $45       ; 0-$40
Floor           = $46
StunTimer       = $47
BossLock        = $48
ScrollDelta     = $49       ; how far objects move this frame because of scrolling
Invincible      = $5B       ; i-frames: enemies don't touch Simon while nonzero
BossHP          = $01A9     ; 0-$40
SimonHeight     = $5F       ; half height, for enemy contact: $0C standing, $0A crouched
WhipLevel       = $70
WhipFlash       = $7E       ; frames left of the stop after a whip upgrade
Hearts          = $71
Multiplier      = $64
PadPressed      = $F5
PadHeld         = $F7

; ---- Castlevania: objects --------------------------------------------------

ObjFlags        = $0300     ; bit 7: hidden
ObjPose         = $031C     ; metasprite; 0 draws nothing
ObjPal          = $0338
ObjY            = $0354
ObjYSub         = $0370
ObjX            = $038C     ; screen x
ObjXSub         = $03A8
ObjVY           = $03C4
ObjVYSub        = $03E0
ObjVX           = $03FC
ObjVXSub        = $0418
ObjAI           = $0434     ; AI type; 0 = empty slot
ObjFacing       = $0450     ; 1 = facing left
ObjPoseTimer    = $0488     ; frames to the next pose; bit 7: no pose animation
ObjPoseStep     = $04A4     ; step in the pose animation
ObjAction       = $046C     ; Simon: 0 walk, 1 jump, 2 whip, 3 crouch, 4 stairs, 5 hurt,
                            ; 6 walk to the stairs, 7 fall, 8 dead, 9 land
ObjLastHit      = $04DC     ; subweapons: the object they last hit
ObjBonus        = $0584     ; subweapons: 0 dagger, 1 axe, 3 holy water, 5 cross
ObjCounter      = $0568     ; Simon: whip timer (the whip hits on $11)

; ---- Castlevania: code -----------------------------------------------------

SwitchBankY     = $C1D6     ; map bank Y at $8000 and remember it in CurrentBank
JumpWithParams  = $CA6D     ; A = index into the .dw table after the jsr
SolidAt         = $F9A0     ; $10 = y, $13:$12 = world x -> $14 = collision (0 = empty)
PlaySFX         = $C1A7

; ---- Buttons and Metroid's constants ---------------------------------------

BTN_A           = $80
BTN_B           = $40
BTN_SELECT      = $20
BTN_START       = $10
BTN_UP          = $08
BTN_DOWN        = $04
BTN_LEFT        = $02
BTN_RIGHT       = $01
BUTTONBIT_DOWN  = 2

sa_Stand        = 0         ; Samus.status
sa_Run          = 1         ; also running jumps
sa_Jump         = 2
sa_Roll         = 3
sa_PntUp        = 4
sa_Door         = 5
sa_PntJump      = 6
sa_Dead         = 7
sa_Dead2        = 8
sa_Begin        = $FF

wa_RegularBeam  = $01       ; projectile status
wa_WaveBeam     = $02
wa_BulletExplode = $04
wa_LayBomb      = $08
wa_BombCount    = $09
wa_BombExplode  = $0A
wa_Missile      = $0B

; ---- The hack's RAM ----------------------------------------------------------
; Castlevania never writes $0100-$012F (its stack stays above $01E0) or
; $07CF-$07F0. Names are Metroid's.

SamusStatus     = $0100
SamusRadiusY    = $0101
SamusRadiusX    = $0102
SamusAnimFrame  = $0103
SamusAnimIndex  = $0104
SamusAnimReset  = $0105
SamusAnimDelay  = $0106
SamusIsHit      = $0107     ; $20 hit, $08 from the left
SamusSpeedX     = $0108
SamusSpeedY     = $0109
SamusAccelX     = $010A
SamusAccelY     = $010B     ; gravity; 0 on the ground
SamusSpeedSubX  = $010C
SamusSpeedSubY  = $010D
SamusSubX       = $010E
SamusSubY       = $010F
SamusJumpDsp    = $0110     ; pixels risen since the jump began
SamusDir        = $0111     ; 0 right, 1 left
SamusHorzMax    = $0112     ; max speed, $X.Y as X + Y/16
SamusInvincible = $0113
SamusKnockDir   = $0114     ; $FF none, 0 pushed left, 1 pushed right
SamusKnockBomb  = $0115
SamusKnockBomb77 = $0116
HealthLo        = $0117     ; BCD: ones in the high nibble, tenths in the low
HealthHi        = $0118     ; BCD: tens in the low nibble (energy tanks above: none)
HealthChangeLo  = $0119
HealthChangeHi  = $011A
MissileToggle   = $011B
WalkSoundDelay  = $011C
Joy1Status      = $011D
Joy1Change      = $011E
Joy1Retrig      = $011F
RetrigDelay     = $0120
MoveCount       = $0121     ; Metroid's ObjectCounter: pixels left to move
SamusXLo        = $0122     ; Samus's centre in the level
SamusXHi        = $0123
SamusY          = $0124
LastHP          = $0125     ; SimonHP as the hack last left it
HackState       = $0126     ; see HS_* below
BufStart        = $0128     ; where the update buffer's next flush starts
BufEnd          = $0129     ; where this flush stops, at an entry's start
StairDir        = $0127     ; on the stairs: MoveDir while the screen catches up (0 none)
ColXLo          = $012B     ; collision point
ColXHi          = $012C
ColY            = $012D
ColCount        = $012E
FollowX         = $012A     ; Simon's screen position last frame, while
FollowY         = $012F     ; Castlevania moves him
RideSlot        = FollowX   ; while Samus moves: the platform she stands on (0 none),
RideLastX       = FollowY   ; and its x in the level last frame
CV_PLATFORM_POSE = $C9

UP_SCREW        = $08       ; as in Metroid's SamusGear
UP_WAVE         = $40
WEAPON_AXE      = $0D       ; Castlevania's CurrentWeapon (low nibble), which unlock them
WEAPON_CROSS    = $09
CurrentWeapon   = $015B

HS_SAMUS        = $01       ; Samus's own state is current (else take Simon's position)
HS_KILL         = $02       ; ask Castlevania to kill Simon
HS_GROUND       = $04       ; standing on the ground: stairs may start
HS_FONT         = $08       ; Samus's tiles are over the font
HS_LENT         = $10       ; the explosion borrowed Castlevania's tiles (draw.asm)
HS_SPLIT        = $40       ; the HUD's colours are in palette 2 above the split

; Samus's three projectiles, by index 0-2 (Castlevania's object slots $14-$16).
BulStatus       = $07CF
BulAnimIndex    = $07D2
BulAnimReset    = $07D5
BulAnimDelay    = $07D8
BulAnimFrame    = $07DB
BulSpeedX       = $07DE
BulSpeedY       = $07E1
BulXLo          = $07E4
BulXHi          = $07E7
BulY            = $07EA
BulDie          = $07ED     ; frames left for a short beam

; At the bottom of the stack page: the stack has not been found to reach
; below $01D9, even with the hack's calls.
SfxPtrLo        = $01B2     ; 4 streams each: where the effect is (0 = idle),
SfxPtrHi        = $01B6     ; and frames to wait before its next writes
SfxWait         = $01BA
HackDepth       = $01BE     ; hack routines running (FarCall); the NMI's sound
                            ; skips the hack's part while one is
SfxSaveX        = $01BF
DebugFlags      = $01C0     ; for the tests: bit 7, Samus goes through walls
HudShown        = $01C1     ; 6 bytes: what the HUD's digit columns show
HudNew          = $01C7     ; 6 bytes: what they should show
Upgrades        = $01CD     ; UP_*: what Samus has picked up, until a game over
ScrewWait       = $01CE     ; frames until the Screw Attack can hit again
BulWave         = $01CF     ; 3 bytes: a wave shot's place in its path (WaveSpeeds)
LastHearts      = $07F0     ; Hearts last frame, for the missile pickup sound

; Castlevania's scratch bytes; the hack uses them the same way, as temporaries
; between calls.
Temp0           = $00
Temp1           = $01
Temp2           = $02
Temp3           = $03
Ptr             = $08       ; 2 bytes, for (Ptr),y
; While sprites are drawn (Castlevania's UpdateSprites sets these up again
; for each object):
DrawDir         = $06
DrawX           = $0C
DrawY           = $0D
DrawCount       = $0E
DrawAttr        = $0F
