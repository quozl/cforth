# Makefile fragment for the final target application

SRC=$(TOPDIR)/src

# Target compiler definitions
CROSS ?= arm-none-eabi-
CPU_VARIANT=-mthumb -mcpu=cortex-m4 --specs=nano.specs 
include $(SRC)/cpu/arm/compiler.mk

include $(SRC)/common.mk
include $(SRC)/cforth/targets.mk

DEFS += -DF_CPU=48000000 -DUSB_SERIAL -DLAYOUT_US_ENGLISH -D__MK20DX256__ -DARDUINO=10805 -DTEENSYDUINO=144

DICTIONARY=ROM
DICTSIZE=0x2000

include $(SRC)/cforth/embed/targets.mk

CFLAGS += -m32 -march=i386

TCFLAGS += -Os

# Omit unreachable functions from output

TCFLAGS += -ffunction-sections -fdata-sections $(DEFS)
TLFLAGS += --defsym=__rtc_localtime=0 --gc-sections -Map main.map

# VPATH += $(SRC)/cpu/arm
VPATH += $(SRC)/lib
VPATH += $(SRC)/platform/arm-teensy3

# This directory, including board information
INCS += -I$(SRC)/platform/arm-teensy3


# Platform-specific object files for low-level startup and platform I/O

PLAT_OBJS += tmk20dx128.o tser_print.o ttmain.o tconsoleio.o tusb_dev.o tusb_mem.o tusb_desc.o tusb_serial.o tanalog.o tpins_teensy.o teeprom.o

# Object files for the Forth system and application-specific extensions

FORTH_OBJS = tembed.o textend.o


# Recipe for linking the final image

LDSCRIPT = $(SRC)/platform/arm-teensy3/mk20dx256.ld

app.elf: $(PLAT_OBJS) $(FORTH_OBJS)
	@echo Linking $@ ... 
	$(TLD) -o $@  $(TLFLAGS) -T$(LDSCRIPT) \
	   $(PLAT_OBJS) $(FORTH_OBJS) \
	   $(LIBDIRS) -lgcc


# This rule extracts the executable bits from an ELF file, yielding a hex file

%.hex: %.elf
	$(CROSS)size $<
	$(TOBJCOPY) -O ihex -R .eeprom $< $@
	@ls -l $@

# This rule loads the hex file to the module
burn: app.hex
	./teensy_loader_cli -w -mmcu=mk20dx128 app.hex

# This rule builds a date stamp object that you can include in the image
# if you wish.

.PHONY: date.o

date.o:
	echo 'const char version[] = "'`cat version`'" ;' >date.c
	echo 'const char build_date[] = "'`date  --iso-8601=minutes`'" ;' >>date.c
	echo "const unsigned char sw_version[] = {" `cut -d . --output-delimiter=, -f 1,2 version` "};" >>date.c
	$(TCC) -c date.c -o $@

EXTRA_CLEAN += *.elf *.dump *.nm *.img date.c $(FORTH_OBJS) $(PLAT_OBJS)
