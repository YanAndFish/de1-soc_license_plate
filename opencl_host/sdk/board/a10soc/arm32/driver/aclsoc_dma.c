/* DMA logic imlementation.
 *
 * The basic flow of DMA transfer is as follows:
 *  1. Pin user memory (a contiguous set of address in processor address space)
 *     to get a list of physical pages (almost never contiguous list of 4KB
 *     blocks).
 *  2. Setup ATT (address translation table) entries for physical page address 
 *     to "row #" mapping in the FPGA PCIe core (a "row number" is just a
 *     counter that is passed in DMA descriptor as a host address).
 *  3. Create and send DMA descriptor (src addr, dest addr, and lengh) to the DMA
 *     core to perform the transfer. 
 *  4. Go to step 2 if have not transfered all currently pinned memory yet.
 *  5. Go to step 1 if need to pin more memory.
 *
 * DMA controller sends an interrupt whenever work for a single DMA descriptor
 * is complete. The driver also checks "done_count" to see how many descriptors
 * completed. This is in case the driver misses an interrupt.
 *
 * To keep interrupt logic simple (i.e. no work-queues), the user has to stall
 * using the following logic until DMA is done:
 *
 *   while (!dma->is_idle())
 *      dma->update(0);
 *
 * The DMA logic is complicated because there are a number of limits of what can
 * be done in one shot. Here they are (all are constants in hw_pcie_constants.h):
 *  - How much user memory can be pinned at one time.
 *  - Size of ATT table in hardware
 *  - Number of outstanding descriptors the hardware can have.
 *
 * Due to hardware restrictions, can only do DMA for 32-byte aligned start
 * addresses (on both host and device) AND 32-byte aligned lengths.
 * Also, need to use a separate descriptor for transfers that do NOT start or
 * end on page boundary. DMA engine does NOT do DMA for these cases, so these
 * transfers are very slow. */


#include <linux/mm.h>
#include <linux/scatterlist.h>
#include <linux/sched.h>
#include <asm/page.h>
#include <linux/spinlock.h>
#include <linux/version.h>
#include <linux/time.h>
#include <asm/outercache.h>
#include <asm/cacheflush.h>
#include<linux/kthread.h>
#include <linux/cache.h>
#include <linux/rcupdate.h>

#include "aclsoc.h"


#include <linux/mm.h>
#include <asm/siginfo.h>    //siginfo

#if USE_DMA

/* Map/Unmap pages for DMA transfer.
 * All docs say I need to do it but unmapping pages after
 * reading clears their content. */

#define DEBUG_UNLOCK_PAGES 0

#if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 20)
void wq_func_dma_update(void *data);
#else
void wq_func_dma_update(struct work_struct *pwork);
#endif

/* Forward declarations */
int read_write (struct aclsoc_dev* aclsoc, void* src, void *dst, size_t bytes, int reading);
void send_active_descriptor (struct aclsoc_dev* aclsoc);
void unlock_dma_buffer (struct aclsoc_dev *aclsoc, struct dma_t *dma);

unsigned long acl_get_dma_offset (struct aclsoc_dev *aclsoc) {
   return ACL_MMD_DMA_OFFSET;
}
unsigned long get_dma_desc_offset(struct aclsoc_dev *aclsoc) {
   return ACL_MMD_DMA_DESCRIPTOR_OFFSET;
}

/* Get memory-mapped address on the device. 
 * Assuming asking for DMA control region, so have hard-coded BAR value. */
void *get_dev_addr(struct aclsoc_dev *aclsoc, void *addr, ssize_t data_size) {

  ssize_t errno = 0;
  void *dev_addr = 0;
  struct aclsoc_dma *d = &(aclsoc->dma_data);
  
  if (d->m_aclsoc == NULL) return dev_addr;
  
  dev_addr = aclsoc_get_checked_addr (ACL_MMD_DMA_BAR, addr, data_size, d->m_aclsoc, &errno, 1);
  if (errno != 0) {
    ACL_DEBUG (KERN_DEBUG "ERROR: addr failed check");
    return NULL;
  }
  return dev_addr;
}


/* write 32 bits to DMA control region */
void dma_write32(struct aclsoc_dev *aclsoc, ssize_t addr, u32 data) {

  unsigned long dma_offset = acl_get_dma_offset(aclsoc);

  void *dev_addr = get_dev_addr (aclsoc, (void*)addr + dma_offset, sizeof(u32));
  ACL_VERBOSE_DEBUG (KERN_DEBUG "DMA: Writing 32 bits %u, addr = 0x%p, dev_addr = 0x%p, dma_offset = 0x%lx",
                     data, addr , dev_addr, dma_offset);
  if (dev_addr == NULL) return;
  writel (data, dev_addr);
  
  ACL_VERBOSE_DEBUG (KERN_DEBUG "   DMA: Read back 32 bits (%u) from 0x%p", readl (dev_addr), dev_addr);
}

