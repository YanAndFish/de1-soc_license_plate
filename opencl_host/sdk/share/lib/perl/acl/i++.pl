# (C) 1992-2018 Intel Corporation.                            
# Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
# and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
# and/or other countries. Other marks and brands may be claimed as the property  
# of others. See Trademarks on intel.com for full list of Intel trademarks or    
# the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
# Your use of Intel Corporation's design tools, logic functions and other        
# software and tools, and its AMPP partner logic functions, and any output       
# files any of the foregoing (including device programming or simulation         
# files), and any associated documentation or information are expressly subject  
# to the terms and conditions of the Altera Program License Subscription         
# Agreement, Intel MegaCore Function License Agreement, or other applicable      
# license agreement, including, without limitation, that your use is for the     
# sole purpose of programming logic devices manufactured by Intel and sold by    
# Intel or its authorized distributors.  Please refer to the applicable          
# agreement for further details.                                                 


# Intel(R) FPGA SDK for HLS compilation.
#  Inputs:  A mix of sorce files and object filse
#  Output:  A subdirectory containing: 
#              Design template
#              Verilog source for the kernels
#              System definition header file
#
# 
# Example:
#     Command:       i++ foo.cpp bar.c fum.o -lm -I../inc
#     Generates:     
#        Subdirectory a.prj including key files:
#           *.v
#           <something>.qsf   - Quartus project settings
#           <something>.sopc  - SOPC Builder project settings
#           kernel_system.tcl - SOPC Builder TCL script for kernel_system.qsys 
#           system.tcl        - SOPC Builder TCL script
#
# vim: set ts=2 sw=2 et

      BEGIN { 
         unshift @INC,
            (grep { -d $_ }
               (map { $ENV{"INTELFPGAOCLSDKROOT"}.$_ }
                  qw(
                     /host/windows64/bin/perl/lib/MSWin32-x64-multi-thread
                     /host/windows64/bin/perl/lib
                     /share/lib/perl
                     /share/lib/perl/5.8.8 ) ) );
      };


use strict;
require acl::File;
require acl::Common;
require acl::Env;
require acl::Report;
use acl::Report qw(escape_string);

#Always get the start time in case we want to measure time
my $main_start_time = time(); 

my $prog = 'i++';
my $return_status = 0;
my $UPLIFT_TODO = 0; # // UPLIFT TODO: remove this variable.

#Filenames
my @source_list = ();
my @object_list = ();
my @tmpobject_list = ();
my @fpga_IR_list = ();
my @fpga_dep_list = ();
my @cleanup_list = ();
my @component_names = ();

my $project_name = undef;
my $keep_log = 0;
my $project_log = undef;
my $executable = undef;
my $optinfile = undef;
my $regtest_errlog = "reg.err";

#directories
my $orig_dir = undef; # path of original working directory.
my $g_work_dir = undef; # path of the project working directory as is.
my $quartus_work_dir = "quartus";
my $cosim_work_dir = "verification";

# Executables
# UPLIFT - Location of these has changed from trunk -> uplift
my $clang_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-clang";
my $opt_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-opt";
my $link_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-link";
my $llc_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-llc";
my $sysinteg_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin".'/system_integrator';
my $mslink_exe = 'link.exe';

#Names
my $prj_name_section ='.prjnam'; # Keep section names of 7 char or less for COFF
my $fpga_IR_section ='.fpgaIR'; 
my $fpga_dep_section ='.fpga.d'; 
my $fpga_log_section ='.fpga.log'; 

#Flow control
my $emulator_flow = 0;
my $simulator_flow = 0;
my $RTL_only_flow_modifier = 0;
my $object_only_flow_modifier = 0;
my $soft_ip_c_flow_modifier = 0; # Hidden option for soft IP compilation
my $x86_linkstep_only = 0;
my $cosim_linkstep_only = 0;
my $preprocess_only = 0;
my $macro_type_string = "";
my $acl_version_string = "1810";
my $cosim_debug = 0;
my $march_set = 0;
my $cosim_log_call_count = 0;
my $cppstd = "";
my $gcc_toolchain_arg = undef;

# Quartus Compile Flow
my $qii_project_name = "quartus_compile";
my $qii_flow = 0;
my $qii_vpins = 1;
my $qii_io_regs = 1;
my $qii_seed = undef;
my $qii_fmax_constraint = undef;
my $qii_dsp_packed = 0; #if enabled, force aggressive DSP packing for Quartus compile results (ARRIA 10 only)
my $g_quartus_version_str = undef; # Do not directly use this variable, use the quartus_version_str() function

# Device information
my $dev_part = undef;
my $dev_family = undef;
my $dev_speed = undef;
my $dev_device = "Arria10";

# Supported devices
### list of supported families
my $A10_family = "Arria10";
my $S10_family = "Stratix10";
my $C10_family = "Cyclone10GX";

### the associated reference fmax
my %family_to_fmax_map = (
    $A10_family => 240,
    $S10_family => 480,
    $C10_family => 240,
  );

### the associated reference boards
my %family_to_board_map = (
    $A10_family => 'A10.xml',
    $S10_family => 'S10.xml',
    $C10_family => 'C10.xml',
  );

# Flow modifier
my $target_x86 = 0; # Hidden option for soft IP compilation to target x86

# Simulators
my $cosim_simulator = "MODELSIM";
my $cosim_64bit = undef; # Avoid using this variable directly, use query_vsim_arch()
my $vsim_version_string = undef; # Avoid using this variable directory, use query_vsim_version_string()

#Output control
my $verbose = 0; # Note: there are three verbosity levels now 1, 2 and 3
my $disassemble = 0; # Hidden option to disassemble the IR
my $dotfiles = 0;
my $pipeline_viewer = 0;
my $save_tmps = 0;
my $debug_symbols = 1;      # Debug info enabled by default. Use -g0 to disable.
my $user_required_debug_symbol = 0; #User explicitly uses -g from the comand line.
my $time_log = undef; # Time various stages of the flow; if not undef, it is a 
                      # file handle (could be STDOUT) to which the output is printed to.
my $time_passes = 0; # will be set to 1 if -time-passes flag is used. This is only going to happen 
                     # in regtest mode.
my $regtest_mode = 0; # In this mode we dump out errors to reg.err log file

#Testbench names
my $tbname = 'tb';

#Command line support
my @cmd_list = ();
my @parseflags=();
my @linkflags=();
my @additional_opt_args   = (); # Extra options for opt, after regular options.
my @additional_llc_args   = ();
my @additional_sysinteg_args = ();
my $all_ipp_args = undef;

## UPLIFT TODO - Don't use Obfuscated string. Go back to obfuscated strings
##               when appropriate.
my $opt_passes = ' -march=fpga -O3';

# Default output file extension
my $default_object_extension = ".o";

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
my @llvm_board_option = ();

# cache result for link.exe checking
my $link_exe_exist = "unknown"; # value could be "unknown", "yes", "no"

# UPLIFT - used for uplift, for now. 
# Prevent any LLVM passes/optimizations from being run.  Better than -O0 -disable-O0-optnone, as
# it allows the bodies of inline functions to be generated(!)
my @safe_opt_zero = qw(-O3 -Xclang -disable-llvm-passes);

# Variable to track the error log number
my $error_log_count = 0;

# checks host OS, returns true for linux, false for windows.
sub isLinuxOS {
    if ($^O eq 'linux') {
      return 1; 
    }
    return;
}

# checks for Windows host OS. Returns true if Windows, false if Linux.
# Uses isLinuxOS so OS check is isolated in single function.
sub isWindowsOS {
    if (isLinuxOS()) {
      return;
    }
    return 1;
}

sub get_gcc_toolchain {
  if (isLinuxOS()) {
    # Do not expose this variables to FAEs or customers!
    # This is for internal use only.
    # Customers need to use the --gcc-toolchain option from i++.
    if (defined $gcc_toolchain_arg && $gcc_toolchain_arg ne '') {
        return '--gcc-toolchain=' . $gcc_toolchain_arg;
    } 
  }
  return '';
}

sub mydie(@) {
    if(@_) {
        print STDERR "Error: ".join("\n",@_)."\n";
    }
    chdir $orig_dir if defined $orig_dir;
    push @cleanup_list, $project_log unless $keep_log;
    remove_named_files(@cleanup_list) unless $save_tmps;
    chdir $g_work_dir if defined $g_work_dir;
    remove_named_files(@cleanup_list) unless $save_tmps;
    exit 1;
}

sub myexit(@) {
    acl::Common::log_time ('Total time ending @'.join("\n",@_), time() - $main_start_time);
    acl::Common::close_time_log();

    print STDERR 'Success: '.join("\n",@_)."\n" if $verbose>1;
    chdir $orig_dir if defined $orig_dir;
    push @cleanup_list, $project_log unless $keep_log;
    remove_named_files(@cleanup_list) unless $save_tmps;
    chdir $g_work_dir if defined $g_work_dir;
    remove_named_files(@cleanup_list) unless $save_tmps;
    exit 0;
}

sub get_temp_error_logfile() {
    $error_log_count = $error_log_count + 1;
    return "temp_err_" . $error_log_count . ".err";   
}

# These routines aim to minimize the system queries for paths
# by maintaining a "cached" copy of the paths, since these
# are static and do not change - this only need to be queried
# once.

# Global Library path names, since these are reused.
# These are only obtained once, only if undef'd.


# $abspath_mslink64 is obtained once, and not modified. 
# This path is used as the base to obtain paths to the
# Microsoft link libraries.
#
# All strings used for substitution operations here
# should be described in lowercase since the detected base paths
# are converted to lowercase.
#
my $abspath_mslink64 = undef;
my $str_mslink64 = 'bin/amd64/'.$mslink_exe;

my $abspath_libcpmt = undef;
my $abspath_msvcrt = undef;
my $abspath_msvcprt = undef;

# Similarly, $abspath_hlsbase points to the path
# for hls_vbase.lib, which is then used to obtain the
# paths for hls_emul and hls_cosim needed at link time.
my $abspath_hlsbase = undef;
my $str_hlsvbase = "/host/windows64/lib/hls_vbase\.lib";

my $abspath_hlscosim = undef;
my $abspath_hlsemul = undef;
my $abspath_hlsfixed_point_math_x86 = undef;
my $abspath_hlsvbase = undef;
my $abspath_mpir = undef;
my $abspath_mpfr = undef;

sub check_link_exe_existance {
  if ( $link_exe_exist eq "unknown" ){
      my $msvc_out = `$mslink_exe 2>&1`;
    chomp $msvc_out;
    if ($msvc_out !~ /Microsoft \(R\) Incremental Linker Version/ ) {
      $link_exe_exist = "no";
    }
    else {
      $link_exe_exist = "yes";
    }
  }

  if( $link_exe_exist eq "no" ){
    mydie("$prog: Can't find the Microsoft linker LINK.EXE. Make sure your Visual Studio is correctly installed and that it's linker can be found.\n");
  }

  # $link_exe_exist eq "yes"
  return 1;
}

sub get_mslink64_path {
    if (!defined $abspath_mslink64) {
      $abspath_mslink64 = acl::File::which_full($mslink_exe);
      chomp $abspath_mslink64;
      # lowercase the base string. All conversions are done in lower
      # case. Windows is case insensitive, but need to make sure
      # all substitution operations consistently in one case.
      $abspath_mslink64 = lc $abspath_mslink64;
    }
    return $abspath_mslink64;
}

sub get_hlsbase_path {
    if (!defined $abspath_hlsbase) {
      $abspath_hlsbase = acl::File::abs_path(acl::Env::sdk_root().'/host/windows64/lib/hls_vbase.lib');
      unless (-e $abspath_hlsbase) {
        mydie("HLS base libraries path does not exist\n");
      }
      # lowercase the base string. All conversions are done in lower
      # case. Windows is case insensitive, but need to make sure
      # all substitution operations consistently in one case.
      $abspath_hlsbase = lc $abspath_hlsbase;
    }
    return $abspath_hlsbase;
}

sub get_hlsvbase_path {
    if (!defined $abspath_hlsvbase) {
      get_hlsbase_path();
      $abspath_hlsvbase = $abspath_hlsbase;
      $abspath_hlsvbase =~ tr{\\}{/};
    }
    return $abspath_hlsvbase;
}

sub get_hlscosim_path {
    if (!defined $abspath_hlscosim) {
      get_hlsbase_path();
      $abspath_hlscosim = $abspath_hlsbase;
      $abspath_hlscosim =~ tr{\\}{/};
      my $str_hlscosim = "/host/windows64/lib/hls_cosim\.lib";
      $abspath_hlscosim =~ s/$str_hlsvbase/$str_hlscosim/g;
      unless (-e $abspath_hlscosim) {
        mydie("hls_cosim.lib does not exist!\n");
      }
    }
    return $abspath_hlscosim;
}

sub get_hlsemul_path {
    if (!defined $abspath_hlsemul) {
      get_hlsbase_path();
      $abspath_hlsemul = $abspath_hlsbase;
      $abspath_hlsemul =~ tr{\\}{/};
      my $str_hlsemul = "/host/windows64/lib/hls_emul\.lib";
      $abspath_hlsemul =~ s/$str_hlsvbase/$str_hlsemul/g;
      unless (-e $abspath_hlsemul) {
        mydie("hls_emul.lib does not exist!\n");
      }
    }
    return $abspath_hlsemul;
}

sub get_hlsfixed_point_math_x86_path {
    if (!defined $abspath_hlsfixed_point_math_x86) {
      get_hlsbase_path();
      $abspath_hlsfixed_point_math_x86 = $abspath_hlsbase;
      $abspath_hlsfixed_point_math_x86 =~ tr{\\}{/};
      my $str_hlsfixed_point_math_x86 = "/host/windows64/lib/hls_fixed_point_math_x86\.lib";
      $abspath_hlsfixed_point_math_x86 =~ s/$str_hlsvbase/$str_hlsfixed_point_math_x86/g;
      unless (-e $abspath_hlsfixed_point_math_x86) {
        mydie("hls_fixed_point_math_x86.lib does not exist!\n");
      }
    }
    return $abspath_hlsfixed_point_math_x86;
}

