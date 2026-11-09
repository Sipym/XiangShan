# Bare-metal TraceRTL corner-case tests.
#   make                 build every test into build/<name>.{elf,bin,txt}

CROSS_COMPILE ?= riscv64-unknown-linux-gnu-
CC      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump

MARCH   ?= rv64gc_zicsr_zifencei
CFLAGS  = -march=$(MARCH) -mabi=lp64d -mcmodel=medany -nostdlib -nostartfiles \
          -static -fno-pic -Wl,--no-relax -T link.ld

BUILD   ?= build
TESTS   ?= $(basename $(wildcard *.S))

all: $(addprefix $(BUILD)/,$(addsuffix .bin,$(TESTS)))

$(BUILD)/%.elf: %.S common.h link.ld
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -o $@ $<

$(BUILD)/%.bin: $(BUILD)/%.elf
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(BUILD)/$*.txt

clean:
	rm -rf $(BUILD)

.PHONY: all clean
.SECONDARY:
