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


/* ===- acl_mmd_device.cpp  ------------------------------------------ C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file implements the class to handle operations on a single device.         */
/* The declaration of the class lives in the acl_mmd_device.h                     */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */


// common and its own header files
#include "acl_mmd.h"
#include "acl_mmd_device.h"

// other header files inside MMD driver
#include "acl_mmd_config.h"
#include "acl_mmd_dma.h"
#include "acl_mmd_mm_io.h"
#include "acl_mmd_debug.h"
#include "pkg_editor.h"

// other standard header files
#include <sstream>
#include <stdlib.h>
#include <fstream>
#include <string.h>

#if defined(LINUX)
#  include <sys/types.h>
#  include <sys/stat.h>
#  include <sys/time.h>
#  include <sys/mman.h>
#  include <fcntl.h>
#  include <signal.h>
#  include <unistd.h>
#endif   // LINUX



static int num_open_devices = 0;

WDC_DEVICE_HANDLE open_device_linux(ACL_MMD_DEVICE_DESCRIPTION *info, int dev_num);

ACL_MMD_DEVICE::ACL_MMD_DEVICE( int dev_num, const char *name, int handle ) :
   kernel_interrupt(NULL),
   kernel_interrupt_user_data(NULL),
   event_update(NULL),
   event_update_user_data(NULL),
   m_io( NULL ),
   m_dma( NULL ),
   m_config( NULL ),
   m_handle( -1 ),
   m_device( INVALID_DEVICE ),
   m_use_dma_for_big_transfers(false),
   m_mmd_irq_handler_enable( false ),
   m_initialized( false ),
   m_being_programmed( false )
{
   ACL_MMD_ASSERT(name != NULL, "passed in an empty name pointer when creating device object.\n");

   int status = 0;

   // Set debug level from the environment variable ACL_MMD_DEBUG
   // Determine if warning messages should be disabled depends on ACL_MMD_WARNING
   if (num_open_devices == 0) {
      set_mmd_debug();
      set_mmd_warn_msg();
   }

   strncpy( m_name, name, (MAX_NAME_LENGTH-1) );
   m_name[(MAX_NAME_LENGTH-1)] = '\0';

   m_handle         = handle;
   m_info.vendor_id = ACL_MMD_ALTERA_VENDOR_ID;
   m_info.device_id = ACL_MMD_BSP_DEVICE_ID;

   m_device = open_device_linux  (&m_info, dev_num);

   // Return to caller if this is simply an invalid device.
   if (m_device == INVALID_DEVICE) {  return;  }

   // Initialize device IO and CONFIG objects
   m_io     = new ACL_MMD_MM_IO_MGR( m_device );
   m_config = new ACL_MMD_CONFIG   ( m_device );

   // Set the segment ID to 0 first forcing cached "segment" to all 1s
   m_segment=(size_t)~0;
   if ( this->set_segment( 0x0 ) ) {  return;  }

   // performance basic I/O tests
   if ( this->version_id_test() ) {   return;   }


   // Initialize the DMA object and enable interrupts on the DMA controller
   ACL_MMD_DEBUG_MSG(":: [%s] INITIALIZING MMD DMA\n", m_name);
   m_dma    = new ACL_MMD_DMA( m_device, m_io, this );
   ACL_MMD_DEBUG_MSG(":: [%s] Writing to DMA CSR control\n", m_name);
   status = m_io->dma->write32( DMA_CSR_CONTROL, ACL_GET_BIT(DMA_CTRL_IRQ_ENABLE) );
   ACL_MMD_ERROR_IF(status, return,
      "[%s] fail to enable interrupts on the DMA controller.\n", m_name);

   if ( this->enable_interrupts() ) {  return;  }

   // Done!
   m_initialized = true;
   ACL_MMD_DEBUG_MSG(":: [%s] successfully initialized (device id: %x).\n", m_name, m_info.device_id);
   ACL_MMD_DEBUG_MSG("::           Using DMA for big transfers? %s\n",
            ( m_use_dma_for_big_transfers ? "yes" : "no" ) );
}