sub get_mpir_path {
    if (!defined $abspath_mpir) {
      get_hlsbase_path();
      $abspath_mpir = $abspath_hlsbase;
      $abspath_mpir =~ tr{\\}{/};
      my $str_mpir = "/host/windows64/lib/altera_mpir\.lib";
      $abspath_mpir =~ s/$str_hlsvbase/$str_mpir/g;
      unless (-e $abspath_mpir) {
        mydie("altera_mpir.lib does not exist!\n");
      }
    }
    return $abspath_mpir;
}

sub get_mpfr_path {
    if (!defined $abspath_mpfr) {
      get_hlsbase_path();
      $abspath_mpfr = $abspath_hlsbase;
      $abspath_mpfr =~ tr{\\}{/};
      my $str_mpfr = "/host/windows64/lib/altera_mpfr\.lib";
      $abspath_mpfr =~ s/$str_hlsvbase/$str_mpfr/g;
      unless (-e $abspath_mpfr) {
        mydie("altera_mpfr.lib does not exist!\n");
      }
    }
    return $abspath_mpfr;
}

sub get_libcpmt_path {
    if (!defined $abspath_libcpmt) {
      get_mslink64_path();
      $abspath_libcpmt = $abspath_mslink64;
      $abspath_libcpmt =~ tr{\\}{/};
      my $str_libcpmt = "lib/amd64/libcpmt.lib";
      $abspath_libcpmt =~ s/$str_mslink64/$str_libcpmt/g;
      unless (-e $abspath_libcpmt) {
        mydie("libcpmt.lib does not exist\n");
      }
    }
    return $abspath_libcpmt;
}

sub get_msvcrt_path {
    if (!defined $abspath_msvcrt) {
      get_mslink64_path();
      $abspath_msvcrt = $abspath_mslink64;
      $abspath_msvcrt =~ tr{\\}{/};
      my $str_msvcrt = "lib/amd64/msvcrt.lib";
      $abspath_msvcrt =~ s/$str_mslink64/$str_msvcrt/g;
      unless (-e $abspath_msvcrt) {
        mydie("msvcrt.lib does not exist\n");
      }
    }
    return $abspath_msvcrt;
}

sub get_msvcprt_path {
    if (!defined $abspath_msvcprt) {
      get_mslink64_path();
      $abspath_msvcprt = $abspath_mslink64;
      $abspath_msvcprt =~ tr{\\}{/};
      my $str_msvcprt = "lib/amd64/msvcprt.lib";
      $abspath_msvcprt =~ s/$str_mslink64/$str_msvcprt/g;
      unless (-e $abspath_msvcprt) {
        mydie("msvcprt.lib does not exist\n");
      }
    }
    return $abspath_msvcprt;
}

sub create_empty_objectfile($$$) {
    my ($object_file, $dummy_file, $work_dir) = @_;
    my @cmd_list = undef;
    if (isLinuxOS()) {
      # Create empty file by copying non-existing section from arbitrary 
      # non-empty file
      @cmd_list = ( 'objcopy',
                    '--binary-architecture=i386:x86-64',
                    '--only-section=.text',
                    '--input-target=binary',
                    '--output-target=elf64-x86-64',
                    $dummy_file,
                    $object_file
          );
    } else {
      @cmd_list = ('coffcopy.exe',
                   '--create-object-file',
                   $object_file
          );
    }
    $return_status = mysystem_full({'title' => 'create object file',
                                    'stderr' => "$work_dir/obj.err",
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie("Not able to create $object_file");
    }
    push @object_list, $object_file;
}

sub add_section_to_object_file ($$$$) {
    my ($object_file, $scn_name, $content_file, $work_dir) = @_;
    my @cmd_list = undef;
    unless (-e $object_file) {
      create_empty_objectfile($object_file, $content_file, $work_dir);
    }
    if (isLinuxOS()) {
      @cmd_list = ('objcopy',
                   '--add-section',
                   $scn_name.'='.$content_file,
                   $object_file
          );
    } else {
      @cmd_list = ('coffcopy.exe',
                   '--add-section',
                   $scn_name,
                   $content_file,
                   $object_file
          );
    }
    $return_status = mysystem_full({'title' => 'Add IR to object file',
                                    'stderr' => "$work_dir/obj.err",
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie("Not able to update $object_file");
    }
    if (isLinuxOS()) {
      @cmd_list = ('objcopy',
                   '--set-section-flags',
                   $scn_name.'=alloc',
                   $object_file
          );
      $return_status = mysystem_full({'title' => 'Change flags to object file',
                                      'stderr' => "$work_dir/obj.err",
                                      'proj_dir' => $orig_dir},
                                     @cmd_list);
      if ($return_status != 0) {
        mydie("Not able to update $object_file");
      }
    }
    return 1;
}

sub check_FPGA_IR_has_component($){
    my ($ref_file) = @_;

    open FILE, "<$ref_file"; 
    my $has_component = undef;
    while (my $line = <FILE>) {
      if (index($line, "!ihc_component") != -1){
        $has_component=1;
        last;
        #Use the !ihc_component metadata to identify HLS components
      }
    }
    close FILE;
    return $has_component;
}

sub add_projectname_to_object_file ($$$$) {
    my ($object_file, $scn_name, $content_file, $work_dir) = @_;
    
    unless (-e $object_file) {
      create_empty_objectfile($object_file, $content_file, $work_dir);
    }
    
    my @cmd_list = undef;
    if (isLinuxOS()) {
      @cmd_list = ('objcopy',
                   '--add-section',
                   $scn_name.'='.$content_file,
                   $object_file
          );
    } else {
      @cmd_list = ('coffcopy.exe',
                   '--add-section',
                   $scn_name,
                   $content_file,
                   $object_file );
    }
    $return_status = mysystem_full({'title' => 'Add project dir name to object file',
                                    'stderr' => "$work_dir/obj.err",
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie("Not able to update $object_file");
    }
    if (isLinuxOS()){
      @cmd_list = ('objcopy',
                   '--set-section-flags',
                   $scn_name.'=alloc',
                   $object_file);
      $return_status = mysystem_full({'title' => 'Change flags to object file',
                                      'stderr' => "$work_dir/obj.err",
                                      'proj_dir' => $orig_dir},
                                     @cmd_list);
      if ($return_status != 0) {
        mydie("Not able to update $object_file");
      }
    }
}

sub get_section_from_object_file ($$$$) {
    my ($object_file, $scn_name ,$dst_file, $work_dir) = @_;
    my @cmd_list = undef;
    if (isLinuxOS()) {
      @cmd_list = ('objcopy',
                   ,'-O', 'binary', 
                   '--only-section='.$scn_name,
                   $object_file,
                   $dst_file
          );
    } else {
      @cmd_list = ( 'coffcopy.exe',
                    '--get-section',
                    $scn_name,
                    $object_file,
                    $dst_file
          );
    }
    $return_status = mysystem_full({'title' => 'Get IR from object file',
                                    'stderr' => "$work_dir/obj.err",
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie("Not able to extract $object_file");
    }
    return (! -z $dst_file);
}

sub get_project_directory_from_file(@) {
    my @filelist = @_;
    my $project_dir = undef;
    my $tmp_file = $$.'prj_name.txt';
    foreach my $filename (@filelist) {
      my @cmd_list = undef;
      if (isLinuxOS()){
        @cmd_list = ( 'objcopy',
                      '-O','binary',
                      '--only-section='.$prj_name_section,
                      $filename,
                      $tmp_file
        );
      } else {
        @cmd_list = ( 'coffcopy.exe',
                 '--get-section',
                 $prj_name_section,
                 $filename,
                 $tmp_file
            );
      }
      $return_status = mysystem_full({'title' => 'Get IRproject_name from object file'}, @cmd_list);
      if($return_status == 0){
        open FILE, "<$tmp_file"; binmode FILE; my $name =<FILE>; close FILE;
        if ($name) {
          if (!$project_dir) {
            $project_dir = $name;
          } elsif ($project_dir ne $name) {
            mydie("All Components must target the same project directory\n"."This compilation tries to create $project_dir and $name!\n");
          }
        }
      }
    }
    push @cleanup_list, $tmp_file;
    if ($project_dir) {
      return $project_dir;
    } elsif ($g_work_dir) { # IF we shortcircuted the object file ...
        return $g_work_dir;
    } else {
        if (isWindowsOS()){#for Windows
          if ($executable eq 'a.exe'){
             $g_work_dir = 'a.prj';
          } else {
            my $l_base = undef;
            my $l_ext = undef;
            ($l_base, $l_ext) = parse_extension($executable); 
            if ($l_ext eq '.exe') {
              $g_work_dir = $l_base . '.prj';
            } else {
              $g_work_dir = $executable . '.prj';
            }
          }
        } else {#for Linux
          if ($executable eq 'a.out') {
             $g_work_dir = 'a.prj';
          } else {
            $g_work_dir = $executable . '.prj';
          }
        }
      return $g_work_dir;
    }
}

# Functions to execute external commands, with various wrapper capabilities
# for the i++ flow
#   1. Logging
#   2. Time measurement
# Arguments:
#   @_[0] = { 
#       'stdout'             => 'filename',   # optional
#       'stderr'             => 'filename',   # optional
#       'title'              => 'string'      # used mydie and log 
#       'out_is_temporary'   => 'boolean'     # optional - set to 0 if log from stdout is to be kept (default = 1)
#       'err_is_temporary'   => 'boolean'     # optional - set to 0 if log from stderr is to be kept (default = 1)
#       'move_err_to_out'    => 'boolean'     # optional - set to 1 if log from stderr is to be moved to log from stdout (default = 0)
#     }
#   @_[1..$#@_] = arguments of command to execute

sub mysystem_full($@) {
    # Default values for some parameters
    my $default_opts = {
      'out_is_temporary' => '1',
      'err_is_temporary' => '1',
    };
    my $input_opts = shift(@_);
    my $opts = {%$default_opts, %$input_opts};
    
    my @cmd = @_;

    my $out = $opts->{'stdout'};
    my $title = $opts->{'title'};
    my $err = $opts->{'stderr'};
    my $proj_dir = $opts->{'proj_dir'};
    my $out_is_temporary = $opts->{'out_is_temporary'};
    my $err_is_temporary = $opts->{'err_is_temporary'};
    my $move_err_to_out = $opts->{'move_err_to_out'};

    # Log the command to console if requested
    print STDOUT "============ ${title} ============\n" if $title && $verbose>1; 
    if ($verbose >= 2) {
      print join(' ',@cmd)."\n";
    }

    # Replace STDOUT/STDERR as requested.
    # Save the original handles.
    if($out) {
      open(OLD_STDOUT, ">&STDOUT") or mydie "Couldn't open STDOUT: $!";
      open(STDOUT, ">>$out") or mydie "Couldn't redirect STDOUT to $out: $!";
      $| = 1;
    }
    if($err) {
      open(OLD_STDERR, ">&STDERR") or mydie "Couldn't open STDERR: $!";
      open(STDERR, ">>$err") or mydie "Couldn't redirect STDERR to $err: $!";
      select(STDERR);
      $| = 1;
      select(STDOUT);
    }

    # Run the command.
    my $start_time = time();
    my $retcode = system(@cmd);
    my $end_time = time();

    # Restore STDOUT/STDERR if they were replaced.
    if($out) {
      close(STDOUT) or mydie "Couldn't close STDOUT: $!";
      open(STDOUT, ">&OLD_STDOUT") or mydie "Couldn't reopen STDOUT: $!";
    }
    if($err) {
      close(STDERR) or mydie "Couldn't close STDERR: $!";
      open(STDERR, ">&OLD_STDERR") or mydie "Couldn't reopen STDERR: $!";
    }

    # Dump out time taken if we're tracking time.
    if ($time_log) {
      if (!$title) {
        # Just use the command as the label.
        $title = join(' ',@cmd);
      }
      acl::Common::log_time ($title, $end_time - $start_time);
    }

    my $result = $retcode >> 8;

    if($retcode != 0) {
      if ($result == 0) {
        # We probably died on an assert, make sure we do not return zero
        $result =- 1;
      }
    }

    # add the content of the errlog to reg.err if regtest mode is on
    if ($err && $result != 0 && $regtest_mode && $proj_dir) {
      acl::Report::append_to_log($err, "$proj_dir/$regtest_errlog");
    }    

    acl::Report::display_hls_error_message($title, 
                                           $out, 
                                           $err, 
                                           $keep_log, 
                                           $out_is_temporary, 
                                           $err_is_temporary, 
                                           $move_err_to_out,
                                           $retcode, 
                                           $time_passes,
                                           \@cleanup_list); 
    
    return ($result);
}

sub disassemble ($) {
    my $file=$_[0];
    if ( $disassemble ) {
      mysystem_full({'stdout' => ''}, "llvm-dis ".$file ) == 0 or mydie("Cannot disassemble:".$file."\n"); 
    }
}

sub get_acl_board_hw_path {
    my $root = $ENV{"INTELFPGAOCLSDKROOT"};
    return "$root/share/models/bm";  
}

sub remove_named_files {
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose>2), dry_run => 0 } )
         or mydie("Cannot remove $fname: $acl::File::error\n");
    }
}

sub unpack_object_files(@) {
    my $work_dir= shift;
    my @list = ();
    my $file;

    acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);

    foreach $file (@_) {
      my $corename = get_name_core($file);
      my $separator = (isLinuxOS())? '/' : '\\';
      my $fname=$work_dir.$separator.$corename.'.fpga.ll';
      if(get_section_from_object_file($file, $fpga_IR_section, $fname, $work_dir)){
        push @fpga_IR_list, $fname;
        #At least one fpga file, make sure default emulator flag is turned off
        $emulator_flow = 0;
      }
      push @cleanup_list, $fname;

      (my $dep_fname=$fname) =~ s/\.ll/\.d/;
      (my $log_fname=$fname) =~ s/\.ll/\.log/;
      push @fpga_dep_list, $fname if(get_section_from_object_file($file, $fpga_dep_section, $dep_fname, $work_dir));
      get_section_from_object_file($file, $fpga_log_section, $log_fname, $work_dir);
      push @cleanup_list, $dep_fname;
      push @cleanup_list, $log_fname;

      if (not $RTL_only_flow_modifier) {
        # Regular object file 
        push @list, $file;
      }
    }
    @object_list=@list;
    if (@fpga_IR_list == 0){
      #No need for project directory, remove it
      push @cleanup_list, $work_dir;
    }
}

