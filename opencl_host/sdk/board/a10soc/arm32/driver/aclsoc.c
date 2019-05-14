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

/* Top-level file for the driver.
 * Deal with device init and shutdown, BAR mapping, and interrupts. */

#include "aclsoc.h"
#include <asm/siginfo.h>    //siginfo
#include <linux/rcupdate.h> //rcu_read_lock
#include <linux/version.h>  //kernel_version

MODULE_AUTHOR  ("Dmitry Denisenko");
MODULE_LICENSE ("Dual BSD/GPL");
MODULE_DESCRIPTION ("Driver for Intel(R) OpenCL SoC Acceleration Devices");
MODULE_SUPPORTED_DEVICE ("Intel(R) OpenCL SoC Devices");


// all these defines should be absorbed by acl_init

// Offsets taken from CV Device handbook, Chapter 3, page 1-16
// Sizes decided by the QSYS system.
#define lwHPS2FPGA_OFFSET   0xFF200000
#define lwHPS2FPGA_SIZE     0x40000   // 2 MB

#define   HPS2FPGA_OFFSET   0xC0000000 
#define   HPS2FPGA_SIZE     0x10000   // Global memory window size

/* Static function declarations */
static int  aclsoc_probe(struct platform_device *pdev);
static int  init_chrdev (struct aclsoc_dev *aclsoc);
static int  aclsoc_remove(struct platform_device * pdev);
static int aclsoc_mmap (struct file *filp, struct vm_area_struct *vma);

static struct aclsoc_dev *aclsoc = 0;
static struct class *aclsoc_class = NULL;

struct file_operations aclsoc_fileops = {
  .owner =    THIS_MODULE,
  .read =     aclsoc_read,
  .write =    aclsoc_write,
  .open =     aclsoc_open,
  .release =  aclsoc_close,
  .mmap    = aclsoc_mmap,
};

/* Allocate /dev/BOARD_NAME device */
static int  init_chrdev (struct aclsoc_dev *aclsoc) {

  int dev_minor =   0;
  int dev_major =   0; 
  int devno = -1;

  /* request major number for device */
  int result = alloc_chrdev_region(&aclsoc->cdev_num, dev_minor, 1 /* one device*/, BOARD_NAME);
  dev_major = MAJOR(aclsoc->cdev_num);
  if (result < 0) {
    ACL_DEBUG (KERN_WARNING "can't get major ID %d", dev_major);
    goto fail_alloc;
  }
  
  aclsoc_class = class_create(THIS_MODULE, DRIVER_NAME);
  if (IS_ERR(aclsoc_class)) {
    printk(KERN_ERR "aclsoc: can't create class\n");
    goto fail_class;
  }
  
  devno = MKDEV(dev_major, dev_minor);
    
  cdev_init (&aclsoc->cdev, &aclsoc_fileops);
  aclsoc->cdev.owner = THIS_MODULE;
  aclsoc->cdev.ops = &aclsoc_fileops;
  result = cdev_add (&aclsoc->cdev, devno, 1);
  /* Fail gracefully if need be */
  if (result) {
    printk(KERN_NOTICE "Error %d adding aclsoc (%d, %d)", result, dev_major, dev_minor);
    goto fail_add;
  }
  ACL_DEBUG (KERN_DEBUG "aclsoc = %d:%d", MAJOR(devno), MINOR(devno));
  
  /* create device nodes under /dev/ using udev */
  aclsoc->device = device_create(aclsoc_class, NULL, devno, NULL, BOARD_NAME "%d", dev_minor);
  if (IS_ERR(aclsoc->device)) {
    printk(KERN_NOTICE "Can't create device\n");
    goto fail_dev_create;
  }
  return 0;
  
/* ERROR HANDLING */
fail_dev_create:
  cdev_del(&aclsoc->cdev);
  
fail_add:
  class_destroy(aclsoc_class);

fail_class:
  /* free the dynamically allocated character device node */
  unregister_chrdev_region(devno, 1/*count*/);
  
fail_alloc:
  return -1;
}


/* Returns virtual mem address corresponding to location of IRQ control
 * register of the board */
static void* get_interrupt_enable_addr(struct aclsoc_dev *aclsoc) {

  /* Bar 2, register MMD_CRA_IRQ_ENABLE is the IRQ enable register
   * (among other things). */
  return (void*)(aclsoc->mapped_region[2 /*ACL_MMD_CRA_BAR*/] + 
                 (unsigned long)(MMD_CRA_IRQ_ENABLE));
}