ACL_MMD_DEVICE::~ACL_MMD_DEVICE()
{
   int status = this->disable_interrupts();
   ACL_MMD_ERROR_IF(status, /* do nothing */ ,
      "[%s] fail disable interrupt in device destructor.\n", m_name);

   if(m_config)   { delete m_config; m_config = NULL; }
   if(m_io)       { delete m_io;     m_io = NULL;     }

   if(is_valid()) {
      --num_open_devices;
      close (m_device);
   }
}

WDC_DEVICE_HANDLE open_device_linux(ACL_MMD_DEVICE_DESCRIPTION *info, int dev_num)
{
   char buf[128] = {0};
   char expected_ver_string[128] = {0};

   sprintf(buf,"/dev/acl%d", dev_num);
   ssize_t device = open (buf, O_RDWR);

   // Try the CV device name if device not found for the first device
   if (device == -1 && dev_num == 0) {
      if (ACL_MMD_CONFIG::fpga_in_user_mode()) {
         ACL_MMD_DEBUG_MSG(":: FPGA is in user mode. Enabling bridges\n");
         ACL_MMD_CONFIG::enable_bridges();
      } else {
         ACL_MMD_DEBUG_MSG(":: FPGA is NOT in user mode. Bridges are disabled!\n");
      }
      sprintf(buf,"/dev/acl");
      device = open (buf, O_RDWR);
   }

   // Return INVALID_DEVICE when the device is not available
   if (device == -1) {
      return INVALID_DEVICE;
   }

   // Make sure the Linux kernel driver is recent
   struct acl_cmd driver_cmd = { ACLSOC_CMD_BAR, ACLSOC_CMD_GET_DRIVER_VERSION,
                              NULL, buf, 0 };
   read (device, &driver_cmd, 0);

   sprintf(expected_ver_string, "%s", KERNEL_DRIVER_VERSION_EXPECTED);

   ACL_MMD_ERROR_IF( strstr(buf, expected_ver_string) != buf, return INVALID_DEVICE,
      "Kernel driver version is %s. Expected version %s\n", buf, expected_ver_string );

   // Set the FD_CLOEXEC flag for the file handle to disable the child to
   // inherit this file handle. So the jtagd will not hold the file handle
   // of the device and keep sending bogus interrupts after we call quartus_pgm.
   int oldflags = fcntl( device, F_GETFD, 0);
   fcntl( device, F_SETFD, oldflags | FD_CLOEXEC );

   ++num_open_devices;
   return device;
}

// Perform operations required when an interrupt is received for this device
void ACL_MMD_DEVICE::service_interrupt(unsigned int irq_type_flag)
{
   unsigned int kernel_update = 0;
   unsigned int dma_update    = 0;

   int status = this->get_interrupt_type(&kernel_update, &dma_update, irq_type_flag);
   ACL_MMD_ERROR_IF(status, return, "[%s] fail to service the interrupt.\n", m_name);

   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_IRQ,
      ":: [%s] Irq service routine called, kernel_update=%d, dma_update=%d \n",
      m_name, kernel_update, dma_update);

   if (kernel_update && kernel_interrupt != NULL) {
      // A kernel-status interrupt - update the status of running kernels
      ACL_MMD_ASSERT(kernel_interrupt,
         "[%s] received kernel interrupt before the handler is installed.\n", m_name);
      kernel_interrupt(m_handle, kernel_interrupt_user_data);
   } else if (dma_update) {
      // A DMA-status interrupt - let the DMA object handle this
      m_dma->service_interrupt();
   }

   // Unmask the kernel_irq to enable the interrupt again.
   if(m_mmd_irq_handler_enable){
      status = this->unmask_irqs();
   } else if(kernel_update) {
      status = this->unmask_kernel_irq();
   }
   ACL_MMD_ERROR_IF(status, return, "[%s] fail to service the interrupt.\n", m_name);

   return;
}