/* read 32 bits from DMA control region */
ssize_t dma_read32(struct aclsoc_dev *aclsoc, ssize_t addr) {
  unsigned long dma_offset = acl_get_dma_offset(aclsoc);
  void *dev_addr = get_dev_addr (aclsoc, (void*)addr + dma_offset, sizeof(u32));
  ACL_VERBOSE_DEBUG (KERN_DEBUG "DMA: Reading 32 bits from 0x%p", addr);
  return readl (dev_addr);
}

union u64_4 {
  struct DMA_DESCRIPTOR desc;
  u64 ints[4];
};


/* Write a single DMA descriptor to the DMA control region. */
void dma_desc_write(struct aclsoc_dev *aclsoc, void *addr, struct DMA_DESCRIPTOR *desc) {
  unsigned long dma_desc_offset = get_dma_desc_offset(aclsoc);

  union u64_4 u;
  void *dev_addr = get_dev_addr (aclsoc, addr + dma_desc_offset, sizeof(u64));

  if (dev_addr == NULL) return;
  
  u.desc = *desc;

  writel(u.desc.read_address,        dev_addr);
  writel(u.desc.write_address,       dev_addr + sizeof(u32)); 
  writel(u.desc.bytes,               dev_addr + 2*sizeof(u32));
  writeb((u16)(54),   dev_addr + 3*sizeof(u32));
  writeb((u8)(u.desc.burst >> 16),   dev_addr + 3*sizeof(u32) + sizeof(u16));
  writeb((u8)(u.desc.burst >> 24),   dev_addr + 3*sizeof(u32) + sizeof(u16) + sizeof(u8));
  writew((u16) u.desc.stride,        dev_addr + 4*sizeof(u32));
  writew((u16)(u.desc.stride >> 16), dev_addr + 4*sizeof(u32) + sizeof(u16));
  writel(u.desc.read_address_hi,     dev_addr + 5*sizeof(u32)); 
  writel(u.desc.write_address_hi,    dev_addr + 6*sizeof(u32));  
  writel(u.desc.control,             dev_addr + 7*sizeof(u32)); 

}

int is_idle (struct aclsoc_dev *aclsoc) {
  struct aclsoc_dma *d = &(aclsoc->dma_data);
  return d->m_idle;
}

/* Add a byte-offset to a void* pointer */
void* compute_address (void* base, unsigned long offset)
{
  unsigned long p = (unsigned long)(base);
  return (void*)(p + offset);
}


/* Init DMA engine. Should be done at device load time */
void aclsoc_dma_init(struct aclsoc_dev *aclsoc) {

  struct aclsoc_dma *d = &(aclsoc->dma_data);
  memset( &d->m_active_mem, 0, sizeof(struct pinned_mem) );
  d->m_idle=1;
  
  d->m_aclsoc = aclsoc;

  /* Enable DMA controller */
  dma_write32 (aclsoc, DMA_CSR_CONTROL, ACL_GET_BIT(DMA_CTRL_IRQ_ENABLE));
  
  // create a workqueue with a single thread and a work structure
  d->my_wq   = create_singlethread_workqueue("aclkmdq");
  d->my_work = (struct work_struct_t*) kmalloc(sizeof(struct work_struct_t), GFP_KERNEL);
  if(d->my_work) {
    d->my_work->data = (void *)aclsoc;
#if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 20)
    INIT_WORK( &d->my_work->work, wq_func_dma_update, (void *)d->my_work->data); 
#else
    INIT_WORK( &d->my_work->work, wq_func_dma_update);
#endif
  }
}


void aclsoc_dma_finish(struct aclsoc_dev *aclsoc) {

  struct aclsoc_dma *d = &(aclsoc->dma_data);
  
  /* Disable DMA interrupt */
  dma_write32 (aclsoc, DMA_CSR_CONTROL, 0);
  
  d->m_idle = 1;
  
  flush_workqueue(d->my_wq);
  destroy_workqueue(d->my_wq);
  kfree(d->my_work);

}

// Handle unexpected ctrl+c signal from user
void aclsoc_dma_stop(struct aclsoc_dev *aclsoc) { 

  struct aclsoc_dma *d = &(aclsoc->dma_data);

  /* Disable DMA interrupt */
  dma_write32 (aclsoc, DMA_CSR_CONTROL, 0);
  
  d->m_idle = 1;
  
  /* Flush any pending work on the workqueue */
  flush_workqueue(d->my_wq);
  
}


/* Called by main interrupt handler in aclsoc.c. By the time we get here,
 * we know it's a DMA interrupt. So only need to do DMA-related stuff. */