# Strips leading directories and removes any extension
sub get_name_core($) {
    my  $base = acl::File::mybasename($_[0]);
    $base =~ s/[^a-z0-9_\.]/_/ig;
    my $suffix = $base;
    $suffix =~ s/.*\.//;
    $base=~ s/\.$suffix//;
    return $base;
}

sub print_debug_log_header($) {
    my $cmd_line = shift;
    open(LOG, ">>$project_log");
    print LOG "*******************************************************\n";
    print LOG " i++ debug log file                                    \n";
    print LOG " This file contains diagnostic information. Any errors \n";
    print LOG " or unexpected behavior encountered when running i++   \n";
    print LOG " should be reported as bugs. Thank you.                \n";
    print LOG "*******************************************************\n";
    print LOG "\n";
    print LOG "Compiler Command: ".$cmd_line."\n";
    print LOG "\n";
    close LOG
}

sub setup_linkstep ($) {
    my $cmd_line = shift;
    # Setup project directory and log file for reminder of compilation
    # We deduce this from the object files and we don't call this if we 
    # know that we are just linking x86

    $g_work_dir = get_project_directory_from_file(@object_list);
    $project_name = (parse_extension($g_work_dir))[0];

    # No turning back, remove anything old
    remove_named_files($g_work_dir,'modelsim.ini');
    remove_named_files($executable) unless ($cosim_linkstep_only);

    acl::File::make_path($g_work_dir) or mydie($acl::File::error.' While trying to create '.$g_work_dir);
    $project_log=${g_work_dir}.'/debug.log';
    $project_log = acl::File::abs_path($project_log);
    print_debug_log_header($cmd_line);
    # Remove immediatly. This is to make sure we don't pick up data from 
    # previos run, not to clean up at the end 

    # Individual file processing, populates fpga_IR_list
    unpack_object_files($g_work_dir, @object_list);

}

sub find_board_spec () {
    my $supported_families = join ', ', keys %family_to_board_map;

    my $board_variant;
    if (exists $family_to_board_map{$dev_family}) {
      $board_variant = $family_to_board_map{$dev_family};
    } else {
      mydie("Unsupported device family. Supported device families are:\n$supported_families\n");
    }
    my $acl_board_hw_path= get_acl_board_hw_path();

    # Make sure the board specification file exists. This is needed by multiple stages of the compile.
    my $board_spec_xml = $acl_board_hw_path."/$board_variant";
    -f $board_spec_xml or mydie("Unsupported device family. Supported device families are:\n$supported_families\n");
    push @llvm_board_option, '-board';
    push @llvm_board_option, $board_spec_xml;
}

# keep the usage help output in alphabetical order within each section!
sub usage() {
    my @family_keys = keys %family_to_board_map;
    my @keys_with_quotes = map { '"'.$_.'"' } @family_keys;
    my $supported_families = join ', ', @keys_with_quotes;
    print <<USAGE;

Usage: i++ [<options>] <input_files> 
Generic flags:
--debug-log Generate the compiler diagnostics log
-h,--help   Display this information
-o <name>   Place the output into <name> and <name>.prj
-v          Verbose mode
--version   Display compiler version information

Flags impacting the compile step (source to object file translation):
-c          Preprocess, parse and generate object files
--component <components>
            Comma-separated list of function names to synthesize to RTL
-D<macro>[=<val>]   
            Define a <macro> with <val> as its value.  If just <macro> is
            given, <val> is taken to be 1
-g          Generate debug information (default)
-g0         Do not generate debug information
-I<dir>     Add directory to the end of the main include path
-march=<arch> 
            Generate code for <arch>, <arch> is one of:
              x86-64, FPGA family, FPGA part code
            FPGA family is one of:
              $supported_families
            or any valid part code from those FPGA families.
--promote-integers  
            Use extra FPGA resources to mimic g++ integer promotion
--quartus-compile 
            Run HDL through a Quartus compilation
--simulator <simulator>
            Specify the simulator to be used for verification.
            Supported simulators are: modelsim (default), none
            If \"none\" is specified, generate RTL for components without testbench

Flags impacting the link step only (object file to binary/RTL translation):
--clock <clock_spec>
            Optimize the RTL for the specified clock frequency or period
--fp-relaxed 
            Relax the order of arithmetic operations
--fpc       Removes intermediate rounding and conversion when possible
-ghdl       Enable full debug visibility and logging of all HDL signals in simulation
-L<dir>     Add directory dir to the list of directories to be searched
-l<library> Search the library named library when linking (Flag is only supported
            on Linux. For Windows, just add .lib files directly to command line)
--x86-only  Only create the executable to run the testbench, but no RTL or 
            cosim support
--fpga-only Create the project directory, all RTL and cosim support, but do 
            not generate the testbench binary 
USAGE

}

sub version($) {
    my $outfile = $_[0];
    print $outfile "Intel(R) HLS Compiler\n";
    print $outfile "Version 18.1.0 Build 222\n";
    print $outfile "Copyright (C) 2018 Intel Corporation\n";
}

sub norm_upper_str($) {
    my $strvar = shift;
    # strip whitespace
    $strvar =~ s/[ \t]//gs;
    # uppercase the string
    $strvar = uc $strvar;
    return $strvar;
}

sub setup_family_and_device() {
    my $cmd = "devinfo \"$dev_device\"";
    chomp(my $devinfo = `$cmd`);
    if($? != 0) {
      mydie("Device information not found.\n$devinfo\n");
    }
    ($dev_family,$dev_part,$dev_speed) = split(",", $devinfo);
    $dev_family =~ s/\s//g;
    print "Target FPGA part name:   $dev_part\n"   if $verbose;
    print "Target FPGA family name: $dev_family\n" if $verbose;
    print "Target FPGA speed grade: $dev_speed\n"  if $verbose;
}

sub create_reporting_tool {
    my $filename = shift;
    my $local_start = time();

    ############################################################################
    # Get File List

    # Get the csr header files, if any
    my @comp_folders = ();
    push @comp_folders, acl::File::simple_glob( $g_work_dir."/components/*" );
    my @csr_h_files = ();
    foreach my $comp_folder (@comp_folders) {
        push @csr_h_files, acl::File::simple_glob( $comp_folder."/*_csr.h" );
    }

    ############################################################################
    # Create Reports
    {
        local $/ = undef;
        acl::File::make_path("$g_work_dir/reports") or die;
        acl::Report::copy_files($g_work_dir) or return;

        # Collect information for infoJSON, and print it to the report
        my $infoJSON = acl::Report::create_infoJSON(0, escape_string($project_name), $dev_family, $dev_part, qii_version(), escape_string($all_ipp_args));

        # warningsJSON
        my @clang_logs = ();
        for (@clang_logs = @fpga_IR_list) { s/\.ll$/\.log/}
        my $warningsJSON = acl::Report::create_warningsJSON(@clang_logs, "$g_work_dir/llvm_warnings.log", "$g_work_dir/system_integrator_warnings.log", 0);
        remove_named_files(@clang_logs);
        remove_named_files("$g_work_dir/llvm_warnings.log");
        remove_named_files("$g_work_dir/system_integrator_warnings.log");

        # This text is to give user information when --quartus-compile was not ran when calling i++ on how to
        # run quartus compile separately (i.e. not part of the i++ command)
        my $quartus_text = "This section contains a summary of the area and fmax data generated by compiling the components through Quartus. \n".
                           "To generate the data, run a Quartus compile on the project created for this design. To run the Quartus compile:\n".
                           "  1) Change to the quartus directory ($g_work_dir/quartus)\n  2) quartus_sh --flow compile quartus_compile\n";
        my $quartusJSON = acl::Report::create_quartusJSON($quartus_text);

        # Create list of files that should be included in fileJSON
        my @dep_files = ();
        # Since we derive the list of dependency files from @fpga_IR_list, it is
        # expected that the .d files will be available alongside the .ll files.
        # In the case of the "full flow", these will be in the .tmp directories
        # created for each input file.  In the case of the "-c flow", where we
        # compile from .o files, the .d and .ll files should be unpacked into
        # the project directory.
        my @files = acl::Report::get_file_list_from_dependency_files(@fpga_dep_list);
        remove_named_files(@fpga_dep_list) unless $save_tmps;
        push @files, @csr_h_files;

        # Create fileJSON
        my $fileJSON = acl::Report::get_source_file_info_for_visualizer(\@files, [], $debug_symbols);

        # create the area_src json file
        acl::Report::parse_to_get_area_src($g_work_dir);
        # List of JSON files to print to report_data.js
        my @json_files = ("area", "area_src", "mav", "lmv", "loops", "summary");

        push @json_files, "schedule_info" if -e "$g_work_dir/schedule_info.json";
        open (my $report, ">$g_work_dir/reports/lib/report_data.js") or return;

        acl::Report::create_json_file_or_print_to_report($report, "info", $infoJSON, \@json_files, $g_work_dir);
        acl::Report::create_json_file_or_print_to_report($report, "warnings", $warningsJSON, \@json_files, $g_work_dir);
        acl::Report::create_json_file_or_print_to_report($report, "quartus", $quartusJSON, \@json_files, $g_work_dir);

        acl::Report::print_json_files_to_report($report, \@json_files, $g_work_dir);

        print $report $fileJSON;
        close($report);

        # create empty verification data file to be filed on simulation run
        open (my $verif_report, ">$g_work_dir/reports/lib/verification_data.js") or return;
        print $verif_report "var verifJSON={};\n";
        close($verif_report);

        if ($pipeline_viewer) {
          acl::Report::create_pipeline_viewer($g_work_dir, "components", $verbose);
        }
    }

    ############################################################################
    # Clean up

    my $json_dir = "$g_work_dir/reports/lib/json";
    my @json_files = ("area", "area_src", "mav", "lmv", "loops", "summary", "info", "warnings", "quartus", "schedule_info");
    foreach (@json_files) {
      my $json_file = "$g_work_dir/$_.json";
      if ( -e $json_file ) {
        # There is no acl::File::move, so copy and remove instead.
        acl::File::copy($json_file, "$json_dir/$_.json")
          or warn "Can't copy $_.json to $json_dir\n";
        remove_named_files($json_file);
      }
    }

    # TODO: delete these two lines when Optimization report is no longer created.
    my $opt_rpt = $g_work_dir.'/opt.rpt';
    acl::File::copy($opt_rpt, "$g_work_dir/reports/optimization.rpt");
    push @cleanup_list, $opt_rpt;

    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    acl::Common::log_time ('Create Report', time() - $local_start) if ($time_log);
}

sub clk_get_exp {
    my $var = shift;
    my $exp = $var;
    $exp=~ s/[\.0-9 ]*//;
    return $exp;
}

sub clk_get_mant {
    my $var = shift;
    my $mant = $var;
    my $exp = clk_get_exp($mant);
    $mant =~ s/$exp//g;
    return $mant;
} 

sub clk_get_fmax {
    my $clk = shift;
    my $exp = clk_get_exp($clk);
    my $mant = clk_get_mant($clk);

    my $fmax = undef;

    if ($exp =~ /^GHz/) {
        $fmax = 1000000000 * $mant;
    } elsif ($exp =~ /^MHz/) {
        $fmax = 1000000 * $mant;
    } elsif ($exp =~ /^kHz/) {
        $fmax = 1000 * $mant;
    } elsif ($exp =~ /^Hz/) {
        $fmax = $mant;
    } elsif ($exp =~ /^ms/) {
        $fmax = 1000/$mant;
    } elsif ($exp =~ /^us/) {
        $fmax = 1000000/$mant;
    } elsif ($exp =~ /^ns/) {
        $fmax = 1000000000/$mant;
    } elsif ($exp =~ /^ps/) {
        $fmax = 1000000000000/$mant;
    } elsif ($exp =~ /^s/) {
        $fmax = 1/$mant;
    }
    if (defined $fmax) { 
        $fmax = $fmax/1000000;
    }
    return $fmax;
}

sub query_raw_vsim_version_string() {
    if (!defined $vsim_version_string) {
        $vsim_version_string = `vsim -version`;
    my $error_code = $?;

    if ($error_code != 0) {
        mydie("Error accessing ModelSim.  Please ensure you have a valid ModelSim installation on your path.\n" .
              "       Check your ModelSim installation with \"vsim -version\" \n"); 
    }
    }

    return $vsim_version_string;

}

sub query_vsim_version_string() {
    my $vsim_simple_str = query_raw_vsim_version_string();
    $vsim_simple_str =~ s/^\s+|\s+$//g;
    return $vsim_simple_str;
}

sub query_vsim_arch() {
    if (!defined $cosim_64bit) {
      my $vsim_version_str = query_raw_vsim_version_string();
    $cosim_64bit = ($vsim_version_str =~ /64 vsim/);
    }

    return $cosim_64bit;
}

sub quartus_version_str() {
  if (!defined $g_quartus_version_str) {
    $g_quartus_version_str = `quartus_sh -v`;
    my $error_code = $?;

    if ($error_code != 0) {
        mydie("Error accessing Quartus. Please ensure you have a valid Quartus installation on your path.\n");
    }
  }

  return $g_quartus_version_str;
}

sub qii_is_pro() {
  # IMPORTANT NOTE:
  # Please notice that the current code is hardcoded for the Pro Edition of Quartus. 
  # It has to be changed if we merge the trunk code to the standard branch.
  return 1;
}

sub qii_version() {
  my $q_version_str = quartus_version_str();
  my ($qii_version_str1) = $q_version_str =~ /Version (.* Build \d*)/;
  my ($qii_version_str2) = $q_version_str =~ /( \w+) Edition/;
  my $qii_version = $qii_version_str1 . $qii_version_str2;
  return $qii_version;
}