// Enable all interrupts (Kernel)
// Won't enable kernel irq unless kernel interrupt callback has been initialized
// Return 0 on success
int ACL_MMD_DEVICE::unmask_irqs()
{
   int status;
   if ( kernel_interrupt == NULL ) {
      status = m_io->mmd_cra->write32( MMD_CRA_IRQ_ENABLE,
          ACL_GET_BIT(ACL_MMD_DMA_IRQ_VEC));
   } else {
      status = m_io->mmd_cra->write32( MMD_CRA_IRQ_ENABLE,
          ACL_GET_BIT(ACL_KERNEL_IRQ_VEC) | ACL_GET_BIT(ACL_MMD_DMA_IRQ_VEC));
   }
   ACL_MMD_ERROR_IF(status, return -1, "[%s] fail to unmask all interrupts.\n", m_name);

   return 0; // success
}

// Enable the kernel interrupt only
// Return 0 on success
int ACL_MMD_DEVICE::unmask_kernel_irq()
{
   int status = 0;
   UINT32 val = 0;

   status |= m_io->mmd_cra->read32 ( MMD_CRA_IRQ_ENABLE, &val);
   val    |= ACL_GET_BIT(ACL_KERNEL_IRQ_VEC);
   status |= m_io->mmd_cra->write32( MMD_CRA_IRQ_ENABLE, val);

   ACL_MMD_ERROR_IF(status, return -1, "[%s] fail to unmask the kernel interrupts.\n", m_name);

   return 0; // success
}

// Disable the interrupt
// Return 0 on success
int ACL_MMD_DEVICE::disable_interrupts()
{
   int status;

   if(m_mmd_irq_handler_enable) {
      ACL_MMD_DEBUG_MSG(":: [%s] Disabling interrupts.\n", m_name);

      status = m_io->mmd_cra->write32( MMD_CRA_IRQ_ENABLE, 0 );
      ACL_MMD_ERROR_IF(status, return -1, "[%s] failed to disable mmd interrupt.\n", m_name);
      m_mmd_irq_handler_enable = false;
   }

   return 0; // success
}
// For Linux, it will set-up a signal handler for signals for kernel driver
// Return 0 on success
int ACL_MMD_DEVICE::enable_interrupts()
{
   int status;
   ACL_MMD_DEBUG_MSG(":: [%s] Enabling MMD interrupts on Linux (via signals).\n", m_name);

   // All interrupt controls are in the kernel driver.
   m_mmd_irq_handler_enable = false;

   // Set "our" device id (the handle id received from acl_mmd.cpp) to correspond to
   // the device managed by the driver. Will get back this id
   // with signal from the driver. Will allow us to differentiate
   // the source of kernel-done signals with multiple boards.

   int result = m_handle << 1;
   struct acl_cmd read_cmd = { ACLSOC_CMD_BAR,
                               ACLSOC_CMD_SET_SIGNAL_PAYLOAD,
                               NULL,
                               &result };
   status = write (m_device, &read_cmd, sizeof(result));
   ACL_MMD_ERROR_IF( status, return -1, "[%s] failed to enable interrupts.\n", m_name );

   return 0; // success
}

// Determine the interrupt type using the irq_type_flag
// Return 0 on success
int ACL_MMD_DEVICE::get_interrupt_type (unsigned int *kernel_update, unsigned int *dma_update, unsigned int irq_type_flag)
{
   *kernel_update = irq_type_flag ? 0: 1;
   *dma_update = 1 - *kernel_update;

   return 0; // success
}
// Called by the host program when there are spare cycles
int ACL_MMD_DEVICE::yield()
{
   usleep(0);
   return 0;
}



// Set kernel interrupt and event update callbacks
// return 0 on success
int ACL_MMD_DEVICE::set_kernel_interrupt(aocl_mmd_interrupt_handler_fn fn, void * user_data)
{
   int status;

   kernel_interrupt = fn;
   kernel_interrupt_user_data = user_data;

   if ( m_device != INVALID_DEVICE ) {
      status = this->unmask_kernel_irq();
      ACL_MMD_ERROR_IF(status, return -1, "[%s] failed to set kernel interrupt callback funciton.\n", m_name);
   }

   return 0; // success
}

