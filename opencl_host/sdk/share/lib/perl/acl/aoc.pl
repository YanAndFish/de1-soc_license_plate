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


# Intel(R) FPGA SDK for OpenCL(TM) kernel compiler.
#  Inputs:  A .cl file containing all the kernels
#  Output:  A subdirectory containing: 
#              Design template
#              Verilog source for the kernels
#              System definition header file
#
# 
# Example:
#     Command:       aoc foobar.cl
#     Generates:     
#        Subdirectory foobar including key files:
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

require acl::Board_migrate;
require acl::Common;
require acl::Env;
require acl::File;
require acl::Incremental;
require acl::Pkg;
require acl::Report;
require acl::Simulator;
use acl::AOCDriverCommon;
use acl::AOCInputParser;
use acl::AOCOpenCLStage;
use acl::Report qw(escape_string);

$dft_opt_passes = ' -march=fpga -O3';
$soft_ip_opt_passes = ' -tbaa -basicaa -simplifycfg -scalarrepl -early-cse -lower-expect -barrier -globalopt -ipconstprop -deadargelim -instcombine -simplifycfg -prune-eh -inline -inline-threshold=10000000 -inlinehint-threshold=100000000 -pragma-unroll-threshold=100000000 -functionattrs -argpromotion -scalarrepl-ssa -early-cse -simplify-libcalls -jump-threading -attributepropagation -correlated-propagation -simplifycfg -instcombine -tailcallelim -simplifycfg  -reassociate -loop-rotate -licm -loop-unswitch-threshold=0 -loop-unswitch -instcombine -indvars -loop-idiom -loop-deletion -gvn -memcpyopt  -sccp -instcombine -jump-threading -correlated-propagation -dse -adce -simplifycfg -instcombine -strip-dead-prototypes -globaldce -constmerge -barrier -loop-simplify -lcssa -loop-unroll -gvn -memcpyopt -sccp -instcombine -jump-threading -correlated-propagation -dse -adce -simplifycfg -instcombine -strip-dead-prototypes -globaldce -constmerge -barrier -always-inline -stripnk -normret -dgvue -acl-load-store-intrinsics-add -convert-iord-iowr-to-intrinsics -lowerconv -dce -lowerconst -always-remove-mem-intrinsics -scalarrepl -priv2reg -promotepriv -instcombine -dce -fixup-bitcasts -lmem-splitter -verify -normls -attributepropagation -gvn -dce -simplifycfg  -lstructify -instcombine-no-v -scalarize-large-aggregates -scalarrepl -fixup-bitcasts -lowerswitch -scalarize -dce -adce -gvn -dce -instcombine -trivial-math -simplify-fp -dce -indexswapping -transform-printf -loop-simplify -lcssa -seloop  -simplifycfg -mergereturn -branch-conversion2 -dce -instcombine -vectorize-kernel -verify -gvn -instcombine -dce -verify -remove-dead-stores -dce -verify -merge-predicated-stores -dce -instcombine -annotate-coalescing-bounds -kernel-duplicator -dce -verify  -memorycoalescing -verify -gvn -dce -verify -scalarreduction -licm -loop-combine -licm -mergereturn -simplifycfg -lowerswitch -gvn -trivial-math -dce -setalignments -verify  -reduce-resources -dce -verify  -adjust-sizes -simplifycfg -lowerswitch -win -barrierstyle -instcombine -dce -mem-bank-port-assignment -loadstorestyle -lwglinsert -rematerialize -dce -loadstorestyle -throughput-annotate -kernel-selector -dce -verify -convert-integer-multipliers -instcombine -dce -adjust-sizes -verify  -fuse-trigonometric-functions -double-pump-fp-unit -instcombine -dce -fpc-decomposition -instcombine -dce -fpc-conversion-removal -instcombine -dce -fpc-dynamic-align -instcombine -dce -simplify-fp -dce -adjust-sizes -verify -floatingpointstyle  -expose-live-values -loop-pipelining -dce -resource-sharing -throughput-print -verify -fpgaverify';

my $UPLIFT_TODO = 0; # // UPLIFT TODO: remove this variable.

my $clang_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-clang";
my $opt_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-opt";
my $link_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-link";
my $llc_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-llc";
my $sysinteg_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/system_integrator";
my $aocl_libedit_exe = "aocl library";

sub print_bsp_msgs($@)
 { 
     my $infile = shift @_;
     my $verbose = acl::Common::get_verbose();
     open(IN, "<$infile") or acl::Common::mydie("Failed to open $infile");
     while( <IN> ) {
       # E.g. Error: BSP_MSG: This is an error message from the BSP
       if( $_ =~ /BSP_MSG:/ ){
         my $filtered_line = $_;
         $filtered_line =~ s/BSP_MSG: *//g;
         if( $filtered_line =~ /^ *Error/ ) {
           print STDERR "$filtered_line";
         } elsif ( $filtered_line =~ /^ *Critical Warning/ ) {
           print STDOUT "$filtered_line";
         } elsif ( $filtered_line =~ /^ *Warning/ && $verbose > 0) {
           print STDOUT "$filtered_line";
         } elsif ( $verbose > 1) {
           print STDOUT "$filtered_line";
         }
       }
     }
     close IN;
 }

sub print_quartus_errors($@)
{ #filename
  my $infile = shift @_;
  my $flag_recomendation = shift @_;
  my $win_longpath_flag = 0;
  
  open(ERR, "<$infile") or acl::Common::mydie("Failed to open $infile");
  while( my $line = <ERR> ) {
    if( $line =~ /^Error/ ) {
      if( acl::AOCDriverCommon::hard_routing_error_code( $line ) && $flag_recomendation ) {
        print STDERR "Error: Kernel fit error, recommend using --high-effort.\n";
      }
      if( acl::AOCDriverCommon::kernel_fit_error( $line ) ) {
        acl::Common::mydie("Cannot fit kernel(s) on device");
      }
      elsif ( acl::AOCDriverCommon::win_longpath_error_quartus( $line ) ) {
        $win_longpath_flag = 1;
        print $line;
      }
      elsif ($line =~ /Error\s*(?:\(\d+\))?:/) {
        print $line;
      }
    }
    if( $line =~ /Path name is too long/ ) {
      $win_longpath_flag = 1;
      print $line;
    }
  }
  close ERR;
  print $win_longpath_suggest if ($win_longpath_flag and acl::Env::is_windows());
  acl::Common::mydie("Compiler Error, not able to generate hardware\n");
}

