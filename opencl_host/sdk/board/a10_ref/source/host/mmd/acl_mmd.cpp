// (C) 1992-2018 Intel Corporation.                            
// Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
// and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
// and/or other countries. Other marks and brands may be claimed as the property  
// of others. See Trademarks on intel.com for full list of Intel trademarks or    
// the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
// Your use of Intel Corporation's design tools, logic functions and other        
// software and tools, and its AMPP partner logic functions, and any output       
// files any of the foregoing (including device programming or simulation         
// files), and any associated documentation or information are expressly subject  
// to the terms and conditions of the Altera Program License Subscription         
// Agreement, Intel MegaCore Function License Agreement, or other applicable      
// license agreement, including, without limitation, that your use is for the     
// sole purpose of programming logic devices manufactured by Intel and sold by    
// Intel or its authorized distributors.  Please refer to the applicable          
// agreement for further details.                                                 


/* ===- acl_mmd.cpp  ------------------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file implements the functions that are defined in aocl_mmd.h               */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */


// common and its own header files
#include "acl_mmd.h"

// other header files inside MMD driver
#include "acl_mmd_device.h"
#include "acl_mmd_debug.h"

// other standard header files
#include <string.h>
#include <stdarg.h>
#include <stdlib.h>

#include <map>
#include <sstream>

#if defined(LINUX)
#  include <signal.h>
#endif   // LINUX

// static helper functions
static bool   blob_has_elf_signature( void* data, size_t data_size );

// global variables used for handling multi-devices and its helper functions
static std::map<int, ACL_MMD_DEVICE*> s_handle_map;
static std::map<int, const char *>     s_device_name_map;

static inline ACL_MMD_DEVICE *get_mmd_device(int handle)
{
   std::map<int, ACL_MMD_DEVICE*>::iterator it = s_handle_map.find(handle);
   ACL_MMD_ASSERT(it != s_handle_map.end(), "can't find handle %d -- aborting\n", handle);

   return it->second;
}

static void discard_mmd_device_handle(int handle)
{
   ACL_MMD_ASSERT(s_handle_map.find(handle) != s_handle_map.end(), "can't find handle %d\n", handle);
   s_handle_map.erase(handle);
   s_device_name_map.erase(handle);
}

static inline bool is_any_device_being_programmed()
{
   bool ret = false;
   for( std::map<int, ACL_MMD_DEVICE*>::iterator it = s_handle_map.begin(); it != s_handle_map.end(); it++) {
      if( it->second->is_being_programmed() ) {
         ret = true;
         break;
      }
   }
   return ret;
}

// Functions for handling interrupts or signals for multiple devices
// This functions are used inside the ACL_MMD_DEVICE class
// On Linux, driver will send a SIG_INT_NOTIFY *signal* to notify about an interrupt.
void mmd_linux_signal_handler (int sig, siginfo_t *info, void *unused)
{
   // the last bit indicates the DMA completion
   unsigned int irq_type_flag = info->si_int & 0x1;
   // other bits shows the handle value of the device that sent the interrupt
   unsigned int handle        = info->si_int >> 1;

   if( s_handle_map.find(handle) == s_handle_map.end() ) {
      ACL_MMD_DEBUG_MSG(":: received an unknown handle %d in signal handler, ignore this.\n", handle);
      return;
   }

   s_handle_map[handle]->service_interrupt(irq_type_flag);
}

// Function to free all ACL_MMD_DEVICE struct allocated for open devices
static inline void free_all_open_devices()
{
   for( std::map<int, ACL_MMD_DEVICE*>::iterator it = s_handle_map.begin(); it != s_handle_map.end(); it++) {
      delete it->second;
   }
}

void ctrl_c_handler(int sig_num)
{
   if( is_any_device_being_programmed() ) {
      ACL_MMD_INFO("The device is still being programmed, cannot terminate at this point.\n");
      return;
   }

   // Free all the resource allocated for open devices before exit the program.
   // It also notifies the kernel driver about the termination of the program,
   // so that the kernel driver won't try to talk to any user-allocated memory
   // space (mainly for the DMA) after the program exit.
   free_all_open_devices();
   exit(1);
}

