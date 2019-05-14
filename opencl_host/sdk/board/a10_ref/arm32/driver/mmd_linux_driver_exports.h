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

/* All defines necessary to communicate with the SoC driver.
 * The actual communication functions are open()/close()/read()/write().
 *
 * Example read call (read single ushort from BAR 0, device address 0x2):
 *   ssize_t f = open ("/dev/de4", O_RDWR);
 *   unsigned short val;
 *   struct acl_cmd read_cmd = { 0, ACLSOC_CMD_DEFAULT, 0x2, &val };
 *   read (f, &read_cmd, sizeof(val));
 *
 * See user.c for a tester of all functions and more elaborate examples.
 */

#ifndef MMD_LINUX_DRIVER_EXPORTS_H
#define MMD_LINUX_DRIVER_EXPORTS_H


/* if bar_id in acl_cmd is set to this, this is a special command,
 * not a usual read/write request. So the command field is used. Otherwise,
 * command field is ignored. */
#define ACLSOC_CMD_BAR 23

/* Here we define a special "bar id" to tell the driver these addresses are in
 * the DMA space. */
#define ACLSOC_DMA_BAR 25

/* Values for 'command' field of acl_cmd. */

/* Default value -- noop. */
#define ACLSOC_CMD_DEFAULT                0

/* Save/Restore all board control registers to user_addr.
 * Allows user program to reprogram the board without having root
 * priviliges (which is required to change control registers). */
#define ACLSOC_CMD_SAVE_SOC_CONTROL_REGS  1
#define ACLSOC_CMD_LOAD_SOC_CONTROL_REGS  2

/* Get device_id of loaded device */
#define ACLSOC_CMD_GET_DEVICE_ID          7

/* Set id to receive back on signal from kernel */
#define ACLSOC_CMD_SET_SIGNAL_PAYLOAD     12

/* Get full driver version, as string */
#define ACLSOC_CMD_GET_DRIVER_VERSION     13

#define ACLSOC_CMD_ENABLE_KERNEL_IRQ      14

/* Map virtual to physical address.
 * Virtual address is passed in user_addr.
 * Physical address is returned in device_addr */
#define ACLSOC_CMD_GET_PHYS_PTR_FROM_VIRT 16

#define ACLSOC_CMD_GET_SLOT_INFO          17

#define ACLSOC_CMD_DMA_STOP               18

#define ACLSOC_CMD_MAX_CMD                19

/* Get m_idle status of DMA */
#define ACLSOC_CMD_GET_DMA_IDLE_STATUS    5
#define ACLSOC_CMD_DMA_UPDATE             6

/* Signal from driver to user (hal) to notify about hw interrupt */
#define SIG_INT_NOTIFY 44

/* Main structure to communicate any command (including read/write)
 * from user space to the driver. */
struct acl_cmd {

  /* base address register of SoC device. device_addr is interpreted
   * as an offset from this BAR's start address. */
  unsigned int bar_id;
  
  /* Special command to execute. Only used if bar_id is set
   * to ACLSOC_CMD_BAR. */
  unsigned int command;
  
  /* Address in device space where to read/write data. */
  void* device_addr;
  
  /* Address in user space where to write/read data.
   * Always virtual address. */
  void* user_addr;
  
  /* Bypass system restrictions on file I/O size.
   * Pass actual size of transfer here */
  size_t size;
  
  /* Tell the system if the conversion of endianness is needed. This is only */
  /* meaningful when the command is read/write to global memmory, so other   */
  /* command can still function correctly without setting this value.        */
  int is_diff_endian;
};

#endif /* MMD_LINUX_DRIVER_EXPORTS_H */
