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


/* ===- acl_mmd_dma_linux.cpp  --------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file implements the class to handle Linux-specific DMA operations.         */
/* The declaration of the class lives in the acl_mmd_dma_linux.h                  */
/* The actual implementation of DMA operation is inside the Linux kernel driver.   */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */


#if defined(LINUX)

// common and its own header files
#include "acl_mmd.h"
#include "acl_mmd_dma_linux.h"

// other header files inside MMD driver
#include "acl_mmd_device.h"
#include "acl_mmd_mm_io.h"

// other standard header files
#include <stdio.h>
#include <unistd.h>
#include <sys/time.h>



ACL_MMD_DMA::ACL_MMD_DMA( WDC_DEVICE_HANDLE dev, ACL_MMD_MM_IO_MGR *io, ACL_MMD_DEVICE *mmd )
{
   ACL_MMD_ASSERT(dev  != INVALID_DEVICE, "passed in an invalid device when creating dma object.\n");
   ACL_MMD_ASSERT(io   != NULL, "passed in an empty pointer for io when creating dma object.\n");
   ACL_MMD_ASSERT(mmd != NULL, "passed in an empty pointer for mmd when creating dma object.\n");

   m_device = dev;
   m_mmd   = mmd;
   m_io     = io;
   m_event  = NULL;
}

ACL_MMD_DMA::~ACL_MMD_DMA()
{
#if !defined (ARM)
   struct acl_cmd driver_cmd = { ACLSOC_CMD_BAR, ACLSOC_CMD_DMA_STOP, NULL, NULL };
   read(m_device, &driver_cmd, sizeof(driver_cmd));
#else
   stall_until_idle();
#endif
}



bool ACL_MMD_DMA::is_idle( )
{
   unsigned int result = 0;

   struct acl_cmd driver_cmd;
   driver_cmd.bar_id      = ACLSOC_CMD_BAR;
   driver_cmd.command     = ACLSOC_CMD_GET_DMA_IDLE_STATUS;
   driver_cmd.device_addr = NULL;
   driver_cmd.user_addr   = &result;
   driver_cmd.size        = sizeof(result);
   read (m_device, &driver_cmd, sizeof(driver_cmd));

   return (result != 0);
}



// Perform operations required when a DMA interrupt comes
// For Linux, 
//    All of the DMA related interrupts are handled inside the kernel driver, 
//    so when MMD gets a signal from the kernel driver indicating DMA is finished, 
//    it only needs to call the event_update_fn when it's needed.
void ACL_MMD_DMA::service_interrupt()
{
   if (m_event)
   {
      // Use a temporary variable to save the event data and reset m_event
      // before calling event_update_fn to avoid race condition that the main
      // thread may start a new DMA transfer before this work-thread is able to
      // reset the m_event.
      aocl_mmd_op_t temp_event = m_event;
      m_event = NULL;

      m_mmd->event_update_fn( temp_event, 0 );
   }
}



// relinquish the CPU to let any other thread to run
// return 0 since there is no useful work to be performed here
int ACL_MMD_DMA::yield()
{
   usleep(0);
   return 0;
}



// Transfer data between host and device
// This function returns right after the transfer is scheduled
// Return 0 on success
int ACL_MMD_DMA::read_write(void *host_addr, size_t dev_addr, size_t bytes, aocl_mmd_op_t e, bool reading)
{
   m_event = e;

   struct acl_cmd driver_cmd;
   driver_cmd.bar_id      = ACLSOC_DMA_BAR;
   driver_cmd.command     = ACLSOC_CMD_DEFAULT;
   driver_cmd.device_addr = reinterpret_cast<void *>(dev_addr);
   driver_cmd.user_addr   = host_addr;
   driver_cmd.size        = bytes;
   if (reading)
      read (m_device, &driver_cmd, sizeof(driver_cmd));
   else
      write(m_device, &driver_cmd, sizeof(driver_cmd));
   return 0; // success
}

#endif // LINUX

