ECHO = @
CXX = arm-linux-gnueabihf-g++ -o 
CPPFLAGS = -DKERNEL_64BIT -DARM -DACL_HOST_MEMORY_SHARED=1 -DOPTION3=1 -DACL_USE_DMA=0 -DACL_COMPILER_IS_MSVC=0 -Wall -Wno-unknown-pragmas -Wno-delete-non-virtual-dtor -D__USE_XOPEN2K8 -Werror -DACL_HAS_STDLIB_STDIO -DACL_HOST_RUNTIME_IS_STATIC=0 -DACL_OPENCL_HOST_SYS=arm -DACL_OPENCL_HOST_BIT=32 -DACL_TARGET_SYS=linux -DACL_TARGET_BIT=64 -DLINUX -DKERNEL_DRIVER_VERSION_EXPECTED=\"18.1\" -DACL_MAX_DEVICE=16 -DACL_VERSION=\"v18.1.0\" -I. -I../../include -I$(INTELFPGAOCLSDKROOT)/host/include/CL -I$(TOP_DEST_DIR)/arm32/driver -I$(INTELFPGAOCLSDKROOT)/host/arm32
CXXFLAGS = -fPIC 

LINKER = g++
LINKER_LIBDIRARGS = -Llib -L$(INTELFPGAOCLSDKROOT)/host/arm32/lib
LINKER_ARGS = -lrt -z noexecstack -Wl,-z,relro,-z,now -Wl,-Bsymbolic -fPIC -Wl,--no-undefined -Wl,--exclude-libs,ALL 
INCORPORATE_LIBS = -lpkg_editor
PREBUILT_OBJS = 
LINK_LIBS =  -lelf 
ARM_CROSS_COMPILER_PREFIX = arm-linux-gnueabihf-

DLLFILE = lib$(MMD_LIB_NAME).so
DLLLIBFILE = 
PERVASIVE_DEPENDENCIES = ../../include/aocl_mmd.h ../../include/pkg_editor.h $(TOP_DEST_DIR)/arm32/driver/hw_mmd_constants.h $(TOP_DEST_DIR)/arm32/driver/mmd_linux_driver_exports.h $(TOP_DEST_DIR)/arm32/driver/version.h

OBJ_EXT = o
OBJS = $(patsubst %.cpp,%.$(OBJ_EXT),$(wildcard *.cpp))
OBJ_DIR?= .
OBJ_FILES = $(addprefix $(OBJ_DIR)$(PS),$(OBJS))



CUR_REL_PATH = ../..

INSTALL_DIR = $(TOP_DEST_DIR)$(PS)arm32$(PS)lib
TARGET_FILES = $(DLLFILE)
SPECIAL_INSTALL_FILE = 
SUB_DIRS =

include $(CUR_REL_PATH)/Makefile.common
