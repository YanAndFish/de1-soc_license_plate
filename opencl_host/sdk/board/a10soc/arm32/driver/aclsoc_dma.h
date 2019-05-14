/* Defines used only by aclsoc_dma.c. */


#if USE_DMA

/* Enable Linux-specific defines in the hw_pcie_dma.h file */
#define LINUX
#include <linux/workqueue.h>
#include "hw_mmd_dma.h"

struct dma_t {
  void *ptr;         /* if ptr is NULL, the whole struct considered invalid */
  size_t len;
  enum dma_data_direction dir;
  struct page **pages;     /* one for each struct page */
  dma_addr_t *dma_addrs;   /* one for each struct page */
  unsigned int num_pages;
};

struct pinned_mem {
  struct dma_t dma;
  struct page **next_page;
  unsigned int pages_rem;
  unsigned int first_page_offset;
  unsigned int last_page_offset;
};

struct work_struct_t{
   struct work_struct work;
   void *data;
};

struct aclsoc_dma {

  // Pinned memory we're currently building DMA transactions for.
  struct pinned_mem m_active_mem;
  struct pinned_mem m_next_mem;

  // The transaction we are currently working on
  struct DMA_DESCRIPTOR m_active_descriptor;

  struct pci_dev *m_pci_dev;
  struct aclsoc_dev *m_aclsoc;

  // workqueue and work structure for bottom-half interrupt routine
  struct workqueue_struct *my_wq;
  struct work_struct_t *my_work;
  
  // Transfer information
  size_t m_device_addr;
  void* m_host_addr;
  dma_addr_t m_host_mapped_addr;
  int m_read;
  size_t m_bytes;
  size_t m_bytes_sent;
  int m_idle;
  int m_prepin_done;
  int m_host_pre_mapped;
  
  // Next pin information
  void* m_host_addr_next_pin;
  size_t m_bytes_sent_prefetch;
  
  // DMA interrupt table
  dma_addr_t dma_irq_table;
  void * host_irq_table;
  
  unsigned int m_error;
  
};

#else
struct aclsoc_dma {};
#endif
