/* 
 * Copyright (c) 2018, Intel Corporation.
 * Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack 
 * words and logos are trademarks of Intel Corporation or its subsidiaries 
 * in the U.S. and/or other countries. Other marks and brands may be 
 * claimed as the property of others.   See Trademarks on intel.com for 
 * full list of Intel trademarks or the Trademarks & Brands Names Database 
 * (if Intel) or See www.Intel.com/legal (if Altera).
 * All rights reserved
 *
 * This software is available to you under a choice of one of two
 * licenses.  You may choose to be licensed under the terms of the GNU
 * General Public License (GPL) Version 2, available from the file
 * COPYING in the main directory of this source tree, or the
 * BSD 3-Clause license below:
 *
 *     Redistribution and use in source and binary forms, with or
 *     without modification, are permitted provided that the following
 *     conditions are met:
 *
 *      - Redistributions of source code must retain the above
 *        copyright notice, this list of conditions and the following
 *        disclaimer.
 *
 *      - Redistributions in binary form must reproduce the above
 *        copyright notice, this list of conditions and the following
 *        disclaimer in the documentation and/or other materials
 *        provided with the distribution.
 *
 *      - Neither Intel nor the names of its contributors may be 
 *        used to endorse or promote products derived from this 
 *        software without specific prior written permission.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

////////////////////////////////////////////////////////////
//                                                        //
// hw_mmd_constants.h                                     //
// Constants to keep in sync with the HW board design     //
//                                                        //
// Note: This file *MUST* be kept in sync with any        //
//       changes to the HW board design!                  //
//                                                        //
////////////////////////////////////////////////////////////

#ifndef HW_MMD_CONSTANTS_H
#define HW_MMD_CONSTANTS_H


#define ACL_READ_BIT( w, b ) (((w) >> (b)) & 1)
#define ACL_READ_BIT_RANGE( w, h, l ) (((w) >> (l)) & ((1 << ((h) - (l) + 1)) - 1))
#define ACL_SET_BIT( w, b ) ((w) |= (1 << (b)))
#define ACL_CLEAR_BIT( w, b ) ((w) &= (~(1 << (b))))
#define ACL_GET_BIT( b ) (unsigned) (1 << (b))

#define QSYS_IFACE 1

// Vendor and Device IDs
#define ACL_MMD_ALTERA_VENDOR_ID              0x1172
#define ACL_C5DK_DEVICE_ID                    0xC500
#define ACL_MMD_BSP_DEVICE_ID     ACL_C5DK_DEVICE_ID
#define ACL_MMD_SUBSYSTEM_VENDOR_ID           0x1172
#define ACL_MMD_SUBSYSTEM_DEVICE_ID           0x0004

#define ACL_BOARD_PKG_NAME                          "c5dk"
#define ACL_VENDOR_NAME                             "Intel(R) Corporation"
#define ACL_BOARD_NAME                              "Cyclone V SoC Development Kit"

// Global memory
#define ACL_MMD_GLOBAL_MEM_BAR                     0

// control register addresses
#define ACL_MMD_CRA_BAR                            0
#define ACL_MMD_CRA_OFFSET                         0
#define ACL_MMD_CRA_SIZE                      0x4000

// Kernel control/status register addresses
#define ACL_KERNEL_CSR_BAR                         0
#define ACL_KERNEL_CSR_OFFSET                 0x4000

// DMA control/status register address
#define ACL_MMD_DMA_BAR                           0
#define ACL_MMD_DMA_OFFSET                  0x0c800

// DMA descriptor slave address
#define ACL_MMD_DMA_DESCRIPTOR_BAR                0
#define ACL_MMD_DMA_DESCRIPTOR_OFFSET       0x0c820

// Avalon Tx port address as seen by the DMA read/write masters
#define ACL_MMD_TX_PORT                0x80000000ll

// Global memory window slave address.  The host has different "view" of global
// memory: it sees only 512megs segments of memory at a time
#define ACL_MMD_MEMWINDOW_BAR                      0
#define ACL_MMD_MEMWINDOW_CRA                0x0c870
#define ACL_MMD_MEMWINDOW_BASE               0x10000
#define ACL_MMD_MEMWINDOW_SIZE               0x10000

// Avalon-MM control-register offsets
#define MMD_CRA_IRQ_STATUS                    0x0040
#define MMD_CRA_IRQ_ENABLE                    0x0050
#define MMD_CRA_ADDR_TRANS                    0x1000

// IRQ vector mappings (as seen by the RxIRQ port)
#define ACL_KERNEL_IRQ_VEC                     0
#define ACL_MMD_DMA_IRQ_VEC                    1

// PLL related
#define USE_KERNELPLL_RECONFIG                 0
#define ACL_KERNELPLL_RECONFIG_BAR             0
#define ACL_KERNELPLL_RECONFIG_OFFSET    0x0c000

// DMA descriptor control bits
#define DMA_ALIGNMENT_BYTES                       64
#define DMA_ALIGNMENT_BYTE_MASK                     (DMA_ALIGNMENT_BYTES-1)
#define DMA_DC_TRANSFER_COMPLETE_IRQ_MASK         14
#define DMA_DC_EARLY_DONE_ENABLE                  24
#define DMA_DC_GO                                 31
// DMA controller control/status registers
#define DMA_CSR_STATUS                          0x00
#define DMA_CSR_CONTROL                         0x04
// DMA CSR status bits
#define DMA_STATUS_BUSY                            0
#define DMA_STATUS_DESCRIPTOR_EMPTY                1
#define DMA_STATUS_RESETTING                       6
#define DMA_STATUS_IRQ                             9
#define DMA_STATUS_COUNT_LO                       16
#define DMA_STATUS_COUNT_HI                       31
// DMA CSR control bits
#define DMA_CTRL_STOP                              0
#define DMA_CTRL_RESET                             1
#define DMA_CTRL_IRQ_ENABLE                        4
#define PIO_DATA                                 0*4
#define PIO_SET                                  4*4
#define PIO_CLR                                  5*4

// Temperature sensor presence and base address macros
#define ACL_MMD_HAS_TEMP_SENSOR                   1
#define ACL_TEMP_SENSOR_ADDRESS          0xcff0

#define ACL_VERSIONID_BAR                          0
#define ACL_VERSIONID_OFFSET                  0xcfc0
#define ACL_VERSIONID                     0xA0C7C1E0
#define ACL_UNIPHYSTATUS_BAR                       0
#define ACL_UNIPHYSTATUS_OFFSET               0xcfe0

#endif // HW_MMD_CONSTANTS_H
