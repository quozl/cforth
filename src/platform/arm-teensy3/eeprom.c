/* Teensyduino Core Library
 * http://www.pjrc.com/teensy/
 * Copyright (c) 2017 PJRC.COM, LLC.
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * 1. The above copyright notice and this permission notice shall be 
 * included in all copies or substantial portions of the Software.
 *
 * 2. If the Software is incorporated into a build system that allows 
 * selection among a list of target devices, then similar target
 * devices manufactured by PJRC.COM must be included in the list of
 * target devices and selectable in the same manner.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// To configure the EEPROM size, edit E2END in avr/eeprom.h.
//
// Do *NOT* edit EEPROM_SIZE in this file.  It will automatically
// change based on your changes to E2END in avr/eeprom.h.
//
// Generally you should avoid editing this code, unless you really
// know what you're doing.

#include "kinetis.h"
//#include "HardwareSerial.h"
#if F_CPU > 120000000 && defined(__MK66FX1M0__)
#include "core_pins.h"	// delayMicroseconds()
#endif


#if defined(__MK20DX128__) || defined(__MK20DX256__)
#define EEPROM_MAX  2048
#define EEPARTITION 0x03  // all 32K dataflash for EEPROM, none for Data
#define EEESPLIT    0x30  // must be 0x30 on these chips
#elif defined(__MK64FX512__)
#define EEPROM_MAX  4096
#define EEPARTITION 0x05  // all 128K dataflash for EEPROM
#define EEESPLIT    0x10  // best endurance: 0x00 = first 12%, 0x10 = first 25%, 0x30 = all equal
#elif defined(__MK66FX1M0__)
#define EEPROM_MAX  4096
#define EEPARTITION 0x05  // 128K dataflash for EEPROM, 128K for Data
#define EEESPLIT    0x10  // best endurance: 0x00 = first 12%, 0x10 = first 25%, 0x30 = all equal
#elif defined(__MKL26Z64__)
#define EEPROM_MAX  255
#endif

#if E2END > (EEPROM_MAX-1)
#error "E2END is set larger than the maximum possible EEPROM size"
#endif

// The EEPROM is really RAM with a hardware-based backup system to
// flash memory.  Selecting a smaller size EEPROM allows more wear
// leveling, for higher write endurance.  If you edit this file,
// set this to the smallest size your application can use.  Also,
// due to Freescale's implementation, writing 16 or 32 bit words
// (aligned to 2 or 4 byte boundaries) has twice the endurance
// compared to writing 8 bit bytes.
//

#if E2END < 32
  #define EEPROM_SIZE 32
  #define EEESIZE 0x09
#elif E2END < 64
  #define EEPROM_SIZE 64
  #define EEESIZE 0x08
#elif E2END < 128
  #define EEPROM_SIZE 128
  #define EEESIZE 0x07
#elif E2END < 256
  #define EEPROM_SIZE 256
  #define EEESIZE 0x06
#elif E2END < 512
  #define EEPROM_SIZE 512
  #define EEESIZE 0x05
#elif E2END < 1024
  #define EEPROM_SIZE 1024
  #define EEESIZE 0x04
#elif E2END < 2048
  #define EEPROM_SIZE 2048
  #define EEESIZE 0x03
#elif E2END < 4096
  #define EEPROM_SIZE 4096
  #define EEESIZE 0x02
#endif

uint32_t eeprom_size() {
  return EEPROM_SIZE;
}

// Writing unaligned 16 or 32 bit data is handled automatically when
// this is defined, but at a cost of extra code size.  Without this,
// any unaligned write will cause a hard fault exception!  If you're
// absolutely sure all 16 and 32 bit writes will be aligned, you can
// remove the extra unnecessary code.
//
#define HANDLE_UNALIGNED_WRITES


void eeprom_initialize(void)
{
	uint32_t count=0;
	uint16_t do_flash_cmd[] = {
		0xf06f, 0x037f, 0x7003, 0x7803,
		0xf013, 0x0f80, 0xd0fb, 0x4770};
	uint8_t status;

	if (FTFL_FCNFG & FTFL_FCNFG_RAMRDY) {
		uint8_t stat = FTFL_FSTAT & 0x70;
		if (stat) FTFL_FSTAT = stat;
		// FlexRAM is configured as traditional RAM
		// We need to reconfigure for EEPROM usage
		kinetis_hsrun_disable();
		FTFL_FCCOB0 = 0x80; // PGMPART = Program Partition Command
		FTFL_FCCOB3 = 0;
		FTFL_FCCOB4 = EEESPLIT | EEESIZE;
		FTFL_FCCOB5 = EEPARTITION;
		__disable_irq();
		// do_flash_cmd() must execute from RAM.  Luckily the C syntax is simple...
		(*((void (*)(volatile uint8_t *))((uint32_t)do_flash_cmd | 1)))(&FTFL_FSTAT);
		__enable_irq();
		kinetis_hsrun_enable();
		status = FTFL_FSTAT;
		if (status & 0x70) {
			FTFL_FSTAT = (status & 0x70);
			return; // error
		}
	}
	// wait for eeprom to become ready (is this really necessary?)
	while (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) {
		if (++count > 200000) break;
	}
}

#define FlexRAM ((volatile uint8_t *)0x14000000)

uint32_t eeprom_base()
{
	return 0x14000000;
}

uint32_t eeprom_length()
{
	uint32_t offset;
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
	if (FlexRAM[0] == 0xff) return 0; /* not initialised */
	for(offset=0; offset<EEPROM_SIZE; offset++) {
		if (FlexRAM[offset] == 0) break;
	}
	return offset;
}