irqreturn_t aclsoc_dma_service_interrupt (struct aclsoc_dev *aclsoc)
{
  struct aclsoc_dma *d = &(aclsoc->dma_data);
  
  // Clear the IRQ bit
  dma_write32 (aclsoc, DMA_CSR_STATUS, ACL_GET_BIT(DMA_STATUS_IRQ) );
  dma_read32 (aclsoc, DMA_CSR_STATUS);
  
  if (d->m_idle)
    return IRQ_HANDLED;
  
  if (*((u32*)d->host_irq_table + 16)) {
    ACL_VERBOSE_DEBUG (KERN_DEBUG "Finished DMA request.\n");
    memset(d->host_irq_table, 0, 128);
    if( !queue_work(d->my_wq, &d->my_work->work) ){
      printk("Failed to schedule DMA work in interrupt service routine\n");
    }
  }

  return IRQ_HANDLED;
}


/* Read/Write large amounts of data using DMA.
 *   dev_addr  -- address on device to read to/write from
 *   dest_addr -- address in user space to read to/write from
 *   len       -- number of bytes to transfer
 *   reading   -- 1 if doing read (from device), 0 if doing write (to device)
 */
ssize_t aclsoc_dma_rw (struct aclsoc_dev *aclsoc,
                       void *dev_addr, void __user* user_addr, 
                       ssize_t len, int reading) {
  ACL_VERBOSE_DEBUG (KERN_DEBUG "DMA: %sing %lu bytes", reading ? "Read" : "Writ", len);
  //ACL_DEBUG (KERN_DEBUG "DMA: %sing %lu bytes", reading ? "Read" : "Writ", len);
  if (reading) {
    read_write (aclsoc, dev_addr,  user_addr, len, reading);
  } else {
    read_write (aclsoc, user_addr,  dev_addr, len, reading);
  }
  
  return 0;
}


/* Return idle status of the DMA hardware. */
int aclsoc_dma_get_idle_status(struct aclsoc_dev *aclsoc) {
  return aclsoc->dma_data.m_idle;
}


int lock_dma_buffer (struct aclsoc_dev *aclsoc, void *addr, ssize_t len, struct pinned_mem *active_mem) {

  int ret;
  unsigned int num_act_pages;
  struct aclsoc_dma *d = &(aclsoc->dma_data);
  size_t start_page, end_page, num_pages;
  struct dma_t *dma = &(active_mem->dma);
  int write = d->m_read;
  
  dma->ptr = addr;
  dma->len = len;
  dma->dir = d->m_read ? PCI_DMA_FROMDEVICE : PCI_DMA_TODEVICE;
  /* num_pages that [addr, addr+len] map to. */
  start_page = (size_t)addr >> PAGE_SHIFT;
  end_page = ((size_t)addr + (size_t)len - 1) >> PAGE_SHIFT;
  num_pages = end_page - start_page + 1;
  
  dma->num_pages = (ssize_t) num_pages;
  dma->pages = (struct page**)kzalloc ( sizeof(struct page*) * dma->num_pages, GFP_KERNEL );
  if (dma->pages == NULL) {
    ACL_DEBUG (KERN_DEBUG "Couldn't allocate array of %u ptrs!", dma->num_pages);
    ACL_DEBUG (KERN_DEBUG "Failed to lock dma buffer from address 0x%08x for %u bytes", (unsigned int) addr, len);
    ACL_DEBUG (KERN_DEBUG "start page was %u ::  end page was %u :: num pages was %u", start_page, end_page, num_pages);
    return -EFAULT;
  }
  
  /* pin user memory and get set of physical pages back in 'p' ptr. */
  ret = aclsoc_get_user_pages(aclsoc->user_task, (unsigned long)addr & PAGE_MASK, num_pages, dma->pages, write);
  if (ret != 0) {
    ACL_DEBUG (KERN_DEBUG "Couldn't pin all user pages. %d!\n", ret);
    ACL_DEBUG (KERN_DEBUG "Failed to lock dma buffer from address 0x%08x for %u bytes", (unsigned int) addr, len);
    return -EFAULT;
  }
  
  /* map pages for FPGA access. */
  num_act_pages = 0;

  active_mem->pages_rem = dma->num_pages;
  active_mem->next_page = dma->pages;
  active_mem->first_page_offset = (unsigned long)addr & (PAGE_SIZE - 1);
  active_mem->last_page_offset = (unsigned long)(addr + len) & (PAGE_SIZE - 1);
  
  //ACL_DEBUG (KERN_DEBUG  "Content of first page (addr  = %p): %s", 
  //             page_to_phys(dma->pages[0]), (char*)phys_to_virt(page_to_phys(dma->pages[0])));
  
  ACL_VERBOSE_DEBUG (KERN_DEBUG  "DMA: Pinned %u bytes (%u pages) at 0x%p", 
        (unsigned int)len, num_pages, addr);
  ACL_VERBOSE_DEBUG (KERN_DEBUG  "DMA: first page offset is %u, last page offset is %u", 
        active_mem->first_page_offset, active_mem->last_page_offset);
         
  return 0;
}


