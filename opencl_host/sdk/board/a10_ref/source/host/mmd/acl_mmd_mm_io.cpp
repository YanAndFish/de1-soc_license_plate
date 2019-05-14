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


/* ===- acl_mmd_mm_io.cpp  ------------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file implements the class to handle memory mapped IO            */
/* The declaration of the class lives in the acl_mmd_mm_io.h.                     */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */


// common and its own header files
#include "acl_mmd.h"
#include "acl_mmd_mm_io.h"

// other header files inside MMD driver
#include "acl_mmd_debug.h"

// other standard header files
#include <string.h>

#if defined(LINUX)
#  include <unistd.h>   // template
#endif   // LINUX



ACL_MMD_MM_IO_DEVICE::ACL_MMD_MM_IO_DEVICE
(
   WDC_DEVICE_HANDLE device,
   DWORD bar,
   KPTR device_offset,
   const char* name,
   bool diff_endian
)
{
   ACL_MMD_ASSERT(device != INVALID_DEVICE, "passed in an invalid device when creating mm_io object.\n");
   ACL_MMD_ASSERT(name != NULL, "passed in an empty name pointer when creating mm_io object.\n");

   strncpy(m_name, name, (MAX_NAME_LENGTH-1));
   m_name[(MAX_NAME_LENGTH-1)] = '\0';

   m_device        = device;
   m_bar           = bar;
   m_offset        = device_offset;
   m_diff_endian   = diff_endian;

   ACL_MMD_DEBUG_MSG(":: [%s] Init: Bar %d, Total offset 0x" SIZE_FMT_X ", diff_endian is %d \n",
               m_name, m_bar, (size_t) m_offset, m_diff_endian?1:0 );
}

ACL_MMD_MM_IO_DEVICE::~ACL_MMD_MM_IO_DEVICE()
{
}


#if defined(LINUX)
// Helper functions to implement all other read/write functions
template<typename T>
DWORD linux_read ( WDC_DEVICE_HANDLE device, DWORD bar, KPTR address, T *data )
{
   struct acl_cmd driver_cmd;
   driver_cmd.bar_id         = bar;
   driver_cmd.command        = ACLSOC_CMD_DEFAULT;
   driver_cmd.device_addr    = reinterpret_cast<void *>(address);
   driver_cmd.user_addr      = data;
   driver_cmd.size           = sizeof(*data);
   // function invoke linux_read will not write to global memory.
   // So is_diff_endian is always false
   driver_cmd.is_diff_endian = 0;

   return read (device, &driver_cmd, sizeof(driver_cmd));
}

template<typename T>
DWORD linux_write ( WDC_DEVICE_HANDLE device, DWORD bar, KPTR address, T data )
{
   struct acl_cmd driver_cmd;
   driver_cmd.bar_id         = bar;
   driver_cmd.command        = ACLSOC_CMD_DEFAULT;
   driver_cmd.device_addr    = reinterpret_cast<void *>(address);
   driver_cmd.user_addr      = &data;
   driver_cmd.size           = sizeof(data);
   // function invoke linux_write will not write to global memory.
   // So is_diff_endian is always false
   driver_cmd.is_diff_endian = 0;

   return write (device, &driver_cmd, sizeof(driver_cmd));
}
#endif // LINUX


int ACL_MMD_MM_IO_DEVICE::read8   ( size_t addr, UINT8  *data )
{
   DWORD status;
   KPTR  bar_addr = convert_to_bar_addr(addr);
   status = linux_read   ( m_device, m_bar, bar_addr, data );

   ACL_MMD_ERROR_IF(status != WD_STATUS_SUCCESS, return -1,
      "[%s] Read 8 bits from 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, addr, (size_t)bar_addr);
   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Read 8 bits (0x%x) from 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, *data, addr, (size_t)bar_addr);

   return 0; // success
}

int ACL_MMD_MM_IO_DEVICE::write8  ( size_t addr, UINT8   data )
{
   DWORD status;
   KPTR  bar_addr = convert_to_bar_addr(addr);
   status = linux_write   ( m_device, m_bar, bar_addr, data );

   ACL_MMD_ERROR_IF(status != WD_STATUS_SUCCESS, return -1,
      "[%s] Writing 8 bits to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, addr, (size_t)bar_addr);
   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Wrote 8 bits (0x%x) to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, data, addr, (size_t)bar_addr);

   return 0; // success
}

