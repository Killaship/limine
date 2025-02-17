PREFIX ?= /usr/local
DESTDIR ?=

export PATH := $(shell pwd)/toolchain/bin:$(PATH)

NCPUS := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

TOOLCHAIN ?= limine

TOOLCHAIN_CC ?= $(TOOLCHAIN)-gcc

ifeq ($(shell PATH="$(PATH)" command -v $(TOOLCHAIN_CC) ; ), )
override TOOLCHAIN_CC := cc
endif

ifeq ($(TOOLCHAIN_CC), clang)
TOOLCHAIN_CC += --target=x86_64-elf
ifeq ($(TOOLCHAIN_CC), clang)
override TOOLCHAIN_CC += --target=x86_64-elf
MAKEOVERRIDES += TOOLCHAIN_CC+=--target=x86_64-elf
endif
endif

CC_MACHINE := $(shell PATH="$(PATH)" $(TOOLCHAIN_CC) -dumpmachine | dd bs=6 count=1 2>/dev/null)

ifneq ($(MAKECMDGOALS), toolchain)
ifneq ($(MAKECMDGOALS), distclean)
ifneq ($(MAKECMDGOALS), distclean2)
ifneq ($(CC_MACHINE), x86_64)
ifneq ($(CC_MACHINE), amd64-)
$(error No suitable x86_64 C compiler found, please install an x86_64 C toolchain or run "make toolchain")
endif
endif
endif
endif
endif

STAGE1_FILES := $(shell find -L ./stage1 -type f -name '*.asm' | sort)

.PHONY: all
all:
	$(MAKE) limine-uefi
	$(MAKE) limine-uefi32
	$(MAKE) limine-bios
	$(MAKE) bin/limine-install

.PHONY: bin/limine-install
bin/limine-install:
	$(MAKE) -C limine-install LIMINE_HDD_BIN="`pwd`/bin/limine-hdd.bin"
	[ -f limine-install/limine-install ] && cp limine-install/limine-install bin/ || true
	[ -f limine-install/limine-install.exe ] && cp limine-install/limine-install.exe bin/ || true

.PHONY: clean
clean: limine-bios-clean limine-uefi-clean limine-uefi32-clean
	$(MAKE) -C limine-install clean

.PHONY: install
install: all
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -s bin/limine-install "$(DESTDIR)$(PREFIX)/bin/"
	install -d "$(DESTDIR)$(PREFIX)/share"
	install -d "$(DESTDIR)$(PREFIX)/share/limine"
	install -m 644 bin/limine.sys "$(DESTDIR)$(PREFIX)/share/limine/" || true
	install -m 644 bin/limine-cd.bin "$(DESTDIR)$(PREFIX)/share/limine/" || true
	install -m 644 bin/limine-eltorito-efi.bin "$(DESTDIR)$(PREFIX)/share/limine/" || true
	install -m 644 bin/limine-pxe.bin "$(DESTDIR)$(PREFIX)/share/limine/" || true
	install -m 644 bin/BOOTX64.EFI "$(DESTDIR)$(PREFIX)/share/limine/" || true
	install -m 644 bin/BOOTIA32.EFI "$(DESTDIR)$(PREFIX)/share/limine/" || true

build/stage1: $(STAGE1_FILES) build/decompressor/decompressor.bin build/stage23-bios/stage2.bin.gz
	mkdir -p bin
	cd stage1/hdd && nasm bootsect.asm -Werror -fbin -o ../../bin/limine-hdd.bin
	cd stage1/cd  && nasm bootsect.asm -Werror -fbin -o ../../bin/limine-cd.bin
	cd stage1/pxe && nasm bootsect.asm -Werror -fbin -o ../../bin/limine-pxe.bin
	cp build/stage23-bios/limine.sys ./bin/
	touch build/stage1

.PHONY: limine-bios
limine-bios: stage23-bios decompressor
	$(MAKE) build/stage1

.PHONY: bin/limine-eltorito-efi.bin
bin/limine-eltorito-efi.bin:
	dd if=/dev/zero of=$@ bs=512 count=2880
	( mformat -i $@ -f 1440 :: && \
	  mmd -D s -i $@ ::/EFI && \
	  mmd -D s -i $@ ::/EFI/BOOT && \
	  ( ( [ -f build/stage23-uefi/BOOTX64.EFI ] && \
	      mcopy -D o -i $@ build/stage23-uefi/BOOTX64.EFI ::/EFI/BOOT ) || true ) && \
	  ( ( [ -f build/stage23-uefi32/BOOTIA32.EFI ] && \
	      mcopy -D o -i $@ build/stage23-uefi32/BOOTIA32.EFI ::/EFI/BOOT ) || true ) \
	) || rm -f $@