uint8_t eeprom_read_byte(const uint8_t *addr)
{
	uint32_t offset = (uint32_t)addr;
	if (offset >= EEPROM_SIZE) return 0;
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
	return FlexRAM[offset];
}

uint16_t eeprom_read_word(const uint16_t *addr)
{
	uint32_t offset = (uint32_t)addr;
	if (offset >= EEPROM_SIZE-1) return 0;
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
	return *(uint16_t *)(&FlexRAM[offset]);
}

uint32_t eeprom_read_dword(const uint32_t *addr)
{
	uint32_t offset = (uint32_t)addr;
	if (offset >= EEPROM_SIZE-3) return 0;
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
	return *(uint32_t *)(&FlexRAM[offset]);
}

void eeprom_read_block(void *buf, const void *addr, uint32_t len)
{
	uint32_t offset = (uint32_t)addr;
	uint8_t *dest = (uint8_t *)buf;
	uint32_t end = offset + len;
	
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
	if (end > EEPROM_SIZE) end = EEPROM_SIZE;
	while (offset < end) {
		*dest++ = FlexRAM[offset++];
	}
}

int eeprom_is_ready(void)
{
	return (FTFL_FCNFG & FTFL_FCNFG_EEERDY) ? 1 : 0;
}

static void flexram_wait(void)
{
	while (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) {
		// TODO: timeout
	}
}

void eeprom_write_byte(uint8_t *addr, uint8_t value)
{
	uint32_t offset = (uint32_t)addr;

	if (offset >= EEPROM_SIZE) return;
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
	if (FlexRAM[offset] != value) {
		kinetis_hsrun_disable();
		uint8_t stat = FTFL_FSTAT & 0x70;
		if (stat) FTFL_FSTAT = stat;
		FlexRAM[offset] = value;
		flexram_wait();
		kinetis_hsrun_enable();
	}
}

void eeprom_write_word(uint16_t *addr, uint16_t value)
{
	uint32_t offset = (uint32_t)addr;

	if (offset >= EEPROM_SIZE-1) return;
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
#ifdef HANDLE_UNALIGNED_WRITES
	if ((offset & 1) == 0) {
#endif
		if (*(uint16_t *)(&FlexRAM[offset]) != value) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			*(uint16_t *)(&FlexRAM[offset]) = value;
			flexram_wait();
			kinetis_hsrun_enable();
		}
#ifdef HANDLE_UNALIGNED_WRITES
	} else {
		if (FlexRAM[offset] != value) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			FlexRAM[offset] = value;
			flexram_wait();
			kinetis_hsrun_enable();
		}
		if (FlexRAM[offset + 1] != (value >> 8)) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			FlexRAM[offset + 1] = value >> 8;
			flexram_wait();
			kinetis_hsrun_enable();
		}
	}
#endif
}

