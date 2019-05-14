#ifndef ACL_MMD_DMA_LINUX_H
#define ACL_MMD_DMA_LINUX_H

/* (C) 1992-2018 Intel Corporation.                             */
/* Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words     */
/* and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.   */
/* and/or other countries. Other marks and brands may be claimed as the property   */
/* of others. See Trademarks on intel.com for full list of Intel trademarks or     */
/* the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera)  */
/* Your use of Intel Corporation's design tools, logic functions and other         */
/* software and tools, and its AMPP partner logic functions, and any output        */
/* files any of the foregoing (including device programming or simulation          */
/* files), and any associated documentation or information are expressly subject   */
/* to the terms and conditions of the Altera Program License Subscription          */
/* Agreement, Intel MegaCore Function License Agreement, or other applicable       */
/* license agreement, including, without limitation, that your use is for the      */
/* sole purpose of programming logic devices manufactured by Intel and sold by     */
/* Intel or its authorized distributors.  Please refer to the applicable           */
/* agreement for further details.                                                  */


/* ===- acl_mmd_dma_linux.h  ----------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file declares the class to handle Linux-specific DMA operations.           */
/* The actual implementation of the class lives in the acl_mmd_dma_linux.cpp      */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */


#if defined(LINUX)

class ACL_MMD_DEVICE;
class ACL_MMD_MM_IO_MGR;

class ACL_MMD_DMA
{
   public:
      ACL_MMD_DMA( WDC_DEVICE_HANDLE dev, ACL_MMD_MM_IO_MGR *io, ACL_MMD_DEVICE *mmd );
      ~ACL_MMD_DMA();

      bool is_idle();
      void stall_until_idle(){ while(!is_idle()) yield(); };

      // Perform operations required when a DMA interrupt comes
      void service_interrupt();

      // Relinquish the CPU to let any other thread to run
      // Return 0 since there is no useful work to be performed here
      int  yield();

      // Transfer data between host and device
      // This function returns right after the transfer is scheduled
      // Return 0 on success
      int read_write(void *host_addr, size_t dev_addr, size_t bytes, aocl_mmd_op_t e, bool reading);

   private:
      aocl_mmd_op_t       m_event;

      WDC_DEVICE_HANDLE   m_device;
      ACL_MMD_DEVICE    *m_mmd;
      ACL_MMD_MM_IO_MGR *m_io;
};

#endif // LINUX

#endif // ACL_MMD_DMA_LINUX_H