# Do setup checks:
sub check_env {
  my ($board_variant,$bsp_flow_name) = @_;
  my $verbose = acl::Common::get_verbose();
  if ($do_env_check and not $emulator_fast) {
    # Is clang on the path?
    acl::Common::mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-clang$exesuffix) can not be found")  unless -x $clang_exe.$exesuffix; 
    # Do we have a license?
    my $clang_output = `$clang_exe --version 2>&1`;
    chomp $clang_output;
    if ($clang_output =~ /Could not acquire OpenCL SDK license/ ) {
      acl::Common::mydie("$prog: Cannot find a valid license for the Intel(R) FPGA SDK for OpenCL(TM)\n");
    }
    if ($clang_output !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
      print "$prog: Clang version: $clang_output\n" if $verbose||$regtest_mode;
      if ($^O !~ m/MSWin/ and ($verbose||$regtest_mode)) {
        my $ld_library_path="$ENV{'LD_LIBRARY_PATH'}";
        print "LD_LIBRARY_PATH is : $ld_library_path\n";
        foreach my $lib_dir (split (':', $ld_library_path)) {
          if( $lib_dir =~ /dspba/){
            if (! -d $lib_dir ){
              print "The library path: $lib_dir does not exist\n";
            }
          }
        }
      }
      my $failure_cause = "The cause of failure cannot be determined. Run executable manually and watch for error messages.\n";
      # Common cause on linux is an old libstdc++ library. Check for this here.
      if ($^O !~ m/MSWin/) {
        my $clang_err_out = `$clang_exe 2>&1 >/dev/null`;
        if ($clang_err_out =~ m!GLIBCXX_!) {
          $failure_cause = "Cause: Available libstdc++ library is too old. You're probably using an unsupported version of Linux OS. " .
                           "A quick work-around for this is to get latest version of gcc (at least 4.4) and do:\n" .
                           "  export LD_LIBRARY_PATH=<gcc_path>/lib64:\$LD_LIBRARY_PATH\n";
        }
      }
      acl::Common::mydie("$prog: Executable $clang_exe exists but is not working!\n\n$failure_cause");
    }

    # Is /opt/llc/system_integrator on the path?
    acl::Common::mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-opt$exesuffix) can not be found")  unless -x $opt_exe.$exesuffix;
    my $opt_out = `$opt_exe  --version 2>&1`;
    chomp $opt_out; 
    if ($opt_out !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
      acl::Common::mydie("$prog: Cannot find a working version of executable (aocl-opt$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
    }
    acl::Common::mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-llc$exesuffix) can not be found")  unless -x $llc_exe.$exesuffix; 
    my $llc_out = `$llc_exe --version`;
    chomp $llc_out; 
    if ($llc_out !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
      acl::Common::mydie("$prog: Cannot find a working version of executable (aocl-llc$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
    }
    acl::Common::mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (system_integrator$exesuffix) can not be found")  unless -x $sysinteg_exe.$exesuffix; 
    my $system_integ = `$sysinteg_exe --help`;
    chomp $system_integ;
    if ($system_integ !~ /system_integrator - Create complete OpenCL system with kernels and a target board/ ) {
      acl::Common::mydie("$prog: Cannot find a working version of executable (system_integrator$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
    }
  }

  if ($do_env_check and $emulator_fast) {
    # Is the Intel offline compiler (ioc64) on the path?
    my $ioc_location = acl::File::which_full ($ioc_exe); chomp $ioc_location;
    acl::Common::mydie ("$prog: The Intel(R) Kernel Builder for OpenCL(TM) compiler ($ioc_exe$exesuffix) can not be found")  unless defined $ioc_location;
    my $ioc_output = `$ioc_exe -version`;
    chomp $ioc_output;
    if ($ioc_output !~ /Kernel Builder for OpenCL API/ && $ioc_output !~ /Intel\(R\) SDK for OpenCL\(TM\)/) {
      if ($^O !~ m/MSWin/ and ($verbose||$regtest_mode)) {
        my $ld_library_path="$ENV{'LD_LIBRARY_PATH'}";
        print "LD_LIBRARY_PATH is : $ld_library_path\n";
      }
      acl::Common::mydie("$prog: Executable $ioc_exe exists but is not working!\n\n");
    }
  }

  my %q_info;
  if (not $standalone)
  {
    # Is Quartus on the path?
    $ENV{QUARTUS_OPENCL_SDK}=1; #Tell Quartus that we are OpenCL
    my $q_out = `quartus_sh --version`;
    $QUARTUS_VERSION = $q_out;

    chomp $q_out;
    if ($q_out eq "") {
      print STDERR "$prog: Quartus is not on the path!\n";
      print STDERR "$prog: Is it installed on your system and quartus bin directory added to PATH environment variable?\n";
      exit 1;
    }

    # Is it right Quartus version?
    my $q_ok = 0;
    $q_info{version} = "";
    $q_info{pro} = 0;
    $q_info{prime} = 0;
    $q_info{internal} = 0;
    $q_info{site} = '';
    my $req_qversion_str = exists($ENV{ACL_ACDS_VERSION_OVERRIDE}) ? $ENV{ACL_ACDS_VERSION_OVERRIDE} : "18.1.0";
    my $req_qversion = acl::Env::get_quartus_version($req_qversion_str);

    foreach my $line (split ('\n', $q_out)) {
      # With QXP flow should be compatible with future versions

      # Do version check.
      my ($qversion_str) = ($line =~ m/Version (\S+)/);
      $q_info{version} = acl::Env::get_quartus_version($qversion_str);
      if(acl::Env::are_quartus_versions_compatible($req_qversion, $q_info{version})) {
        $q_ok++;
      }

      # check if Internal version
      if ($line =~ /Internal/) {
        $q_info{internal}++;
      }

      # check which site it is from
      if ($line =~ m/\s+([A-Z][A-Z])\s+/) {
        $q_info{site} = $1;
      }

      # Need this to bypass version check for internal testing with ACDS 15.0.
      if ($line =~ /Prime/) {
        $q_info{prime}++;
      }
      if ($line =~ /Pro Edition/) {
        $q_info{pro}++;
        $is_pro_mode = 1;
      }
    }
    if ($do_env_check && $q_ok != 1) {
      print STDERR "$prog: The following ACDS version was found: \n$q_out\n";
      print STDERR "This ACDS version is not supported by this release of the Intel(R) FPGA SDK for OpenCL(TM), which is of version $req_qversion_str.\n";
      exit 1;
    }
    if ($do_env_check && $q_info{prime} == 1 && $q_info{pro} != 1) {
      print STDERR "$prog: This release of the Intel(R) FPGA SDK for OpenCL(TM) requires Quartus Prime Pro Edition.";
      print STDERR " However, the following version was found: \n$q_out\n";
      exit 1;
    }
  
    # Is it Quartus Prime Standard or Pro device?
    my $acl_board_hw_path = acl::AOCDriverCommon::get_acl_board_hw_path($board_variant);
    my $board_spec_xml = acl::AOCDriverCommon::find_board_spec($acl_board_hw_path);
    if( ! $bsp_flow_name ) {
      $bsp_flow_name = ":".acl::Env::aocl_boardspec( "$board_spec_xml", "defaultname" );
    }
    $target_model = acl::Env::aocl_boardspec( "$board_spec_xml", "targetmodel".$bsp_flow_name);
    $bsp_version = acl::Env::aocl_boardspec( "$board_spec_xml", "version");

    ( $target_model !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n");
    $target_model =~ s/_tm.xml//;

    if ($do_env_check) {
      if (($q_info{prime} == 1) && ($q_info{pro} == 1) && ($target_model !~ /^arria10/ && $target_model !~ /^stratix10/ && $target_model !~ /^cyclone10/)) {
        print STDERR "$prog: Use Quartus Prime Standard Edition for non A10/S10/C10GX devices.";
        print STDERR " Current Quartus Version is: \n$q_out\n";
        exit 1;
      }
    }
  }
  
  # Compile Check: fast|aggressive compiles|incremental
  if ($fast_compile && $high_effort_compile) {
    acl::Common::mydie("Illegal argument combination: cannot specify both fast-compile and high-effort compile options\n");
  }

  if ($fast_compile) {
    if ($target_model !~ /(^arria10)|(^stratix10)/) {
      acl::Common::mydie("Fast compile is not supported on your device family.\n");
    }
    if ($target_model =~ /^stratix10/) {
      print "Warning: Fast compile on S10 device family is preliminary and has limited support.\n";
    }
  }
  if ($high_effort_compile) {
    if ($target_model !~ /(^arria10)|(^stratix10)/) {
      acl::Common::mydie("High effort compile is not supported on your device family.\n");
    }
  }
  if ($incremental_compile) {
    if ($target_model =~ /^stratix10/) {
      print "Warning: Incremental compile on S10 device family is preliminary and has limited support.\n";
    }

    # To support empty kernel flow on incremental, need to add check to see if user's empty-kernel file has changed
    # Error out unless someone has a use case for this
    if ($empty_kernel_flow) {
      acl::Common::mydie("-empty-kernel flag is not supported with incremental compiles\n");
    }
  }

  # If here, everything checks out fine.
  print "$prog: Environment checks are completed successfully.\n" if $verbose;
  return %q_info;
}

sub extract_atoms_from_postfit_netlist($$$$) {
  my ($base,$location,$atom,$bsp_flow_name) = @_;

   # Grab DSP location constraints from specified Quartus compile directory  
    my $script_abs_path = acl::File::abs_path( acl::Env::sdk_root()."/ip/board/bsp/extract_atom_locations_from_postfit_netlist.tcl"); 

    # Pre-process relativ or absolute location
    my $location_dir = '';
    if (substr($location,0,1) eq '/') {
      # Path is already absolute
      $location_dir = $location;
    } else {
      # Path is currently relative
      $location_dir = acl::File::abs_path("../$location");
    }
      
    # Error out if reference compile directory not found
    if (! -d $location_dir) {
      acl::Common::mydie("Directory '$location' for $atom locations does not exist!\n");
    }

    # Error out if reference compile board target does not match
    my $current_board = ::acl::Env::aocl_boardspec( ".", "name");
    my $reference_board = ::acl::Env::aocl_boardspec( $location_dir, "name");
    if ($current_board ne $reference_board) {
      acl::Common::mydie("Reference compile board name '$reference_board' and current compile board name '$current_board' do not match!\n");
    };

    my $project = ::acl::Env::aocl_boardspec( ".", "project".$bsp_flow_name);
    my $revision = ::acl::Env::aocl_boardspec( ".", "revision".$bsp_flow_name);
    ( $project.$revision !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n");
    chomp $revision;
    if (defined $ENV{ACL_QSH_REVISION})
    {
      # Environment variable ACL_QSH_REVISION can be used
      # replace default revision (internal use only).  
      $revision = $ENV{ACL_QSH_REVISION};
    }
    my $current_compile = acl::File::mybasename($location);
    my $cmd = "cd $location_dir;quartus_cdb -t $script_abs_path $atom $current_compile $base $project $revision;cd $work_dir";
    print "$prog: Extracting $atom locations from '$location' compile directory (from '$revision' revision)\n";
    my $locationoutput_full = `$cmd`;

    # Error out if project cannot be opened   
    (my $locationoutput_projecterror) = $locationoutput_full =~ /(Error\: ERROR\: Project does not exist.*)/s;
    if ($locationoutput_projecterror) {
      acl::Common::mydie("Project '$project' and revision '$revision' in directory '$location' does not exist!\n");
    }
 
    # Error out if atom netlist cannot be read
    (my $locationoutput_netlisterror) = $locationoutput_full =~ /(Error\: ERROR\: Cannot read atom netlist.*)/s;
    if ($locationoutput_netlisterror) {
      acl::Common::mydie("Cannot read atom netlist from revision '$revision' in directory '$location'!\n");
    }

    # Add location constraints to current Quartus compile directory
    (my $locationoutput) = $locationoutput_full =~ /(\# $atom locations.*)\# $atom locations END/s;
    my @designs = acl::File::simple_glob( "*.qsf" );
    $#designs > -1 or acl::Common::mydie ("Internal Compiler Error. $atom location argument was passed but could not find any qsf files\n");
    foreach (@designs) {
      my $qsf = $_;
      open(my $fd, ">>$qsf");
      print $fd "\n";
      print $fd $locationoutput;
      close($fd);
    }
}

sub remove_intermediate_files($$) {
   my ($dir,$exceptfile) = @_;
   my $verbose = acl::Common::get_verbose();
   my $thedir = "$dir/.";
   my $thisdir = "$dir/..";
   my %is_exception = (
      $exceptfile => 1,
      "$dir/." => 1,
      "$dir/.." => 1,
   );
   foreach my $file ( acl::File::simple_glob( "$dir/*", { all => 1 } ) ) {
      if ( $is_exception{$file} ) {
         next;
      }
      if ( $file =~ m/\.aclx$/ ) {
         next if $exceptfile eq acl::File::abs_path($file);
      }
      acl::File::remove_tree( $file, { verbose => $verbose, dry_run => 0 } )
         or acl::Common::mydie("Cannot remove intermediate files under directory $dir: $acl::File::error\n");
   }
   # If output file is outside the intermediate dir, then can remove the intermediate dir
   my $files_remain = 0;
   foreach my $file ( acl::File::simple_glob( "$dir/*", { all => 1 } ) ) {
      next if $file eq "$dir/.";
      next if $file eq "$dir/..";
      $files_remain = 1;
      last;
   }
   unless ( $files_remain ) { rmdir $dir; }
}

sub create_object {
  my ($base, $input_work_dir, $src, $obj, $board_variant, $using_default_board, $all_aoc_args) = @_;

  my $pkg_file_final = $obj;
  (my $src_pkg_file_final = $obj) =~ s/aoco/source/;
  my $pkg_file = acl::Common::set_package_file_name($pkg_file_final);
  my $src_pkg_file = acl::Common::set_source_package_file_name($src_pkg_file_final.".tmp");
  my $verbose = acl::Common::get_verbose();
  my $quiet_mode = acl::Common::get_quiet_mode();
  my $save_temps = acl::Common::get_save_temps();
  $fulllog = "$base.log"; #definition moved to global space

  #Create the new direcory verbatim, then rewrite it to not contain spaces
  $work_dir = $input_work_dir;
  acl::File::make_path($work_dir) or acl::Common::mydie("Cannot create temporary directory $work_dir: $!");

  my $acl_board_hw_path = acl::AOCDriverCommon::get_acl_board_hw_path($board_variant);

  # If just packaging an HDL library component, call 'aocl library' and be done with it.
  if ($hdl_comp_pkg_flow) {
    print "$prog: Packaging HDL component for library inclusion\n" if $verbose||$report;
    $return_status = acl::Common::mysystem_full(
        {'time' => 1, 'time-label' => 'aocl library'},
        "$aocl_libedit_exe -c \"$src\" -o \"$obj\"");
    $return_status == 0 or acl::Common::mydie("Packing of HDL component FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    # remove temp directory
    acl::File::remove_tree($work_dir) unless $save_temps;
    return $return_status;
  }

  # Make sure the board specification file exists. This is needed by multiple stages of the compile.
  my $board_spec_xml = acl::AOCDriverCommon::find_board_spec($acl_board_hw_path);
  my $llvm_board_option = "-board $board_spec_xml";   # To be passed to LLVM executables.
  my $llvm_profilerconf_option = (defined $absolute_profilerconf_file ? "-profile-config $absolute_profilerconf_file" : ""); # To be passed to LLVM executables
  
  if (!$accel_gen_flow && !$soft_ip_c_flow) {
    my $default_text;
    if ($using_default_board) {
       $default_text = "default ";
    } else {
       $default_text = "";
    }
    print "$prog: Selected ${default_text}target board $board_variant\n" if $verbose||$report;
  }

  my $pkg = undef;
  my $src_pkg = undef;

  # OK, no turning back remove the result file, so no one thinks we succedded
  unlink $obj;
  unlink $src_pkg_file_final;

  if ( $soft_ip_c_flow ) {
      $clang_arg_after = "-x soft-ip-c -soft-ip-c-func-name=$soft_ip_c_name";
  } elsif ($accel_gen_flow ) {
      $clang_arg_after = "-x cl -soft-ip-c-func-name=$accel_name";
  }

  my $clangout = "$base.pre.bc";
  my @cmd_list = ();

  # Create package file in source directory, and save compile options.
  $pkg = create acl::Pkg($pkg_file);

  # Figure out the compiler triple for the current flow.

  my $fpga_triple = 'spir64-unknown-unknown-intelfpga';
  my $emulator_triple = ($emulator_arch eq 'windows64') ? 'x86_64-pc-windows-intelfpga' : 'x86_64-unknown-linux-intelfpga';
  my $cur_flow_triple = $emulator_flow ? $emulator_triple : $fpga_triple;
  
  my @triple_list;
  
  # Triple list to compute.
  if ($created_shared_aoco) {
    @triple_list = ($fpga_triple, 'x86_64-pc-windows-intelfpga', 'x86_64-unknown-linux-intelfpga');
  } else {
    @triple_list = ($cur_flow_triple);
  }

  my @metadata_compile_unit_flag = ();
  if ($emulator_flow){
    my $suffix =$src; 
    $suffix =~ s/.*\.//;
    my $outbase = $src; 
    $outbase =~ s/\.$suffix//;
    push (@metadata_compile_unit_flag, "-main-file-name");
    my $just_file_name = substr $outbase, rindex($outbase, '/') +1 ;
    $just_file_name .='_metadata';
    push @metadata_compile_unit_flag, $just_file_name;
  }

  # clang args that should apply to all compile flows.
  my @clang_common_args = ();
  if ($orig_force_initial_dir ne '') {
    # When the -initial-dir argument is used we need to ensure
    # relative include paths can be resolved relative to $orig_force_initial_dir
    # instead of the location of the .cl file.
    push(@clang_common_args, "-I$orig_force_initial_dir");
  }

  my $dep_file = "$work_dir/$base.d";
  if ( not $c_acceleration and not $emulator_fast) {
    print "$prog: Running OpenCL parser....\n" if (!$quiet_mode); 
    chdir $force_initial_dir or acl::Common::mydie("Cannot change into dir $force_initial_dir: $!\n");

    # Emulated flows to cover
    my @emu_list = $created_shared_aoco ? (0, 1) : $emulator_flow;

    # These two nested loops should produce either one clang call for regular compiles
    # Or three clang calls for three triples if -shared was specified: 
    #     (non-emulated, fpga), (emulated, linux), (emulated, windows)
    foreach my $emu_flow (@emu_list) {        
      foreach my $cur_triple (@triple_list) {
      
        # Skip {emulated_flow, triple} combinations that don't make sense
        if ($emu_flow and ($cur_triple =~ /spir/)) { next; }
        if (not $emu_flow and ($cur_triple !~ /spir/)) { next; }
        
        my $cur_clangout;
        if ($cur_triple eq $cur_flow_triple) {
          $cur_clangout = "$work_dir/$base.pre.bc";
        } else {
          $cur_clangout = "$work_dir/$base.pre." . $cur_triple . ".bc";
        }

        my @debug_options = ( $debug ? qw(-mllvm -debug) : ());

        #my @clang_std_opts = ( $emu_flow ? qw(-cc1 -target-abi opencl -emit-llvm-bc -mllvm -gen-efi-tb -Wuninitialized) : qw( -cc1 -emit-llvm-bc -O3 -cl-std=CL1.2 -disable-llvm-passes));
        my @clang_std_opts = ( $emu_flow ? qw(-cc1 -emit-llvm-bc -x cl -cl-std=CL1.2 -O3 -disable-llvm-passes) : qw( -cc1 -emit-llvm-bc -O3 -cl-std=CL1.2 -disable-llvm-passes));
        # UPLIFT - end change

        # Tell clang if compiling for FPGA.  Will change ABI to pass/return structs by value, etc.
        push(@clang_std_opts, '-ffpga') if !$emu_flow;

        my @board_options = map { ('-mllvm', $_) } split( /\s+/, $llvm_board_option );
        my @board_def = (
            "-DACL_BOARD_$board_variant=1", # Keep this around for backward compatibility
            "-DAOCL_BOARD_$board_variant=1",
            );
        my @clang_arg_after_array = split(/\s+/m,$clang_arg_after);
        my @clang_dependency_args = ( ($cur_triple eq $cur_flow_triple) ? ("-MT", "$base.bc", "-sys-header-deps", "-dependency-file", $dep_file) : ());
       
        # Add Vfs lib used for decryption
        my @clang_decryption_vfs = "";
        if (acl::Env::is_linux()) {
          @clang_decryption_vfs = "-ivfsoverlay-lib".acl::Env::sdk_root()."/linux64/lib/libaoc_clang_decrypt.so";
        }

        # UPLIFT - cmd below is a little diff than trunk. 
        # UPLIFT - Remove board options for UPLIFT, add -DINTELFPGA_CL
        @cmd_list = (
            $clang_exe,
            @clang_std_opts,
            "-DINTELFPGA_CL",
            $emulator_flow ? "-D__FPGA_EMULATION_X86__" : "",
            ('-triple',$cur_triple),
            @debug_options, 
            $src,
            @clang_arg_after_array,
            ('-include', $ocl_header),
            '-o',
            $cur_clangout,
            @clang_dependency_args,
            @user_clang_args,
            @metadata_compile_unit_flag,
            @clang_common_args,
            @clang_decryption_vfs
            );
        $return_status = acl::Common::mysystem_full(
            { 'stdout' => "$work_dir/clang.log",
              'stderr' => "$work_dir/clang.err",
              'time' => 1, 
              'time-label' => 'clang'},
            @cmd_list);

        # Only save warnings and errors corresponding to current flow triple.
        # Otherwise, will get all warnings in triplicate.
        my $banner = '!========== [clang] parse ==========';
        if ($cur_triple eq $cur_flow_triple) {
          acl::Common::move_to_log($banner, "$work_dir/clang.log", "$work_dir/$fulllog"); 
          acl::Report::append_to_log("$work_dir/clang.err", "$work_dir/$fulllog");
          acl::Report::append_to_err("$work_dir/clang.err");
          if ($return_status != 0 and $regtest_mode) {
            acl::Common::move_to_log($banner, "$work_dir/clang.err", $regtest_errlog);
          } else {
            unlink "$work_dir/clang.err";
          }
        }

        $return_status == 0 or acl::Common::mydie("OpenCL parser FAILED");

        # Save clang output to .aoco file. This will be used for creating
        # a library out of this file.
        # ".acl.clang_ir" section prefix name is also hard-coded into lib/libedit/inc/libedit.h!
        $pkg->set_file(".acl.clang_ir.$cur_triple", $cur_clangout)
             or acl::Common::mydie("Cannot save compiler object file $cur_clangout into package file: $acl::Pkg::error\n");
      }
    }
  } elsif ( $emulator_fast ) {
    my $ioc_output = $work_dir."/".$base.".ioc.obj";

    # get directory name for source file
    my $unix_style = acl::File::file_slashes($src);
    my $src_dirname = acl::File::mydirname($unix_style);

    my $ioc_cmd = "-cmd=compile";
    my $ioc_dev = "-device=fpga_fast_emu";
    my $ioc_opt;
    # Linux and Windows require slightly different quotes
    if (acl::Env::is_windows()) {
      $ioc_opt = "-bo=\"-cl-std=CL1.2 ".join(" ", @user_clang_args)." -I\\\"$src_dirname\\\"\"";
    } else {
      $ioc_opt = "-bo=-cl-std=CL1.2 ".join(" ", @user_clang_args)." -I\"$src_dirname\"";
    }
    my $ioc_inp = "-input=$src";
    my $ioc_out = "-ir=$ioc_output";

    @cmd_list = (
        $ioc_exe,
        $ioc_cmd,
        $ioc_dev,
        $ioc_opt,
        $ioc_inp,
        $ioc_out,
        @clang_common_args);

    $return_status = acl::Common::mysystem_full(
        { 'stdout' => "$work_dir/ioc.log",
        'stderr' => "$work_dir/ioc.err",
        'time' => 1,
        'time-label' => 'ioc'},
        @cmd_list);

    acl::Report::append_to_err("$work_dir/ioc.err");
    if ($return_status==0 or $regtest_mode==0) { unlink "$work_dir/ioc.err"; }

    if ($return_status != 0) {
      if ($regtest_mode) {
        acl::Common::move_to_log('!========== Fast Emulator - ioc ==========', "$work_dir/ioc.err", $regtest_errlog);
      }
      acl::Common::mydie("OpenCL kernel compilation FAILED");
    }

    # Go through ioc.log and print any errors or warnings.
    open(INPUT,"<$work_dir/ioc.log") or acl::Common::mydie("Cannot open $work_dir/ioc.log $!");
    my $start_printing = acl::Common::get_verbose() > 1;
    my $compile_failed = 0;
    while (my $line = <INPUT>) {
      $compile_failed = 1 if ($line =~ m/^Compilation failed!?$/);
      if (acl::Common::get_verbose() > 2) {
        print $line;
      } elsif ($line =~ m/^Compilation started$/) {
        $start_printing = 1;
      } elsif ($line =~ m/^Compilation failed$/ and $start_printing == 0) {
        $start_printing = 1;
      } elsif ($line =~ m/^Compilation failed!?$/) {
        $start_printing = 0 unless acl::Common::get_verbose();
      } elsif ($line =~ m/^Compilation done$/) {
        $start_printing = 0;
      } elsif ($start_printing) {
        print $line;
      }
    }
    close INPUT;

    acl::Common::mydie("OpenCL kernel compilation FAILED") if ($compile_failed);
    unlink $work_dir."/ioc.log" unless acl::Common::get_save_temps();

    # Save output to .aoco file.
    $pkg->set_file(".acl.ioc_obj", $ioc_output)
      or acl::Common::mydie("Cannot save compiler object file $ioc_output into package file: $acl::Pkg::error\n");
  }

  if ( $parse_only ) { 
    unlink $pkg_file;
    print "$prog: OpenCL parser completed \n" if (!$quiet_mode); 
    return;
  }

  if ( defined $program_hash ){ 
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.hash',$program_hash);
  }
  if ($emulator_flow) {
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.board',$emulatorDevice);
    if ($emulator_fast) {
      acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.target','emulator_fast');
    } else {
      acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.target','emulator');
    }
  } elsif ($new_sim_mode) {
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.board',"SimulatorDevice");
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.simulator_object',"");
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.target','simulator');
  } else {
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.board',$board_variant);
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.target','fpga');
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.board_package',acl::Board_env::get_board_path());
  }
  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.compileoptions',join(' ',@user_opencl_args));

  # Set version of the compiler, for informational use.
  # It will be set again when we actually produce executable contents.
  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());

  if ($emulator_fast) {
    print "$prog: OpenCL kernel compilation completed successfully.\n" if (!$quiet_mode);
  } else {
    # pacakge clangout and .d files into package
    $pkg->add_file('.acl.aoco',"$work_dir/$clangout");
    $pkg->add_file('.acl.dep',$dep_file);
    $pkg->add_file('.acl.clang_log',"$work_dir/$fulllog");
  
    print "$prog: OpenCL parser completed successfully.\n" if (!$quiet_mode);

    my $ll_file = $obj;
    $ll_file =~ s/.aoco/.pre.ll/g;
    # Clang already generates LLVM IR as text.
    acl::File::copy("$work_dir/$clangout", $ll_file) if $disassemble;
  }
    

  # remove temp directory
  acl::File::remove_tree($work_dir) unless $save_temps;
}

sub compile_design {
  my ($base,$final_work_dir,$obj,$x_file,$board_variant,$all_aoc_args,$bsp_flow_name) = @_;
  $fulllog = "$base.log"; #definition moved to global space
  my $pkgo_file = $obj; # Should have been created by first phase.
  my $pkg_file_final = $output_file || acl::File::abs_path("$base.aocx");
  my $pkg_file = acl::Common::set_package_file_name($pkg_file_final.".tmp");
  my $verbose = acl::Common::get_verbose();
  my $quiet_mode = acl::Common::get_quiet_mode();
  my $save_temps = acl::Common::get_save_temps();
  # copy partition file if it exists
  acl::File::copy( $save_partition_file, $work_dir."/saved_partitions.txt" ) if $save_partition_file ne '';
  acl::File::copy( $set_partition_file, $work_dir."/set_partitions.txt" ) if $set_partition_file ne '';

  # OK, no turning back remove the result file, so no one thinks we succedded
  unlink $pkg_file_final;
  #Create the new direcory verbatim, then rewrite it to not contain spaces
  $work_dir = $final_work_dir;
  # Get the absolute work dir without the base use by simulation temporary folder
  my $work_dir_no_base = acl::File::mydirname($work_dir);

  # To support relative BSP paths, access this before changing dir
  my $postqsys_script = acl::Env::board_post_qsys_script();

  # Check if pkgo_file for simulation or emulation
  my $pkgo = get acl::Pkg($pkgo_file)
     or acl::Common::mydie("Cannot find package file: $acl::Pkg::error\n");
  my $simulator = $pkgo->exists_section('.acl.simulator_object');
  if ($simulator && $skip_qsys) {
    # Invoke QSys to create testbench into a temp folder before changing dir
    $new_sim_mode = 1;
    acl::Simulator::opencl_create_sim_system($board_variant, 1, $work_dir_no_base, $work_dir."/".$base.".bc.xml");
  }

  chdir $work_dir or acl::Common::mydie("Cannot change dir into $work_dir: $!");

  # If using the fast emulator, just extract the emulator binary and be done with it.
  if ($pkgo->exists_section('.acl.fast_emulator_object.linux') ||
      $pkgo->exists_section('.acl.fast_emulator_object.windows')) {
    if ($pkgo->exists_section('.acl.fast_emulator_object.linux')) {
      $pkgo->get_file('.acl.fast_emulator_object.linux',$pkg_file_final);
    } elsif ($pkgo->exists_section('.acl.fast_emulator_object.windows')) {
      $pkgo->get_file('.acl.fast_emulator_object.windows',$pkg_file_final);
    }
    print "Emulator flow is successful.\n" if $verbose;
    print "To execute emulated kernel, ensure host code selects the Intel(R)\nFPGA OpenCL emulator platform.\n" if $verbose;

    return;
  }

  acl::File::copy( $pkgo_file, $pkg_file )
   or acl::Common::mydie("Cannot copy binary package file $pkgo_file to $pkg_file: $acl::File::error");
  my $pkg = get acl::Pkg($pkg_file)
     or acl::Common::mydie("Cannot find package file: $acl::Pkg::error\n");

  #Remember the reason we are here, cannot query pkg_file after rename
  my $emulator = $pkg->exists_section('.acl.emulator_object.linux') ||
      $pkg->exists_section('.acl.emulator_object.windows');

  if(!$emulator && !$simulator){
    $board_variant = acl::AOCDriverCommon::get_pkg_section($pkg,'.acl.board');
  }

  my $block_migrations_csv = join(',', @blocked_migrations);
  my $add_migrations_csv = join(',', @additional_migrations);
  if ( ! $no_automigrate && ! $emulator) {
    acl::Board_migrate::migrate_platform_preqsys($bsp_flow_name,$add_migrations_csv,$block_migrations_csv);
  }

  # Set version again, for informational purposes.
  # Do it again, because the second half flow is more authoritative
  # about the executable contents of the package file.
  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());

  if ($emulator) {
    unlink( $pkg_file_final ) if -f $pkg_file_final;
    rename( $pkg_file, $pkg_file_final )
      or acl::Common::mydie("Cannot rename $pkg_file to $pkg_file_final: $!");

    print "Emulator flow is successful.\n" if $verbose;
    print "To execute emulated kernel, invoke host with \n\tenv CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=1 <host_program>\n For multi device emulations replace the 1 with the number of devices you wish to emulate\n" if $verbose;

    return;
  }

  # print the message to indicate long processing time
  if ($new_sim_mode) {
    print "Compiling for Simulator.\n" if (!$quiet_mode);
  } else {
    print "Compiling for FPGA. This process may take a long time, please be patient.\n" if (!$quiet_mode);
  }

  if ( ! $skip_qsys) { 
    #Ignore SOPC Builder's return value
    my $sopc_builder_cmd = "qsys-script";
    my $ip_gen_cmd = 'qsys-generate';

    # Make sure both qsys-script and ip-generate are on the command line
    my $qsys_location = acl::File::which_full ("qsys-script"); chomp $qsys_location;
    if ( not defined $qsys_location ) {
       acl::Common::mydie ("Error: qsys-script executable not found!\n".
              "Add quartus bin directory to the front of the PATH to solve this problem.\n");
    }
    my $ip_gen_location = acl::File::which_full ("ip-generate"); chomp $ip_gen_location;
        
    # Run Java Runtime Engine with max heap size 512MB, and serial garbage collection.
    my $jre_tweaks = "-Xmx512M -XX:+UseSerialGC";

    my $windows_longpath_flag = 0;
    open LOG, "<sopc.tmp";
    while (my $line = <LOG>) {
      if ($line =~ /Error\s*(?:\(\d+\))?:/) {
        print $line;
        # Is this a windows long-path issue?
        $windows_longpath_flag = 1 if acl::AOCDriverCommon::win_longpath_error_quartus($line);
      }
    }
    print $win_longpath_suggest if ($windows_longpath_flag and acl::Env::is_windows());
    close LOG;

    # Parse the board spec for information on how the system is built
    my $version = ::acl::Env::aocl_boardspec( ".", "version".$bsp_flow_name);
    my $generic_kernel = ::acl::Env::aocl_boardspec( ".", "generic_kernel".$bsp_flow_name);
    my $qsys_file = ::acl::Env::aocl_boardspec( ".", "qsys_file".$bsp_flow_name);
    my $project = ::acl::Env::aocl_boardspec( ".", "project".$bsp_flow_name);
    ( $version.$generic_kernel.$qsys_file.$project !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n" );
    # Save the true project name for when we query the DEVICE from the Quartus project
    my $project_for_device = $project;

    # Simulation flow overrides
    if($new_sim_mode) {
      $project = "none";
      $generic_kernel = 1;
      $qsys_file = "none";
      $postqsys_script = "";
    }

    # Handle the new Qsys requirement for a --quartus-project flag from 16.0 -> 16.1
    my $qsys_quartus_project = ( $QUARTUS_VERSION =~ m/Version 16\.0/ ) ? "" : "--quartus-project=$project";

    # Build the kernel Qsys system
    my $acl_board_hw_path = acl::AOCDriverCommon::get_acl_board_hw_path($board_variant);

    # Skip Qsys (kernel_system.tcl => kernel_system.qsys)
    my $skip_kernel_system_qsys = ((!$new_sim_mode) and ($qsys_file eq "none") and ($bsp_version >= 18.0)) ? 1 : 0;

    if(!$skip_kernel_system_qsys) {
      if ($generic_kernel or ($version eq "0.9" and -e "base.qsf")) 
      {
        $return_status = acl::Common::mysystem_full(
          {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
          "$sopc_builder_cmd $qsys_quartus_project --script=kernel_system.tcl $jre_tweaks" );
        acl::Common::move_to_log("!========== Qsys kernel_system script ==========", "sopc.tmp", $fulllog);
        $return_status == 0 or  acl::Common::mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        if (!($qsys_file eq "none"))
        {
          $return_status =acl::Common::mysystem_full(
            {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
            "$sopc_builder_cmd $qsys_quartus_project --script=system.tcl $jre_tweaks --system-file=$qsys_file" );
          acl::Common::move_to_log("!========== Qsys system script ==========", "sopc.tmp", $fulllog);
          $return_status == 0 or  acl::Common::mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
      } else {
        $return_status = acl::Common::mysystem_full(
          {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
          "$sopc_builder_cmd $qsys_quartus_project --script=system.tcl $jre_tweaks --system-file=$qsys_file" );
        acl::Common::move_to_log("!========== Qsys script ==========", "sopc.tmp", $fulllog);
        $return_status == 0 or  acl::Common::mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }
    }

    # Generate HDL from the Qsys system
    if ($new_sim_mode) {
      acl::Simulator::opencl_create_sim_system($board_variant, 0, $work_dir_no_base, $work_dir."/".$base.".bc.xml");
    } elsif ($simulation_mode) {
      print "Qsys ip-generate (simulation mode) started!\n" ;      
      $return_status = acl::Common::mysystem_full( 
        {'time' => 1, 'time-label' => 'ip generate (simulation), ', 'stdout' => 'ipgen.tmp', 'stderr' => '&STDOUT'},
      "$ip_gen_cmd --component-file=$qsys_file --file-set=SIM_VERILOG --component-param=CALIBRATION_MODE=Skip  --output-directory=system/simulation --report-file=sip:system/simulation/system.sip --jvm-max-heap-size=3G" );                           
      print "Qsys ip-generate done!\n" ;            
    } else {    
      my $generate_cmd = ::acl::Env::aocl_boardspec( ".", "generate_cmd".$bsp_flow_name);
      ( $generate_cmd !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n");
      $return_status = acl::Common::mysystem_full( 
        {'time' => 1, 'time-label' => 'ip generate', 'stdout' => 'ipgen.tmp', 'stderr' => '&STDOUT'},
        "$generate_cmd" );  
    }
    
    # Check the log file for errors
    $windows_longpath_flag = 0;
    open LOG, "<ipgen.tmp";
    while (my $line = <LOG>) {
      if ($line =~ /Error\s*(?:\(\d+\))?:/) {
        print $line;
        # Is this a windows long-path issue?
        $windows_longpath_flag = 1 if acl::AOCDriverCommon::win_longpath_error_quartus($line);
      }
    }
    print $win_longpath_suggest if ($windows_longpath_flag and acl::Env::is_windows());
    close LOG;

    acl::Common::move_to_log("!========== ip-generate ==========","ipgen.tmp",$fulllog);
    $return_status == 0 or acl::Common::mydie("ip-generate FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");

    # Some boards may post-process qsys output
    if (defined $postqsys_script and $postqsys_script ne "") {
      acl::AOCDriverCommon::mysystem( "$postqsys_script" ) == 0 or acl::Common::mydie("Couldn't run postqsys-script for the board!\n");
    }
    print_bsp_msgs($fulllog);
  }

  # For simulation flow, compile the simulation, package it into the aocx, and then exit
  if($new_sim_mode) {
    # Generate compile and run scripts, and compile the design
    acl::Simulator::compile_opencl_simulator($fulllog, $work_dir);
    # Bundle up the simulation directory and simulation information used by MMD into aocx
    my $sim_options_filename = acl::Simulator::get_sim_options();
    my @sim_dir = acl::Simulator::get_sim_package();
    $return_status = $pkg->package('fpga-sim.bin', 'sys_description.hex', @sim_dir, $sim_options_filename);
    $return_status == 0 or acl::Common::mydie("Bundling simulation files FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    $pkg->set_file(".acl.fpga.bin","fpga-sim.bin");
    unlink("fpga-sim.bin");
    # Remove the generated verilog.
    if (!$save_temps) {
      unlink( $sim_options_filename );
      foreach my $dir (@sim_dir) {
        acl::File::remove_tree($dir)
          or acl::Common::mydie("Cannot remove files under temporary directory $dir: $!\n");
      }
    }
    else {
      # Output repackaging script for ease of use later
      my $pkg_relative_filepath = "../$base.aocx";
      if ($output_file) {
        my $outbase = $output_file;
        if ($outbase =~ /.*\/(\S+)/) {
          $outbase = $1;
        }
        $pkg_relative_filepath = "../$outbase";
      }
      acl::Simulator::write_sim_repackage_script($pkg_relative_filepath);
    }

    # Move temporary file to final location.
    unlink( $pkg_file_final ) if -f $pkg_file_final;
    rename( $pkg_file, $pkg_file_final )
      or acl::Common::mydie("Cannot rename $pkg_file to $pkg_file_final: $!");

    print "Simulator flow is successful.\n" if $verbose;
    print "To execute simulator, invoke host with \n\tenv CL_CONTEXT_MPSIM_DEVICE_INTELFPGA=1 <host_program>\n" if $verbose;

    return;
  }

  # Override the fitter seed, if specified.
  if ( $fit_seed ) {
    my @designs = acl::File::simple_glob( "*.qsf" );
    $#designs > -1 or acl::Common::mydie ("Internal Compiler Error.  Seed argument was passed but could not find any qsf files\n");
    foreach (@designs) {
      my $qsf = $_;
      open(my $append_fh, ">>", $qsf) or acl::Common::mydie("Internal Compiler Error.  Failed adding the seed argument to qsf files\n");
      print {$append_fh} "\nset_global_assignment -name SEED $fit_seed\n";
      close( $append_fh );
    }
  }

  # Add DSP location constraints, if specified.
  if ( $dsploc ) {
    extract_atoms_from_postfit_netlist($base,$dsploc,"DSP",$bsp_flow_name);
  } 

  # Add RAM location constraints, if specified.
  if ( $ramloc ) {
    extract_atoms_from_postfit_netlist($base,$ramloc,"RAM",$bsp_flow_name); 
  } 

  if ( $ip_gen_only ) { return; }

  # "Old --hw" starting point
  my $project = ::acl::Env::aocl_boardspec( ".", "project".$bsp_flow_name);
  ( $project !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n");
  my @designs = acl::File::simple_glob( "$project.qpf" );
  $#designs >= 0 or acl::Common::mydie ("Internal Compiler Error.  BSP specified project name $project, but $project.qpf does not exist.\n");
  $#designs == 0 or acl::Common::mydie ("Internal Compiler Error.\n");
  my $design = shift @designs;

  my $synthesize_cmd = ::acl::Env::aocl_boardspec( ".", "synthesize_cmd".$bsp_flow_name);
  ( $synthesize_cmd !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n");

  my $retry = 0;
  my $MAX_RETRIES = 3;
  if ($high_effort) {
    print "High-effort hardware generation selected, compile time may increase signficantly.\n";
  }

  do {

    if (defined $ENV{ACL_QSH_COMPILE_CMD})
    {
      # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default
      # quartus compile command (internal use only).  
      my $top = acl::File::mybasename($design); 
      $top =~ s/\.qpf//;
      my $custom_cmd = $ENV{ACL_QSH_COMPILE_CMD};
      $custom_cmd =~ s/PROJECT/$top/;
      $custom_cmd =~ s/REVISION/$top/;
      $return_status = acl::Common::mysystem_full(
        {'time' => 1, 'time-label' => 'Quartus compilation', 'stdout' => $quartus_log},
        $custom_cmd);
    } else {
      $return_status = acl::Common::mysystem_full(
        {'time' => 1, 'time-label' => 'Quartus compilation', 'stdout' => $quartus_log, 'stderr' => 'quartuserr.tmp'},
        $synthesize_cmd);
    }

    print_bsp_msgs($quartus_log);

    if ( $return_status != 0 ) {
      if ($high_effort && acl::AOCDriverCommon::hard_routing_error($quartus_log) && $retry < $MAX_RETRIES) {
        print " kernel fitting error encountered - retrying aocx compile.\n";
        $retry = $retry + 1;

        # Override the fitter seed, if specified.
        my @designs = acl::File::simple_glob( "*.qsf" );
        $#designs > -1 or print_quartus_errors($quartus_log, 0);
        my $seed = $retry * 10;
        foreach (@designs) {
          my $qsf = $_;
          if ($retry > 1) {
            # Remove the old seed setting
            open( my $read_fh, "<", $qsf ) or acl::Common::mydie("Unexpected Compiler Error, not able to generate hardware in high effort mode.");
            my @file_lines = <$read_fh>; 
            close( $read_fh ); 

            open( my $write_fh, ">", $qsf ) or acl::Common::mydie("Unexpected Compiler Error, not able to generate hardware in high effort mode.");
            foreach my $line ( @file_lines ) { 
              print {$write_fh} $line unless ( $line =~ /set_global_assignment -name SEED/ ); 
            } 
            print {$write_fh} "set_global_assignment -name SEED $seed\n";
            close( $write_fh ); 
          } else {
            $return_status = acl::AOCDriverCommon::mysystem( "echo \"\nset_global_assignment -name SEED $seed\n\" >> $qsf" );
          }
        }
      } else {
        $retry = 0;
        print_quartus_errors($quartus_log, $high_effort == 0);
      }
    } else {
      $retry = 0;
    }
  } while ($retry && $retry < $MAX_RETRIES);

  # postcompile migration
  if( ! $no_automigrate && ! $emulator ) {
    acl::Board_migrate::migrate_platform_postcompile($bsp_flow_name,$add_migrations_csv,$block_migrations_csv);
  }

  my $fpga_bin = 'fpga.bin';
  if ( -f $fpga_bin ) {
    $pkg->set_file('.acl.fpga.bin',$fpga_bin)
       or acl::Common::mydie("Cannot save FPGA configuration file $fpga_bin into package file: $acl::Pkg::error\n");

  } else { #If fpga.bin not found, package up sof and core.rbf

    # Save the SOF in the package file.
    my @sofs = (acl::File::simple_glob( "*.sof" ));
    if ( $#sofs < 0 ) {
      print "$prog: Warning: Cannot find a FPGA programming (.sof) file\n";
    } else {
      if ( $#sofs > 0 ) {
        print "$prog: Warning: Found ".(1+$#sofs)." FPGA programming files. Using the first: $sofs[0]\n";
      }
      $pkg->set_file('.acl.sof',$sofs[0])
        or acl::Common::mydie("Cannot save FPGA programming file into package file: $acl::Pkg::error\n");
    }
    # Save the RBF in the package file, if it exists.
    # Sort by name instead of leaving it random.
    # Besides, sorting will pick foo.core.rbf over foo.periph.rbf
    foreach my $rbf_type ( qw( core periph ) ) {
      my @rbfs = sort { $a cmp $b } (acl::File::simple_glob( "*.$rbf_type.rbf" ));
      if ( $#rbfs < 0 ) {
        #     print "$prog: Warning: Cannot find a FPGA core programming (.rbf) file\n";
      } else {
        if ( $#rbfs > 0 ) {
          print "$prog: Warning: Found ".(1+$#rbfs)." FPGA $rbf_type.rbf programming files. Using the first: $rbfs[0]\n";
        }
        $pkg->set_file(".acl.$rbf_type.rbf",$rbfs[0])
          or acl::Common::mydie("Cannot save FPGA $rbf_type.rbf programming file into package file: $acl::Pkg::error\n");
      }
    }
  }

  my $pll_config = 'pll_config.bin';
  if ( -f $pll_config ) {
    $pkg->set_file('.acl.pll_config',$pll_config)
       or acl::Common::mydie("Cannot save FPGA clocking configuration file $pll_config into package file: $acl::Pkg::error\n");
  }

  my $acl_quartus_report = 'acl_quartus_report.txt';
  if ( -f $acl_quartus_report ) {
    $pkg->set_file('.acl.quartus_report',$acl_quartus_report)
       or acl::Common::mydie("Cannot save Quartus report file $acl_quartus_report into package file: $acl::Pkg::error\n");
  
    # Retrieve the target and check if it is fpga, if it is, execute tcl script to generate the report
    my $target = acl::AOCDriverCommon::get_pkg_section($pkg,'.acl.target');
    if ($target eq 'fpga') {
      # Returns the clock frequencies from the board for Quartus report and STA late (if applicable)
      my @clk_freqs = acl::AOCDriverCommon::get_pll_frequency();
      if ($clk_freqs[0] != -1) {
        my $compile_report_script = acl::Env::sdk_root()."/share/lib/tcl/quartus_compile_report.tcl";
        my $project_name = ::acl::Env::aocl_boardspec( ".", "project".$bsp_flow_name);
        my $project_rev = ::acl::Env::aocl_boardspec( ".", "revision".$bsp_flow_name);
        my $report_name = "./reports/lib/json/quartus.json";
        my $skip_entity_area_report = $fast_compile || $empty_kernel_flow;
        my $a_fmax = $clk_freqs[0];
        my $k_fmax = $clk_freqs[1];
        my $clk2x_fmax = $clk_freqs[2];
        my @kernel_list = acl::AOCDriverCommon::get_kernel_list($base);

        my @cmd_list = ();
        (my $mProg = $prog) =~ s/#//g;
        @cmd_list = (
            "quartus_sh", 
            "-t", 
            $compile_report_script, 
            $mProg, 
            $project_name, 
            $project_rev, 
            $report_name, 
            $skip_entity_area_report, 
            $a_fmax, 
            $clk2x_fmax, 
            $k_fmax, 
            @kernel_list);

        # Execute quartus_compile_report.tcl
        my $quartus_compile_report_cmd = join(' ', @cmd_list);
        $return_status = acl::Common::mysystem_full( 
            {'time' => 1, 'time-label' => 'Quartus full compile', 'stdout' => 'quartus_compile_report.log', 'stderr' => 'quartus_compile_report.log'}, $quartus_compile_report_cmd);
        $return_status == 0 or acl::Common::mydie("Quartus full compile: generating Quartus compile report FAILED.\nRefer to quartus_compile_report.log for details.\n");

        # Execute quartus_html_report.tcl
        my $update_html_report_cmd = acl::AOCDriverCommon::get_pkg_section($pkg,'.acl.update_html_report');
        $return_status = acl::Common::mysystem_full( 
            {'time' => 1, 'time-label' => 'Quartus full compile', 'stdout' => 'quartus_update_html.log', 'stderr' => 'quartus_update_html.log'}, $update_html_report_cmd);
        $return_status == 0 or acl::Common::mydie("Quartus full compile: updating HTML report FAILED.\nRefer to quartus_update_html.log for details.\n");
      }
    }
  }
  
  # BSP Honor check: Incremental
  acl::Common::mydie("Incremental compile was requested but this BSP did not invoke the incremental-compile API.") if ($incremental_compile && ! -f 'partitions.fit.rpt');

  # BSP Honor check: Fast
  if ($fast_compile) {
    my $revision_of_interest = ::acl::Env::aocl_boardspec(".", "revision".$bsp_flow_name);
    my $fit_report = $revision_of_interest . ".fit.rpt";

    # Read entire file
    open (my $fit_report_fh, '<', $fit_report) or acl::Common::mydie("Could not open $fit_report for reading.");
    my @lines = <$fit_report_fh>;
    close ($fit_report_fh);

    foreach my $line (@lines) {
      if ($line =~ /.*Optimization Mode.*/) {
        my @parts = split(";", $line);
        for (my $i = 0; $i < scalar @parts; $i++) {
            $parts[$i] =~ s/^\s+|\s+$//g;
        }
        acl::Common::mydie("Fast compile was requested but this BSP did not invoke the fast-compile API") if ($parts[2] ne "Aggressive Compile Time");
      }
    }
  }

  # BSP Honor check: Empty Kernel
  if ($empty_kernel_flow) {
    my $revision_of_interest = ::acl::Env::aocl_boardspec(".", "revision".$bsp_flow_name);
    my $fit_report = $revision_of_interest . ".fit.rpt";

    # Read entire fit report
    open (my $fit_report_fh, '<', $fit_report) or acl::Common::mydie("Could not open $fit_report for reading.");
    my @fit_lines = <$fit_report_fh>;
    close ($fit_report_fh);

    # Read entired empty_kernel_partition file
    my $empty_kernel_file = "empty_kernel_partition.txt";
    open (my $empty_kernels_fh, '<', $empty_kernel_file) or acl::Common::mydie("Could not open $empty_kernel_file for reading.");
    my @empty_lines = <$empty_kernels_fh>;
    close ($empty_kernels_fh);

    my $partition_summary_match;
    while ($partition_summary_match = shift (@fit_lines)) {
      last if ($partition_summary_match =~ /.*Fitter Partition Summary.*/);
    }
        
    foreach my $empty_line (@empty_lines) {
      chomp $empty_line;
      my $partition_emptied = 0;
      foreach my $fit_line (@fit_lines) {
        # Fit Partition Summary has "Yes" on Empty column
        if ($fit_line =~ m/\Q$empty_line\E .* Yes /) {
          $partition_emptied = 1;
          last;
        }
      }
      acl::Common::mydie("Empty kernel compile was requested but this BSP did not invoke the empty-kernel API") if (!$partition_emptied);
    }
  }

  unlink( $pkg_file_final ) if -f $pkg_file_final;
  rename( $pkg_file, $pkg_file_final )
    or acl::Common::mydie("Cannot rename $pkg_file to $pkg_file_final: $!");

  if ((! $incremental_compile || ! -e "prev") && ! $save_temps) {
    acl::File::remove_tree("prev")
      or acl::Common::mydie("Cannot remove files under temporary directory prev: $!\n");
  }

  # Check for hold-time violations
  foreach my $clk_failure_file (acl::File::simple_glob( "$work_dir/*.failing_clocks.rpt" )) {
    open (RPT_FILE, "<$clk_failure_file") or acl::Common::mydie("Could not open file $clk_failure_file for read.");
    while (<RPT_FILE>) {
      if ($_ =~ m/^;\s+(-\d+(?:\.\d+)?)\s+;.*;\s+(.*)\s+;.*;\s+Hold\s+;$/) {
        my $slack = $1;
        my $clock = $2;
        my $hold_threshold = -0.010; # Error out if hold violation is greater than 10 ps.
        if ($slack < $hold_threshold) {
          my $message = <<"HOLD_VIOLATION_MESSAGE";
Warning: hold time violation of $slack ns on clock:
  $clock
See $clk_failure_file for more details.
This could potentially cause funcitonal failures.  Consider recompiling with a
different seed (using -seed=<S>).
HOLD_VIOLATION_MESSAGE
          # The other action a user could take is to use the hidden -add-qsf flag
          # to manually add additional clock uncertainty (Peter's idea).
          print $message;
        }
      }
    }
    close(RPT_FILE);
  }
  
  # check sta log for timing not met warnings
  if ($timing_slack_check){
    my $slack_violation_filename = 'slackTime_violation.txt';
    if (open(my $fh, '<', $slack_violation_filename)) {
        my $line = <$fh>;
        acl::Common::mydie("Timing Violation detected: $line\n");
    }
  }

  print "$prog: Hardware generation completed successfully.\n" if $verbose;
  
  my $orig_dir = acl::Common::get_original_dir();
  chdir $orig_dir or acl::Common::mydie("Cannot change back into directory $orig_dir: $!");
  remove_intermediate_files($work_dir,$pkg_file_final) if $tidy;
}

sub main {
  my $all_aoc_args="@ARGV";
  my @args = (); # regular args.
  my $dirbase = undef;
  my $bsp_variant=undef;
  my $using_default_board = 0;
  my $bsp_flow_name = undef;
  my $regtest_bak_cache = 0;
  my $incremental_input_dir = '';
  my $verbose = acl::Common::get_verbose();
  my $quiet_mode = acl::Common::get_quiet_mode();
  my $save_temps = acl::Common::get_save_temps();
  # simulator controls
  my $sim_accurate_memory = 0;
  my $sim_kernel_clk_frequency = undef;
  my $base = undef;

  if (!@ARGV) {
    push @ARGV, qw(-help);
  }
  # Parse Input Arguments
  acl::AOCInputParser::parse_args( \@args,
                                   \$bsp_variant,
                                   \$bsp_flow_name,
                                   \$regtest_bak_cache,
                                   \$incremental_input_dir,
                                   \$verbose,
                                   \$quiet_mode,
                                   \$save_temps,
                                   \$sim_accurate_memory,
                                   \$sim_kernel_clk_frequency,
                                   @ARGV );

  acl::AOCInputParser::process_args( \@args,
                                     \$using_default_board,
                                     \$dirbase,
                                     \$base,
                                     $sim_accurate_memory,
                                     $sim_kernel_clk_frequency,
                                     $bsp_variant,
                                     $regtest_bak_cache,
                                     $verbose,
                                     $incremental_input_dir);

  # Check that this a valid board directory by checking for a board_spec.xml 
  # file in the board directory.
  if (not $run_quartus) {
    my $board_xml = acl::AOCDriverCommon::get_acl_board_hw_path($board_variant)."/board_spec.xml";
    if (!-f $board_xml) {
      print "Board '$board_variant' not found.\n";
      my $board_path = acl::Board_env::get_board_path();
      print "Searched in the board package at: \n  $board_path\n";
      acl::Common::list_boards();
      print "If you are using a 3rd party board, please ensure:\n";
      print "  1) The board package is installed (contact your 3rd party vendor)\n";
      print "  2) You have used -board-package=<bsp-path> to specify the path to\n";
      print "     your board package installation\n";
      acl::Common::mydie("No board_spec.xml found for board '$board_variant' (Searched for: $board_xml).");
    }
    if( !$bsp_flow_name ) {
      # if the boardspec xml version is before 17.0, then use the default
      # flow for that board, which is the first and only flow
      if( "$ENV{'ACL_DEFAULT_FLOW'}" ne '' && ::acl::Env::aocl_boardspec( "$board_xml", "version" ) >= 17.0 ) {
        $bsp_flow_name = "$ENV{'ACL_DEFAULT_FLOW'}";
      } else {
        $bsp_flow_name = ::acl::Env::aocl_boardspec("$board_xml", "defaultname");
      }
      $sysinteg_arg_after .= " --bsp-flow $bsp_flow_name";
      $bsp_flow_name = ":".$bsp_flow_name;
    }
  }

  my $final_work_dir = acl::File::abs_path("$dirbase");

  my %quartus_info = check_env($board_variant,$bsp_flow_name);
  if ($regtest_mode) {
    $tmp_dir .= "/$quartus_info{site}";
  }
  if ($ENV{'AOCL_TMP_DIR'} ne '') {
    print "AOCL_TMP_DIR directory was specified at $ENV{'AOCL_TMP_DIR'}.\n";
    print "Ensure Linux and Windows compiles do not share the same directory as files may be incompatible.\n";
  }
  $ENV{'AOCL_TMP_DIR'} = "$tmp_dir" if ($ENV{'AOCL_TMP_DIR'} eq '');
  print "$prog: Cached files in $ENV{'AOCL_TMP_DIR'} may be used to reduce compilation time\n" if $verbose;

  if (not $run_quartus && not $aoco_to_aocr_aocx_only) {
    if(!$atleastoneflag && $verbose) {
      print "You are now compiling the full flow!!\n";
    }
    # foreach source file, we need to create an object file and object directory
    for (my $i = 0; $i <= $#absolute_srcfile_list; $i++) {
      my $abs_srcfile = $absolute_srcfile_list[$i];
      my $abs_objfile = $objfile_list[$i];
      my $input_base = acl::File::mybasename($abs_srcfile);   
      # Regex: looking for first character not to be alphanumeric
      if ($input_base =~ m/^[^a-zA-Z0-9]/){
        # Quartus will fail if filename does not begin with alphanumeric character
        # Preemptively catching the issue
        acl::Common::mydie("Bad file name: $input_base Ensure file name begins with alphanumeric character");
      }
      $input_base =~ s/\.cl//;
      my $input_work_dir = $abs_objfile; 
      $input_work_dir =~ s/\.aoco//;
      create_object ($input_base, $input_work_dir.".$$".".temp", $abs_srcfile, $abs_objfile, $board_variant, $using_default_board, $all_aoc_args);
    }
  }
  if (not ($compile_step || $parse_only) && not $aocr_to_aocx_only) {
    acl::AOCOpenCLStage::link_objects();
    acl::AOCOpenCLStage::create_system ($base, $final_work_dir, $final_work_dir.".aocr", $all_aoc_args, $bsp_flow_name, $incremental_input_dir, @absolute_srcfile_list);
  }
  if (not ($compile_step || $report_only || $parse_only || $opt_only || $verilog_gen_only)) {
    compile_design ($base, $final_work_dir, $final_work_dir.".aocr", $x_file, $board_variant, $all_aoc_args, $bsp_flow_name);
  }

  if ($time_log_filename) {
    acl::Common::close_time_log();
  }
}

main();
exit 0;
# vim: set ts=2 sw=2 expandtab