static void* get_interrupt_status_addr(struct aclsoc_dev *aclsoc) {

  /* Bar 2, register MMD_CRA_IRQ_STATUS is the IRQ status register
   * (among other things). */
  return (void*)(aclsoc->mapped_region[2 /*ACL_MMD_CRA_BAR*/] +
                 (unsigned long)(MMD_CRA_IRQ_STATUS));
}

void mask_kernel_irq(struct aclsoc_dev *aclsoc){
  u32 val;
  val = readl(get_interrupt_enable_addr(aclsoc));

  if((val & ACL_GET_BIT(ACL_KERNEL_IRQ_VEC)) != 0){
    val ^= ACL_GET_BIT(ACL_KERNEL_IRQ_VEC);
  }

  writel (val, get_interrupt_enable_addr(aclsoc));
  //Read again to ensure the writel is finished
  //Without doing this might cause the programe moving
  //forward without properly mask the irq.
  val = readl(get_interrupt_enable_addr(aclsoc));
}

/* Disable interrupt generation on the device. */
static void mask_irq(struct aclsoc_dev *aclsoc) {

  writel (0x0, get_interrupt_enable_addr(aclsoc));
}

/* Enable interrupt generation on the device. */
static void unmask_irq(struct aclsoc_dev *aclsoc) {

  writel (0x3, get_interrupt_enable_addr(aclsoc));
}

/* Enable interrupt generation on the device. */
void unmask_kernel_irq(struct aclsoc_dev *aclsoc) {

  u32 val = 0;
  val = readl(get_interrupt_enable_addr(aclsoc));
  val |= ACL_GET_BIT(ACL_KERNEL_IRQ_VEC);
  writel (val, get_interrupt_enable_addr(aclsoc));
}

void unmask_dma_irq(struct aclsoc_dev *aclsoc) {

  u32 val = 0;
  val = readl(get_interrupt_enable_addr(aclsoc));
  val |= ACL_GET_BIT(ACL_DMA_IRQ_VEC);
  writel (val, get_interrupt_enable_addr(aclsoc));
}

// Given irq status, determine type of interrupt
// Result is returned in kernel_update/dma_update arguments.
// Using 'int' instead of 'bool' for returns because the kernel code
// is pure C and doesn't support bools.
void get_interrupt_type (unsigned int irq_status, unsigned int *kernel_update,
                         unsigned int *dma_update)
{
   *kernel_update = (irq_status & (1 << ACL_KERNEL_IRQ_VEC)) > 0;
   *dma_update = (irq_status & (1 << ACL_DMA_IRQ_VEC)) > 0;
}

irqreturn_t aclsoc_irq (int irq, void *dev_id) {


  struct aclsoc_dev *aclsoc = (struct aclsoc_dev *)dev_id;
  u32 irq_status;
  irqreturn_t res;
  unsigned int kernel_update = 0, dma_update = 0;
  
  if (aclsoc == NULL) {
    return IRQ_NONE;
  }
  
  /* From this point on, this is our interrupt. So return IRQ_HANDLED
   * no matter what (since nobody else in the system will handle this
   * interrupt for us). */
  aclsoc->num_handled_interrupts++;
  
  /* Kernel and DMA interrupts are on separate lines. Since DMA is not working,
   * can only get a kernel-done interrupt. */
  irq_status = readl(get_interrupt_status_addr(aclsoc));

  get_interrupt_type (irq_status, &kernel_update, &dma_update);

  ACL_VERBOSE_DEBUG (KERN_WARNING "irq_status = 0x%x, kernel = %d, dma = %d",
                     irq_status, kernel_update, dma_update); 

  if(!dma_update && !kernel_update){
    return IRQ_HANDLED;
  } else if (dma_update) {
    /* A DMA-status interrupt - let the DMA object handle this without going to
     * user space */
    res = aclsoc_dma_service_interrupt(aclsoc);
  } else if (kernel_update) {
    mask_kernel_irq(aclsoc);
    #if !POLLING
      /* Send SIGNAL to user program to notify about the kernel update interrupt. */
      rcu_read_lock();
      aclsoc->user_task = pid_task(find_vpid(aclsoc->user_pid), PIDTYPE_PID);
      rcu_read_unlock();

      if (aclsoc->user_task != NULL) {
        int ret = send_sig_info(SIG_INT_NOTIFY, &aclsoc->signal_info, aclsoc->user_task);      
        if (ret < 0) {
          /* Can get to this state if the host is suspended for whatever reason.
           * Just print a warning message the first few times. The FPGA will keep
           * the interrupt level high until the kernel done bit is cleared (by the host).*/
          aclsoc->num_undelivered_signals++;
          if (aclsoc->num_undelivered_signals < 5) {
            ACL_DEBUG (KERN_DEBUG "Error sending signal to host! irq_status is 0x%x\n", irq_status);
          }
        }
      }
    #else
       ACL_VERBOSE_DEBUG (KERN_WARNING "Kernel update interrupt. Letting host POLL for it.");
    #endif
    res = IRQ_HANDLED;
     
  }

  return res;
}


