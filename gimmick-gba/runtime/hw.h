// The GBA's hardware, or on the PC build the arrays that stand in for it, so the
// drawing code can run there and be looked at frame by frame.
#ifndef HW_H
#define HW_H
#include "platform.h"

#ifdef HOST
extern u8 sim_io[0x400], sim_vram[0x18000], sim_pal[0x400], sim_oam[0x400];
#define REG16(a) (*(volatile u16 *)(sim_io + ((a) & 0x3FF)))
#define REG32(a) (*(volatile u32 *)(sim_io + ((a) & 0x3FF)))
#define BG_PAL ((volatile u16 *)sim_pal)
#define OBJ_PAL ((volatile u16 *)(sim_pal + 0x200))
#define VRAM ((volatile u8 *)sim_vram)
#define OBJ_VRAM ((volatile u8 *)(sim_vram + 0x10000))
#define OAM ((volatile u16 *)sim_oam)
#else
#define REG16(a) (*(volatile u16 *)(a))
#define REG32(a) (*(volatile u32 *)(a))
#define BG_PAL ((volatile u16 *)0x05000000)
#define OBJ_PAL ((volatile u16 *)0x05000200)
#define VRAM ((volatile u8 *)0x06000000)
#define OBJ_VRAM ((volatile u8 *)0x06010000)
#define OAM ((volatile u16 *)0x07000000)
#endif

#define DISPCNT REG16(0x04000000)
#define DISPSTAT REG16(0x04000004)
#define VCOUNT REG16(0x04000006)
#define BG0CNT REG16(0x04000008)
#define BG1CNT REG16(0x0400000A)
#define BG2CNT REG16(0x0400000C)
#define BG3CNT REG16(0x0400000E)
#define BG2HOFS REG16(0x04000018)
#define BG2VOFS REG16(0x0400001A)
#define BG0HOFS REG16(0x04000010)
#define BG0VOFS REG16(0x04000012)
#define BG1HOFS REG16(0x04000014)
#define BG1VOFS REG16(0x04000016)
#define DMA3SAD REG32(0x040000D4)
#define DMA3DAD REG32(0x040000D8)
#define DMA3CNT REG32(0x040000DC)
#define TM0CNT_L REG16(0x04000100)
#define TM0CNT_H REG16(0x04000102)
#define TM2CNT_L REG16(0x04000108)
#define TM2CNT_H REG16(0x0400010A)
#define TM3CNT_L REG16(0x0400010C)
#define TM3CNT_H REG16(0x0400010E)
#define SOUNDCNT_H REG16(0x04000082)
#define SOUNDCNT_X REG16(0x04000084)
#define FIFO_A 0x040000A0
#define DMA1SAD REG32(0x040000BC)
#define DMA1DAD REG32(0x040000C0)
#define DMA1CNT_H REG16(0x040000C6)
#define IME REG16(0x04000208)
#define IE REG16(0x04000200)
#define IF REG16(0x04000202)
#define BIOS_IF REG16(0x03007FF8)
#define IRQ_VECTOR REG32(0x03007FFC)
#define KEYINPUT REG16(0x04000130)
#define WAITCNT REG16(0x04000204)
#define WIN0H REG16(0x04000040)
#define WIN0V REG16(0x04000044)
#define WIN1H REG16(0x04000042)
#define WIN1V REG16(0x04000046)
#define WININ REG16(0x04000048)
#define WINOUT REG16(0x0400004A)

#define SCREEN_W 240
#define SCREEN_H 160
#define CHARBLOCK_TEXT 1
#define MAP_TEXT 31
#define MAP(n) ((volatile u16 *)(VRAM + (n) * 0x800))


extern const u8 *chr4;   // the CHR converted to GBA tiles
void video_init(void);
void video_present(void);
#endif