void unlock_dma_buffer (struct aclsoc_dev *aclsoc, struct dma_t *dma) {

  struct aclsoc_dma *d = &(aclsoc->dma_data);
  int dirty = d->m_read;
  
  #if DEBUG_UNLOCK_PAGES
  unsigned int *s = (unsigned int*)phys_to_virt(page_to_phys(dma->pages[0]));
  
  ACL_DEBUG (KERN_DEBUG  "1. Content of first page (addr  = %p): %u", 
               page_to_phys(dma->pages[0]), s);
  #endif
  
  /* Unpin pages */
  aclsoc_release_user_pages (aclsoc->user_task, dma->pages, dma->num_pages, dirty);
  
  // TODO: If do map/unmap for reads, the data is 0 by now!!!!
  //#if DEBUG_UNLOCK_PAGES
  //ACL_DEBUG (KERN_DEBUG  "2. Content of first page: %u", s);
  //#endif

  /* TODO: try to re-use these buffers on future allocs */
  kfree (dma->pages);

  ACL_VERBOSE_DEBUG (KERN_DEBUG  "DMA: Unpinned %u pages", 
                          dma->num_pages);
                          
  /* Reset all dma fields. */
  memset (dma, 0, sizeof(struct dma_t));
  
}


int thread_pin_buf (void *data)
{
  struct aclsoc_dev *aclsoc = (struct aclsoc_dev *) data;
  struct aclsoc_dma *d = &(aclsoc->dma_data);
  size_t bytes_rem = (d->m_bytes - d->m_bytes_sent_prefetch);
  unsigned int lock_size = (bytes_rem > ACL_MMD_DMA_MAX_PINNED_MEM_SIZE) ? 
              ACL_MMD_DMA_MAX_PINNED_MEM_SIZE : 
              bytes_rem;
  unsigned long last_page_portion = ((unsigned long)(d->m_host_addr_next_pin) + lock_size) & (PAGE_SIZE - 1);
  void *host_pin_addr;
  
  if (lock_size == ACL_MMD_DMA_MAX_PINNED_MEM_SIZE && 
              last_page_portion != 0) {
    lock_size -= last_page_portion;
    ACL_VERBOSE_DEBUG (KERN_DEBUG "Doing max pinning would end at %p. Instead, pinning %u bytes from %p to %p",
              d->m_host_addr_next_pin + lock_size + last_page_portion, lock_size, d->m_host_addr_next_pin, d->m_host_addr_next_pin+lock_size);
  }
  
  host_pin_addr = d->m_host_addr_next_pin;
  d->m_bytes_sent_prefetch = d->m_bytes_sent_prefetch + lock_size;
  d->m_host_addr_next_pin = compute_address (d->m_host_addr, d->m_bytes_sent_prefetch);
  
  if (lock_dma_buffer (aclsoc, host_pin_addr, lock_size, &d->m_next_mem) != 0) {
    printk("Pin Failed in thread_pin_buf");
    d->m_next_mem.dma.ptr = NULL;
    d->m_error = 1;
  }
  
  wmb();
  
  d->m_prepin_done = 1;
  
  do_exit;
  
  return 0;
}