void load_signal_info (struct aclsoc_dev *aclsoc) {

  /* Setup siginfo struct to send signal to user process. Doing it once here
   * so don't waste time inside the interrupt handler. */
  struct siginfo *info = &aclsoc->signal_info;
  memset(info, 0, sizeof(struct siginfo));
  info->si_signo = SIG_INT_NOTIFY;
  /* this is bit of a trickery: SI_QUEUE is normally used by sigqueue from user
   * space,  and kernel space should use SI_KERNEL. But if SI_KERNEL is used the
   * real_time data is not delivered to the user space signal handler function. */
  info->si_code = SI_QUEUE;
  info->si_int = 0;  /* Signal payload. Will be filled later with 
                        ACLSOC_CMD_SET_SIGNAL_PAYLOAD cmd from user. */
                        
  /* Perform the same setup for struct siginfo for dma */
  info = &aclsoc->signal_info_dma;
  memset(info, 0, sizeof(struct siginfo));
  info->si_signo = SIG_INT_NOTIFY;
  info->si_code  = SI_QUEUE;
  info->si_int   = 0;

}


int init_irq (struct aclsoc_dev *aclsoc, struct platform_device *pdev) {

  u32 irq_type;
  int res;
  struct resource *r_irq;
  struct aclsoc_dma *dma;
  
#if POLLING
  return 0; 
#endif

  if (aclsoc == NULL) {
    ACL_DEBUG (KERN_DEBUG "Invalid inputs to init_irq (%p)\n", aclsoc);
    return -1;
  }

  /* Using non-shared MSI interrupts.*/
  irq_type = 0;
  
  r_irq = platform_get_resource(pdev, IORESOURCE_IRQ, 0);

  if (!r_irq) {
      ACL_DEBUG(KERN_DEBUG "No IRQ resource defined - platform_get_resource failed\n");
      return -1;
  }

  res = request_irq(r_irq->start, aclsoc_irq, 0, DRIVER_NAME , aclsoc);

  ACL_DEBUG(KERN_DEBUG "Virtualized IRQ (r_irq->start) requested: %d\n", r_irq->start);

  if (res) {
    //kfree(r_irq);
    ACL_DEBUG (KERN_DEBUG "Could not request IRQ #%d, error %d\n", r_irq->start, res);
    return -1;
  }
  ACL_DEBUG (KERN_DEBUG "Successfully requested IRQ #%d, result %d\n", r_irq->start, res);

  aclsoc->num_handled_interrupts = 0;
  aclsoc->num_undelivered_signals = 0;
  
  aclsoc_dma_init(aclsoc);
  dma = &(aclsoc->dma_data);
  dma->host_irq_table = dma_alloc_coherent(NULL, 128, &(dma->dma_irq_table), GFP_KERNEL);
  if (dma->host_irq_table == NULL) {
    return -ENOMEM;
  }
  
  memset(dma->host_irq_table, 0, 128);
  
  /* Enable interrupts */
  unmask_irq(aclsoc);
  
  return 0;
}


void release_irq (struct aclsoc_dev *aclsoc, struct platform_device *pdev) {

  int num_usignals;
  struct resource *r_irq;
  struct aclsoc_dma *dma;

#if POLLING
  return;
#endif
  aclsoc_dma_finish(aclsoc);
  
  /* Disable interrupts before going away. If something bad happened in
   * user space and the user program crashes, the interrupt assigned to the device
   * will be freed (on automatic close()) call but the device will continue 
   * generating interrupts. Soon the kernel will notice, complain, and bring down
   * the whole system. */
  mask_irq(aclsoc);
  
  dma = &(aclsoc->dma_data);
  dma_free_coherent(NULL, 128, dma->host_irq_table, dma->dma_irq_table);

  r_irq = platform_get_resource(pdev, IORESOURCE_IRQ, 0);
  
  ACL_VERBOSE_DEBUG (KERN_DEBUG "Freeing IRQ %d\n", r_irq->start);
  free_irq (r_irq->start, (void*)aclsoc);
  
  ACL_VERBOSE_DEBUG (KERN_DEBUG "Handled %d interrupts\n", 
        aclsoc->num_handled_interrupts);
        
  num_usignals = aclsoc->num_undelivered_signals;
  if (num_usignals > 0) {
    ACL_DEBUG (KERN_DEBUG "Number undelivered signals is %d\n", num_usignals);
  }
    
  mask_irq(aclsoc);
}