int ACL_MMD_DEVICE::set_status_handler(aocl_mmd_status_handler_fn fn, void * user_data)
{
   event_update = fn;
   event_update_user_data = user_data;

   return 0; // success
}

// The callback function set by "set_status_handler"
// It's used to notify/update the host whenever an event is finished
void ACL_MMD_DEVICE::event_update_fn(aocl_mmd_op_t op, int status)
{
   ACL_MMD_ASSERT(event_update, "[%s] event_update is called with a empty update function pointer.\n", m_name);

   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_OP,":: [%s] Update for event e=%p.\n", m_name, op);
   event_update(m_handle, event_update_user_data, op, status);
}



// Memory I/O
// return 0 on success
int ACL_MMD_DEVICE::write_block( aocl_mmd_op_t e, aocl_mmd_interface_t mmd_interface, void *host_addr, size_t dev_addr, size_t size )
{
   ACL_MMD_ASSERT(event_update, "[%s] event_update callback function is not provided.\n", m_name);
   int status = -1; // assume failure

   switch(mmd_interface)
   {
      case AOCL_MMD_KERNEL:
         ACL_MMD_DEBUG_MSG("AOCL_MMD_KERNEL\n");
         status = m_io->kernel_if->write_block( dev_addr, size, host_addr );
         break;
      case AOCL_MMD_MEMORY:
         ACL_MMD_DEBUG_MSG("AOCL_MMD_MEMORY\n");
         status = read_write_block (e, host_addr, dev_addr, size, false /*writing*/);
         ACL_MMD_DEBUG_MSG("ALRIGHT HERE WE ARE\n");
         break;
      case AOCL_MMD_PLL:
         ACL_MMD_DEBUG_MSG("AOCL_MMD_PLL\n");
         status = m_io->pll->write_block( dev_addr, size, host_addr );
         break;
      default:
         ACL_MMD_ASSERT(0, "[%s] unknown MMD interface.\n", m_name);
   }

   ACL_MMD_ERROR_IF(status, return -1, "[%s] failed to write block.\n", m_name);
   return 0; // success
}

int ACL_MMD_DEVICE::read_block( aocl_mmd_op_t e, aocl_mmd_interface_t mmd_interface, void *host_addr, size_t dev_addr, size_t size )
{
   ACL_MMD_ASSERT(event_update, "[%s] event_update callback function is not provided.\n", m_name);
   int status = -1; // assume failure

   switch(mmd_interface)
   {
      case AOCL_MMD_KERNEL:
         status = m_io->kernel_if->read_block( dev_addr, size, host_addr );
         break;
      case AOCL_MMD_MEMORY:
         status = read_write_block (e, host_addr, dev_addr, size, true /*reading*/);
         break;
      case AOCL_MMD_PLL:
         status = m_io->pll->read_block( dev_addr, size, host_addr );
         break;
      default:
         ACL_MMD_ASSERT(0, "[%s] unknown MMD interface.\n", m_name);
   }

   ACL_MMD_ERROR_IF(status, return -1, "[%s] failed to read block.\n", m_name);

   return 0; // success
}

// Copy a block between two locations in device memory
// return 0 on success
int ACL_MMD_DEVICE::copy_block( aocl_mmd_op_t e, aocl_mmd_interface_t mmd_interface, size_t src, size_t dst, size_t size )
{
   ACL_MMD_ASSERT(event_update, "[%s] event_update callback function is not provided.\n", m_name);
   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_OP,
      ":: [%s] Copying " SIZE_FMT_U " bytes data from 0x" SIZE_FMT_X " (device) to 0x" SIZE_FMT_X " (device), with e=%p\n",
      m_name, size, src, dst, e);