int ACL_MMD_MM_IO_DEVICE::read32  ( size_t addr, UINT32 *data )
{
   DWORD status;
   KPTR  bar_addr = convert_to_bar_addr(addr);
   status = linux_read    ( m_device, m_bar, bar_addr, data );

   ACL_MMD_ERROR_IF(status != WD_STATUS_SUCCESS, return -1,
      "[%s] Read 32 bits from 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, addr, (size_t)bar_addr);
   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Read 32 bits (0x%x) from 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, *data, addr, (size_t)bar_addr);

   return 0; // success
}

int ACL_MMD_MM_IO_DEVICE::write32 ( size_t addr, UINT32  data )
{
   DWORD status;
   KPTR  bar_addr = convert_to_bar_addr(addr);
   status = linux_write    ( m_device, m_bar, bar_addr, data );

   ACL_MMD_ERROR_IF(status != WD_STATUS_SUCCESS, return -1,
      "[%s] Writing 32 bits to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, addr, (size_t)bar_addr);
   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Wrote 32 bits (0x%x) to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, data, addr, (size_t) bar_addr);

   return 0; // success
}

int ACL_MMD_MM_IO_DEVICE::read64  ( size_t addr, UINT64 *data )
{
   DWORD status;
   KPTR  bar_addr = convert_to_bar_addr(addr);
   status = linux_read    ( m_device, m_bar, bar_addr, data );

   ACL_MMD_ERROR_IF(status != WD_STATUS_SUCCESS, return -1,
      "[%s] Read 64 bits from 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, addr, (size_t)bar_addr);
   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Read 64 bits (0x%llx) from 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, *data, addr, (size_t)bar_addr);

   return 0; // success
}

int ACL_MMD_MM_IO_DEVICE::write64 ( size_t addr, UINT64  data )
{
   DWORD status;
   KPTR  bar_addr = convert_to_bar_addr(addr);
   status = linux_write    ( m_device, m_bar, bar_addr, data );

   ACL_MMD_ERROR_IF(status != WD_STATUS_SUCCESS, return -1,
      "[%s] Writing 64 bits to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, bar_addr, (size_t)bar_addr);
   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Wrote 64 bits (0x%llx) to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, data, addr, (size_t)bar_addr);

   return 0; // success
}


int ACL_MMD_MM_IO_DEVICE::write_block ( size_t addr, size_t size, void *src )
{
   DWORD status;
   KPTR  bar_addr = convert_to_bar_addr(addr);

   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Writing block (" SIZE_FMT_U " bytes) to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, size, addr, (size_t)bar_addr);

   // Can't use templated linux_write here because *src doesn't give you the size to read.
   struct acl_cmd driver_cmd;
   driver_cmd.bar_id         = m_bar;
   driver_cmd.device_addr    = reinterpret_cast<void *>(bar_addr);
   driver_cmd.user_addr      = src;
   driver_cmd.size           = size;
   // Notify the driver if the host and device's memory have different endianess.
   driver_cmd.is_diff_endian = m_diff_endian?1:0;
   status = write (m_device, &driver_cmd, sizeof(driver_cmd));

   ACL_MMD_ERROR_IF(status != WD_STATUS_SUCCESS, return -1,
      "[%s] Writing block (" SIZE_FMT_U " bytes) to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, size, addr, (size_t)bar_addr);
   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Writing block (" SIZE_FMT_U " bytes) to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset) SUCCEEDED\n",
      m_name, size, addr, (size_t)bar_addr);
   return 0; // success
}

int ACL_MMD_MM_IO_DEVICE::read_block ( size_t addr, size_t size, void *dst )
{
   DWORD status;
   KPTR  bar_addr = convert_to_bar_addr(addr);

   ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_MMD,
      ":::::: [%s] Reading block (" SIZE_FMT_U " bytes) from 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, size, addr, (size_t)bar_addr);

   // Can't use templated linux_write here because *src doesn't give you the size to read.
   struct acl_cmd driver_cmd;
   driver_cmd.bar_id         = m_bar;
   driver_cmd.device_addr    = reinterpret_cast<void *>(bar_addr);
   driver_cmd.user_addr      = dst;
   driver_cmd.size           = size;
   // Notify the driver if the host and device's memory have different endianess.
   driver_cmd.is_diff_endian = m_diff_endian?1:0;
   status = read (m_device, &driver_cmd, sizeof(driver_cmd));

   ACL_MMD_ERROR_IF(status != WD_STATUS_SUCCESS, return -1,
      "[%s] Reading block (" SIZE_FMT_U " bytes) to 0x" SIZE_FMT_X " (0x" SIZE_FMT_X " with offset)\n",
      m_name, size, addr, (size_t)bar_addr);
   return 0; // success
}



