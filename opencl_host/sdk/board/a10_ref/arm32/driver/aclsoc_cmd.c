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


/* Handling of special commands (anything that is not read/write/open/close)
 * that user may call.
 * See mmd_linux_driver_exports.h for explanations of each command. */


#include <linux/mm.h>
#include <linux/device.h>
#include <linux/sched.h>

#include "aclsoc.h"

/* Execute special command */
ssize_t aclsoc_exec_cmd (struct aclsoc_dev *aclsoc,
                         struct acl_cmd kcmd,
                         size_t count) {
  ssize_t result = 0;

  switch (kcmd.command) {
  case ACLSOC_CMD_GET_DMA_IDLE_STATUS: {
    u32 idle = 1; // no DMA
    result = copy_to_user ( kcmd.user_addr, &idle, sizeof(idle) );
    break;
  }

  case ACLSOC_CMD_ENABLE_KERNEL_IRQ: {
    unmask_kernel_irq(aclsoc);
    break;
  }

  case ACLSOC_CMD_SET_SIGNAL_PAYLOAD: {
    u32 id;
    result = copy_from_user ( &id, kcmd.user_addr, sizeof(id) );
    aclsoc->signal_info.si_int = id;
    break;
  }

  case ACLSOC_CMD_GET_DRIVER_VERSION: {
    /* Driver version is a string */
    result = copy_to_user ( kcmd.user_addr, &ACL_DRIVER_VERSION, strlen(ACL_DRIVER_VERSION)+1 );
    break;
  }

  case ACLSOC_CMD_GET_DEVICE_ID: {
    u32 id = ACL_C5DK_DEVICE_ID;
    result = copy_to_user ( kcmd.user_addr, &id, sizeof(id) );
    break;
  }

  case ACLSOC_CMD_GET_PHYS_PTR_FROM_VIRT: {
    unsigned long vm_addr;
    int i;
    result = copy_from_user ( &vm_addr, kcmd.user_addr, sizeof(vm_addr) );

    for (i = 0; i < 128; i++) {
      if (aclsoc->addr_map[i].vm_start == 0) break;
      if (aclsoc->addr_map[i].vm_start == vm_addr) {
        result = copy_to_user ( kcmd.device_addr, &aclsoc->addr_map[i].dma_handle, sizeof(kcmd.device_addr) );
        break;
      }
    }
    break;
  }

  case ACLSOC_CMD_LOAD_SOC_CONTROL_REGS:
    /* Things to do after reprogramming the FGPA */
    init_irq (aclsoc);
    break;

  case ACLSOC_CMD_SAVE_SOC_CONTROL_REGS:
    /* Prepare for reprogramming the FGPA */
    release_irq (aclsoc);
    break;

  default:
    ACL_DEBUG (KERN_WARNING " Invalid or unsupported command %u! Ignoring the call. See aclsoc_cmd.c for list of understood commands", kcmd.command);
    result = -EFAULT;
    break;
  }

  return result;
}