#define BLOCK_SIZE (8*1024*1024)
   static unsigned char data[BLOCK_SIZE] __attribute__((aligned(128)));

   do {
      size_t transfer_size = (size > BLOCK_SIZE) ? BLOCK_SIZE : size;
      read_block ( NULL /* blocking read  */, mmd_interface, data, src, transfer_size );
      write_block( NULL /* blocking write */, mmd_interface, data, dst, transfer_size );

      src  += transfer_size;
      dst  += transfer_size;
      size -= transfer_size;
   } while (size > 0);

   if (e)  { this->event_update_fn(e, 0); }

   return 0; // success
}



// Read or Write a block of data to device memory.
// Directly read/write through BAR
// Return 0 on success
int ACL_MMD_DEVICE::read_write_block( aocl_mmd_op_t e, void *host_addr, size_t dev_addr, size_t size, bool reading )
{
   const uintptr_t uintptr_host = reinterpret_cast<uintptr_t>(host_addr);

   int    status   = 0;
   size_t dma_size = 0;

   if(reading){
      ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_OP,
         ":: [%s] Reading " SIZE_FMT_U " bytes data from 0x" SIZE_FMT_X " (device) to %p (host), with e=%p\n",
         m_name, size, dev_addr, host_addr, e);
   } else {
      ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_OP,
         ":: [%s] Writing " SIZE_FMT_U " bytes data from %p (host) to 0x" SIZE_FMT_X " (device), with e=%p\n",
         m_name, size, host_addr, dev_addr, e);
   }

   // Return immediately if size is zero
   if( size == 0 ) {
      if (e)  { this->event_update_fn(e, 0); }
      return 0;
   }

   bool aligned = ((uintptr_host & DMA_ALIGNMENT_BYTE_MASK) | (dev_addr & DMA_ALIGNMENT_BYTE_MASK)) == 0;
   if ( m_use_dma_for_big_transfers && aligned && (size >= 1024) )
   {
      // DMA transfers must END at aligned boundary.
      // If that's not the case, use DMA up to such boundary, and regular
      // read/write for the remaining part.
      dma_size = size - (size & DMA_ALIGNMENT_BYTE_MASK);
   } else if( m_use_dma_for_big_transfers && (size >= 1024) ) {
      ACL_MMD_WARN_MSG("[%s] NOT using DMA to transfer " SIZE_FMT_U " bytes from %s to %s because of lack of alignment\n"
         "**                 host ptr (%p) and/or dev offset (0x" SIZE_FMT_X ") is not aligned to %u bytes\n",
         m_name, size, (reading ? "device":"host"), (reading ? "host":"device"), host_addr, dev_addr, DMA_ALIGNMENT_BYTES);
   }

   // Perform read/write through BAR if the data is not fit for DMA or if there is remaining part from DMA
   if ( dma_size < size ) {
      void * host_addr_new = reinterpret_cast<void *>(uintptr_host + dma_size);
      size_t dev_addr_new  = dev_addr + dma_size;
      size_t remain_size   = size - dma_size;

      ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_OP,
         ":: [%s] Perform read/write through BAR for remaining " SIZE_FMT_U " bytes (out of " SIZE_FMT_U " bytes)\n",
         m_name, remain_size, size);

      status = read_write_block_bar( host_addr_new, dev_addr_new, remain_size, reading );
      ACL_MMD_ERROR_IF(status, return -1, "[%s] failed to perform read/write through BAR.\n", m_name);
   }

   if ( dma_size != 0 ) {
      m_dma->read_write (host_addr, dev_addr, dma_size, e, reading);

      // Block if event is NULL
      if (e == NULL) {  m_dma->stall_until_idle();  }
   } else {
      if (e != NULL) {  this->event_update_fn(e, 0);  }
   }

   return 0; // success
}