// DMA request handler for pre-mapped pointers
// Memory is already accesible from FPGA so DMA is faster.
int aclsoc_dma_mapped_mem (struct aclsoc_dev *aclsoc)
{
  struct aclsoc_dma *d = &(aclsoc->dma_data);
  unsigned int dwBytes;
  unsigned int dma_status = 0;
  
  if (d->m_bytes_sent == d->m_bytes)
  {
    dma_status = dma_read32 (aclsoc, DMA_CSR_STATUS);
  
    if (dma_status & 1) {
      printk("Error: DMA is not idle. Status was %u\n", dma_status);
      return 1;
    }
    
    ACL_VERBOSE_DEBUG (KERN_DEBUG "Mapped DMA finished\n");
      
    d->m_host_pre_mapped = 0;
    
    // If d->m_idle is already set, the user must have sent a ctrl+c
    if (d->m_idle) {
      return 1;
    }
  
    d->m_idle = 1;
  
    // send signal to notify the completion of the DMA transfer
    rcu_read_lock();
    aclsoc->user_task = pid_task(find_vpid(aclsoc->user_pid), PIDTYPE_PID);
    rcu_read_unlock();

    if(aclsoc->user_task != NULL) {
      if( send_sig_info(SIG_INT_NOTIFY, &aclsoc->signal_info_dma, aclsoc->user_task) < 0) {
        printk("Error sending signal to host!\n");
      }
    }
    
    return 1;
  }
  
  if (d->m_bytes_sent < d->m_bytes)
  {
    int desc_sent = 0;
    
    // Keep sending DMA requests until we run out of descriptors or data
    while (d->m_bytes_sent < d->m_bytes && desc_sent < (ACL_MMD_DMA_MAX_DESCRIPTORS - 1))
    {
      // Set the next descriptor to send
      size_t hps_addr_lo32 = d->m_host_mapped_addr + d->m_bytes_sent;
      size_t fpga_addr_lo32 = d->m_device_addr + d->m_bytes_sent;
      
      d->m_active_descriptor.read_address = d->m_read ? fpga_addr_lo32 : hps_addr_lo32;
      d->m_active_descriptor.write_address = d->m_read ? hps_addr_lo32 : fpga_addr_lo32;
      d->m_active_descriptor.bytes = 0;  // Updated below
      d->m_active_descriptor.burst = 0;
      d->m_active_descriptor.stride = ACL_MMD_DMA_STRIDE;
      d->m_active_descriptor.read_address_hi = d->m_read ? ACL_DMA_FPGA_HI32 : ACL_DMA_HPS_HI32;
      d->m_active_descriptor.write_address_hi = d->m_read ? ACL_DMA_HPS_HI32 : ACL_DMA_FPGA_HI32;
      
      dwBytes = ((d->m_bytes - d->m_bytes_sent) > ACL_MMD_DMA_MAX_TRANSFER_SIZE) ?
                ACL_MMD_DMA_MAX_TRANSFER_SIZE : (d->m_bytes - d->m_bytes_sent);
      
      d->m_active_descriptor.bytes = dwBytes;
      d->m_bytes_sent += dwBytes;

      send_active_descriptor(aclsoc);
      desc_sent++;
      wmb();
    }

    // Send one more descriptor.
    // This does loopback from HPS memory to DMA to HPS memory.
    // When this finishes, we know all descriptors are done.
    *((u32*) d->host_irq_table) = 1;
    wmb();
    
    d->m_active_descriptor.read_address = d->dma_irq_table;
    d->m_active_descriptor.write_address = d->dma_irq_table + 64;
    d->m_active_descriptor.bytes = 64;  // Updated below
    d->m_active_descriptor.burst = 0;
    d->m_active_descriptor.stride = ACL_MMD_DMA_STRIDE;
    d->m_active_descriptor.read_address_hi = ACL_DMA_HPS_HI32;
    d->m_active_descriptor.write_address_hi = ACL_DMA_HPS_HI32;

    send_active_descriptor(aclsoc);
    wmb();

  }

  return 1;
}


