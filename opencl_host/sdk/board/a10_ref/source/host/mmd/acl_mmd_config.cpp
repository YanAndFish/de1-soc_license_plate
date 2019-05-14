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


/* ===- acl_mmd_config.cpp  ------------------------------------------ C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file implements the class to handle functions that program the FPGA.       */
/* The declaration of the class lives in the acl_mmd_config.h.                    */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */

// common and its own header files
#include "acl_mmd.h"
#include "acl_mmd_config.h"

// other header files inside MMD driver
#include "acl_mmd_debug.h"

// other standard header files
#include <stdlib.h>
#include <string.h>

#include <unistd.h>

// Function to install the signal handler for Ctrl-C
// Implemented inside acl_mmd.cpp
extern int install_ctrl_c_handler(int ingore_sig);

ACL_MMD_CONFIG::ACL_MMD_CONFIG(WDC_DEVICE_HANDLE device)
{
   m_device = device;
   return;
}

ACL_MMD_CONFIG::~ACL_MMD_CONFIG()
{
}

// Program using an in-memory image of RBF (Not core rbf) file
// Return 0 on success.
int ACL_MMD_CONFIG::program_with_RBF_image(char *rbf_image, size_t rbf_len)
{
   int program_failed = 1;
   ACL_MMD_ERROR_IF(rbf_image == NULL, return 1,
      "rbf_image is a NULL pointer.\n");

   // write image to temp file
   char tmp_filename[FILENAME_MAX];
   char buf[FILENAME_MAX];
   tmpnam(tmp_filename);
   FILE *tmp = fopen (tmp_filename, "wb");

   ACL_MMD_ERROR_IF( tmp == NULL, return 1,
      "couldn't open tmp file %s for writing!\n", tmp_filename);

   fwrite (rbf_image, sizeof(char), rbf_len, tmp);
   fclose (tmp);

   sprintf (buf, "cat %s > /dev/fpga0", tmp_filename);
   system (buf);
   program_failed = (fpga_in_user_mode() == 0); // failed if NOT in user mode

   ACL_MMD_ERROR_IF( remove (tmp_filename) != 0, /* do nothing */,
      "couldn't delete temporary RBF file %s\n", tmp_filename);

   return program_failed;
}

// For Windows, the register values are stored in this class, and do
//   nothing else
// For Linux, the register values are stored inside the kernel driver,
//   And, it will disable the interrupt and the aer on the upstream,
//   when the save_soc_control_regs() function is called. They will
//   be enable when load_soc_control_regs() is called.
// Return 0 on success
int ACL_MMD_CONFIG::save_soc_control_regs()
{
   int save_failed = 1;

   struct acl_cmd cmd_save = { ACLSOC_CMD_BAR, ACLSOC_CMD_SAVE_SOC_CONTROL_REGS, NULL, NULL };
   save_failed = read(m_device, &cmd_save, 0);
   disable_bridges();

   return save_failed;
}

int ACL_MMD_CONFIG::load_soc_control_regs()
{
   int load_failed = 1;

   struct acl_cmd cmd_load = { ACLSOC_CMD_BAR, ACLSOC_CMD_LOAD_SOC_CONTROL_REGS, NULL, NULL };
   enable_bridges();
   load_failed = read(m_device, &cmd_load, 0);

   return load_failed;
}

// Disable communication bridges between ARM and FPGA
void ACL_MMD_CONFIG::disable_bridges()
{
   system ("echo 0 > /sys/class/fpga-bridge/fpga2hps/enable");
   system ("echo 0 > /sys/class/fpga-bridge/hps2fpga/enable");
   system ("echo 0 > /sys/class/fpga-bridge/lwhps2fpga/enable");
}

// Enable communication bridges between ARM and FPGA
void ACL_MMD_CONFIG::enable_bridges()
{
   system ("echo 1 > /sys/class/fpga-bridge/fpga2hps/enable");
   system ("echo 1 > /sys/class/fpga-bridge/hps2fpga/enable");
   system ("echo 1 > /sys/class/fpga-bridge/lwhps2fpga/enable");
}

int ACL_MMD_CONFIG::fpga_in_user_mode()
{
  #define BUF_SIZE 1024
  char buf[BUF_SIZE];
  const char *status_file = "/sys/class/fpga/fpga0/status";
  char *fgets_res = NULL;

  FILE *status = fopen (status_file, "r");
  if (status == NULL) {
    fprintf (stderr, "Couldn't open FPGA status from %s!\n", status_file);
    return 0;
  }

  fgets_res = fgets (buf, BUF_SIZE, status);
  fclose (status);

  if (fgets_res == NULL) {
    fprintf (stderr, "Couldn't read FPGA status from %s!\n", status_file);
    return 0;
  }
  if (strstr (buf, "user mode") == NULL) {
    fprintf (stderr, "After reprogramming, FPGA is not in user mode (%s)!\n", buf);
    return 0;
  }

  // If here, FPGA is in user mode
  return 1;
}
