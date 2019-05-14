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

#include <asm/io.h> // __raw_writel
#include "aclsoc.h"
#include "hw_mmd_constants.h"
#include <linux/time.h>

/* Re-configure FPGA kernel partition with given bitstream.
 * Support for Arria 10 devices and higher */
int aclsoc_pr (struct aclsoc_dev *aclsoc, void __user* core_bitstream, ssize_t len) {
  char *data;
  int i;
  int result = -EFAULT;
  uint32_t to_send, status;
  u64 startj, ej;

  ACL_DEBUG (KERN_DEBUG "Call to %s", __FUNCTION__);


  /* Basic error checks */  
  if (aclsoc == NULL) {
    ACL_DEBUG (KERN_WARNING "Need to open device before can do reconfigure!");
    return result;
  }
  if (core_bitstream == NULL) {
    ACL_DEBUG (KERN_WARNING "Programming bitstream is not provided!");
    return result;
  }
  if (len < 1000000) {
    ACL_DEBUG (KERN_WARNING "Programming bitstream length is suspiciously small. Not doing PR!");
    return result;
  }

  ACL_DEBUG (KERN_DEBUG "OK to proceed with PR!");
  aclsoc->pr_in_progress = 1;

  startj = get_jiffies_64();

  mb();
  status = ioread32(aclsoc->mapped_region[ACL_PRCONTROLLER_BAR]+ACL_PRCONTROLLER_OFFSET+4);
  ACL_DEBUG (KERN_DEBUG "Reading 0x%08X from PR IP status register", (int) status);

  to_send = 0x00000001; 
  ACL_DEBUG (KERN_DEBUG "Writing 0x%08X to PR IP status register", (int) to_send);
  iowrite32(to_send, aclsoc->mapped_region[ACL_PRCONTROLLER_BAR]+ACL_PRCONTROLLER_OFFSET+4);

  mb();
  status = ioread32(aclsoc->mapped_region[ACL_PRCONTROLLER_BAR]+ACL_PRCONTROLLER_OFFSET+4);
  ACL_DEBUG (KERN_DEBUG "Reading 0x%08X from PR IP status register", (int) status);
  if ((status != 0x10) && (status != 0x0)) {
    return -EFAULT;
  }

  data = (char __user*)core_bitstream;
  ACL_DEBUG (KERN_DEBUG "Writing %d bytes of bitstream file to PR IP at mapped_region %d (0x%p), OFFSET 0x%08X", (int)len, ACL_PRCONTROLLER_BAR, aclsoc->mapped_region[ACL_PRCONTROLLER_BAR], (int) ACL_PRCONTROLLER_OFFSET);

  for (i = 0; i < len; i=i+4) {
    result = copy_from_user ( &to_send, data + i, sizeof(to_send));
    iowrite32(to_send, aclsoc->mapped_region[ACL_PRCONTROLLER_BAR]+ACL_PRCONTROLLER_OFFSET);
  }

  mb();

  status = ioread32(aclsoc->mapped_region[ACL_PRCONTROLLER_BAR]+ACL_PRCONTROLLER_OFFSET+4);
  //
  mb();
  ACL_DEBUG (KERN_DEBUG "Reading 0x%08X from PR IP status register", (int) status);
  if (status == 0x14){
    ACL_DEBUG (KERN_DEBUG "PR done!: 0x%08X\n", (int) status);
    result = 0;
  } else {
    ACL_DEBUG (KERN_DEBUG "PR error!: 0x%08X\n", (int) status);
    result = 1;
  }

  ej = get_jiffies_64();
  ACL_DEBUG (KERN_DEBUG "PR took %u usec\n", jiffies_to_usecs(ej - startj));

  ACL_DEBUG (KERN_DEBUG "PR completed!");
  aclsoc->pr_in_progress = 0;
  return result;
}