void abort_signal_handler(int sig_num)
{
   free_all_open_devices();
   exit(1);
}

// Function to install the signal handler for Ctrl-C
// If ignore_sig != 0, the ctrl-c signal will be ignored by the program
// If ignore_sig  = 0, the custom signal handler (ctrl_c_handler) will be used
int install_ctrl_c_handler(int ingore_sig)
{
   struct sigaction sig;
   sig.sa_handler = (ingore_sig ? SIG_IGN : ctrl_c_handler);
   sigemptyset(&sig.sa_mask);
   sig.sa_flags = 0;
   sigaction(SIGINT, &sig, NULL);

   return 0;
}

// Get information about the board using the enum aocl_mmd_offline_info_t for
// offline info (called without a handle), and the enum aocl_mmd_info_t for
// info specific to a certain board.
#define RESULT_INT(X) {*((int*)param_value) = X; if (param_size_ret) *param_size_ret=sizeof(int);}
#define RESULT_STR(X) do { \
    size_t Xlen = strlen(X) + 1; \
    memcpy((void*)param_value,X,(param_value_size <= Xlen) ? param_value_size : Xlen); \
    if (param_size_ret) *param_size_ret=Xlen; \
  } while(0)

int aocl_mmd_get_offline_info(
   aocl_mmd_offline_info_t requested_info_id,
   size_t param_value_size,
   void* param_value,
   size_t* param_size_ret
)
{
   switch(requested_info_id)
   {
      case AOCL_MMD_VERSION:     RESULT_STR(MMD_VERSION); break;
      case AOCL_MMD_NUM_BOARDS:  RESULT_INT(ACL_MAX_DEVICE); break;
      case AOCL_MMD_BOARD_NAMES:
      {
         // Construct a list of all possible devices supported by this MMD layer
         std::ostringstream boards;
         for (unsigned i=0; i<ACL_MAX_DEVICE; i++) {
            boards << "acl" << i;
            if (i<ACL_MAX_DEVICE-1) boards << ";";
         }
         RESULT_STR(boards.str().c_str());
         break;
      }
      case AOCL_MMD_VENDOR_NAME:
      {
         RESULT_STR(ACL_VENDOR_NAME);
         break;
      }
      case AOCL_MMD_VENDOR_ID:  RESULT_INT(ACL_MMD_ALTERA_VENDOR_ID); break;
      case AOCL_MMD_USES_YIELD:  RESULT_INT(0); break;
      case AOCL_MMD_MEM_TYPES_SUPPORTED: RESULT_INT(AOCL_MMD_PHYSICAL_MEMORY); break;
   }
   return 0;
}

int aocl_mmd_get_info(
   int handle,
   aocl_mmd_info_t requested_info_id,
   size_t param_value_size,
   void* param_value,
   size_t* param_size_ret
)
{
   ACL_MMD_DEVICE *mmd_dev = get_mmd_device(handle);
   ACL_MMD_ERROR_IF(!mmd_dev->is_initialized(), return -1,
      "aocl_mmd_get_info failed due to the target device (handle %d) is not properly initialized.\n", handle);

   switch(requested_info_id)
   {
     case AOCL_MMD_BOARD_NAME:            RESULT_STR(ACL_BOARD_NAME); break;
     case AOCL_MMD_NUM_KERNEL_INTERFACES: RESULT_INT(1); break;
     case AOCL_MMD_KERNEL_INTERFACES:     RESULT_INT(AOCL_MMD_KERNEL); break;
#if USE_KERNELPLL_RECONFIG==0
     case AOCL_MMD_PLL_INTERFACES:        RESULT_INT(-1); break;
#else
     case AOCL_MMD_PLL_INTERFACES:        RESULT_INT(AOCL_MMD_PLL); break;
#endif
     case AOCL_MMD_MEMORY_INTERFACE:      RESULT_INT(AOCL_MMD_MEMORY); break;
     case AOCL_MMD_TEMPERATURE:
     {
         float *r;
         int temp;
         mmd_dev->get_ondie_temp_slow_call( &temp );
         r = (float*)param_value;
         *r = (float)temp;
         if (param_size_ret)
           *param_size_ret = sizeof(float);
         break;
     }

     // currently not supported
     case AOCL_MMD_PCIE_INFO: /* FALLTHRU */
     case AOCL_MMD_BOARD_UNIQUE_ID:       return -1;
   }
   return 0;
}