.PHONY: limine-uefi
limine-uefi:
	$(MAKE) gnu-efi
	$(MAKE) stage23-uefi
	mkdir -p bin
	cp build/stage23-uefi/BOOTX64.EFI ./bin/
	$(MAKE) bin/limine-eltorito-efi.bin

.PHONY: limine-uefi32
limine-uefi32:
	$(MAKE) gnu-efi
	$(MAKE) stage23-uefi32
	mkdir -p bin
	cp build/stage23-uefi32/BOOTIA32.EFI ./bin/
	$(MAKE) bin/limine-eltorito-efi.bin

.PHONY: limine-bios-clean
limine-bios-clean: stage23-bios-clean decompressor-clean

.PHONY: limine-uefi-clean
limine-uefi-clean: stage23-uefi-clean

.PHONY: limine-uefi32-clean
limine-uefi32-clean: stage23-uefi32-clean

.PHONY: distclean2
distclean2: clean test-clean
	rm -rf bin build toolchain ovmf* gnu-efi

.PHONY: distclean
distclean: distclean2
	rm -rf stivale

stivale:
	git clone https://github.com/stivale/stivale.git

.PHONY: stage23-uefi
stage23-uefi: stivale
	$(MAKE) -C stage23 all TARGET=uefi BUILDDIR="`pwd`/build/stage23-uefi"

.PHONY: stage23-uefi-clean
stage23-uefi-clean:
	$(MAKE) -C stage23 clean TARGET=uefi BUILDDIR="`pwd`/build/stage23-uefi"

.PHONY: stage23-uefi32
stage23-uefi32: stivale
	$(MAKE) -C stage23 all TARGET=uefi32 BUILDDIR="`pwd`/build/stage23-uefi32"

.PHONY: stage23-uefi32-clean
stage23-uefi32-clean:
	$(MAKE) -C stage23 clean TARGET=uefi32 BUILDDIR="`pwd`/build/stage23-uefi32"

.PHONY: stage23-bios
stage23-bios: stivale
	$(MAKE) -C stage23 all TARGET=bios BUILDDIR="`pwd`/build/stage23-bios"

.PHONY: stage23-bios-clean
stage23-bios-clean:
	$(MAKE) -C stage23 clean TARGET=bios BUILDDIR="`pwd`/build/stage23-bios"

.PHONY: decompressor
decompressor:
	$(MAKE) -C decompressor all BUILDDIR="`pwd`/build/decompressor"

.PHONY: decompressor-clean
decompressor-clean:
	$(MAKE) -C decompressor clean BUILDDIR="`pwd`/build/decompressor"

.PHONY: test-clean
test-clean:
	$(MAKE) -C test clean
	rm -rf test_image test.hdd test.iso

.PHONY: toolchain
toolchain:
	MAKE="$(MAKE)" aux/make_toolchain.sh "`pwd`/toolchain" -j$(NCPUS)

