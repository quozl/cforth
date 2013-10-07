# allow override of default cross location
CROSS ?= /usr/local/arm/arm-linux/bin/
TCC=$(CROSS)gcc
TLD=$(CROSS)ld
TOBJDUMP=$(CROSS)objdump
TOBJCOPY=$(CROSS)objcopy

CPU_VARIANT ?= -marm
TCFLAGS += $(CPU_VARIANT)

LIBDIRS=-L$(dir $(shell $(TCC) -print-libgcc-file-name))
