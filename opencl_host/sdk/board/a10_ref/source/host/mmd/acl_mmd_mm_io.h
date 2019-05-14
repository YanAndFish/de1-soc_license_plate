#ifndef ACL_MMD_MM_IO_H
#define ACL_MMD_MM_IO_H

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


/* ===- acl_mmd_mm_io.h  --------------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file declares the class to handle memory mapped IO.              */
/* The actual implementation of the class lives in the acl_mmd_mm_io.cpp,         */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */

class ACL_MMD_MM_IO_DEVICE
{
   public:
      ACL_MMD_MM_IO_DEVICE (WDC_DEVICE_HANDLE device, DWORD bar, KPTR device_offset, const char* name , bool diff_endian = false);
      ~ACL_MMD_MM_IO_DEVICE();

      DWORD bar_id()                           { return m_bar; };
      KPTR  convert_to_bar_addr( size_t addr ) { return addr + m_offset; };

      // read/write functions to the memory-mapped io device
      // return 0 on success, negative on error
      int read8  ( size_t addr, UINT8  *data );
      int write8 ( size_t addr, UINT8   data );
      int read32 ( size_t addr, UINT32 *data );
      int write32( size_t addr, UINT32  data );
      int read64 ( size_t addr, UINT64 *data );
      int write64( size_t addr, UINT64  data );

      int read_block ( size_t addr, size_t size, void *dst );
      int write_block( size_t addr, size_t size, void *src );

   private:
      static const int MAX_NAME_LENGTH = 32;

      char              m_name[MAX_NAME_LENGTH];
      WDC_DEVICE_HANDLE m_device;
      DWORD             m_bar;
      KPTR              m_offset;
      bool              m_diff_endian;  //indicates if the host and this device have different endianess
};

/*
 * Utility functions to clean up the various address translations for reads/writes
 */
class ACL_MMD_MM_IO_MGR
{
   public:
      ACL_MMD_MM_IO_MGR( WDC_DEVICE_HANDLE device );
      ~ACL_MMD_MM_IO_MGR();

      ACL_MMD_MM_IO_DEVICE *mem;
      ACL_MMD_MM_IO_DEVICE *mmd_cra;
      ACL_MMD_MM_IO_DEVICE *dma;
      ACL_MMD_MM_IO_DEVICE *dma_descriptor;
      ACL_MMD_MM_IO_DEVICE *window;
      ACL_MMD_MM_IO_DEVICE *version;
      ACL_MMD_MM_IO_DEVICE *uniphy_status;
      ACL_MMD_MM_IO_DEVICE *kernel_if;
      ACL_MMD_MM_IO_DEVICE *pll;
      ACL_MMD_MM_IO_DEVICE *temp_sensor;
};

#endif // ACL_MMD_MM_IO_H