gnu-efi:
	git clone https://git.code.sf.net/p/gnu-efi/code --branch=3.0.13 --depth=1 $@
	cp aux/elf/* gnu-efi/inc/

ovmf-x64:
	mkdir -p ovmf-x64
	cd ovmf-x64 && curl -o OVMF-X64.zip https://efi.akeo.ie/OVMF/OVMF-X64.zip && 7z x OVMF-X64.zip

ovmf-ia32:
	mkdir -p ovmf-ia32
	cd ovmf-ia32 && curl -o OVMF-IA32.zip https://efi.akeo.ie/OVMF/OVMF-IA32.zip && 7z x OVMF-IA32.zip

.PHONY: test.hdd
test.hdd:
	rm -f test.hdd
	dd if=/dev/zero bs=1M count=0 seek=64 of=test.hdd
	parted -s test.hdd mklabel gpt
	parted -s test.hdd mkpart primary 2048s 100%

.PHONY: echfs-test
echfs-test:
	$(MAKE) test-clean
	$(MAKE) test.hdd
	$(MAKE) limine-bios
	$(MAKE) bin/limine-install
	$(MAKE) -C test
	echfs-utils -g -p0 test.hdd quick-format 512 > part_guid
	sed "s/@GUID@/`cat part_guid`/g" < test/limine.cfg > limine.cfg.tmp
	echfs-utils -g -p0 test.hdd import limine.cfg.tmp limine.cfg
	rm -f limine.cfg.tmp part_guid
	echfs-utils -g -p0 test.hdd import test/test.elf boot/test.elf
	echfs-utils -g -p0 test.hdd import test/bg.bmp boot/bg.bmp
	echfs-utils -g -p0 test.hdd import bin/limine.sys boot/limine.sys
	bin/limine-install test.hdd
	qemu-system-x86_64 -net none -smp 4 -enable-kvm -cpu host -hda test.hdd -debugcon stdio

.PHONY: ext2-test
ext2-test:
	$(MAKE) test-clean
	$(MAKE) test.hdd
	$(MAKE) limine-bios
	$(MAKE) bin/limine-install
	$(MAKE) -C test
	rm -rf test_image/
	mkdir test_image
	sudo losetup -Pf --show test.hdd > loopback_dev
	sudo partprobe `cat loopback_dev`
	sudo mkfs.ext2 `cat loopback_dev`p1
	sudo mount `cat loopback_dev`p1 test_image
	sudo mkdir test_image/boot
	sudo cp -rv bin/* test/* test_image/boot/
	sync
	sudo umount test_image/
	sudo losetup -d `cat loopback_dev`
	rm -rf test_image loopback_dev
	bin/limine-install test.hdd
	qemu-system-x86_64 -net none -smp 4 -enable-kvm -cpu host -hda test.hdd -debugcon stdio

.PHONY: fat12-test
fat12-test:
	$(MAKE) test-clean
	$(MAKE) test.hdd
	$(MAKE) limine-bios
	$(MAKE) bin/limine-install
	$(MAKE) -C test
	rm -rf test_image/
	mkdir test_image
	sudo losetup -Pf --show test.hdd > loopback_dev
	sudo partprobe `cat loopback_dev`
	sudo mkfs.fat -F 12 `cat loopback_dev`p1
	sudo mount `cat loopback_dev`p1 test_image
	sudo mkdir test_image/boot
	sudo cp -rv bin/* test/* test_image/boot/
	sync
	sudo umount test_image/
	sudo losetup -d `cat loopback_dev`
	rm -rf test_image loopback_dev
	bin/limine-install test.hdd
	qemu-system-x86_64 -net none -smp 4 -enable-kvm -cpu host -hda test.hdd -debugcon stdio

.PHONY: fat16-test
fat16-test:
	$(MAKE) test-clean
	$(MAKE) test.hdd
	$(MAKE) limine-bios
	$(MAKE) bin/limine-install
	$(MAKE) -C test
	rm -rf test_image/
	mkdir test_image
	sudo losetup -Pf --show test.hdd > loopback_dev
	sudo partprobe `cat loopback_dev`
	sudo mkfs.fat -F 16 `cat loopback_dev`p1
	sudo mount `cat loopback_dev`p1 test_image
	sudo mkdir test_image/boot
	sudo cp -rv bin/* test/* test_image/boot/
	sync
	sudo umount test_image/
	sudo losetup -d `cat loopback_dev`
	rm -rf test_image loopback_dev
	bin/limine-install test.hdd
	qemu-system-x86_64 -net none -smp 4 -enable-kvm -cpu host -hda test.hdd -debugcon stdio

.PHONY: fat32-test
fat32-test:
	$(MAKE) test-clean
	$(MAKE) test.hdd
	$(MAKE) limine-bios
	$(MAKE) bin/limine-install
	$(MAKE) -C test
	rm -rf test_image/
	mkdir test_image
	sudo losetup -Pf --show test.hdd > loopback_dev
	sudo partprobe `cat loopback_dev`
	sudo mkfs.fat -F 32 `cat loopback_dev`p1
	sudo mount `cat loopback_dev`p1 test_image
	sudo mkdir test_image/boot
	sudo cp -rv bin/* test/* test_image/boot/
	sync
	sudo umount test_image/
	sudo losetup -d `cat loopback_dev`
	rm -rf test_image loopback_dev
	bin/limine-install test.hdd
	qemu-system-x86_64 -net none -smp 4 -enable-kvm -cpu host -hda test.hdd -debugcon stdio

.PHONY: iso9660-test
iso9660-test:
	$(MAKE) test-clean
	$(MAKE) test.hdd
	$(MAKE) limine-bios
	$(MAKE) -C test
	rm -rf test_image/
	mkdir -p test_image/boot
	cp -rv bin/* test/* test_image/boot/
	xorriso -as mkisofs -b boot/limine-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table test_image/ -o test.iso
	qemu-system-x86_64 -net none -smp 4 -enable-kvm -cpu host -cdrom test.iso -debugcon stdio

.PHONY: full-hybrid-test
full-hybrid-test:
	$(MAKE) ovmf-x64
	$(MAKE) ovmf-ia32
	$(MAKE) test-clean
	$(MAKE) limine-uefi
	$(MAKE) limine-uefi32
	$(MAKE) limine-bios
	$(MAKE) bin/limine-install
	$(MAKE) -C test
	rm -rf test_image/
	mkdir -p test_image/boot
	cp -rv bin/* test/* test_image/boot/
	xorriso -as mkisofs -b boot/limine-cd.bin -no-emul-boot -boot-load-size 4 -boot-info-table --efi-boot boot/limine-eltorito-efi.bin -efi-boot-part --efi-boot-image --protective-msdos-label test_image/ -o test.iso
	bin/limine-install test.iso
	qemu-system-x86_64 -M q35 -bios ovmf-x64/OVMF.fd -net none -smp 4 -enable-kvm -cpu host -cdrom test.iso -debugcon stdio
	qemu-system-x86_64 -M q35 -bios ovmf-x64/OVMF.fd -net none -smp 4 -enable-kvm -cpu host -hda test.iso -debugcon stdio
	qemu-system-x86_64 -M q35 -bios ovmf-ia32/OVMF.fd -net none -smp 4 -enable-kvm -cpu host -cdrom test.iso -debugcon stdio
	qemu-system-x86_64 -M q35 -bios ovmf-ia32/OVMF.fd -net none -smp 4 -enable-kvm -cpu host -hda test.iso -debugcon stdio
	qemu-system-x86_64 -M q35 -net none -smp 4 -enable-kvm -cpu host -cdrom test.iso -debugcon stdio
	qemu-system-x86_64 -M q35 -net none -smp 4 -enable-kvm -cpu host -hda test.iso -debugcon stdio

.PHONY: pxe-test
pxe-test:
	$(MAKE) test-clean
	$(MAKE) limine-bios
	$(MAKE) -C test
	rm -rf test_image/
	mkdir -p test_image/boot
	cp -rv bin/* test/* test_image/boot/
	qemu-system-x86_64 -enable-kvm -smp 4 -cpu host -netdev user,id=n0,tftp=./test_image,bootfile=boot/limine-pxe.bin -device rtl8139,netdev=n0,mac=00:00:00:11:11:11 -debugcon stdio

.PHONY: uefi-test
uefi-test:
	$(MAKE) ovmf-x64
	$(MAKE) test-clean
	$(MAKE) test.hdd
	$(MAKE) limine-uefi
	$(MAKE) -C test
	rm -rf test_image/
	mkdir test_image
	sudo losetup -Pf --show test.hdd > loopback_dev
	sudo partprobe `cat loopback_dev`
	sudo mkfs.fat -F 32 `cat loopback_dev`p1
	sudo mount `cat loopback_dev`p1 test_image
	sudo mkdir test_image/boot
	sudo cp -rv bin/* test/* test_image/boot/
	sudo mkdir -p test_image/EFI/BOOT
	sudo cp bin/BOOTX64.EFI test_image/EFI/BOOT/
	sync
	sudo umount test_image/
	sudo losetup -d `cat loopback_dev`
	rm -rf test_image loopback_dev
	qemu-system-x86_64 -M q35 -L ovmf -bios ovmf-x64/OVMF.fd -net none -smp 4 -enable-kvm -cpu host -hda test.hdd -debugcon stdio

.PHONY: uefi32-test
uefi32-test:
	$(MAKE) ovmf-ia32
	$(MAKE) test-clean
	$(MAKE) test.hdd
	$(MAKE) limine-uefi32
	$(MAKE) -C test
	rm -rf test_image/
	mkdir test_image
	sudo losetup -Pf --show test.hdd > loopback_dev
	sudo partprobe `cat loopback_dev`
	sudo mkfs.fat -F 32 `cat loopback_dev`p1
	sudo mount `cat loopback_dev`p1 test_image
	sudo mkdir test_image/boot
	sudo cp -rv bin/* test/* test_image/boot/
	sudo mkdir -p test_image/EFI/BOOT
	sudo cp bin/BOOTIA32.EFI test_image/EFI/BOOT/
	sync
	sudo umount test_image/
	sudo losetup -d `cat loopback_dev`
	rm -rf test_image loopback_dev
	qemu-system-x86_64 -M q35 -L ovmf -bios ovmf-ia32/OVMF.fd -net none -smp 4 -enable-kvm -cpu host -hda test.hdd -debugcon stdio
