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

#ifndef HW_MMD_DMA_H
#define HW_MMD_DMA_H

// DMA parameters to tweak
static const unsigned int ACL_MMD_DMA_MAX_PINNED_MEM_SIZE = 16*1024*1024;
static const unsigned int ACL_MMD_DMA_STRIDE = 0x00010001;
static const unsigned int ACL_MMD_DMA_TIMEOUT = 50000;  // us

// Constants matched to the HW
static const unsigned int ACL_MMD_DMA_MAX_TRANSFER_SIZE = 1*1024*1024;
static const unsigned int ACL_MMD_DMA_MAX_DESCRIPTORS = 128;

#ifdef LINUX
#  define cl_ulong unsigned long
#endif

struct DMA_DESCRIPTOR {
   unsigned int read_address;
   unsigned int write_address;
   unsigned int bytes;
   unsigned int burst;
   unsigned int stride;
   unsigned int read_address_hi;
   unsigned int write_address_hi;
   unsigned int control;
};

#endif // HW_MMD_DMA_H