ACL_MMD_MM_IO_MGR::ACL_MMD_MM_IO_MGR( WDC_DEVICE_HANDLE device ) :
   mem (NULL),
   mmd_cra (NULL),
   dma (NULL),
   dma_descriptor (NULL),
   window (NULL),
   version (NULL),
   uniphy_status (NULL),
   kernel_if (NULL),
   pll (NULL),
   temp_sensor (NULL)
{
   ACL_MMD_ASSERT(device != INVALID_DEVICE, "passed in an invalid device when creating mm_io_mgr.\n");

   // This is the MMD interface for directly accessing memory.
   // This view of memory is segmented so that the size of this
   // address space can be smaller than the amount of physical device.
   // The window interface controls which region of physical memory
   // this interface currently maps to. The last flag indicate if
   // the device on both side of transferring have different endianess.
#ifdef ACL_BIG_ENDIAN
   mem = new ACL_MMD_MM_IO_DEVICE( device, ACL_MMD_GLOBAL_MEM_BAR, (KPTR)ACL_MMD_MEMWINDOW_BASE, "GLOBAL-MEM" , true );
#else
   mem = new ACL_MMD_MM_IO_DEVICE( device, ACL_MMD_GLOBAL_MEM_BAR, (KPTR)ACL_MMD_MEMWINDOW_BASE, "GLOBAL-MEM" , false);
#endif

   // This is the CRA port of our HPS2FPGA controller.  Used for configuring
   // interrupts and things like that.
   mmd_cra = new ACL_MMD_MM_IO_DEVICE( device, ACL_MMD_CRA_BAR, ACL_MMD_CRA_OFFSET, "HPS2FPGA-CRA" );
   // This interface sets the high order address bits for the FPGA's direct
   // memory accesses via "mem" (above).
   window = new ACL_MMD_MM_IO_DEVICE( device, ACL_MMD_MEMWINDOW_BAR, ACL_MMD_MEMWINDOW_CRA, "MEMWINDOW" );

   // DMA interfaces
   dma = new ACL_MMD_MM_IO_DEVICE( device, ACL_MMD_DMA_BAR, ACL_MMD_DMA_OFFSET, "DMA-CSR" );
   dma_descriptor = new ACL_MMD_MM_IO_DEVICE( device, ACL_MMD_DMA_DESCRIPTOR_BAR, ACL_MMD_DMA_DESCRIPTOR_OFFSET, "DMA-DESCRIPTOR" );

   // Version ID check
   version = new ACL_MMD_MM_IO_DEVICE( device, ACL_VERSIONID_BAR, ACL_VERSIONID_OFFSET, "VERSION" );

   // Uniphy Status
   uniphy_status = new ACL_MMD_MM_IO_DEVICE( device, ACL_UNIPHYSTATUS_BAR, ACL_UNIPHYSTATUS_OFFSET, "UNIPHYSTATUS" );

   // Kernel interface
   kernel_if = new ACL_MMD_MM_IO_DEVICE( device, ACL_KERNEL_CSR_BAR, ACL_KERNEL_CSR_OFFSET, "KERNEL" );

   // PLL interface
   pll = new ACL_MMD_MM_IO_DEVICE( device, ACL_KERNELPLL_RECONFIG_BAR, ACL_KERNELPLL_RECONFIG_OFFSET, "PLL" );

   // temperature sensor
   if( ACL_MMD_HAS_TEMP_SENSOR ) {
      temp_sensor = new ACL_MMD_MM_IO_DEVICE( device, ACL_VERSIONID_BAR, ACL_TEMP_SENSOR_ADDRESS, "TEMP-SENSOR");
   }
}

ACL_MMD_MM_IO_MGR::~ACL_MMD_MM_IO_MGR()
{
   if(mem)            { delete mem;            mem = NULL;            }
   if(mmd_cra)        { delete mmd_cra;        mmd_cra = NULL;        }
   if(dma)            { delete dma;            dma = NULL;            }
   if(dma_descriptor) { delete dma_descriptor; dma_descriptor = NULL; }
   if(window)         { delete window;         window = NULL;         }
   if(version)        { delete version;        version = NULL;        }
   if(uniphy_status)  { delete uniphy_status;  uniphy_status = NULL;  }
   if(kernel_if)      { delete kernel_if;      kernel_if = NULL;      }
   if(pll)            { delete pll;            pll = NULL;            }
   if(temp_sensor)    { delete temp_sensor;    temp_sensor = NULL;    }
}