static void free_map_info (struct addr_map_elem *info) 
{
  if (info->vm_start != 0) {
    ACL_DEBUG (KERN_DEBUG "free_map_info on vaddr %p, dma 0x%x\n", info->cpu_addr, info->dma_handle);
    dma_free_coherent(NULL, 
            info->size, 
            info->cpu_addr,
            info->dma_handle);
    memset (info, 0, sizeof(*info) * 1);
  }
}

static void aclsoc_release_mmap_memory (struct kref *ref)
{
  struct addr_map_elem *info = container_of(ref, struct addr_map_elem, ref);
  free_map_info (info);
}

/* aclsoc_vma_open and _close will are called during mmap/munmp
 * operation. There are no direct call to these functions in this
 * driver. */
static void aclsoc_vma_open (struct vm_area_struct *vma)
{
  struct addr_map_elem *info = vma->vm_private_data;
  kref_get(&info->ref);
}

static void aclsoc_vma_close (struct vm_area_struct *vma)
{
  struct addr_map_elem *info = vma->vm_private_data;
  kref_put(&info->ref, aclsoc_release_mmap_memory);
}

static struct vm_operations_struct aclsoc_vm_ops = {
  .open =  aclsoc_vma_open,
  .close = aclsoc_vma_close,
};


static int aclsoc_mmap (struct file *filp, struct vm_area_struct *vma) {
  
  int iMapInfo;
  size_t size = vma->vm_end - vma->vm_start;
  size_t allocated_size = size;
  void *kalloc_memory = NULL;
  dma_addr_t dma_handle;
  struct addr_map_elem *info = NULL;
  
  /* Make sure we have space to store this allocation */
  for (iMapInfo = 0; iMapInfo < MAX_ADDR_MAP_ENTRIES; iMapInfo++) {
    if (aclsoc->addr_map[iMapInfo].vm_start == 0) break;
  }
  if (iMapInfo == MAX_ADDR_MAP_ENTRIES) {
    printk (KERN_DEBUG "Out of addr_map buffers!\n");
    return -ENOMEM;
  }
  info = &(aclsoc->addr_map[iMapInfo]);
  
  kalloc_memory = dma_alloc_coherent(NULL, allocated_size, &dma_handle, GFP_KERNEL);
  if (kalloc_memory == NULL) {
    return -ENOMEM;
  }
  
  // kmalloc returns "kernel logical addresses".
  // __pa()          maps "kernel logical addresses" to "physical addresses".
  // remap_pfn_range maps "physical addresses" to "user virtual addresses".
  // kernel logical addresses are usually just physical addresses with an offset.
  // Make the pages uncache-able. Otherwise, will run into consistency issues.
  vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
  if (remap_pfn_range(vma, vma->vm_start,
                      dma_handle >> PAGE_SHIFT,
                      size,
                      vma->vm_page_prot) < 0) {
    return -EAGAIN;
  }
  
  info->vm_start = vma->vm_start;
  info->size = allocated_size;
  info->cpu_addr = kalloc_memory;
  info->dma_handle = dma_handle;
  kref_init(&info->ref);

  vma->vm_ops = &aclsoc_vm_ops;
  vma->vm_private_data = info;
  
  return 0;
}

/* Free all DMA buffers here, just in case the user forgot some */
void free_contiguous_memory(struct aclsoc_dev *aclsoc) {

  int iMapInfo;
  for (iMapInfo = 0; iMapInfo < MAX_ADDR_MAP_ENTRIES; iMapInfo++) {
    free_map_info(&(aclsoc->addr_map[iMapInfo]));
  }
}