// Return 1 if something was done. 0 otherwise.
// This handles DMA requests for host memory that hasn't been pinned yet.
// 
int aclsoc_dma_update (struct aclsoc_dev *aclsoc, int forced)
{
  unsigned int dma_status = 0;
  struct aclsoc_dma *d = &(aclsoc->dma_data);
  int desc_sent = 0;
  struct task_struct *pin_task;

  // There was error in previous run of aclsoc_dma_update. Most likely in pinning user page.
  // Stop DMA for current host execution.
  // The DMA will go into good state when MMD is opened again.
  if (d->m_error || d->m_idle) {
    return 1;
  }
  
  if (d->m_bytes_sent == d->m_bytes)
  {
    dma_status = dma_read32 (aclsoc, DMA_CSR_STATUS);
    
    // Sanity check. This should never be true, but if it is, want some message for debug.
    if (dma_status & 1) {
      printk("Error: DMA is not idle. Status was %u\n", dma_status);
      return 1;
    }
    
    unlock_dma_buffer (aclsoc, &d->m_active_mem.dma);
    d->m_active_mem.dma.ptr = NULL;
  
    ACL_VERBOSE_DEBUG (KERN_DEBUG "DMA finished\n");
    
    // Someone already set the DMA work as idle
    // This happens when user sends a ctrl+c.
    // Return without sending dma completion signal to runtime
    if (d->m_idle) {
      return 1;
    }
  
    d->m_idle = 1;
  
    // send signal to notify the completion of the DMA transfer
    rcu_read_lock();
    aclsoc->user_task = pid_task(find_vpid(aclsoc->user_pid), PIDTYPE_PID);
    rcu_read_unlock();
    
    if(aclsoc->user_task != NULL) {
      if( send_sig_info(SIG_INT_NOTIFY, &aclsoc->signal_info_dma, aclsoc->user_task) < 0) {
        printk("Error sending signal to host!\n");
      }
    }
    
    return 1;
  }

  // Pin the first set of pages for DMA
  // This gets called only at beginning of user's DMA request
  // After this, memory pinning will be done by seperate thread
  if (d->m_active_mem.dma.ptr == NULL)
  {
    size_t bytes_rem = (d->m_bytes - d->m_bytes_sent);
    unsigned int lock_size = (bytes_rem > ACL_MMD_DMA_MAX_PINNED_MEM_SIZE) ? 
                        ACL_MMD_DMA_MAX_PINNED_MEM_SIZE : 
                        bytes_rem;
    void* lock_addr = compute_address (d->m_host_addr, d->m_bytes_sent);
    unsigned long last_page_portion = ((unsigned long)(lock_addr) + lock_size) & (PAGE_SIZE - 1);
     
    if (lock_size == ACL_MMD_DMA_MAX_PINNED_MEM_SIZE && 
                        last_page_portion != 0) {
      lock_size -= last_page_portion;
      ACL_VERBOSE_DEBUG (KERN_DEBUG "Doing max pinning would end at %p. Instead, pinning %u bytes from %p to %p",
                        lock_addr + lock_size + last_page_portion, lock_size, lock_addr, lock_addr+lock_size);
    }

    // No active segment of pinned memory - pin one
    if (lock_dma_buffer (aclsoc, lock_addr, lock_size, &d->m_active_mem) != 0) {
      printk("Pin failed\n");
      return 1;
    }
     
    // Prepare pointers for next pin
    d->m_bytes_sent_prefetch = d->m_bytes_sent + lock_size;
    d->m_host_addr_next_pin = compute_address (d->m_host_addr, d->m_bytes_sent + lock_size);
    
    // Launch thread to pin next set of pages
    if (d->m_bytes_sent_prefetch < d->m_bytes) {
      d->m_prepin_done = 0;
      pin_task = kthread_run(&thread_pin_buf,(void *)aclsoc,"aclsoc_pin_task");
    }
  }
  
  // No more pages left in active mem.
  // Unpin it and set the pre-pinned mem as active mem.
  if (d->m_active_mem.pages_rem == 0) {
    dma_status = dma_read32 (aclsoc, DMA_CSR_STATUS);
    
    // Sanity check. This should never be true, but if it is, want some message for debug.
    if (dma_status & 1) {
      printk("Error: DMA is not idle. Status was %u\n", dma_status);
      return 1;
    }
    
    // Poll until pre-pin launched in earlier work is complete
    while (d->m_bytes_sent < d->m_bytes && !d->m_prepin_done)
    {
      ndelay(100);
    }
    
    unlock_dma_buffer (aclsoc, &d->m_active_mem.dma);
    d->m_active_mem.dma.ptr = NULL;
  
    if (d->m_bytes_sent < d->m_bytes) {
      d->m_active_mem = d->m_next_mem;
      d->m_next_mem.dma.ptr = NULL;
    }
    
    // m_error is set by pre-pin thread.
    // Something went wrong during pre-pin
    if (d->m_error) {
      return 1;
    }
    
    // Launch thread to pin next set of pages
    if (d->m_bytes_sent_prefetch < d->m_bytes) {
      d->m_prepin_done = 0;
      pin_task = kthread_run(&thread_pin_buf,(void *)aclsoc,"aclsoc_pin_task");
    }
  }

  // Main DMA work
  // Keep sending requests to DMA until there aren't any more descriptors or pages left.
  while (desc_sent < (ACL_MMD_DMA_MAX_DESCRIPTORS - 1) && d->m_active_mem.pages_rem > 0)
  {
    unsigned int consecutive_mem = 1;
    unsigned int dwBytes;
    unsigned int unaligned_start = 0;
    int pages_sent = 0;
    dma_addr_t pPhysicalAddr;
    size_t hps_addr_lo32, fpga_addr_lo32;
  
    struct page *next_page = *(d->m_active_mem.next_page);
    
    if (d->m_read) {
      void *page_addr = page_address(next_page);
      __cpuc_flush_dcache_area (page_addr, PAGE_SIZE);
    } else {
      void *page_addr = page_address(next_page);
      __cpuc_flush_dcache_area (page_addr, PAGE_SIZE);
    }

    pPhysicalAddr = page_to_phys (next_page);
    pages_sent++;
    dwBytes = PAGE_SIZE;
    
    // First page. If we begin with an offset, we can't use the full page
    if (d->m_active_mem.first_page_offset != 0)
    {
      dwBytes -= d->m_active_mem.first_page_offset;
      pPhysicalAddr += d->m_active_mem.first_page_offset;
      ACL_VERBOSE_DEBUG (KERN_DEBUG "First page. Adjusted bytes to %u. Adjusted PhysAddr to 0x%lx",
                  dwBytes, pPhysicalAddr);
      d->m_active_mem.first_page_offset = 0;
      unaligned_start = 1;
    }
    
    // Last page (could also be the first page.
    if (d->m_active_mem.pages_rem == 1 && d->m_active_mem.last_page_offset != 0)
    {
      dwBytes -= (PAGE_SIZE - d->m_active_mem.last_page_offset);
      ACL_VERBOSE_DEBUG (KERN_DEBUG "Last page. Adjusted bytes to %u.", dwBytes);
    }
    
    ++d->m_active_mem.next_page;
    --d->m_active_mem.pages_rem;
    
    
    // Round up all consecutive memory pages into 1 DMA request. Max transfer size is 1MB.
    while (d->m_active_mem.pages_rem > 0 && consecutive_mem && !unaligned_start &&
            d->m_active_mem.pages_rem > 1 && dwBytes < ACL_MMD_DMA_MAX_TRANSFER_SIZE)
    {
      unsigned long next_pPhysicalAddr;
      
      next_page = *(d->m_active_mem.next_page);
      
      // Flush L1 cache for the next page
      if (d->m_read) {
        void *page_addr = page_address(next_page);
        __cpuc_flush_dcache_area (page_addr, PAGE_SIZE);
      } else {
        void *page_addr = page_address(next_page);
        __cpuc_flush_dcache_area(page_addr, PAGE_SIZE);
      }
      
      // Check if the next page is consecutive to current page
      next_pPhysicalAddr = page_to_phys (next_page);
      consecutive_mem = (next_pPhysicalAddr == pPhysicalAddr + dwBytes);
      
      // If pages are consecutive, append and get ready to check the next page
      if (consecutive_mem == 1) {
        ACL_VERBOSE_DEBUG (KERN_DEBUG "Consecutive pages detected.\n");
        ACL_VERBOSE_DEBUG (KERN_DEBUG "Current transfer for %u bytes starts at 0x%08x and next page starts at 0x%08x\n",
                pPhysicalAddr, dwBytes, next_pPhysicalAddr);
        
        dwBytes += PAGE_SIZE;
        pages_sent++;
        
        if (d->m_active_mem.pages_rem == 1 && d->m_active_mem.last_page_offset != 0)
        {
          dwBytes -= (PAGE_SIZE - d->m_active_mem.last_page_offset);
          ACL_VERBOSE_DEBUG (KERN_DEBUG "Last page. Adjusted bytes to %u.", dwBytes);
        }
        
        ++d->m_active_mem.next_page;
        --d->m_active_mem.pages_rem;
      }
      
    }
    
    // Flush L2 cache
    if (d->m_read) {
      outer_inv_range(pPhysicalAddr, pPhysicalAddr + dwBytes);
    } else {
      outer_clean_range(pPhysicalAddr, pPhysicalAddr + dwBytes);
    }
  
    // Set the next descriptor to send
    hps_addr_lo32 = pPhysicalAddr;
    fpga_addr_lo32 = (size_t)d->m_device_addr + d->m_bytes_sent;
    
    d->m_active_descriptor.read_address = d->m_read ? fpga_addr_lo32 : hps_addr_lo32;
    d->m_active_descriptor.write_address = d->m_read ? hps_addr_lo32 : fpga_addr_lo32;
    d->m_active_descriptor.bytes = 0; // Updated below
    d->m_active_descriptor.burst = 0;
    d->m_active_descriptor.stride = ACL_MMD_DMA_STRIDE;
    d->m_active_descriptor.read_address_hi = d->m_read ? ACL_DMA_FPGA_HI32 : ACL_DMA_HPS_HI32;
    d->m_active_descriptor.write_address_hi = d->m_read ? ACL_DMA_HPS_HI32 : ACL_DMA_FPGA_HI32;
    
    d->m_active_descriptor.bytes = (unsigned int)(dwBytes);
    d->m_bytes_sent += dwBytes;

    send_active_descriptor(aclsoc);
    desc_sent++;
    wmb();
    
    ACL_VERBOSE_DEBUG(KERN_DEBUG "Sending %u bytes for %s starting from 0x%08x to 0x%08x\n",
          dwBytes, d->m_read ? "read" : "write", d->m_read ? (d->m_device_addr + d->m_bytes_sent) : pPhysicalAddr,
          d->m_read ? pPhysicalAddr : (d->m_device_addr + d->m_bytes_sent));

  }

  // Send one more descriptor.
  // This does loopback from HPS memory to DMA to HPS memory.
  // When this finishes, we know all descriptors are done.
  *((u32*) d->host_irq_table) = 1;
  wmb();
  
  d->m_active_descriptor.read_address = d->dma_irq_table;
  d->m_active_descriptor.write_address = d->dma_irq_table + 64;
  d->m_active_descriptor.bytes = 64;  // Updated below
  d->m_active_descriptor.burst = 0;
  d->m_active_descriptor.stride = ACL_MMD_DMA_STRIDE;
  d->m_active_descriptor.read_address_hi = ACL_DMA_HPS_HI32;
  d->m_active_descriptor.write_address_hi = ACL_DMA_HPS_HI32;
  
  send_active_descriptor(aclsoc);
  wmb();
  
  ACL_VERBOSE_DEBUG (KERN_DEBUG "Sent %u descriptors. Waiting for interrupt\n", desc_sent);

  return 1;
}

