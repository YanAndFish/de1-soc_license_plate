#ifndef ACL_MMD_DEBUG_H
#define ACL_MMD_DEBUG_H

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


/* ===- acl_mmd_debug.h  --------------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */


enum ACL_VERBOSITY
{
   VERBOSITY_DEFAULT = 1,
   VERBOSITY_INVOCATION = 2,     // Dump kernel invocation details
   VERBOSITY_OP = 3,             // Dump operation invocation details
   VERBOSITY_IRQ = 5,
   VERBOSITY_BLOCKTX = 9,        // Dump block transfers
   VERBOSITY_MMD = 10,          // Dump all MMD transactions
   VERBOSITY_EVERYTHING = 100
};

extern int ACL_MMD_DEBUG;
extern int ACL_MMD_WARNING;

// This function gets the value of ACL_MMD_DEBUG from the environment variable
void set_mmd_debug();
void set_mmd_warn_msg();

#include <stdio.h>

#define ACL_MMD_DEBUG_MSG(m, ...) ACL_MMD_DEBUG_MSG_VERBOSE(VERBOSITY_DEFAULT,m, ## __VA_ARGS__)
#define ACL_MMD_DEBUG_MSG_VERBOSE(verbosity, m, ...) if ( (ACL_MMD_DEBUG|0) >= verbosity) do { printf((m), ## __VA_ARGS__),fflush(stdout); } while (0)


#define ACL_MMD_WARN_MSG(...) \
   do { if ( ACL_MMD_WARNING ) { \
      printf("** WARNING: " __VA_ARGS__); fflush(stdout); } \
   } while(0)


#endif  // ACL_MMD_DEBUG_H

