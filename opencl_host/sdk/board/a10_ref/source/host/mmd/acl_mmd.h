#ifndef ACL_MMD_H
#define ACL_MMD_H

/* (C) 1992-2018 Intel Corporation.                             */
/* Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words     */
/* and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.   */
/* and/or other countries. Other marks and brands may be claimed as the property   */
/* of others. See Trademarks on intel.com for full list of Intel trademarks or     */
/* the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera)  */
/* Your use of Intel Corporation's design tools, logic functions and other         */
/* software and tools, and its AMPP partner logic functions, and any output        */
/* files any of the foregoing (including device programming or simulation          */
/* files), and any associated documentation or information are expressly subject   */
/* to the terms and conditions of the Altera Program License Subscription          */
/* Agreement, Intel MegaCore Function License Agreement, or other applicable       */
/* license agreement, including, without limitation, that your use is for the      */
/* sole purpose of programming logic devices manufactured by Intel and sold by     */
/* Intel or its authorized distributors.  Please refer to the applicable           */
/* agreement for further details.                                                  */


/* ===- acl_mmd.h  --------------------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file defines macros and types that are used inside the MMD driver          */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */


#ifndef ACL_MMD_EXPORT
#  define ACL_MMD_EXPORT __declspec(dllimport)
#endif

#define MMD_VERSION AOCL_MMD_VERSION_STRING

#include <stddef.h>
#include <stdio.h>
#include <assert.h>
#include "cl_platform.h"
#include "hw_mmd_constants.h"
#include "mmd_linux_driver_exports.h"
#include "aocl_mmd.h"

typedef uintptr_t            KPTR;
typedef ssize_t WDC_DEVICE_HANDLE;

typedef unsigned int        DWORD;
typedef unsigned long long  QWORD;
typedef char                 INT8;
typedef unsigned char       UINT8;
typedef int                 INT32;
typedef unsigned int       UINT32;
typedef long long           INT64;
typedef unsigned long long UINT64;

#  define INVALID_DEVICE (-1)
#  define WD_STATUS_SUCCESS 0

// define for the format string for size_t type
#  define SIZE_FMT_U "%zu"
#  define SIZE_FMT_X "%zx"

typedef enum {
  AOCL_MMD_KERNEL = 0,      // Control interface into kernel interface
  AOCL_MMD_MEMORY = 1,      // Data interface to device memory
  AOCL_MMD_PLL = 2,         // Interface for reconfigurable PLL
} aocl_mmd_interface_t;

// Describes the properties of key components in a standard ACL device
struct ACL_MMD_DEVICE_DESCRIPTION
{
   DWORD vendor_id;
   DWORD device_id;
   char  mmd_info_str[1024];
};


#define ACL_MMD_ASSERT(COND,...) \
   do { if ( !(COND) ) { \
      printf("\nMMD FATAL: %s:%d: ",__FILE__,__LINE__); printf(__VA_ARGS__); fflush(stdout); assert(0); } \
   } while(0)

#define ACL_MMD_ERROR_IF(COND,NEXT,...) \
   do { if ( COND )  { \
      printf("\nMMD ERROR: " __VA_ARGS__); fflush(stdout); NEXT; } \
   } while(0)

#define ACL_MMD_INFO(...) \
   do { \
      printf("MMD INFO : " __VA_ARGS__); fflush(stdout); \
   } while(0)

#endif   // ACL_MMD_H
