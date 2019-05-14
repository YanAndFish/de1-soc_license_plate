#ifndef ACL_MMD_CONFIG_H
#define ACL_MMD_CONFIG_H

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


/* ===- acl_mmd_config.h  -------------------------------------------- C++ -*-=== */
/*                                                                                 */
/*                         Intel(R) OpenCL MMD Driver                                */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */
/*                                                                                 */
/* This file declares the class to handle functions that program the FPGA.         */
/* The actual implementation of the class lives in the acl_mmd_config.cpp,        */
/* so look there for full documentation.                                           */
/*                                                                                 */
/* ===-------------------------------------------------------------------------=== */


class ACL_MMD_CONFIG
{
   public:
      ACL_MMD_CONFIG(WDC_DEVICE_HANDLE device);
      ~ACL_MMD_CONFIG();

      // Program using an in-memory image of RBF (Not core rbf) file
      // This is used for ARM only
      // Return 0 on success.
      int program_with_RBF_image(char *rbf_image, size_t rbf_len);

      // Functions to save/load control registers from SOC Configuration Space
      // Return 0 on success.
      int save_soc_control_regs();
      int load_soc_control_regs();

      // Control FPGA to HPS bridges (ARM only)
      static void enable_bridges();
      static void disable_bridges();

      static int fpga_in_user_mode();

   private:
      WDC_DEVICE_HANDLE   m_device;
};

#endif // ACL_MMD_CONFIG_H
