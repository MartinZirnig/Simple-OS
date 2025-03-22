# OS/src/BootLoader/Makefile

ASM = nasm
SRC = .
BUILD = ../../build/BootLoader

$(BUILD)/bld.img: $(BUILD)/bld.bin
	cp $(BUILD)/bld.bin $(BUILD)/bld.img
	truncate -s 1440k $(BUILD)/bld.img

$(BUILD)/bld.bin: $(SRC)/bld.asm
	mkdir -p $(BUILD)
	$(ASM) $(SRC)/bld.asm -f bin -o $(BUILD)/bld.bin

clean:
	rm -f $(BUILD)/bld.bin $(BUILD)/bld.img