// Read or Write a block of data to device memory through BAR
// Return 0 on success
int ACL_MMD_DEVICE::read_write_block_bar( void *host_addr, size_t dev_addr, size_t size, bool reading )
{
   void * cur_host_addr = host_addr;
   size_t cur_dev_addr  = dev_addr;
   size_t bytes_transfered = 0;

   for (bytes_transfered=0; bytes_transfered<size; )
   {
      // decide the size to transfer for current iteration
      size_t cur_size = ACL_MMD_MEMWINDOW_SIZE - ( cur_dev_addr%ACL_MMD_MEMWINDOW_SIZE );
      if (bytes_transfered + cur_size >= size) {
         cur_size = size - bytes_transfered;
      }

      // set the proper window segment
      set_segment( cur_dev_addr );
      size_t window_rel_ptr_start = cur_dev_addr % ACL_MMD_MEMWINDOW_SIZE;
      size_t window_rel_ptr       = window_rel_ptr_start;

      // A simple blocking read
      // The address should be in the global memory range, we assume
      // any offsets are already accounted for in the offset
      ACL_MMD_ASSERT( window_rel_ptr + cur_size <= ACL_MMD_MEMWINDOW_SIZE,
         "[%s] trying to access out of the range of the memory window.\n", m_name);

      // Workaround a bug in Jungo driver.
      // First, transfer the non 8 bytes data at the front, one byte at a time
      // Then, transfer multiple of 8 bytes (size of size_t) using read/write_block
      // At the end, transfer the remaining bytes, one byte at a time
      size_t dev_odd_start = std::min (sizeof(size_t) - window_rel_ptr % sizeof(size_t), cur_size);
      if (dev_odd_start != sizeof(size_t)) {
         read_write_small_size( cur_host_addr, window_rel_ptr, dev_odd_start, reading );
         incr_ptrs (&cur_host_addr, &window_rel_ptr, &bytes_transfered, dev_odd_start );
         cur_size -= dev_odd_start;
      }

      size_t tail_size  = cur_size % sizeof(size_t);
      size_t size_mul_8 = cur_size - tail_size;

      if (size_mul_8 != 0) {
         if ( reading ) {
            m_io->mem->read_block ( window_rel_ptr, size_mul_8, cur_host_addr );
         } else {
            m_io->mem->write_block( window_rel_ptr, size_mul_8, cur_host_addr );
         }
         incr_ptrs (&cur_host_addr, &window_rel_ptr, &bytes_transfered, size_mul_8);
      }

      if (tail_size != 0) {
         read_write_small_size( cur_host_addr, window_rel_ptr, tail_size, reading );
         incr_ptrs (&cur_host_addr, &window_rel_ptr, &bytes_transfered, tail_size );
         cur_size -= tail_size;
      }

      // increase the current device address to be transferred
      cur_dev_addr += (window_rel_ptr - window_rel_ptr_start);
   }
   return 0; // success
}

// Read or Write a small size of data to device memory, one byte at a time
// Return 0 on success
int ACL_MMD_DEVICE::read_write_small_size (void *host_addr, size_t dev_addr, size_t size, bool reading)
{
   UINT8 *ucharptr_host = static_cast<UINT8 *>(host_addr);
   int status;

   for(size_t i = 0; i < size; ++i) {
      if(reading) {
         status = m_io->mem->read8 ( dev_addr+i, ucharptr_host+i);
      } else {
         status = m_io->mem->write8( dev_addr+i, ucharptr_host[i]);
      }
      ACL_MMD_ERROR_IF(status, return -1, "[%s] failed to read write with odd size.\n", m_name);
   }

   return 0; // success
}

// Set the segment that the memory windows is accessing to
// Return 0 on success
int ACL_MMD_DEVICE::set_segment( size_t addr )
{
   UINT64 segment_readback;
   UINT64 cur_segment = addr & ~(ACL_MMD_MEMWINDOW_SIZE-1);
   DWORD  status = 0;

   // Only execute the write if we need to *change* segments
   if ( cur_segment != m_segment )
   {
      // Reordering rules could cause the segment change to get reordered,
      // so read before and after!
      status |= m_io->window->read64 ( 0 , &segment_readback );

      status |= m_io->window->write64( 0 , cur_segment );
      m_segment = cur_segment;
      ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_BLOCKTX,":::::: [%s] Changed segment id to %llu.\n", m_name, m_segment);

      status |= m_io->window->read64 ( 0 , &segment_readback );
   }

   ACL_MMD_ERROR_IF(status, return -1,
      "[%s] failed to set segment for memory access windows.\n", m_name);

   return 0; // success
}