sub parse_args {
    my @user_parseflags = ();
    my @user_linkflags =();
    while ( $#ARGV >= 0 ) {
      my $arg = shift @ARGV;
      if ( ($arg eq '-h') or ($arg eq '--help') ) { usage(); exit 0; }
      elsif ($arg eq '--list-deps') { print join("\n",values %INC),"\n"; exit 0; }
      elsif ( ($arg eq '--version') or ($arg eq '-V') ) { version(\*STDOUT); exit 0; }
      elsif ( ($arg eq '-v') ) { $verbose += 1; if ($verbose > 1) {$prog = "#$prog";} }
      elsif ( ($arg eq '-g') ) { 
          $user_required_debug_symbol = 1;
          $debug_symbols = 1;
      }
      elsif ( ($arg eq '-g0') ) { $debug_symbols = 0;}
      elsif ( ($arg eq '-o') ) {
          # Absorb -o argument, and don't pass it down to Clang
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a name argument.");
          $project_name = shift @ARGV;
      }
      elsif ( $arg =~ /^-o(.+)/ ) {
          $project_name = $1;
      }
      elsif ( ($arg eq '--component') ) {
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie('Option --component requires a function name');
          print "Warning: Specifying components with the --component flag may cause attribute information to be lost. It is recommended that the component attribute is used instead.\n";
          push @component_names, shift @ARGV;
      }
      elsif ( $arg =~ /^-march=(.*)/ ) {
        $march_set = 1;
        my $arch = $1;
        if      ($arch eq 'x86-64') {
          $emulator_flow = 1;
        } else {
          $simulator_flow = 1;
          $dev_device = $arch;
        }
      }
      elsif ($arg =~ /^-std=(.*)/) {
        $cppstd = $1;
      }
      elsif ($arg =~ /^--gcc-toolchain=(.*)/) {
        $gcc_toolchain_arg = $1;
      }
      elsif ($arg eq '--cosim' ) {
          $RTL_only_flow_modifier = 0;
      }
      elsif ($arg eq '--x86-only' ) {
          $x86_linkstep_only = 1;
          $cosim_linkstep_only = 0;
      }
      elsif ($arg eq '--fpga-only' ) {
          $cosim_linkstep_only = 1;
          $x86_linkstep_only = 0;
      }
      elsif ($arg eq '-ghdl') {
          $RTL_only_flow_modifier = 0;
          $cosim_debug = 1;
      }
      elsif ($arg eq '--cosim-log-call-count') {
          $cosim_log_call_count = 1;
      }
      elsif ($arg eq '--simulator') {
          $#ARGV >= 0 or mydie('Option --simulator requires an argument');
          $cosim_simulator = norm_upper_str(shift @ARGV);
      }
      elsif ( ($arg eq '--regtest_mode') ) {
          $regtest_mode = 1;
          $time_log = "time.out";
          $keep_log = 1;
          $save_tmps = 1;
          $time_passes = 1;
          push @additional_llc_args, "-dump-hld-area-debug-files";
          push @additional_llc_args, "-time-passes";
          push @additional_opt_args, "-time-passes";
          push @additional_sysinteg_args, "--regtest_mode";
      }
      elsif ( ($arg eq '--clang-arg') ) {
          $#ARGV >= 0 or mydie('Option --clang-arg requires an argument');
          # Just push onto args list
          push @user_parseflags, shift @ARGV;
      }
      elsif ( ($arg eq '--debug-log') ) {
        $keep_log = 1;
      }
      elsif ( ($arg eq '--opt-arg') ) {
          $#ARGV >= 0 or mydie('Option --opt-arg requires an argument');
          push @additional_opt_args, shift @ARGV;
      }
      elsif ( ($arg eq '--llc-arg') ) {
          $#ARGV >= 0 or mydie('Option --llc-arg requires an argument');
          push @additional_llc_args, shift @ARGV;
      }
      elsif ( ($arg eq '--optllc-arg') ) {
          $#ARGV >= 0 or mydie('Option --optllc-arg requires an argument');
          my $optllc_arg = (shift @ARGV);
          push @additional_opt_args, $optllc_arg;
          push @additional_llc_args, $optllc_arg;
      }
      elsif ( ($arg eq '--sysinteg-arg') ) {
          $#ARGV >= 0 or mydie('Option --sysinteg-arg requires an argument');
          push @additional_sysinteg_args, shift @ARGV;
      }
      elsif ( ($arg eq '-c') ) {
          $object_only_flow_modifier = 1;
      }
      elsif ( ($arg eq '--dis') ) {
          $disassemble = 1;
      }
      elsif ($arg eq '--dot') {
        $dotfiles = 1;
      }
      elsif ($arg eq '--pipeline-viewer') {
        $dotfiles = 1;
        $pipeline_viewer = 1;
      }
      elsif ($arg eq '--save-temps') {
        $save_tmps = 1;
      }
      elsif ($arg eq '-save-temps') {
        mydie('unsupported option \'-save-temps\'');
      }
      elsif ( ($arg eq '--clock') ) {
          my $clk_option = (shift @ARGV);
          $qii_fmax_constraint = clk_get_fmax($clk_option);
          if (!defined $qii_fmax_constraint) {
              mydie("i++: bad value ($clk_option) for --clock argument\n");
          }
          push @additional_opt_args, '-scheduler-fmax='.$qii_fmax_constraint;
          push @additional_llc_args, '-scheduler-fmax='.$qii_fmax_constraint;
      }
      elsif ( ($arg eq '--dont-error-if-large-area-est') ) {
        push @additional_opt_args, '-cont-if-too-large';
        push @additional_llc_args, '-cont-if-too-large';
      }
      elsif ( ($arg eq '--fp-relaxed') ) {
          push @additional_opt_args, "-fp-relaxed=true";
      }
      elsif ( ($arg eq '--fpc') ) {
          push @additional_opt_args, "-fpc=true";
      }
      elsif ( ($arg eq '--promote-integers') ) {
          print "Warning: The --promote-integers flag has been deprecated. Promoting integers is now the default behaviour.\n"
      }
      # Soft IP C generation flow
      elsif ($arg eq '--soft-ip-c') {
          $soft_ip_c_flow_modifier = 1;
          $simulator_flow = 1;
          $disassemble = 1;
      }
      # Soft IP C generation flow for x86
      elsif ($arg eq '--soft-ip-c-x86') {
          $soft_ip_c_flow_modifier = 1;
          $simulator_flow = 1;
          $target_x86 = 1;
          $disassemble = 1;
      }
      elsif ($arg eq '--quartus-compile') {
          $qii_flow = 1;
      }
      elsif ($arg eq '--quartus-no-vpins') {
          $qii_vpins = 0;
      }
      elsif ($arg eq '--quartus-dont-register-ios') {
          $qii_io_regs = 0;
      }
      elsif ($arg eq '--quartus-aggressive-pack-dsps') {
          $qii_dsp_packed = 1;
      }
      elsif ($arg eq "--quartus-seed") {
          $qii_seed = shift @ARGV;
      }
      elsif ($arg eq '--standalone') {
        # Our tools use this flag to indicate that the package should not check for existance of ACDS
        # Currently unused by i++ but we don't want to pass this flag to Clang so we gobble it up here
      }
      elsif ($arg eq '--time') {
        if($#ARGV >= 0 && $ARGV[0] !~ m/^-./) {
          $time_log = shift(@ARGV);
        }
        else {
          $time_log = "-"; # Default to stdout.
        }
      }
      elsif ($arg =~ /^-L/) {
        if(isWindowsOS()) {
            $arg = substr $arg, 2;
            $arg = '-LIBPATH:' . $arg;
        }
        push @user_linkflags, $arg;  
      }
      elsif($arg =~ /^-Wl/ or 
            $arg =~  /^-l/) {
          isLinuxOS() or mydie("\"$arg\" not supported on Windows. Use -L or list the libraries on the command line instead.");
          push @user_linkflags, $arg;
      }
      elsif ($arg eq '-I') { # -Iinc syntax falls through to default below (even if first letter of inc id ' '
          ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a name argument.");
          push  @user_parseflags, $arg.(shift @ARGV);
      }
      elsif ( $arg =~ m/\.c$|\.cc$|\.cp$|\.cxx$|\.cpp$|\.CPP$|\.c\+\+$|\.C$/ ) {
          push @source_list, $arg;
      }
      elsif ( $arg =~ m/\Q$default_object_extension\E$/ ) {
          push @object_list, $arg;
      } 
      elsif ( $arg =~ m/\.lib$/ && isWindowsOS()) {
          push @user_linkflags, $arg;
      }
      elsif ( ($arg eq '-E')  or ($arg =~ /^-M/ ) ){ #preprocess only;
          $preprocess_only= 1;
          $object_only_flow_modifier= 1;
          push @user_parseflags, $arg;
      } else {
          push @user_parseflags, $arg;
      }
    }

    # Default to x86-64
    if ( not $emulator_flow and not $simulator_flow and not $x86_linkstep_only) {
      $emulator_flow = 1;
    }

    # Default to c++14
    if ($cppstd eq "") {
      $cppstd="c++14";
    } elsif (lc($cppstd) ne "c++14") {
      mydie("Error: HLS only supports C++14.\n");
    }

    # if $debug_symbols is set and we're running on
    # a Windows OS, disable debug symbols silently here
    # since the default is to generate debug_symbols.
    if ($debug_symbols && $emulator_flow && isWindowsOS()) {
      $debug_symbols = 0;
      # if the user explicitly requests debug symbols and we're running on a Windows OS with -march=x86-64
      # dont't enable debug symbols.
      if ($user_required_debug_symbol){
        print "$prog: Debug symbols are not supported on Windows for x86, ignoring -g.\n";
      } 
    }

    if (@component_names) {
      push @additional_opt_args, "-hls-component-name=".join(',',@component_names);
    }

    # All arguments in, make sure we have at least one file
    (@source_list + @object_list) > 0 or mydie('No input files');
    if ($debug_symbols) {
      push @user_parseflags, '-g';
      push @additional_llc_args, '-dbg-info-enabled';
    }

    if (!$emulator_flow){
        if ($cosim_simulator eq "NONE") {
            $RTL_only_flow_modifier = 1;
        } elsif ($cosim_simulator eq "MODELSIM") {
            query_vsim_arch();
        } else {
            mydie("Unrecognized simulator $cosim_simulator\n");
        }
    }

    if ( $emulator_flow && $cosim_simulator eq "NONE") {
      mydie("i++: The --simulator none flag is valid only with FPGA architectures\n");
    }

    if ($time_log) {
      # open time log file
      acl::Common::open_time_log($time_log, 0);  # 0 means not append
    }

    # make sure that the device and family variables are set to the correct
    # values based on the user inputs and the flow
    setup_family_and_device();

    # Make sure that the qii compile flow is only used with the altera compile flow
    if ($qii_flow and not $simulator_flow) {
        mydie("The --quartus-compile argument can only be used with FPGA architectures\n");
    }
    # Check qii flow args
    if ((not $qii_flow) and $qii_dsp_packed) {
        mydie("The --quartus-aggressive-pack-dsps argument must be used with the --quartus-compile argument\n");
    }
    if ($qii_dsp_packed and not ($dev_family eq $A10_family)) {
        mydie("The --quartus-aggressive-pack-dsps argument is only applicable to the Arria 10 device family\n");
    }

    if ($dotfiles) {
      push @additional_opt_args, '--dump-dot';
      push @additional_llc_args, '--dump-dot'; 
      push @additional_sysinteg_args, '--dump-dot';
    }

    # caching is disabled for LSUs in HLS components for now
    # enabling caches is tracked by case:314272
    push @additional_opt_args, '-nocaching';
    push @additional_opt_args, '-noprefetching';

    $orig_dir = acl::File::abs_path('.');

    # Check legality related to --x86-only and --fpga-only
    if ($object_only_flow_modifier) {
      if ($x86_linkstep_only) {
        print "Warning:--x86-only has no effect\n";
      }
      if ($cosim_linkstep_only) {
        print "Warning:--fpga-only has no effect\n";
      }
    }
    if ($march_set && $#source_list<0) {
      print "Warning:-march has no effect. Using settings from -c compile\n";
    }
    if ($cosim_linkstep_only && $project_name && $#source_list<0) {
      print "Warning:-o has no effect. Project directory name set during -c compile\n";
    }
    if ($x86_linkstep_only && $cosim_linkstep_only) {
      mydie("Command line can only contain one of --x86-only, --fpga-only\n");
    }
    
    # Sanity check and generate the project and executable name
    # Defaults follow g++ convention on the respective platform:
    #   Windows Default: a.exe / a.prj
    #   Linux Default: a.out / a.prj
    if ( $project_name ) {
      if ( $#source_list > 0 && $object_only_flow_modifier) {
        mydie("Cannot specify -o with -c and multiple source files\n");
      }
      if ( !$object_only_flow_modifier && $project_name =~ m/\Q$default_object_extension\E$/) {
        mydie("'-o $project_name'. Result files with extension $default_object_extension only allowed together with -c\n");
      }
      if (isLinuxOS()) {
        $executable = $project_name;
      } else  {
        my ($basename, $extension) = parse_extension($project_name);
        if ($extension eq '.exe') {
          $executable = $project_name;
        } else {
          $executable = $project_name.'.exe';
    }
      }
    } else {
      $project_name = 'a';
      $executable = ${project_name}.(isWindowsOS() ? '.exe' : '.out');
    }

    # Consolidate some flags
    push (@parseflags, "-Wunknown-pragmas");
    push (@parseflags, @user_parseflags);
    push (@parseflags,"-I" . $ENV{'INTELFPGAOCLSDKROOT'} . "/include");
    # UPLIFT - add path to host/include

    my $emulator_arch=acl::Env::get_arch();
    my $host_lib_path = acl::File::abs_path( acl::Env::sdk_root().'/host/'.${emulator_arch}.'/lib');
    push (@linkflags, @user_linkflags);
    if (isLinuxOS()) {
      push (@linkflags, '-lstdc++');
      push (@linkflags, '-lm');
      push (@linkflags, '-L'.$host_lib_path);
    }

    #Setting defualt value of fmax
    if (!defined $qii_fmax_constraint) {#default fmax
      my $supported_families = join ', ', keys %family_to_fmax_map;
      my $fmax_variant;
      if (exists $family_to_fmax_map{$dev_family}) {
        $fmax_variant = $family_to_fmax_map{$dev_family};
      } else {
        mydie("Unsupported device family. Supported device families are:\n$supported_families\n");
      }
   
      $qii_fmax_constraint = $fmax_variant;
   
      push @additional_opt_args, '-scheduler-fmax='.$qii_fmax_constraint;
      push @additional_llc_args, '-scheduler-fmax='.$qii_fmax_constraint;
    } 
}

