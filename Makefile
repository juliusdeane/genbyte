##############################################################################
# Author: Julius Deane <cloud-svc@juliusdeane.com>
# AKA: Román Ramírez <rramirez@rootedcon.com>
# License: Apache 2.0

# Hope you find this tool useful :)
# Quick use:
# $ make
# $ make generate_key
# $ make install_key
# $ make sign
# $ make install
# $ sudo insmod bytegen
# ...
# $ sudo rmmod bytegen
# ...
# $ make test
##############################################################################

# This will be the name of the files created, for example, [bytegen].ko.
TARGET_MODULE := bytegen
UDEV_RULES_FILENAME := /etc/udev/rules.d/99-$(TARGET_MODULE).rules
UDEV_RULES_FILENAME_EXISTS = $(shell test -e $(UDEV_RULES_FILENAME) && echo yes)

# Get actual directory.
PWD := $(shell pwd)

# KERNEL_VERSION variable may define a particular kernel to use.
# * if not set, default to actual kernel in use.
KERNEL_VERSION ?= $(shell uname -r)

# /lib/modules/<6.8.0-86-generic>/build/...
BUILDSYSTEM_DIR ?= /lib/modules/$(KERNEL_VERSION)/build
KERNEL_EXTRA_DIR ?= /lib/modules/$(KERNEL_VERSION)/extra
KERNEL_UPDATES_DIR ?= /lib/modules/$(KERNEL_VERSION)/updates

# Default compiler may be gcc:
# - But, setting this removes a warning :)
#COMPILER := gcc
COMPILER := x86_64-linux-gnu-gcc-12

obj-m := $(TARGET_MODULE).o
ccflags-y := -std=gnu99 -Wno-declaration-after-statement

# BE Careful with this: too short and you will end rebooting and enrolling
# keys many times...
# => 15 years key live (in days).
KEY_NAME := MOK
KEY_SIZE := 4096
KEY_LIVE_DAYS := 4749
KEY_COMMON_NAME := JuliusDeaneMOKey
HASH_ALGORITHM := sha512

##############################################################################
# // END config variables.
##############################################################################

##############################################################################
# BEGIN make options.
##############################################################################
# make / make all
all: build

# https://www.kernel.org/doc/html/v4.15/admin-guide/module-signing.html
generate_key:
	@echo "[SIGNING KEYS] Create signing keys (MOK):"
	@openssl req -new -batch -x509 -nodes -utf8 -$(HASH_ALGORITHM) \
                 -newkey rsa:$(KEY_SIZE) \
                 -days $(KEY_LIVE_DAYS) \
                 -keyout $(KEY_NAME).secret -outform DER -out $(KEY_NAME).der \
                 -subj "/CN=$(KEY_COMMON_NAME)/"

install_key:
	sudo cp $(KEY_NAME).der $(BUILDSYSTEM_DIR)/certs/$(KEY_NAME).x509
	sudo cp $(KEY_NAME).secret $(BUILDSYSTEM_DIR)/certs/$(KEY_NAME).pem
	@echo "==> IMPORTANT:"
	@echo "Now you'll asked a password you will need to enter after reboot, so you can enroll the key for the kernel to be able to load the module."
	@echo "Please, take care of this as this is a critical step if you have Secure Boot and your kernel does not allow to load arbitrary modules."
	@echo
	@echo "Enter password now:"
	@sudo mokutil --import $(KEY_NAME).der
	@echo
	@echo "Now *reboot*, then follow the instructions to add the key and finally enter the password."
	@echo

build:
# BUILD considerations:
# 1. CONFIG_DEBUG_INFO_BTF_MODULES=, empty is a trick to avoid getting this warning:
#
# "Skipping BTF generation for /home/user/bytegen.ko due to unavailability of vmlinux"
#
# 2. CC=$(COMPILER), is a trick to avoid getting this warning:
#
# "  The kernel was built by: x86_64-linux-gnu-gcc-12 (Ubuntu 12.3.0-1ubuntu1~22.04.2) 12.3.0
#    You are using:           gcc-12 (Ubuntu 12.3.0-1ubuntu1~22.04.2) 12.3.0"
#
	@echo "[BUILD] Compile kernel module:"
	$(MAKE) CONFIG_DEBUG_INFO_BTF_MODULES= CC=$(COMPILER) -C $(BUILDSYSTEM_DIR) M=$(PWD) modules
	@echo

sign:
	@echo "[SIGN] Sign kernel module with keys loaded into the MOK:"
	@cp $(TARGET_MODULE).ko $(TARGET_MODULE).ko.bak
# Using kernel helper tool:
	@/usr/src/linux-headers-$(shell uname -r)/scripts/sign-file $(HASH_ALGORITHM) $(KEY_NAME).secret $(KEY_NAME).der $(TARGET_MODULE).ko
# You may prefer to use kmodsign directly:
# @kmodsign $(HASH_ALGORITHM) $(KEY_NAME).secret $(KEY_NAME).der $(TARGET_MODULE).ko
	@echo

install:
	@echo "[MODULE INSTALL] Will require root privileges."
# ASSURE extra/ modules dir exists and it is ready.
	@sudo mkdir -p $(KERNEL_EXTRA_DIR)
	@sudo $(MAKE) -C $(BUILDSYSTEM_DIR) M=$(PWD) modules_install
	@sudo depmod -a
	@echo

uninstall:
	@echo "[MODULE UNINSTALL] Will require root privileges."
	@sudo rm -f $(KERNEL_EXTRA_DIR)/$(TARGET_MODULE).ko
	@sudo rm -f $(KERNEL_UPDATES_DIR)/$(TARGET_MODULE).ko

	@sudo modprobe -r $(TARGET_MODULE)
# Will not try to remove extra/. Maybe it was already there and we break something :-?
	@sudo depmod -a
	@echo

load:
	@echo "[MODULE LOAD] Using modprobe."
	@modprobe $(TARGET_MODULE)
	@echo

unload:
	@echo "[MODULE UNLOAD] Using modprobe."
	@sudo modprobe -r $(TARGET_MODULE)
	@echo

insmod:
	@echo "[MODULE LOAD] Using insmod."
	@sudo insmod ./$(TARGET_MODULE).ko

rmmod:
	@echo "[MODULE UNLOAD] Using rmsmod."
	@sudo rmmod ./$(TARGET_MODULE).ko

testmod:
	@echo "[MODULE TEST LOADED] Using lsmod."
	@lsmod |grep -i $(TARGET_MODULE)

test:
	@echo "[MODULE TEST] Using dd (4 x A)."
	@if [ "$(shell sudo dd if=/dev/$(TARGET_MODULE)/0x41 bs=1 count=4)" = "AAAA" ]; then \
		echo "\e[32m[OK] Test successful.\e[0m"; \
		exit 0; \
	else \
		echo "\e[31m[ERROR] Test failed.\e[0m"; \
		exit 1; \
	fi
	@echo

clean:
	@rm -f *.ko *.o .bytegen.* .Module* .module* Module.symvers modules.order bytegen.mod* *.ko.bak
##############################################################################
# //END make options.
##############################################################################