void eeprom_write_dword(uint32_t *addr, uint32_t value)
{
	uint32_t offset = (uint32_t)addr;

	if (offset >= EEPROM_SIZE-3) return;
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
#ifdef HANDLE_UNALIGNED_WRITES
	switch (offset & 3) {
	case 0:
#endif
		if (*(uint32_t *)(&FlexRAM[offset]) != value) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			*(uint32_t *)(&FlexRAM[offset]) = value;
			flexram_wait();
			kinetis_hsrun_enable();
		}
		return;
#ifdef HANDLE_UNALIGNED_WRITES
	case 2:
		if (*(uint16_t *)(&FlexRAM[offset]) != value) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			*(uint16_t *)(&FlexRAM[offset]) = value;
			flexram_wait();
			kinetis_hsrun_enable();
		}
		if (*(uint16_t *)(&FlexRAM[offset + 2]) != (value >> 16)) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			*(uint16_t *)(&FlexRAM[offset + 2]) = value >> 16;
			flexram_wait();
			kinetis_hsrun_enable();
		}
		return;
	default:
		if (FlexRAM[offset] != value) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			FlexRAM[offset] = value;
			flexram_wait();
			kinetis_hsrun_enable();
		}
		if (*(uint16_t *)(&FlexRAM[offset + 1]) != (value >> 8)) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			*(uint16_t *)(&FlexRAM[offset + 1]) = value >> 8;
			flexram_wait();
			kinetis_hsrun_enable();
		}
		if (FlexRAM[offset + 3] != (value >> 24)) {
			kinetis_hsrun_disable();
			uint8_t stat = FTFL_FSTAT & 0x70;
			if (stat) FTFL_FSTAT = stat;
			FlexRAM[offset + 3] = value >> 24;
			flexram_wait();
			kinetis_hsrun_enable();
		}
	}
#endif
}

void eeprom_write_block(const void *buf, void *addr, uint32_t len)
{
	uint32_t offset = (uint32_t)addr;
	const uint8_t *src = (const uint8_t *)buf;

	if (offset >= EEPROM_SIZE) return;
	if (!(FTFL_FCNFG & FTFL_FCNFG_EEERDY)) eeprom_initialize();
	if (len >= EEPROM_SIZE) len = EEPROM_SIZE;
	if (offset + len >= EEPROM_SIZE) len = EEPROM_SIZE - offset;
	while (len > 0) {
		uint32_t lsb = offset & 3;
		if (lsb == 0 && len >= 4) {
			// write aligned 32 bits
			uint32_t val32;
			val32 = *src++;
			val32 |= (*src++ << 8);
			val32 |= (*src++ << 16);
			val32 |= (*src++ << 24);
			if (*(uint32_t *)(&FlexRAM[offset]) != val32) {
				kinetis_hsrun_disable();
				uint8_t stat = FTFL_FSTAT & 0x70;
				if (stat) FTFL_FSTAT = stat;
				*(uint32_t *)(&FlexRAM[offset]) = val32;
				flexram_wait();
				kinetis_hsrun_enable();
			}
			offset += 4;
			len -= 4;
		} else if ((lsb == 0 || lsb == 2) && len >= 2) {
			// write aligned 16 bits
			uint16_t val16;
			val16 = *src++;
			val16 |= (*src++ << 8);
			if (*(uint16_t *)(&FlexRAM[offset]) != val16) {
				kinetis_hsrun_disable();
				uint8_t stat = FTFL_FSTAT & 0x70;
				if (stat) FTFL_FSTAT = stat;
				*(uint16_t *)(&FlexRAM[offset]) = val16;
				flexram_wait();
				kinetis_hsrun_enable();
			}
			offset += 2;
			len -= 2;
		} else {
			// write 8 bits
			uint8_t val8 = *src++;
			if (FlexRAM[offset] != val8) {
				kinetis_hsrun_disable();
				uint8_t stat = FTFL_FSTAT & 0x70;
				if (stat) FTFL_FSTAT = stat;
				FlexRAM[offset] = val8;
				flexram_wait();
				kinetis_hsrun_enable();
			}
			offset++;
			len--;
		}
	}
}

/*
void do_flash_cmd(volatile uint8_t *fstat)
{
	*fstat = 0x80;
	while ((*fstat & 0x80) == 0) ; // wait
}
00000000 <do_flash_cmd>:
   0:	f06f 037f 	mvn.w	r3, #127	; 0x7f
   4:	7003      	strb	r3, [r0, #0]
   6:	7803      	ldrb	r3, [r0, #0]
   8:	f013 0f80 	tst.w	r3, #128	; 0x80
   c:	d0fb      	beq.n	6 <do_flash_cmd+0x6>
   e:	4770      	bx	lr
*/

