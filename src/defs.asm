; Gimmick! 1.5: addresses in the original game, and the hack's own RAM.
;
; Object arrays have 10 slots: slot 0 is Yumetaro, slot 1 is the star.
; See smb3-gimmick's docs/yumetaro-physics-guide.md for what each one means.

; ---- Game RAM -------------------------------------------------------------

Pad_Pressed     = $F5       ; buttons newly pressed this frame
Pad_Held        = $F7       ; buttons held
BTN_A           = $80
BTN_B           = $40
BTN_SELECT      = $20
BTN_UP          = $08

FrameCount      = $ED       ; global frame counter (low byte)
CamX_Sub        = $14
CamX_Tile       = $15
CurScreen       = $16       ; vertical screen 0-3
MapperCmd       = $3F       ; last FME-7 command written to $8000
Bank8000        = $40       ; shadow: PRG bank at $8000
BankA000        = $41       ; shadow: PRG bank at $A000
JumpHold        = $4B
BLockout        = $55       ; B is ignored while this counts down (after an item)
Item_Slot0      = $36       ; the item B+Up uses: 0 none, 1 medicine, 2 fireball, 3 bomb
ITEM_FIREBALL   = 2

Obj_Status      = $90
Obj_YSub        = $9A
Obj_YTile       = $A4       ; high nibble = vertical screen, low nibble = row
Obj_XSub        = $AE
Obj_XTile       = $B8
Obj_VY          = $C2
Obj_VX          = $CC
Obj_Standable   = $D6       ; $40 = can be stood on
Obj_Frame       = $0300
Obj_Facing      = $030A     ; 0 left, 1 right
Obj_Type        = $0350     ; slot 1: 0 star, 1 fireball, 2 bomb
Obj_StoodOn     = $0364
Obj_OnFloor     = $036E     ; bit 7
Obj_HitWall     = $0378     ; bit 7
Obj_Timer2      = $038C     ; Yumetaro: hurt timer. Star: rest / vanish counter.
Obj_Flags       = $03C8     ; $20 = behind background, bit 0 = palette flicker

Star_Status     = Obj_Status+1
Star_Type       = Obj_Type+1
Trail_Status    = $0439     ; 5 entries: star trail history

; Star status values
STAR_NONE       = $00
STAR_THROWN     = $01
STAR_TUBE       = $02
STAR_CHARGE0    = $7F       ; first frame of a charge is $80
STAR_READY      = $A0       ; charged enough to throw
STAR_VANISH     = $D0

; ---- Game ROM -------------------------------------------------------------

PlaySound       = $F285     ; A = sound id
DrawMetasprite  = $F468     ; X = slot, $00/$01 = frame pointer table
StarFrames      = $8523     ; bank $1D: the star's frame pointer table

SND_STAR_CHARGE = $10
SND_STAR_BOUNCE = $15
SND_ITEM_ROTATE = $14       ; quick rising arpeggio on SFX track 11
SND_SPLASH      = $1E       ; something falls into water
SND_LAND        = $0F

STAR_FRAME_STAR = $14       ; the plain star
STAR_FRAME_SPLASH = $1B     ; 8 frames of splash, as when the star sinks

; ---- Banks ----------------------------------------------------------------

HACK_BANK       = $20       ; new code, mapped at $A000 while it runs

; ---- Hack RAM ($0470-$048C, unused by the original game) ------------------

FX_SLOTS        = 2
FX_T            = $0470     ; 2 bytes each: effect frame number, 0 = free
FX_Kind         = $0472
FX_YSub         = $0474
FX_YTile        = $0476
FX_XSub         = $0478
FX_XTile        = $047A
FX_Facing       = $047C
FX_Cur          = $047E     ; slot being drawn
FX_Frame        = $047F     ; its metasprite frame
Save_Area       = $0480     ; 7 bytes ($0480-$0486): slot 1 while an effect is drawn
Floor_F         = $0487     ; FrameCount when Yumetaro was last on the floor
Floor_On        = $0488     ;   1 while that is recent enough to jump (coyote time)
JumpBuf_F       = $0489     ; FrameCount when A was last pressed
JumpBuf_On      = $048A     ;   1 while that press is waiting to become a jump
Tap_Mode        = $048B     ; 1: tap B to summon and to throw (Select switches)
Tap_Throw       = $048C     ;   1: B was tapped while charging, throw when ready

; ---- Tuning ---------------------------------------------------------------

GHOST_LEN       = 12        ; frames the recalled star takes to fly home
SPLASH_LEN      = 16        ; frames a skip's splash lasts
SND_RECALL      = SND_ITEM_ROTATE  ; track 11 outranks the charge sound's track 10,
                                   ; which carries on underneath
SKIP_MIN_VX     = 24        ; a star this fast sideways skips off water ...
SKIP_MIN_VY     = 12        ; ... unless it would bounce up slower than this
SKIP_MAX_VY     = 48        ; the highest a skip bounces
SND_TAP_ON      = SND_ITEM_ROTATE
SND_TAP_OFF     = SND_LAND
COYOTE_FRAMES   = 6         ; Gimmick! 2 has coyote time ...
JUMPBUF_FRAMES  = 6         ; ... and jump buffering