static int  aclsoc_probe(struct platform_device *pdev) {

  int res, i;

  ACL_VERBOSE_DEBUG (KERN_DEBUG "Calling %s", __FUNCTION__);

  // That's static aclsoc -- this driver is only for one instance of the device!  
  aclsoc = kzalloc(sizeof(struct aclsoc_dev), GFP_KERNEL);
  if (!aclsoc) {
    ACL_DEBUG(KERN_WARNING "Couldn't allocate memory!\n");
    goto fail_kzalloc;
  }
  
  spin_lock_init(&aclsoc->lock);
  sema_init (&aclsoc->sem, 1);
  aclsoc->user_pid = -1;
  aclsoc->num_handles_open = 0;
  
  aclsoc->addr_map = kzalloc(sizeof(struct addr_map_elem) * MAX_ADDR_MAP_ENTRIES, GFP_KERNEL);
  aclsoc->buffer = kmalloc (BUF_SIZE * sizeof(char), GFP_KERNEL);
  if (!aclsoc->buffer) {
    ACL_DEBUG(KERN_WARNING "Couldn't allocate memory for buffer!\n");
    goto fail_kmalloc;
  }
  
  res = init_chrdev (aclsoc);
  if (res) {
    goto fail_chrdev_init;
  }

  // region 0 for global memory, region 2 for control
  
  // all control traffic uses slow lwHPS2FGPA bridge
  aclsoc->mapped_region[2] = ioremap (lwHPS2FPGA_OFFSET, lwHPS2FPGA_SIZE);
  aclsoc->mapped_region_size[2] = lwHPS2FPGA_SIZE;

  aclsoc->mapped_region[1] = (void*)0;
  aclsoc->mapped_region_size[1] = 0;
  
  // all data traffic uses wide HPS2FPGA bridge
  aclsoc->mapped_region[0] = ioremap (HPS2FPGA_OFFSET, 2 * HPS2FPGA_SIZE);
  aclsoc->mapped_region_size[0] = 2 * HPS2FPGA_SIZE;
  
  for (i = 0; i < 3; i+=2) {
    printk(KERN_DEBUG "mapped region %d (lw) to [%p, %p]. Size = %zu\n", 
          i,
          aclsoc->mapped_region[i],
          aclsoc->mapped_region[i] + aclsoc->mapped_region_size[i],
          aclsoc->mapped_region_size[i]);
  }
  

#if !POLLING
  return init_irq (aclsoc, pdev);
#else
  return 0;
#endif


/* ERROR HANDLING */
fail_chrdev_init:
  kfree (aclsoc->buffer);
  
fail_kmalloc:
  kfree (aclsoc);
  
fail_kzalloc:
  return -1;
}


static int aclsoc_remove(struct platform_device * pdev) {
  ACL_DEBUG (KERN_DEBUG "Called aclsoc_remove \n");

  ACL_DEBUG (KERN_DEBUG ": aclsoc is %p\n", aclsoc);
  if (aclsoc == NULL) {
    return 0;
  }
  
  #if !POLLING
    release_irq (aclsoc, pdev);
  #endif

  device_destroy(aclsoc_class, aclsoc->cdev_num);
  class_destroy(aclsoc_class);
  cdev_del (&aclsoc->cdev);
  unregister_chrdev_region (aclsoc->cdev_num, 1);  
  
  iounmap (aclsoc->mapped_region[0]);
  iounmap (aclsoc->mapped_region[2]);
  
  kfree (aclsoc->buffer);
  
  free_contiguous_memory(aclsoc);
  kfree (aclsoc->addr_map);
  
  kfree (aclsoc);
  aclsoc = 0;
  return 0;
}

static const struct of_device_id aclsoc_of_match[] = {
   { .compatible = "altr,socfpga", },
   { /* end of list */ },
};
MODULE_DEVICE_TABLE(of, aclsoc_of_match);

static struct platform_driver aclsoc_driver = {
  .probe          = aclsoc_probe,
  .remove         = aclsoc_remove,
  .driver = {
      .name  = DRIVER_NAME,
      .owner = THIS_MODULE,
      .of_match_table = aclsoc_of_match,
  },
};


/* Initialize the driver module (but not any device) and register
 * the module with the kernel subsystem. */
static int __init aclsoc_init(void) {

  ACL_DEBUG (KERN_DEBUG "----------------------------\n");
  ACL_DEBUG (KERN_DEBUG "Driver version: %s \n", ACL_DRIVER_VERSION);
  platform_driver_register(&aclsoc_driver);

  ACL_DEBUG (KERN_DEBUG "end aclsoc_init \n");

  return 0;
}

static void __exit aclsoc_exit(void)
{
  printk(KERN_DEBUG "unloading driver\n");

  platform_driver_unregister(&aclsoc_driver);
  printk(KERN_DEBUG "aclsoc driver is unloaded!\n");
}



module_init (aclsoc_init);
module_exit (aclsoc_exit);