#undef RESULT_INT
#undef RESULT_STR



// Open and initialize the named device.
int AOCL_MMD_CALL aocl_mmd_open(const char *name)
{
   static int signal_handler_installed = 0;
   static int unique_id = 0;
   int dev_num = -1;

   if (sscanf(name, "acl%d", &dev_num) != 1)     { return -1; }
   if (dev_num < 0 || dev_num >= ACL_MAX_DEVICE) { return -1; }
   if (++unique_id <= 0)                         { unique_id = 1; }

   ACL_MMD_ASSERT(s_handle_map.find(unique_id) == s_handle_map.end(),
      "unique_id %d is used before.\n", unique_id);

   if(signal_handler_installed == 0) {
      // Enable if driver is using signals to communicate with the host.
      struct sigaction sig;
      sig.sa_sigaction = mmd_linux_signal_handler;
      sig.sa_flags = SA_SIGINFO;
      sigaction(SIG_INT_NOTIFY, &sig, NULL);

      // Install signal handler for SIGABRT from assertions in the upper layers
      struct sigaction sig1;
      sig1.sa_handler = abort_signal_handler;
      sigemptyset(&sig1.sa_mask);
      sig1.sa_flags = 0;
      sigaction(SIGABRT, &sig1, NULL);

      install_ctrl_c_handler(0 /* use the custom signal handler */);
      signal_handler_installed = 1;
   }
   ACL_MMD_DEVICE *mmd_dev = new ACL_MMD_DEVICE( dev_num, name, unique_id );
   if ( !mmd_dev->is_valid() ){
      delete mmd_dev;
      return -1;
   }

   s_handle_map[ unique_id ] = mmd_dev;
   s_device_name_map[ unique_id ] = name;
   if (mmd_dev->is_initialized()) {
      return unique_id;
   } else {
      // Perform a bitwise-not operation to the unique_id if the device
      // do not pass the initial test. This negative unique_id indicates
      // a fail to open the device, but still provide actual the unique_id
      // to allow reprogram executable to get access to the device and
      // reprogram the board when the board is not usable.
      return ~unique_id;
   }
}

// Close an opened device, by its handle.
int AOCL_MMD_CALL aocl_mmd_close(int handle)
{
   delete get_mmd_device(handle);
   discard_mmd_device_handle(handle);

   return 0;
}



// Set the interrupt handler for the opened device.
int AOCL_MMD_CALL aocl_mmd_set_interrupt_handler( int handle, aocl_mmd_interrupt_handler_fn fn, void* user_data )
{
   ACL_MMD_DEVICE *mmd_dev = get_mmd_device(handle);
   ACL_MMD_ERROR_IF(!mmd_dev->is_initialized(), return -1,
      "aocl_mmd_set_interrupt_handler failed due to the target device (handle %d) is not properly initialized.\n", handle);

   return mmd_dev->set_kernel_interrupt(fn, user_data);
}

// Set the operation status handler for the opened device.
int AOCL_MMD_CALL aocl_mmd_set_status_handler( int handle, aocl_mmd_status_handler_fn fn, void* user_data )
{
   ACL_MMD_DEVICE *mmd_dev = get_mmd_device(handle);
   ACL_MMD_ERROR_IF(!mmd_dev->is_initialized(), return -1,
      "aocl_mmd_set_status_handler failed due to the target device (handle %d) is not properly initialized.\n", handle);

   return mmd_dev->set_status_handler(fn, user_data);
}



// Called when the host is idle and hence possibly waiting for events to be
// processed by the device
int AOCL_MMD_CALL aocl_mmd_yield(int handle)
{
   return get_mmd_device(handle)->yield();
}