sub fpga_parse ($$$){
    my $source_file= shift;
    my $objfile = shift;
    my $work_dir = shift;
    print "Analyzing $source_file for hardware generation\n" if $verbose;

    # OK, no turning back remove the old result file, so no one thinks we 
    # succedded. Can't be defered since we only clean it up IF we don't do -c
    if ($preprocess_only || !$object_only_flow_modifier) { 
      push @cleanup_list, $objfile; 
    };

    my $outputfile=$work_dir.'/fpga.ll';
    # Create a .d dependency file alongside the FPGA IR.  This file will be used
    # directly in the full flow, or be packed into the .o file in the case of a
    # -c compile.
    (my $dep_file=$outputfile) =~ s/\.ll/\.d/;
    (my $log_file=$outputfile) =~ s/\.ll/\.log/;
    my @clang_dependency_args = ("-MMD");

    # UPLIFT - clang_std_opts2 is different on UPLIFT
    my @clang_opts2 = qw(-S -x c++ -ffpga -fhls -emit-llvm -Wuninitialized -fno-exceptions --std);
      push (@clang_opts2, $cppstd);
      if (isLinuxOS()) {
        # UPLIFT - triple is different on UPLIFT
      push (@clang_opts2, qw(-target x86_64-unknown-linux-gnu));
      } elsif (isWindowsOS()) {
      push (@clang_opts2, qw(-target x86_64-pc-win32 -D_DLL));
    }

    push (@clang_opts2, @safe_opt_zero);
    push (@clang_opts2, get_gcc_toolchain() );
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_opts2,
      "-D__INTELFPGA_COMPILER__=$acl_version_string",
      "-D__INTELFPGA_TYPE__=$macro_type_string",
      "-DHLS_SYNTHESIS",
      @parseflags,
      $source_file,
      @clang_dependency_args,
      $preprocess_only ? '':('-o',$outputfile)
    );

    $return_status = mysystem_full({'title' => 'FPGA Parse',
                                    'stderr' => "$work_dir/clang.err",
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    acl::Report::append_to_log("$work_dir/clang.err", "$log_file");
    if ($return_status) {
      push @cleanup_list, $objfile; #Object file created
      mydie();
    }

    if ($preprocess_only) {
      return;
    }
    
    if( !$target_x86){
      # For FPGA, we need to rewrite the triple.  Unfortunately, we can't do this in the regular -O3 opt, as
      # there are immutable passes (TargetLibraryInfo) that check the triple before we can run.  Run this
      # pass first as a standalone pass.  The alternate (better compile time) would be to run this as the last
      # part of clang, but that would also need changes to cllib.  See FB568473.

      #Also, for soft-ip-c-x86 flow, fpga_parse is run, but the ABI should be in x86

      my $spir_rw_outputfile = substr($outputfile,0,-2).'rw.ll' ;
      my @cmd_list = ($opt_exe, '-rewritetofpga', 
                      $outputfile,
                      '-o', $spir_rw_outputfile,
                      '-S');
      if(@component_names){
        my @component_flag_list = ('-add-hls-comp-from-flag',
                      "-hls-component-name=".join(',',@component_names));
        push @cmd_list, @component_flag_list;
      }
      my $temp_err_log = "$work_dir/" . get_temp_error_logfile();
      $return_status = mysystem_full({'title' => 'Transforming to FPGA ABI',
                                      'stderr' => $temp_err_log,
                                      'logs_are_temporary' => '1',
                                      'proj_dir' => $orig_dir},
                                     @cmd_list);
      acl::Report::append_to_log($temp_err_log, "$work_dir/opt.err");
      push @cleanup_list, "$work_dir/opt.err";
      if ($return_status) {
        mydie();
      }
      push @cleanup_list, $outputfile;
      $outputfile=$spir_rw_outputfile;
    }
    
    # Now the IR parsed from clang is modified to use the SPIR triple

    my $separator = (isLinuxOS())? '/' : '\\';
    my $prj_name_tmpfile = $work_dir.$separator.'prj_name.txt';
    my $prj_name = acl::File::mydirname($project_name).(parse_extension(acl::File::mybasename($project_name)))[0];
    
    # add section to object file unless we are going straight to linkstep
    if($object_only_flow_modifier){
      if (check_FPGA_IR_has_component($outputfile)){
        open FILE, ">$prj_name_tmpfile"; binmode FILE; print FILE ${prj_name}.".prj"; close FILE;
        add_projectname_to_object_file($objfile, $prj_name_section, $prj_name_tmpfile, $work_dir);
        push @cleanup_list, $prj_name_tmpfile;
      }
      add_section_to_object_file($objfile, $fpga_IR_section, $outputfile, $work_dir);
      add_section_to_object_file($objfile, $fpga_dep_section, $dep_file, $work_dir);
      add_section_to_object_file($objfile, $fpga_log_section, $log_file, $work_dir) if -s $log_file;
    } else {
      $g_work_dir = $prj_name.'.prj';
      push @fpga_IR_list, $outputfile;
      push @fpga_dep_list, $dep_file;
    }
    push @cleanup_list, $outputfile;
    push @cleanup_list, $dep_file;
    push @cleanup_list, $log_file;

}

sub testbench_compile ($$$) {
    my $source_file= shift;
    my $object_file = shift;
    my $work_dir = shift;
    print "Analyzing $source_file for testbench generation\n" if $verbose;

    # UPLIFT - change clang_std_opts for UPLIFT
    my @clang_std_opts =  qw(-S -emit-llvm -x c++ -fhls -Wuninitialized -fno-exceptions --std);
    push (@clang_std_opts, $cppstd);
    if (!isLinuxOS()) {
	    push (@clang_std_opts, '-D_DLL');
    }
    push (@clang_std_opts, @safe_opt_zero);
    push (@clang_std_opts, get_gcc_toolchain() );

    my @macro_options;
    @macro_options= qw(-DHLS_X86);

    #On Windows, do not use -g
    my @parseflags_nog;
    if (isWindowsOS()){
      @parseflags_nog = grep { $_ ne '-g' } @parseflags;
      if ($user_required_debug_symbol){
        print "$prog: Debug symbols are not supported on Windows for testbench parse, ignoring -g.\n";
      }
    } else {
      @parseflags_nog = @parseflags;
    }
    
    my $parsed_file=$work_dir.'/parsed.bc';
    # UPLIFT - following command is a little different
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      @clang_std_opts,
      "-D__INTELFPGA_COMPILER__=$acl_version_string",
      "-D__INTELFPGA_TYPE__=$macro_type_string",
      @parseflags_nog,
      @macro_options,
      $source_file,
      $preprocess_only ? '':('-o',$parsed_file)
      );

    $return_status = mysystem_full({'title' => 'Testbench parse',
                                    'stderr' => "$work_dir/clang.err",
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      push @cleanup_list, $object_file; #Object file created
      mydie();
    }

    if ($preprocess_only) {
      return;
    }

    push @cleanup_list, $parsed_file;
    print "Creating x86-64 testbench \n" if $verbose;

    my $resfile=$work_dir.'/tb.bc';
    my @flow_options= qw(-HLS -replacecomponentshlssim);
    ##my @flow_options= qw(-replacecomponentshlssim); ## Was on uplift, recent added -HLS
    my $verification_path = acl::File::mybasename((parse_extension(${project_name}))[0]).".prj";

    my $simscript = get_sim_script_dir() . '/msim_run.tcl';

    my @cosim_verification_opts = ("-verificationpath", "$verification_path/$cosim_work_dir", "-verificationscript", "$simscript");
    @cmd_list = (
      $opt_exe,  
      '-emulDirCleanup', 
      @flow_options,
      @cosim_verification_opts,
      @additional_opt_args,
      @llvm_board_option,
      '-o', $resfile,
      $parsed_file );
    my $temp_err_log = "$work_dir/" . get_temp_error_logfile();
    $return_status = mysystem_full({'title' => 'Testbench component wrapper generation',
                                    'stderr' => $temp_err_log,
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    acl::Report::append_to_log($temp_err_log, "$work_dir/opt.err");
    push @cleanup_list, "$work_dir/opt.err";
    if ($return_status != 0) {
      mydie();
    }
    disassemble($resfile);

    push @cleanup_list, $resfile;

    my @clang_std_opts2;
    if (isLinuxOS()) {
      @clang_std_opts2 = qw(-B/usr/bin -O0);
    } elsif (isWindowsOS()) {
      @clang_std_opts2 = qw(-O0);
    }

    my @cosim_libs;
    push @cosim_libs, '-lhls_cosim';

    if (isLinuxOS()) {
      @cmd_list = (
        $clang_exe,'-c',
        ($verbose>2)?'-v':'',
        $resfile,
        '-o', $object_file);
    } elsif (isWindowsOS()) {
      @cmd_list = (
        $clang_exe, '-c',
        ($verbose>2)?'-v':'',
        $resfile,
        '-o', $object_file);

    }
    $return_status = mysystem_full({'title' => 'Clang (Generating testbench object file)',
                                    'stderr' => 'clang.err',
                                    'proj_dir' => $orig_dir},
                                   @cmd_list );
    if ($return_status != 0) {
      mydie();
    }

    if (!$object_only_flow_modifier) {
      push @cleanup_list, $resfile;
      push @object_list, $object_file;
    }
}

sub emulator_compile ($$$) {
    my $source_file= shift;
    my $object_file = shift;
    my $work_dir = shift;
    print "Analyzing $source_file\n" if $verbose;
    
    my $parsed_file=$work_dir.'/tb.ll';
    @cmd_list = (
      $clang_exe,
      '-emit-llvm',
      ($verbose>2)?'-v':'',
      qw(-x c++ --std), $cppstd,
      get_gcc_toolchain(),
      qw(-O0 -fhls -Wuninitialized -c -D_DLL),
      '-DHLS_X86',
      "-D__INTELFPGA_COMPILER__=$acl_version_string",
      "-D__INTELFPGA_TYPE__=$macro_type_string",
      $source_file,
      @parseflags,
      $preprocess_only ? '':('-o',$parsed_file)
    );

    $return_status = mysystem_full({'title' => 'x86-64 compile',
                                    'stderr' => 'clang.err',
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie();
    }
    if ($preprocess_only) {
      return;
    }

    push @cleanup_list, $parsed_file;
    
    # Calling opt

    my $resfile=$work_dir.'/tb.bc';

    @cmd_list = (
      $opt_exe,  
      '-emulDirCleanup', 
      @additional_opt_args,
      @llvm_board_option,
      '-o', $resfile,
      $parsed_file );
    my $temp_err_log = get_temp_error_logfile();
    $return_status = mysystem_full( {'title' => 'Optimization calls',
                                     'stderr' => $temp_err_log,
                                    },
                                   @cmd_list);
    acl::Report::append_to_log($temp_err_log, 'opt.err');
    acl::Report::move_to_err('opt.err');
    $return_status == 0 or mydie();
    disassemble($resfile);

    push @cleanup_list, $resfile;


   # creating object file
    my @clang_std_opts2;
    if (isLinuxOS()) {
      @clang_std_opts2 = qw(-B/usr/bin -O0);
    } elsif (isWindowsOS()) {
      @clang_std_opts2 = qw(-O0);
    }


    @cmd_list = (
      $clang_exe,'-c',
      ($verbose>2)?'-v':'',
      $resfile,
      '-o', $object_file);
    
    mysystem_full({'title' => 'Clang (Generating object file)'}, @cmd_list ) == 0 or mydie();

    push @object_list, $object_file;
    if (!$object_only_flow_modifier) { push @cleanup_list, $object_file; };
}

sub generate_fpga(@){
    my @IR_list=@_;
    print "Optimizing component(s) and generating Verilog files\n" if $verbose;

    my $all_sources = link_IR("fpga_merged", @{IR_list});
    push @cleanup_list, $all_sources;
    my $linked_bc=$g_work_dir.'/fpga.linked.bc';

    # Link with standard library.
    my $early_version = 'acl_early.bc';
    if ($target_x86){
      $early_version = 'acl_earlyx86.bc';
    }
    my $early_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/$early_version");
    @cmd_list = (
      $link_exe,
      $all_sources,
      $early_bc,
      '-o',
      $linked_bc );
    
    $return_status = mysystem_full({'title' => 'Early IP Link',
                                    'stderr' => "$g_work_dir/link1.err",
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie();
    }
    
    disassemble($linked_bc);
    
    # llc produces visualization data in the current directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    
    my $kwgid='fpga.opt.bc';
    ## UPLIFT -- following code is a little different on uplift
    #my @flow_options = qw(-HLS);
    #if ( $soft_ip_c_flow_modifier ) { push(@flow_options, qw(-SIPC)); }
    #push(@flow_options, qw(--grif --soft-elementary-math=false --fas=false));
    ## else
    my @flow_options = qw(-HLS);
    if ($soft_ip_c_flow_modifier) {
      push(@flow_options, qw(-SIPC));
      if ($target_x86) {
        # Only run certain passes for x86 SIPC flow.
        push(@flow_options, qw(-inline -dce -stripnk -cleanup-soft-ip));
      }
    }
    if (!$target_x86) {
      push(@flow_options, qw(-O3 -march=fpga));
      push(@flow_options, "-pass-remarks-output=opt.rpt.yaml");
    }

    push(@flow_options, qw(--soft-elementary-math=false));
    push(@flow_options, qw(--fas=false)) if $UPLIFT_TODO;

    my $opt_input = 'fpga.linked.bc';

    # endif
    my @cmd_list = (
      $opt_exe,
      @flow_options,
      @llvm_board_option,
      @additional_opt_args,
      $opt_input,
      '-o', $kwgid );
    # end UPLIFT comment 
    my $temp_err_log = get_temp_error_logfile();
    $return_status = mysystem_full({'title' => 'Main Optimizer',
                                    'stderr' => $temp_err_log,
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    acl::Report::append_to_log($temp_err_log, 'opt.err');
    push @cleanup_list, "opt.err";
    if ($return_status != 0) {
      mydie();
    }
    disassemble($kwgid);
    if ( $soft_ip_c_flow_modifier ) { myexit('Soft IP'); }

    # Lower instructions to IP library function calls
    my $lowered='fpga.lowered.bc';
    @flow_options = qw(-HLS -insert-ip-library-calls);
    ## UPLIFT -- --grif is not supported by uplift's aocl-llc
    #if ($UPLIFT_TODO) { push(@flow_options, qw(--grif --soft-elementary-math=false --fas=false)); }
    if ($UPLIFT_TODO) { push(@flow_options, qw(--soft-elementary-math=false --fas=false)); }
    @cmd_list = (
        $opt_exe,
        @flow_options,
        @additional_opt_args,
        $kwgid,
        '-o', $lowered);
    $temp_err_log = get_temp_error_logfile();
    $return_status = mysystem_full({'title' => 'Lower intrinsics to IP calls',
                                    'stderr' => $temp_err_log,
                                    'proj_dir' => $orig_dir},
                                   @cmd_list );
    acl::Report::append_to_log($temp_err_log, 'opt.err');
    push @cleanup_list, "opt.err";
    if ($return_status != 0) {
      mydie();
    }

    # Link with the soft IP library 
    my $linked='fpga.linked2.bc';
    my $late_bc = acl::File::abs_path( acl::Env::sdk_root().'/share/lib/acl/acl_late.bc');
    @cmd_list = (
      $link_exe,
      $lowered,
      $late_bc,
      '-o', $linked );
    $return_status = mysystem_full({'title' => 'Late IP library',
                                    'stderr' => 'link2.err',
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie();
    }

    # Inline IP calls, simplify and clean up
    my $final = get_name_core(${project_name}).'.bc';

    # UPLIFT - this command below is different on UPLIFT
    #          see inline_opts
    my @inline_opts = $UPLIFT_TODO ?
      qw(-HLS -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk -rename-basic-blocks -annotate-barrier-deps) :
      qw(-HLS -always-inline -instcombine -dce -stripnk -rename-basic-blocks -annotate-barrier-deps);
    @cmd_list = (
      $opt_exe,
      @inline_opts,
      @llvm_board_option,
      @additional_opt_args,
      $linked,
      '-o', $final);
    $temp_err_log = get_temp_error_logfile();
    $return_status = mysystem_full({'title' => 'Inline and clean up',
                                    'stderr' => $temp_err_log,
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    acl::Report::append_to_log($temp_err_log, 'opt.err');
    push @cleanup_list, "opt.err";
    if ($return_status != 0) {
      mydie();
    }

    disassemble($final);
    push @cleanup_list, $g_work_dir."/$final";

    # UPLIFT - don't support obfuscated strings for now.
    my $llc_option_macro = ' -march=fpga ';
    my @llc_option_macro_array = split(' ', $llc_option_macro);
    ## UPLIFT does not support --grif option.
    ##push(@additional_llc_args, qw(--grif));

    # DSPBA backend needs to know the device that we're targeting
    push(@additional_llc_args, qw(--device));
    push(@additional_llc_args, qq($dev_part) );

    # DSPBA backend needs to know the device family - Bugz:309237 tracks extraction of this info from the part number in DSPBA
    # Device is defined by this point - even if it was set to the default.
    # Query Quartus to get the device family`
    push(@additional_llc_args, qw(--family));
    push(@additional_llc_args, "\"".$dev_family."\"" );

    # DSPBA backend needs to know the device speed grade - Bugz:309237 tracks extraction of this info from the part number in DSPBA
    # The device is now defined, even if we've chosen the default automatically.
    # Query Quartus to get the device speed grade.
    push(@additional_llc_args, qw(--speed_grade));
    push(@additional_llc_args, qq($dev_speed) );

    my $core_name=get_name_core($project_name);
    @cmd_list = (
        $llc_exe,
        @llc_option_macro_array,
        qw(-HLS),
        qw(--board hls.xml),
        @additional_llc_args,
        $final,
        '-o',
        "$core_name.v",
        '-pass-remarks-input=opt.rpt.yaml',
        "-mattr=+design:$core_name");
    $return_status = mysystem_full({'title' => 'Verilog code generation, llc',
                                    'stderr' => 'llc.err',
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie();
    }

    my $xml_file = get_name_core(${project_name}).'.bc.xml';
    $return_status = mysystem_full({'title' => 'System Integration',
                                    'stderr' => 'sys_intg.err',
                                    'proj_dir' => $orig_dir},
                                   ($sysinteg_exe, @additional_sysinteg_args,'--hls', 'hls.xml', $xml_file ));
    if ($return_status != 0) {
      mydie();
    }

    my @components = get_generated_components();
    my $ipgen_result = create_qsys_components(@components);
    mydie("Failed to generate Qsys files\n") if ($ipgen_result);

    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    #Cleanup everything but final bc
    push @cleanup_list, acl::File::simple_glob( $g_work_dir."/*.*.bc" );
    push @cleanup_list, $g_work_dir."/$xml_file";
    push @cleanup_list, $g_work_dir.'/hls.xml';
    push @cleanup_list, $g_work_dir.'/'.get_name_core($project_name).'.v';
    push @cleanup_list, acl::File::simple_glob( $g_work_dir."/*.attrib" );
    push @cleanup_list, $g_work_dir.'/interfacedesc.txt';
    push @cleanup_list, $g_work_dir.'/compiler_metrics.out';
    push @cleanup_list, $g_work_dir.'/opt.rpt.yaml';

    create_reporting_tool(${final});
}

sub link_IR (@) {
    my ($basename,@list) = @_;
    my $result_file = shift @list;
    my $indexnum = 0;
    foreach (@list) {
        # Just add one file at the time since llvm-link has some issues
        # with unifying types otherwise. Introduces small overhead if 3
        # source files or more
        my $next_res = ${g_work_dir}.'/'.${basename}.${indexnum}++.'.bc';

        @cmd_list = (
            $link_exe,
            $result_file,
            $_,
            '-o',$next_res );

        $return_status = mysystem_full({'title' => 'Link IR',
                                        'stderr' => 'link3.err',
                                        'proj_dir' => $orig_dir},
                                       @cmd_list );
        if ($return_status != 0) {
          mydie();
        }
        push @cleanup_list, $next_res;

        $result_file = ${next_res};
    }
    if ($result_file =~ /\.bc$/) { disassemble($result_file); }
    return $result_file;
}

sub link_x86 ($$) {
    my $output_name = shift ;
    my $emulator_flow = shift;
    print "Linking x86 objects\n" if $verbose;

    acl::File::make_path(acl::File::mydirname($output_name)) or mydie("Can't create simulation directory ".acl::File::mydirname($output_name).": $!");

    if (isLinuxOS()) {
      if ($emulator_flow){
        push @linkflags, '-lhls_emul';
      } else {
        push @linkflags, '-lhls_cosim';
        push @linkflags, '-Wl,-rpath=' . $ENV{'INTELFPGAOCLSDKROOT'} . '/linux64/lib/dspba/linux64';
      }
      push @linkflags, '-lhls_fixed_point_math_x86';
      push @linkflags, '-laltera_mpir';
      push @linkflags, '-laltera_mpfr';
   
    @cmd_list = (
      $clang_exe,
      ($verbose>2)?'-v':'',
      "-D__INTELFPGA_TYPE__=$macro_type_string",
      "-DHLS_X86",
      get_gcc_toolchain(),
      @object_list,
      '-o',
      $executable,
      @linkflags,
      );

    } else {
      check_link_exe_existance();
      @cmd_list = (
        $mslink_exe,
        @object_list,
        @linkflags,
        '-nologo',
        '-defaultlib:msvcrt',
          '-ignore:4006',
          '-ignore:4088',
        '-out:'.$executable);

      push @cmd_list, get_hlsvbase_path();
      push @cmd_list, get_msvcrt_path();
      push @cmd_list, get_hlsfixed_point_math_x86_path();
      push @cmd_list, get_mpir_path();
      push @cmd_list, get_mpfr_path();

      if ($emulator_flow){
        push @cmd_list, get_hlsemul_path();
      } else {
        push @cmd_list, get_hlscosim_path();
      }
    }

    $return_status = mysystem_full({'title' => 'Link x86-64',
                                    'stderr' => 'link4.err',
                                    'proj_dir' => $orig_dir},
                                   @cmd_list );
    if ($return_status != 0) {
      mydie();
    }

    
    return;
}

sub get_generated_components() {
  # read the comma-separated list of components from a file
  my $project_bc_xml_filename = get_name_core(${project_name}).'.bc.xml';
  my $BC_XML_FILE;
  open (BC_XML_FILE, "<${project_bc_xml_filename}") or mydie "Couldn't open ${project_bc_xml_filename} for read!\n";
  my @dut_array;
  while(my $var =<BC_XML_FILE>) {
    if ($var =~ /<KERNEL name="(.*)" filename/) {
        push(@dut_array,$1); 
    }
  }
  close BC_XML_FILE;
  return @dut_array;
}

sub hls_sim_generate_verilog(@) {
    my $projdir = acl::File::mybasename($g_work_dir);
    print "Generating cosimulation support\n" if $verbose;
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    my @dut_array = get_generated_components();
    # finally, recreate the comma-separated string from the array with unique elements
    my $DUT_LIST  = join(',',@dut_array);
    print "Generating simulation files for components: $DUT_LIST\n" if $verbose;
    my $SEARCH_PATH = acl::Env::sdk_root()."/ip/,.,../components/**/*,\$"; # no space between paths!

    # Set default value of $count_log
    my $count_log = ".";
 
    if ($cosim_log_call_count) {
      $count_log = "sim_component_call_count.log";
    }

    # Because the qsys-script tcl cannot accept arguments, 
    # pass them in using the --cmd option, which runs a tcl cmd
    #
    my $set_pro = qii_is_pro() ?  1 : 0;
    my $num_reset_cycles = 4;
    my $init_var_tcl_cmd = "set quartus_pro $set_pro; set num_reset_cycles $num_reset_cycles; set sim_qsys $tbname; set component_list $DUT_LIST; set component_call_count_filename $count_log";

    # Create the simulation directory and enter it
    my $sim_dir_abs_path = acl::File::abs_path("./$cosim_work_dir");
    print "HLS simulation directory: $sim_dir_abs_path.\n" if $verbose;
    acl::File::make_path($cosim_work_dir) or mydie("Can't create simulation directory $sim_dir_abs_path: $!");
    chdir $cosim_work_dir or mydie("Can't change into dir $cosim_work_dir: $!\n");

    my $gen_qsys_tcl = acl::Env::sdk_root()."/share/lib/tcl/hls_sim_generate_qsys.tcl";

    # Run hls_sim_generate_qsys.tcl to generate the .qsys file for the simulation system 
    my $pro_string = "";
    if (qii_is_pro()) { $pro_string = "--quartus-project=none"; }
    $return_status = mysystem_full(
      {'stdout' => $project_log, 'stderr' => 'temp.err', 
       'out_is_temporary' => '0', 
       'move_err_to_out' => '1',
       'title' => 'Generate testbench QSYS system', 'proj_dir' => $orig_dir},
      'qsys-script',
      $pro_string,
      '--search-path='.$SEARCH_PATH,
      '--script='.$gen_qsys_tcl,
      '--cmd='.$init_var_tcl_cmd);
    if ($return_status != 0) {
      mydie();
    }


    # Generate the verilog for the simulation system
    @cmd_list = ('qsys-generate',
      '--search-path='.$SEARCH_PATH,
      '--simulation=VERILOG',
      '--family='.$dev_family,
      '--part='.$dev_part,
      $tbname.".qsys");
    $return_status = mysystem_full({'stdout' => $project_log,
                                    'stderr' => 'temp.err',
                                    'out_is_temporary' => '0', 
                                    'move_err_to_out' => '1',
                                    'title' => 'Generate testbench Verilog from Platform Designer system',
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    if ($return_status != 0) {
      mydie();
    }

    # Generate scripts that the user can run to perform the actual simulation.
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
    generate_simulation_scripts();
}


# This module creates a file:
# Moved everything into one file to deal with run time parameters, i.e. execution directory vs scripts placement.
#Previous do scripts are rewritten to strings that gets put into the run script
#Also perl driver in project directory is gone.
#  - compile_do      (the string run by the compilation phase, in the output dir)
#  - simulate_do     (the string run by the simulation phase, in the output dir)
#  - <source>        (the executable top-level simulation script, in the top-level dir)
sub generate_simulation_scripts() {
    # Working directories
    my $projdir = acl::File::mybasename($g_work_dir);
    my $qsyssimdir = get_qsys_sim_dir();
    my $simscriptdir = get_sim_script_dir();
    my $cosimdir = "$g_work_dir/$cosim_work_dir";
    # Library names
    my $cosimlib = query_vsim_arch() ? 'hls_cosim_msim' : 'hls_cosim_msim32';
    # Script filenames
    my $fname_compilescript = $simscriptdir.'/msim_compile.tcl';
    my $fname_runscript = $simscriptdir.'/msim_run.tcl';
    my $fname_msimsetup = $simscriptdir.'/msim_setup.tcl';
    my $fname_svlib = $ENV{'INTELFPGAOCLSDKROOT'} . (isLinuxOS() ? "/host/linux64/lib/lib${cosimlib}" : "/windows64/bin/${cosimlib}");
    my $fname_exe_com_script = isLinuxOS() ? 'compile.sh' : 'compile.cmd';

    # Modify the msim_setup script
    post_process_msim_file("$cosimdir/$fname_msimsetup", "$simscriptdir");
    
    # Generate the modelsim compilation script
    my $COMPILE_SCRIPT_FILE;
    open(COMPILE_SCRIPT_FILE, ">", "$cosimdir/$fname_compilescript") or mydie "Couldn't open $cosimdir/$fname_compilescript for write!\n";
    print COMPILE_SCRIPT_FILE "onerror {abort all; exit -code 1;}\n";
    print COMPILE_SCRIPT_FILE "set VSIM_VERSION_STR \"", query_vsim_version_string(), "\"\n";
    print COMPILE_SCRIPT_FILE "set QSYS_SIMDIR $qsyssimdir\n";
    print COMPILE_SCRIPT_FILE "source $fname_msimsetup\n";
    print COMPILE_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC";
    if (isWindowsOS()) {
        print COMPILE_SCRIPT_FILE " -nodpiexports";
    }
    print COMPILE_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                            : "\"\n");
    print COMPILE_SCRIPT_FILE "dev_com\n";
    print COMPILE_SCRIPT_FILE "com\n";
    print COMPILE_SCRIPT_FILE "elab\n";
    print COMPILE_SCRIPT_FILE "exit -code 0\n";
    close(COMPILE_SCRIPT_FILE);

    # Generate the run script
    my $RUN_SCRIPT_FILE;
    open(RUN_SCRIPT_FILE, ">", "$cosimdir/$fname_runscript") or mydie "Couldn't open $cosimdir/$fname_runscript for write!\n";
    print RUN_SCRIPT_FILE "onerror {abort all; puts stderr \"The simulation process encountered an error and has aborted.\"; exit -code 1;}\n";
    print RUN_SCRIPT_FILE "set VSIM_VERSION_STR \"", query_vsim_version_string(),"\"\n";
    print RUN_SCRIPT_FILE "set QSYS_SIMDIR $qsyssimdir\n";
    print RUN_SCRIPT_FILE "source $fname_msimsetup\n";
    print RUN_SCRIPT_FILE "# Suppress warnings from the std arithmetic libraries\n";
    print RUN_SCRIPT_FILE "set StdArithNoWarnings 1\n";
    print RUN_SCRIPT_FILE "set ELAB_OPTIONS \"+nowarnTFMPC -dpioutoftheblue 1 -sv_lib \\\"$fname_svlib\\\"";
    if (isWindowsOS()) {
        print RUN_SCRIPT_FILE " -nodpiexports";
    }
    print RUN_SCRIPT_FILE ($cosim_debug ? " -voptargs=+acc\"\n"
                                        : "\"\n");
    print RUN_SCRIPT_FILE "elab\n";
    print RUN_SCRIPT_FILE "onfinish {stop}\n";
    print RUN_SCRIPT_FILE "log -r *\n" if $cosim_debug;
    print RUN_SCRIPT_FILE "run -all\n";
    print RUN_SCRIPT_FILE "set failed [expr [coverage attribute -name TESTSTATUS -concise] > 1]\n";
    print RUN_SCRIPT_FILE "if {\${failed} != 0} { puts stderr \"The simulation process encountered an error and has been terminated.\"; }\n";
    print RUN_SCRIPT_FILE "exit -code \${failed}\n";
    close(RUN_SCRIPT_FILE);


    # Generate a script that we'll call to compile the design
    my $EXE_COM_FILE;
    open(EXE_COM_FILE, '>', "$cosimdir/$fname_exe_com_script") or die "Could not open file '$cosimdir/$fname_exe_com_script' $!";
    if (isLinuxOS()) {
      print EXE_COM_FILE "#!/bin/sh\n";
      print EXE_COM_FILE "\n";
      print EXE_COM_FILE "# Identify the directory to run from\n";
      print EXE_COM_FILE "rundir=\$PWD\n";
      print EXE_COM_FILE "scripthome=\$(dirname \$0)\n";
      print EXE_COM_FILE "cd \${scripthome}\n";
      print EXE_COM_FILE "# Compile and elaborate the testbench\n";
      print EXE_COM_FILE "vsim -batch -do \"do $fname_compilescript\"\n";
      print EXE_COM_FILE "retval=\$?\n";
      print EXE_COM_FILE "cd \${rundir}\n";
      print EXE_COM_FILE "exit \${retval}\n";
    } elsif (isWindowsOS()) {
      print EXE_COM_FILE "set rundir=\%cd\%\n";
      print EXE_COM_FILE "set scripthome=\%\~dp0\n";
      print EXE_COM_FILE "cd %scripthome%\n";
      print EXE_COM_FILE "vsim -batch -do \"do $fname_compilescript\"\n";
      print EXE_COM_FILE "set exitCode=%ERRORLEVEL%\n";
      print EXE_COM_FILE "cd %rundir%\n";
      print EXE_COM_FILE "exit /b %exitCode%\n";
    }
    close(EXE_COM_FILE);
    if(isLinuxOS()) {
      system("chmod +x $cosimdir/$fname_exe_com_script"); 
    }
}

sub compile_verification_project() {
    # Working directories
    my $cosimdir = "$g_work_dir/$cosim_work_dir";
    my $fname_exe_com_script = isLinuxOS() ? 'compile.sh' : 'compile.cmd';
    # Compile the cosim design in the cosim directory
    $orig_dir = acl::File::abs_path('.');
    chdir $cosimdir or mydie("Can't change into dir $g_work_dir: $!\n");
    if (isLinuxOS()) {
      @cmd_list = ("./$fname_exe_com_script");
    } elsif (isWindowsOS()) {
      @cmd_list = ("$fname_exe_com_script");
    }

    $return_status = mysystem_full({'stdout' => $project_log,
                                    'stderr' => 'temp.err',
                                    'out_is_temporary' => '0', 
                                    'move_err_to_out' => '1',
                                    'title' => 'Elaborate verification testbench',
                                    'proj_dir' => $orig_dir},
                                   @cmd_list);
    my $tempErr = acl::File::abs_path('temp.err');
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");

    # Missing license is such a common problem, let's give a special message
    if($return_status == 4) {
      my @temp;
      if (isWindowsOS()) {
        @temp = `where vsim`;
      } else {
        @temp = `which vsim`;
      }
      chomp(my $vsim_path = shift @temp);

      mydie("Missing simulator license for $vsim_path.  Either:\n" .
            "  1) Ensure you have a valid ModelSim license\n" .
            "  2) Use the --simulator none flag to skip the verification flow\n");
    } elsif($return_status == 127) { # same for Modelsim not installed on the PATH
      mydie("Error accessing ModelSim.  Please ensure you have a valid ModelSim installation on your path.\n" .
            "       Check your ModelSim installation with \"vmap -version\" \n"); 
    } elsif($return_status != 0) {
      mydie("Cosim testbench elaboration failed.\n");
    }
}

sub gen_qsys_script(@) {
    my @components = @_;

    my $qsys_ext = qii_is_pro() ? ".ip" : ".qsys";

    foreach (@components) {
        # Generate the tcl for the system
        my $tclfilename = "components/$_/$_.tcl";
        open(my $qsys_script, '>', "$tclfilename") or die "Could not open file '$tclfilename' $!";

        print $qsys_script <<SCRIPT;
package require -exact qsys 16.1

# create the system with the name
create_system $_

# set project properties
set_project_property HIDE_FROM_IP_CATALOG false
set_project_property DEVICE_FAMILY "${dev_family}"
set_project_property DEVICE "${dev_part}"

# adding the ip for which the variation has to be created for
add_instance ${_}_internal_inst ${_}_internal
set_instance_property ${_}_internal_inst AUTO_EXPORT true

# save the Qsys file
save_system "$_$qsys_ext"
SCRIPT
        close $qsys_script;
        push @cleanup_list, $g_work_dir."/$tclfilename";
    }
}

sub run_qsys_script(@) {
    my @components = @_;

    my $curr_dir = acl::File::abs_path('.');
    chdir "components" or mydie("Can't change into dir components: $!\n");

    foreach (@components) {
      chdir "$_" or mydie("Can't change into dir $_: $!\n");

      # Generate the verilog for the simulation system
      @cmd_list = ('qsys-script',
                   "--script=$_.tcl");
      if (qii_is_pro()) { push(@cmd_list, ('--quartus-project=none')); }
      $return_status = mysystem_full({'stdout' => $project_log,
                                      'stderr' => 'temp.err',
                                      'out_is_temporary' => '0', 
                                      'move_err_to_out' => '1',
                                      'title' => 'Generate component script for Platform Designer',
                                      'proj_dir' => $orig_dir},
                                     @cmd_list);
      if ($return_status != 0) {
        mydie();
      }

      # This is a temporary workaround so that the IP can be seen in the GUI
      # See case:375326
      if (qii_is_pro()) {
        @cmd_list = ('qsys-generate', '--quartus-project=none', '--synthesis', '--ipxact', "${_}.ip");
        $return_status = mysystem_full({'stdout' => $project_log,
                                        'stderr' => 'temp.err',
                                        'out_is_temporary' => '0',
                                        'move_err_to_out' => '1',
                                        'title' => 'Generate component ipxact for Platform Designer',
                                        'proj_dir' => $orig_dir},
                                       @cmd_list);
        if ($return_status != 0) {
          mydie();
        }
      }

      chdir ".." or mydie("Can't change into dir ..: $!\n");
    }
    chdir $curr_dir or mydie("Can't change into dir $curr_dir: $!\n");
}

sub post_process_msim_file(@) {
  my ($file,$libpath) = @_;
  open(FILE, "<$file") or die "Can't open $file for read";
  my @lines;
  while(my $line = <FILE>) {
    # fix library paths
    $line =~ s|\./libraries/|$libpath/libraries/|g;
    # fix vsim version call because it does not work in batch mode
    $line =~ s|\[\s*vsim\s*-version\s*\]|\$VSIM_VERSION_STR|g;
    push(@lines,$line);
  }
  close(FILE);
  open(OFH,">$file") or die "Can't open $file for write";
  foreach my $line (@lines) {
    print OFH $line;
  }
  close(OFH);
  return 0;
}

sub post_process_qsys_files(@) {
    my @components = @_;

    my $return_status = 0;
    foreach (@components) {
        my $qsys_ip_file =  qii_is_pro() ? "components/$_/$_/$_.ipxact" :
                                              "components/$_/$_.qsys";
        # Read in the current QSYS file
        open (FILE, "<$qsys_ip_file") or die "Can't open $qsys_ip_file for read";
        my @lines;
        while (my $line = <FILE>) {
            # this organizes the components in the IP catalog under the same HLS/ directory
            if (qii_is_pro()) {
                $line =~ s/Altera Corporation/HLS/g;
            } else {
                $line =~ s/categories=""/categories="HLS"/g;
            }
            push(@lines, $line);
        }
        close(FILE);
        # Write out the modified QSYS file
        open (OFH, ">$qsys_ip_file") or die "Can't open $qsys_ip_file  for write";
        foreach my $line (@lines) {
                print OFH $line;
        }
        close(OFH);
    }
    return $return_status;
}

sub create_ip_folder(@) {
  my @components = @_;
  my $OCLROOTDIR = $ENV{'INTELFPGAOCLSDKROOT'};

  my $qsys_ext = qii_is_pro() ? ".ip" : ".qsys";

  foreach (@components) {
    my $component = $_;
    open(FILELIST, "<$component.files") or die "Can't open $component.files for read";
    while(my $file = <FILELIST>) {
      chomp $file;
      if($file =~ m|\$::env\(INTELFPGAOCLSDKROOT\)/|) {
        $file =~ s|\$::env\(INTELFPGAOCLSDKROOT\)/||g;
        acl::File::copy("$OCLROOTDIR/$file", "components/".$component."/".$file);
      } else {
        acl::File::copy($file, "components/".$component."/".$file);
        push @cleanup_list, $g_work_dir.'/'.$file;
      }
    }
    close(FILELIST);

    # if it exists, copy the slave CSR header file
    acl::File::copy($component."_csr.h", "components/".$component."/".$component."_csr.h");

    # if it exists, copy the inteface file for each component
    acl::File::copy($component."_interface_structs.v", "components/".$component."/"."interface_structs.v");

    # cleanup
    push @cleanup_list, $g_work_dir.'/'.$component."_interface_structs.v";
    push @cleanup_list, $g_work_dir.'/'.$component."_csr.h";
    push @cleanup_list, $g_work_dir.'/'.$component.".files";
  }
  acl::File::copy("interface_structs.v", "components/interface_structs.v");
  push @cleanup_list, $g_work_dir.'/interface_structs.v';
  return 0;
}

sub create_qsys_components(@) {
    my @components = @_;
    create_ip_folder(@components);
    gen_qsys_script(@components);
    run_qsys_script(@components);
    post_process_qsys_files(@components);
}

sub get_qsys_output_dir($) {
   my ($target) = @_;

   my $dir = ($target eq "SIM_VERILOG") ? "simulation" : "synthesis";

   if (qii_is_pro() or $dev_family eq  $A10_family) {
      $dir = ($target eq "SIM_VERILOG")   ? "sim"   :
             ($target eq "SYNTH_VERILOG") ? "synth" :
                                            "";
   }

   return $dir;
}

sub get_qsys_sim_dir() {
   my $qsysdir = $tbname.'/'.get_qsys_output_dir("SIM_VERILOG");

   return $qsysdir;
}

sub get_sim_script_dir() {

   my $qsysdir = get_qsys_sim_dir();
   my $simscriptdir = $qsysdir.'/mentor';

   return $simscriptdir;
}

sub generate_top_level_qii_verilog($@) {
    my ($qii_project_name, @components) = @_;
    my %clock2x_used;
    my %component_portlists;
    foreach (@components) {
      #read in component module from file and parse for portlist
      my $example = '../components/'.$_.'/'.$_.'_inst.v';
      open (FILE, "<$example") or die "Can't open $example for read";
      #parse for portlist
      my $in_module = 0;
      while (my $line = <FILE>) {
        if($in_module) {
          if($line =~ m=^ *\.([a-z]+)=) {
          }
          if($line =~ m=^\s*\.(\S+)\s*\( \),*\s+// (\d+)-bit \S+ (input|output)=) {
            my $hi = $2 - "1";
            my $range = "[$hi:0]";
            push(@{$component_portlists{$_}}, {'dir' => $3, 'range' => $range, 'name' => $1});
            if($1 eq "clock2x") {
              push(@{$clock2x_used{$_}}, 1);
            }
          }
        } else {
          if($line =~ m|^$_ ${_}_inst \($|) {
            $in_module = 1;
          }
        }
      }
      close(FILE);
    }

    #output top level
    open (OFH, ">${qii_project_name}.sv") or die "Can't open ${qii_project_name}.sv for write";
    print OFH "module ${qii_project_name} (\n";

    #ports
    print OFH "\t  input logic resetn\n";
    print OFH "\t, input logic clock\n";
    if (scalar keys %clock2x_used) {
        print OFH "\t, input logic clock2x\n";
    }
    foreach (@components) {
        my @portlist = @{$component_portlists{$_}};
        foreach my $port (@portlist) {
            #skip clocks and reset
            my $port_name = $port->{'name'};
            if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                next;
            }
            #component ports
            print OFH "\t, $port->{'dir'} logic $port->{'range'} ${_}_$port->{'name'}\n";
        }
    }
    print OFH "\t);\n\n";

    if ($qii_io_regs) {
        #declare registers
        foreach (@components) {
            my @portlist = @{$component_portlists{$_}};
            foreach my $port (@portlist) {
                my $port_name = $port->{'name'};
                #skip clocks and reset
                if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                    next;
                }
                print OFH "\tlogic $port->{'range'} ${_}_${port_name}_reg;\n";
            }
        }

        #wire registers
        foreach (@components) {
            my @portlist = @{$component_portlists{$_}};
            print OFH "\n\n\talways @(posedge clock) begin\n";
            foreach my $port (@portlist) {
                my $port_name = "$port->{'name'}";
                #skip clocks and reset
                if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                    next;
                }

                $port_name = "${_}_${port_name}";
                if ($port->{'dir'} eq "input") {
                    print OFH "\t\t${port_name}_reg <= ${port_name};\n";
                } else {
                    print OFH "\t\t${port_name} <= ${port_name}_reg;\n";
                }
            }
            print OFH "\tend\n";
        }
    }

    #reset synchronizer
    print OFH "\n\n\treg [2:0] sync_resetn;\n";
    print OFH "\talways @(posedge clock or negedge resetn) begin\n";
    print OFH "\t\tif (!resetn) begin\n";
    print OFH "\t\t\tsync_resetn <= 3'b0;\n";
    print OFH "\t\tend else begin\n";
    print OFH "\t\t\tsync_resetn <= {sync_resetn[1:0], 1'b1};\n";
    print OFH "\t\tend\n";
    print OFH "\tend\n";

    #component instances
    my $comp_idx = 0;
    foreach (@components) {
        my @portlist = @{$component_portlists{$_}};
        print OFH "\n\n\t${_} ${_}_inst (\n";
        print OFH "\t\t  .resetn(sync_resetn[2])\n";
        print OFH "\t\t, .clock(clock)\n";
        if (exists $clock2x_used{$_}) {
            print OFH "\t\t, .clock2x(clock2x)\n";
        }
        foreach my $port (@portlist) {
            my $port_name = $port->{'name'};
            #skip clocks and reset
            if ($port_name eq "resetn" or $port_name eq "clock" or $port_name eq "clock2x") {
                next;
            }
            my $reg_name_suffix = $qii_io_regs ? "_reg" : "";
            my $reg_name = "${_}_${port_name}${reg_name_suffix}";
            print OFH "\t\t, .${port_name}(${reg_name})\n";
        }
        print OFH "\t);\n\n";
        $comp_idx = $comp_idx + 1
    }
    print OFH "\n\nendmodule\n";
    close(OFH);

    return scalar keys %clock2x_used;
}

sub generate_qpf($@) {
  my ($qii_project_name) = @_;
  open (OUT_QPF, ">${qii_project_name}.qpf") or die;
  print OUT_QPF "# This Quartus project file sets up a project to measure the area and fmax of\n";
  print OUT_QPF "# your components in a full Quartus compilation for the targeted device\n";
  print OUT_QPF "PROJECT_REVISION = ${qii_project_name}";
  close (OUT_QPF);
}

sub generate_qsf($@) {
    my ($qii_project_name, @components) = @_;

    my $qsys_ext  = qii_is_pro() ? ".ip" : ".qsys";
    my $qsys_type = qii_is_pro() ? "IP" : "QSYS";

    open (OUT_QSF, ">${qii_project_name}.qsf") or die;
    print OUT_QSF "# This Quartus settings file sets up a project to measure the area and fmax of\n";
    print OUT_QSF "# your components in a full Quartus compilation for the targeted device\n";
    print OUT_QSF "\n";
    print OUT_QSF "# Family and device are derived from the -march argument to i++\n";
    print OUT_QSF "set_global_assignment -name FAMILY \"${dev_family}\"\n";
    print OUT_QSF "set_global_assignment -name DEVICE ${dev_part}\n";

    print OUT_QSF "# This script parses the Quartus reports and generates a summary that can be viewed via reports/report.html or reports/lib/json/quartus.json\n";
    # add call to parsing script after STA is run
    my $qii_rpt_tcl = "generate_report.tcl";
    print OUT_QSF "set_global_assignment -name POST_FLOW_SCRIPT_FILE \"quartus_sh:${qii_rpt_tcl}\"\n";

    print OUT_QSF "\n";
    print OUT_QSF "# Files implementing a basic registered instance of each component\n";
    print OUT_QSF "set_global_assignment -name TOP_LEVEL_ENTITY ${qii_project_name}\n";
    print OUT_QSF "set_global_assignment -name SDC_FILE ${qii_project_name}.sdc\n";
    # add component Qsys files to project
    foreach (@components) {
      print OUT_QSF "set_global_assignment -name ${qsys_type}_FILE ../components/$_/$_$qsys_ext\n";
    }
    # add generated top level verilog file to project
    print OUT_QSF "set_global_assignment -name SYSTEMVERILOG_FILE ${qii_project_name}.sv\n";

    print OUT_QSF "\n";
    print OUT_QSF "# Partitions are used to separate the component logic from the project harness when tallying area results\n";
    print OUT_QSF "set_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id component_partition\n";
    print OUT_QSF "set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id component_partition\n";
    foreach (@components) {
      if (qii_is_pro()) {
        print OUT_QSF "set_instance_assignment -name PARTITION component_${_} -to \"${_}:${_}_inst\"\n";
      } else {
        print OUT_QSF "set_instance_assignment -name PARTITION_HIERARCHY component_${_} -to \"${_}:${_}_inst\" -section_id component_partition\n";
      }
    }

    print OUT_QSF "\n";
    print OUT_QSF "# No need to generate a bitstream for this compile so save time by skipping the assembler\n";
    print OUT_QSF "set_global_assignment -name FLOW_DISABLE_ASSEMBLER ON\n";

    print OUT_QSF "\n";
    print OUT_QSF "# Use the --quartus-seed flag to i++, or modify this setting to run other seeds\n";
    my $seed = 0;
    my $seed_comment = "# ";
    if (defined $qii_seed ) {
      $seed = $qii_seed;
      $seed_comment = "";
    }
    print OUT_QSF $seed_comment."set_global_assignment -name SEED $seed";


    print OUT_QSF "\n";
    print OUT_QSF "# This assignment configures all component I/Os as virtual pins to more accurately\n";
    print OUT_QSF "# model placement and routing in a larger system\n";
    my $qii_vpins_comment = "# ";
    if ($qii_vpins) {
      $qii_vpins_comment = "";
    }
    print OUT_QSF $qii_vpins_comment."set_instance_assignment -name VIRTUAL_PIN ON -to *";

    close(OUT_QSF);
}

sub generate_sdc($$) {
  my ($qii_project_name, $clock2x_used) = @_;

  open (OUT_SDC, ">${qii_project_name}.sdc") or die;
  print OUT_SDC "create_clock -period 1 clock\n";                                                                                                          
  if ($clock2x_used) {                                                                                                                                        
    print OUT_SDC "create_clock -period 0.5 clock2x\n";                                                                                           
  }                                                                                                                                                           
  close (OUT_SDC);
}

sub generate_quartus_ini() {
  open(OUT_INI, ">quartus.ini") or die;
  if ($qii_dsp_packed) {
    print OUT_INI "fsv_mac_merge_for_density=on\n";
  }
  close(OUT_INI);
}

sub generate_report_script($@) {
  my ($qii_project_name, $clock2x_used, @components) = @_;
  my $qii_rpt_tcl = acl::Env::sdk_root()."/share/lib/tcl/quartus_compile_report.tcl";
  my $html_rpt_tcl = acl::Env::sdk_root()."/share/lib/tcl/quartus_html_report.tcl";
  open(OUT_TCL, ">generate_report.tcl") or die;
  print OUT_TCL "# This script has the logic to create a summary report\n";
  print OUT_TCL "source $qii_rpt_tcl\n";
  print OUT_TCL "source $html_rpt_tcl\n";
  print OUT_TCL "# These are generated by i++ based on the components\n";
  print OUT_TCL "set show_clk2x   $clock2x_used\n";
  print OUT_TCL "set components   [list " . join(" ", @components) . "]\n";
  print OUT_TCL "# This is where we'll generate the report\n";
  print OUT_TCL "set report_name  \"../reports/lib/json/quartus.json\"\n";
  print OUT_TCL "# These get sent to the script by Quartus\n";
  print OUT_TCL "set project_name [lindex \$quartus(args) 1]\n";
  print OUT_TCL "set project_rev  [lindex \$quartus(args) 2]\n";
  print OUT_TCL "# This call creates the report\n";
  print OUT_TCL "generate_hls_report \$project_name \$project_rev \$report_name \$show_clk2x \$components\n"; 
  print OUT_TCL "update_html_report_data\n";
  close(OUT_TCL);
}

sub generate_qii_project {
    # change to the working directory
    chdir $g_work_dir or mydie("Can't change into dir $g_work_dir: $!\n");
    my @components = get_generated_components();
    if (not -d "$quartus_work_dir") {
        mkdir "$quartus_work_dir" or mydie("Can't make dir $quartus_work_dir: $!\n");
    }
    chdir "$quartus_work_dir" or mydie("Can't change into dir $quartus_work_dir: $!\n");

    my $clock2x_used = generate_top_level_qii_verilog($qii_project_name, @components);
    generate_report_script($qii_project_name, $clock2x_used, @components);
    generate_qsf($qii_project_name, @components);
    generate_qpf($qii_project_name);
    generate_sdc($qii_project_name, $clock2x_used);
    generate_quartus_ini();

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
}

sub compile_qii_project($) {
    my ($qii_project_name) = @_;

    # change to the working directory
    chdir $g_work_dir."/$quartus_work_dir" or mydie("Can't change into dir $g_work_dir/$quartus_work_dir: $!\n");

    @cmd_list = ('quartus_sh',
            "--flow",
            "compile",
            "$qii_project_name");

    mysystem_full(
        {'stdout' => $project_log, 
         'stderr' => $project_log, 
         'out_is_temporary' => '0',
         'err_is_temporary' => '0',
         'title' => 'run Quartus compile'}, 
        @cmd_list) == 0 or mydie();

    # change back to original directory
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
}

# Accept a filename dir/base.ext and return (dir/base, .ext)
sub parse_extension {
  my $filename = shift;
  my ($ext) = $filename =~ /(\.[^.\/\\]+)$/;
  my $base = $filename;
  if(defined $ext) {
    $base =~ s/$ext$//;
  }
  return ($base, $ext);
}

sub run_quartus_compile($) {
    my ($qii_project_name) = @_;
    print "Run Quartus\n" if $verbose;
    compile_qii_project($qii_project_name);
}

sub main {
    my $cmd_line = $prog . " " . join(" ", @ARGV);
    $all_ipp_args = $cmd_line;
    if ( isWindowsOS() ){
      $default_object_extension = ".obj";
    }    
    parse_args();

    if ( $emulator_flow ) {$macro_type_string = "NONE";}
    else                  {$macro_type_string = "VERILOG";}

    # Process all source files one by one
    while ($#source_list >= 0) {
      my $source_file = shift @source_list;
      my $object_name = undef;
      if($object_only_flow_modifier) {
        if ( !($project_name eq 'a') or !($executable eq isWindowsOS() ? "a.exe" : "a.out")) {
          # -c, so -o name applies to object file, don't add .o
          $object_name = $project_name;
        } else {
          # reuse source base name
          $object_name = get_name_core($source_file).$default_object_extension;
        }
      } else {
          # object file name is temporary, make sure we do not collide with parallel compiles
          $object_name = get_name_core($source_file).$$.$default_object_extension;
      }

      my $work_dir=$object_name.'.'.$$.'.tmp';
      if ( $emulator_flow ) {
        my $work_dir=$object_name.'.'.$$.'.tmp';
        acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);
        push @cleanup_list, $work_dir;

        emulator_compile($source_file, $object_name, $work_dir);
      } else {
        my $work_dir=$object_name.'.'.$$.'.tmp';
        acl::File::make_path($work_dir) or mydie($acl::File::error.' While trying to create '.$work_dir);
        push @cleanup_list, $work_dir;

        if (!$RTL_only_flow_modifier && !$soft_ip_c_flow_modifier) {
          testbench_compile($source_file, $object_name, $work_dir);
        } else {
          remove_named_files($object_name);
        }
        fpga_parse($source_file, $object_name, $work_dir);
      }
    }

    if ($object_only_flow_modifier) { myexit('Object generation'); }

    setup_linkstep($cmd_line) unless  ($x86_linkstep_only); #unpack objects and setup project directory

    if (!$emulator_flow && !$x86_linkstep_only) {
      # Now do the 'real' compiles depend link step, wich includes llvm compile for
      # testbench and components
      if ($#fpga_IR_list >= 0) {
        find_board_spec();
        generate_fpga(@fpga_IR_list);
      }

      if (!($cosim_simulator eq "NONE") && $#fpga_IR_list >= 0) {
        hls_sim_generate_verilog(get_name_core($project_name)) if not $RTL_only_flow_modifier;
      }

      if ($#fpga_IR_list >= 0) {
        generate_qii_project();
      }

      # Run ModelSim compilation,
      if ($#fpga_IR_list >= 0) {
        compile_verification_project() if not $RTL_only_flow_modifier;
      } 
    } #emulation

    if (!$cosim_linkstep_only && $#object_list >= 0) {
      link_x86($executable, $emulator_flow);
    }

    # Run Quartus compile
    if ($qii_flow && $#fpga_IR_list >= 0) {
      run_quartus_compile($qii_project_name);
    }

    myexit("Main flow");
}

main;
