// (C) 1992-2018 Intel Corporation.                            
// Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
// and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
// and/or other countries. Other marks and brands may be claimed as the property  
// of others. See Trademarks on intel.com for full list of Intel trademarks or    
// the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
// Your use of Intel Corporation's design tools, logic functions and other        
// software and tools, and its AMPP partner logic functions, and any output       
// files any of the foregoing (including device programming or simulation         
// files), and any associated documentation or information are expressly subject  
// to the terms and conditions of the Altera Program License Subscription         
// Agreement, Intel MegaCore Function License Agreement, or other applicable      
// license agreement, including, without limitation, that your use is for the     
// sole purpose of programming logic devices manufactured by Intel and sold by    
// Intel or its authorized distributors.  Please refer to the applicable          
// agreement for further details.                                                 


/* ===- acl_mmd_debug.cpp  ------------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */

#include <stdio.h>
#include <stdlib.h>

int ACL_MMD_DEBUG   = 0;
int ACL_MMD_WARNING = 1;  // turn on the warning message by default

void set_mmd_debug()
{
   char * mmd_debug_var = getenv("ACL_MMD_DEBUG");
   if (mmd_debug_var) {
      ACL_MMD_DEBUG = atoi(mmd_debug_var);
      printf("\n:: MMD DEBUG LEVEL set to %d\n", ACL_MMD_DEBUG );
   }
}

void set_mmd_warn_msg()
{
   char * mmd_warn_var = getenv("ACL_MMD_WARNING");
   if(mmd_warn_var){
      ACL_MMD_WARNING = atoi(mmd_warn_var);
   }
}