void ACL_MMD_DEVICE::incr_ptrs (void **host, size_t *dev, size_t *counter, size_t incr)
{
   const uintptr_t uintptr_host = reinterpret_cast<uintptr_t>(*host);

   *host     = reinterpret_cast<void *>(uintptr_host+incr);
   *dev     += incr;
   *counter += incr;
}



// Query the on-chip temperature sensor - this call takes significant time
// so must not be used within performance critical code.
bool ACL_MMD_DEVICE::get_ondie_temp_slow_call( cl_int *temp )
{
   cl_int read_data;

   // We assume this during read later
   ACL_MMD_ASSERT( sizeof(cl_int) == sizeof(INT32), "sizeof(cl_int) != sizeof(INT32)" );

   if (! ACL_MMD_HAS_TEMP_SENSOR) {
      ACL_MMD_DEBUG_MSG(":: [%s] On-chip temperature sensor not supported by this board.\n", m_name);
      return false;
   }

   ACL_MMD_DEBUG_MSG(":: [%s] Querying on-chip temperature sensor...\n", m_name);
   m_io->temp_sensor->read32(0, (UINT32 *)&read_data);

   ACL_MMD_DEBUG_MSG(":: [%s] Read temp sensor data.  Value is: %i degrees Celsius\n", m_name, read_data);
   *temp = read_data;
   return true;
}



void *ACL_MMD_DEVICE::shared_mem_alloc ( size_t size, unsigned long long *device_ptr_out )
{
#if defined(LINUX)
   #ifdef ACL_HOST_MEMORY_SHARED
      void *host_ptr = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, m_device, 0);

      if (device_ptr_out != NULL && host_ptr == (void*)-1) {
         // when mmap fails, it returns (void*)-1, not NULL
         host_ptr = NULL;
         *device_ptr_out = (unsigned long long)0;

      } else if (device_ptr_out != NULL) {

         /* map received host_ptr to FPGA-usable address. */
         void* dev_ptr = NULL;
         struct acl_cmd read_cmd = { ACLSOC_CMD_BAR,
               ACLSOC_CMD_GET_PHYS_PTR_FROM_VIRT,
               &dev_ptr,
               &host_ptr,
               sizeof(dev_ptr) };

         bool failed_flag = (read (m_device, &read_cmd, sizeof(dev_ptr)) != 0);
         ACL_MMD_DEBUG_MSG("  Mapped vaddr %p to phys addr %p. %s\n",
                  host_ptr, dev_ptr, failed_flag==0 ? "OK" : "FAILED");
         if (failed_flag) {
            *device_ptr_out = (unsigned long long)NULL;
         } else {
            /* When change to 64-bit pointers on the device, update driver code
             * to deal with larger-than-void* ptrs. */
            *device_ptr_out = (unsigned long long)dev_ptr;

            /* Now need to add offset of the shared system. */
         }
      }

      return host_ptr;
   #else
      return NULL;
   #endif
#endif   // LINUX
}

void ACL_MMD_DEVICE::shared_mem_free ( void* vptr, size_t size )
{
   if (vptr != NULL) {
      munmap (vptr, size);
   }
}



// C5soc is not programmed with this