// Read, write and copy operations on a single interface.
int AOCL_MMD_CALL aocl_mmd_read(
   int handle,
   aocl_mmd_op_t op,
   size_t len,
   void* dst,
   int mmd_interface, size_t offset )
{
   void * host_addr = dst;
   size_t dev_addr  = offset;

   ACL_MMD_DEVICE *mmd_dev = get_mmd_device(handle);
   ACL_MMD_ERROR_IF(!mmd_dev->is_initialized(), return -1,
      "aocl_mmd_read failed due to the target device (handle %d) is not properly initialized.\n", handle);

   return mmd_dev->read_block( op, (aocl_mmd_interface_t)mmd_interface, host_addr, dev_addr, len );
}

void * get_pc() { return __builtin_return_address(0); }
int AOCL_MMD_CALL aocl_mmd_write(
   int handle,
   aocl_mmd_op_t op,
   size_t len,
   const void* src,
   int mmd_interface, size_t offset )
{
   void * host_addr = const_cast<void *>(src);
   size_t dev_addr  = offset;
   ACL_MMD_DEVICE *mmd_dev = get_mmd_device(handle);
   ACL_MMD_ERROR_IF(!mmd_dev->is_initialized(), return -1,
      "aocl_mmd_write failed due to the target device (handle %d) is not properly initialized.\n", handle);
   int ret_val = mmd_dev->write_block( op, (aocl_mmd_interface_t)mmd_interface, host_addr, dev_addr, len );
   return ret_val;
}

int AOCL_MMD_CALL aocl_mmd_copy(
    int handle,
    aocl_mmd_op_t op,
    size_t len,
    int mmd_interface, size_t src_offset, size_t dst_offset )
{
   ACL_MMD_DEVICE *mmd_dev = get_mmd_device(handle);
   ACL_MMD_ERROR_IF(!mmd_dev->is_initialized(), return -1,
      "aocl_mmd_copy failed due to the target device (handle %d) is not properly initialized.\n", handle);

   return mmd_dev->copy_block( op, (aocl_mmd_interface_t)mmd_interface, src_offset, dst_offset, len );
}

// not used by c5soc
// Reprogram the device
int AOCL_MMD_CALL aocl_mmd_reprogram(int handle, void *data, size_t data_size)
{
   // assuming the an ELF-formatted blob.
   if ( !blob_has_elf_signature( data, data_size ) ) {
      printf("DOES NOT HAVE ELF SIGNATURE\n");
      ACL_MMD_DEBUG_MSG("ad hoc fpga bin\n");
      return -1;
   }

   if( get_mmd_device(handle)->reprogram( data, data_size ) ) {
      printf("Reprogram FAILED\n");
      return -1;
   }

   // Delete and re-open the device to reinitialize hardware
   const char *device_name = s_device_name_map[handle];
   delete get_mmd_device(handle);
   discard_mmd_device_handle(handle);

   return aocl_mmd_open(device_name);
}


// Shared memory allocator
AOCL_MMD_CALL void* aocl_mmd_shared_mem_alloc( int handle, size_t size, unsigned long long *device_ptr_out )
{
   return get_mmd_device(handle)->shared_mem_alloc (size, device_ptr_out);
}

// Shared memory de-allocator
AOCL_MMD_CALL void aocl_mmd_shared_mem_free ( int handle, void* host_ptr, size_t size )
{
   get_mmd_device(handle)->shared_mem_free (host_ptr, size);
}

// This function checks if the input data has an ELF-formatted blob.
// Return true when it does.
static bool blob_has_elf_signature( void* data, size_t data_size )
{
   bool result = false;
   if ( data && data_size > 4 ) {
      unsigned char* cdata = (unsigned char*)data;
      const unsigned char elf_signature[4] = { 0177, 'E', 'L', 'F' }; // Little endian
      result = (cdata[0] == elf_signature[0])
            && (cdata[1] == elf_signature[1])
            && (cdata[2] == elf_signature[2])
            && (cdata[3] == elf_signature[3]);
   }
   return result;
}