#if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 20)
void wq_func_dma_update(void *data){
  struct aclsoc_dev *aclsoc = (struct aclsoc_dev *)data;
#else
void wq_func_dma_update(struct work_struct *pwork){
  struct work_struct_t * my_work_struct_t = container_of(pwork, struct work_struct_t, work);
  struct aclsoc_dev *aclsoc = (struct aclsoc_dev *)my_work_struct_t->data;
#endif
  struct aclsoc_dma *d = &(aclsoc->dma_data);

  if (d->m_host_pre_mapped) {
    aclsoc_dma_mapped_mem(aclsoc);
  } else {
    aclsoc_dma_update(aclsoc, 1);
  }
   
   return;
}

void send_active_descriptor(struct aclsoc_dev *aclsoc)
{
  struct aclsoc_dma *d = &(aclsoc->dma_data);

  // DMA controller is setup to only handle aligned requests - verify this is a 256-bit aligned request
  // If this fails, I think we need to bite the bullet and write our own DMA
  if(((d->m_active_descriptor.read_address & DMA_ALIGNMENT_BYTE_MASK) != 0) ||
     ((d->m_active_descriptor.write_address & DMA_ALIGNMENT_BYTE_MASK) != 0) ||
     ((d->m_active_descriptor.bytes & DMA_ALIGNMENT_BYTE_MASK) != 0) )
  {
    ACL_DEBUG (KERN_WARNING "Error: Attempted to send unaligned descriptor\n");
    ACL_DEBUG (KERN_WARNING "       0x%u -> 0x%u (0x%u bytes)\n", 
            d->m_active_descriptor.read_address,
            d->m_active_descriptor.write_address,
            d->m_active_descriptor.bytes);
    assert(0);
  }
  
  d->m_active_descriptor.control = (unsigned int)( ACL_GET_BIT(DMA_DC_GO) | 
                                  ACL_GET_BIT(DMA_DC_EARLY_DONE_ENABLE) |
                                  ACL_GET_BIT(DMA_DC_TRANSFER_COMPLETE_IRQ_MASK) );
  wmb();
  dma_desc_write (aclsoc, 0, &d->m_active_descriptor);
  
}


int read_write
(
  struct aclsoc_dev *aclsoc, 
  void* src,
  void *dst,
  size_t bytes,
  int reading
)
{  
  size_t dev_addr;
  struct aclsoc_dma *d = &(aclsoc->dma_data);
  int iMapInfo;
  struct addr_map_elem * map_struct = NULL;
  
  assert(d->m_active_mem.dma.ptr == NULL);
  assert(d->m_idle);

  // Copy the parameters over and mark the job as running
  d->m_read = reading;
  d->m_bytes = (bytes);
  assert(d->m_bytes == bytes);
  d->m_host_addr = reading ? dst : src;
  dev_addr = (size_t)(reading ? src : dst);
  d->m_device_addr = (size_t)(dev_addr);

  // Start processing the request
  d->m_idle = 0;
  d->m_bytes_sent = 0;
  
  // Reset parameters
  d->m_next_mem.dma.ptr = NULL;
  d->m_prepin_done = 1;
  memset(d->host_irq_table, 0, 128);
  d->m_error = 0;
   
  // Check if the host's memory is already mapped
  d->m_host_pre_mapped = 0;
   
  // We know that host's memory is already mapped if host's pointer is
  // within the range of any of the mapped addresses
  for (iMapInfo = 0; iMapInfo < MAX_ADDR_MAP_ENTRIES; iMapInfo++)
  {
    int larger_than_cpu_addr;
    int smaller_than_cap_cpu_addr;
    size_t addr_offset;
    map_struct = &(aclsoc->addr_map[iMapInfo]);
    if (map_struct->vm_start == 0) continue;
    
    larger_than_cpu_addr = (int) d->m_host_addr >= map_struct->vm_start;
    smaller_than_cap_cpu_addr = (int) (d->m_host_addr + d->m_bytes) <= (map_struct->vm_start + map_struct->size);
    
    if (larger_than_cpu_addr & smaller_than_cap_cpu_addr) {
      addr_offset = d->m_host_addr - (void *) map_struct->vm_start;
      d->m_host_mapped_addr = map_struct->dma_handle + addr_offset;
      d->m_host_pre_mapped = 1;
      ACL_VERBOSE_DEBUG (KERN_DEBUG "Memory has already been pinned by host\n");
    }
  }
  
  if( !queue_work(d->my_wq, &d->my_work->work) ){
    printk("Failed to schedule DMA work in read_write\n");
  }
  
  return 1;
}

#else // USE_DMA is 0

irqreturn_t aclsoc_dma_service_interrupt (struct aclsoc_dev *aclsoc) {
  return IRQ_HANDLED;
}
ssize_t aclsoc_dma_rw (struct aclsoc_dev *aclsoc, 
                       void *dev_addr, void __user* user_addr, 
                       ssize_t len, int reading) {return 0; }
void aclsoc_dma_init(struct aclsoc_dev *aclsoc) {}
void aclsoc_dma_finish(struct aclsoc_dev *aclsoc) {}
int aclsoc_dma_get_idle_status(struct aclsoc_dev *aclsoc) { return 1; }
int aclsoc_dma_update(struct aclsoc_dev *aclsoc, int forced) { return 0; }

MODULE_LICENSE("GPL");

#endif // USE_DMA