// Reprogram the device with given binary file
// return 0 on success
int ACL_MMD_DEVICE::reprogram(void *data, size_t data_size)
{
   int reprogram_failed = 1;   // assume failure
//   const char *SOFNAME  = "reprogram_temp.sof";
   size_t rbf_len = 0;//, sof_len = 0;

   struct acl_pkg_file *pkg = acl_pkg_open_file_from_memory( (char*)data, data_size, ACL_PKG_SHOW_ERROR );
   ACL_MMD_ERROR_IF(pkg == NULL, return reprogram_failed, "cannot open file from memory using pkg editor.\n");

   // set the being_programmed flag, diable interrupt and save control registers
   m_being_programmed = true;
   this->disable_interrupts();
   m_config->save_soc_control_regs();
   ACL_MMD_DEBUG_MSG(":: [%s] Checking ACL_PKG_SECTION_CORE_RBF\n", m_name);
  if( acl_pkg_section_exists(pkg, ACL_PKG_SECTION_RBF, &rbf_len) ) {
      char *rbf = NULL;
      int read_rbf_ok = acl_pkg_read_section_transient( pkg, ACL_PKG_SECTION_RBF, &rbf );
      if( read_rbf_ok ){
         ACL_MMD_DEBUG_MSG(":: [%s] Starting reprogramming the device with RBF file...\n", m_name);
         reprogram_failed = m_config->program_with_RBF_image(rbf, rbf_len);
      }
   }

   m_config->load_soc_control_regs();

   // Clean up
   if ( pkg ) acl_pkg_close_file(pkg);
   m_being_programmed = false;

   return reprogram_failed;
}


// Perform a simple version id read to test the basic read functionality
// Return 0 on success
int ACL_MMD_DEVICE::version_id_test()
{
   unsigned int version = ACL_VERSIONID ^ 1; // make sure it's not what we hope to find.
   unsigned int iattempt;
   unsigned int max_attempts = 1;
   unsigned int usleep_per_attempt = 20;     // 20 ms per.

   ACL_MMD_DEBUG_MSG(":: [%s] Doing HPS-to-FPGA read test ...\n", m_name);
   for( iattempt = 0; iattempt < max_attempts; iattempt ++){
      m_io->version->read32(0, &version);
      if( version == (unsigned int)ACL_VERSIONID){
         ACL_MMD_DEBUG_MSG(":: [%s] HPS-to-FPGA read test passed\n", m_name);
         return 0;
      }
      usleep( usleep_per_attempt*1000 );
   }

   // Kernel read command succeed, but got bad data. (version id doesn't match)
   ACL_MMD_INFO("[%s] HPS-to-FPGA read test failed, read 0x%0x after %u attempts\n",
      m_name, version, iattempt);
   return -1;
}

// Wait until the uniphy calibrated
// Return 0 on success
int ACL_MMD_DEVICE::wait_for_uniphy()
{
   const unsigned int ACL_UNIPHYSTATUS = 0;
   unsigned int status = 1, retries = 0;
   ACL_MMD_DEBUG_MSG(":: [%s] Uniphys are going to be calibrated\n", m_name);
   while( retries++ < 8){
      m_io->uniphy_status->read32(0, &status);

      if( status == ACL_UNIPHYSTATUS){
         ACL_MMD_DEBUG_MSG(":: [%s] Uniphys are calibrated\n", m_name);
         return 0;   // success
      } else {
         ACL_MMD_DEBUG_MSG(":: [%s] Uniphys did not calibrate, retrying\n", m_name);
      }
      usleep(400*1000);
   }

   ACL_MMD_INFO("[%s] uniphy(s) did not calibrate.  Expected 0 but read %x\n",
      m_name, status);

   // Failure! Was it communication error or actual calibration failure?
   if ( ACL_READ_BIT( status , 3) )  // This bit is hardcoded to 0
      ACL_MMD_INFO("                Uniphy calibration status is corrupt.  This is likely a communication error with the board and/or uniphy_status module.\n");
   else {
      // This is a 32-bit interface with the first 4 bits aggregating the
      // various calibration signals.  The remaining 28-bits would indicate
      // failure for their respective memory core.  Tell users which ones
      // failed
      for (int i = 0; i < 32-4; i++) {
         if ( ACL_READ_BIT( status , 4+i) )
            ACL_MMD_INFO("  Uniphy core %d failed to calibrate\n",i );
      }
      ACL_MMD_INFO("     If there are more failures than Uniphy controllers connected, \n");
      ACL_MMD_INFO("     ensure the uniphy_status core is correctly parameterized.\n" );
   }

   return -1;   // failure
}

