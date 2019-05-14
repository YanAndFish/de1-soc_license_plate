# This is a special makefile format for compiling kernel drivers.
# You may have to update KDIR to point to your configured Linux kernel for
# the ARM processor on the device.

# Configured Linux kernel source.
ifeq ($(ARC_PICE),1)
KDIR ?= /p/psg/flows/sw/aclboardpkg/.platform/linux-socfpga/linux-socfpga-socfpga-4.1.22-ltsi
else
KDIR ?= /tools/aclboardpkg/.platform/linux-socfpga/linux-socfpga-socfpga-4.1.22-ltsi
endif


CROSS_COMPILE := arm-linux-gnueabihf-
ARCH := arm

# Final module
obj-m := aclsoc_drv.o

# List of object files to compile for the final module.
aclsoc_drv-y := aclsoc.o aclsoc_fileio.o aclsoc_pr.o aclsoc_cmd.o aclsoc_dma.o

all :
	$(CROSS_COMPILE)gcc -g -DLINUX -Wall -Werror -o user user.c
	[ ! -d $(KDIR) ] || CFLAGS=-DCONFIG_INTELFPGA_STAPL $(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -C $(KDIR) M=`pwd` modules

clean : clean-intermediates clean-module

clean-module :
	rm -f *.ko

clean-intermediates:
	rm -f $(obj-m)
	rm -f *.o
	rm -f *.mod.*
	rm -f *.symvers
	rm -f *.order
	rm -f .acl*cmd
	rm -rf .tmp_versions

.PHONY: all clean clean-intermediates clean-module
