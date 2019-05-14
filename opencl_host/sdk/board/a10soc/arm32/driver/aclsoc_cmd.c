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
#include <asm/cacheflush.h>
#include <linux/pagemap.h>

#include "aclsoc.h"

/* Execute special command */
ssize_t aclsoc_exec_cmd (struct aclsoc_dev *aclsoc, 
                         struct acl_cmd kcmd, 
                         size_t count) {
  ssize_t result = 0;

  switch (kcmd.command) {  
  case ACLSOC_CMD_GET_DMA_IDLE_STATUS: {
    u32 idle =  aclsoc_dma_get_idle_status(aclsoc);
    result = copy_to_user ( kcmd.user_addr, &idle, sizeof(idle) );
    break;
  }

  case ACLSOC_CMD_DMA_UPDATE: {
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
    aclsoc->signal_info_dma.si_int = id | 0x1; // use the last bit to indicate the DMA completion
    break;
  }
  
  case ACLSOC_CMD_GET_DRIVER_VERSION: {
    /* Driver version is a string */
    result = copy_to_user ( kcmd.user_addr, &ACL_DRIVER_VERSION, strlen(ACL_DRIVER_VERSION)+1 );
    break;
  }

  case ACLSOC_CMD_GET_DEVICE_ID: {
    u32 id = ACL_A10SOC_DEVICE_ID;
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

  case ACLSOC_CMD_DO_PR: 
    ACL_DEBUG (KERN_DEBUG "Starting PR");
    result = aclsoc_pr (aclsoc, kcmd.user_addr, count);
    if (result != 0) {
      ACL_DEBUG (KERN_DEBUG "PR failed.");
    }
    break;
    
  case ACLSOC_CMD_DMA_STOP:
    aclsoc_dma_stop(aclsoc);
    break;

  default:
    ACL_DEBUG (KERN_WARNING " Invalid or unsupported command %u! Ingnoring the call. See aclsoc_common.h for list of understood commands", kcmd.command);
    result = -EFAULT;
    break;
  } //end switch
  
  return result;
}

/* Pinning user pages.
 *
 * Taken from <kernel code>/drivers/infiniband/hw/ipath/ipath_user_pages.c
 */
static void __aclsoc_release_user_pages(struct page **p, size_t num_pages,
           int dirty)
{
  size_t i;

  for (i = 0; i < num_pages; i++) {
    if (dirty) {
      set_page_dirty_lock(p[i]);
    }
    put_page(p[i]);
  }
}

/* call with target_task->mm->mmap_sem held */
static int __aclsoc_get_user_pages(struct task_struct *target_task, unsigned long start_page, size_t num_pages,
      struct page **p, struct vm_area_struct **vma, int write)
{
  size_t got;
  int ret;
  

  for (got = 0; got < num_pages; got += ret) {
    ret = get_user_pages_unlocked(target_task, target_task->mm,
             start_page + got * PAGE_SIZE,
             num_pages - got, write, 1,
             p + got);

    if (ret < 0)
      goto bail_release;
  }

  target_task->mm->locked_vm += num_pages;

  ret = 0;
  goto bail;

bail_release:
  __aclsoc_release_user_pages(p, got, 0);
bail:
  return ret;
}


/**
 * aclsoc_get_user_pages - lock user pages into memory
 * @start_page: the start page
 * @num_pages: the number of pages
 * @p: the output page structures
 *
 * This function takes a given start page (page aligned user virtual
 * address) and pins it and the following specified number of pages.
 */
int aclsoc_get_user_pages(struct task_struct *target_task, unsigned long start_page, size_t num_pages,
       struct page **p, int write)
{
  int ret;

  ret = __aclsoc_get_user_pages(target_task, start_page, num_pages, p, NULL, write);

  return ret;
}

void aclsoc_release_user_pages(struct task_struct *target_task, struct page **p, size_t num_pages, int dirty)
{
  down_write(&target_task->mm->mmap_sem);

  __aclsoc_release_user_pages(p, num_pages, dirty);

  target_task->mm->locked_vm -= num_pages;

  up_write(&target_task->mm->mmap_sem);
}

