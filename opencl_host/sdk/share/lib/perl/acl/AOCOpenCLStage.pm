
=pod

=head1 COPYRIGHT

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


=head1 NAME

acl::AOCOpenCLStage.pm - OpenCL Compiler Invocations. Stage 1

=head1 VERSION

$Header: //acds/rel/18.1/acl/sysgen/lib/acl/AOCOpenCLStage.pm#2 $

=head1 DESCRIPTION

This module provides methods that run the Stage 1 of the compiler.
They take user source code and process it through CLang, LLVM,
the Backend, and finally System Integrator

=cut 

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


package acl::AOCOpenCLStage;
use strict;
use Exporter;

require acl::Common;
require acl::Env;
require acl::File;
require acl::Incremental;
require acl::Pkg;
require acl::Report;
use acl::AOCDriverCommon;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw ( link_objects create_system );

# Exported Functions

sub link_objects {
  my $quiet_mode = acl::Common::get_quiet_mode();
  print "$prog: Linking Object files....\n" if (!$quiet_mode);  
  my $bsp_path = undef;
  my $board_name = undef;
  my $target = undef;
  my $version = undef;
  my $compileoptions = undef;

  my @bc_temp_list = ();
  my @ioc_obj_temp_list = ();
  
  for (my $i = 0; $i <= $#objfile_list; $i++) {
    my $obj = $objfile_list[$i];
    my $dep_file_temp = $obj.".d.temp";
    my $bc_file_temp = $obj.".temp.bc";
    my $ioc_obj_file_temp = $obj.".temp.ioc.obj";
    my $log_file_temp = $obj.".temp.log";

    # read information from package file
    my $pkg = get acl::Pkg($obj) or die "Can't find pkg file $obj: $acl::Pkg::error\n";   
    my $obj_target = acl::AOCDriverCommon::get_pkg_section($pkg,'.acl.target');
    my $obj_version = acl::AOCDriverCommon::get_pkg_section($pkg,'.acl.version');

    #check to make sure the tragets for all the files are same
    if (!defined $target) {
      $target = $obj_target;
    } elsif ($target ne $obj_target) {
      acl::Common::mydie("Invalid target for $obj");
    }

    #check to make sure the versions for all the files are same
    if (!defined $version) {
      $version = $obj_version;
    } elsif ($version ne $obj_version) {
      acl::Common::mydie("Invalid version for $obj");
    }
    
    my $obj_compileoptions = acl::AOCDriverCommon::get_pkg_section($pkg,'.acl.compileoptions');
    #handle cases where the argument can be '-' or '--'
    $obj_compileoptions =~ s/[-]+//ig;
    my $obj_sort_compileoptions = join '', sort split(//, $obj_compileoptions);

    #check to make sure the compile options for all the files are same
    if (!defined $compileoptions) {
      $compileoptions = $obj_sort_compileoptions;
    } elsif ($compileoptions ne $obj_sort_compileoptions) {
      acl::Common::mydie("Invalid compileoptions for $obj");
    }

    if ( !($obj_target eq 'emulator' or $obj_target eq 'simulator' or $obj_target eq 'emulator_fast') ) {
      my $obj_board_package = acl::AOCDriverCommon::get_pkg_section($pkg,'.acl.board_package');
      my $obj_board_name = acl::AOCDriverCommon::get_pkg_section($pkg,'.acl.board');
      if (!defined $bsp_path) {
        $bsp_path = $obj_board_package;
      } elsif ($bsp_path ne $obj_board_package) {
        acl::Common::mydie("Invalid board package path for $obj");
      }
      if (!defined $board_name) {
        $board_name = $obj_board_name;
      } elsif ($board_name ne $obj_board_name) {
        acl::Common::mydie("Invalid board name for $obj");
      }
    }

    if ($obj_target eq 'emulator_fast') {
      $pkg->get_file('.acl.ioc_obj',$ioc_obj_file_temp);
      push @ioc_obj_temp_list, $ioc_obj_file_temp;
    } else {
      $pkg->get_file('.acl.dep',$dep_file_temp);
      $pkg->get_file('.acl.aoco',$bc_file_temp);
      push @all_dep_files, $dep_file_temp;
      push @bc_temp_list, $bc_file_temp;

      # Deal with clang logs
      $pkg->get_file('.acl.clang_log',$log_file_temp);
      open(INPUT,"<$log_file_temp") or acl::Common::mydie("Can't open $log_file_temp: $!");
      push @clang_warnings, <INPUT>;
      close INPUT;
      unlink $log_file_temp;
    }
  }

  if ($user_defined_flow eq 1) {
    if($emulator_flow eq 1 && $target ne 'emulator' && $target ne 'emulator_fast') {
      acl::Common::mydie("Object target does not match 'emulator'");
    }
    if($new_sim_mode eq 1 && $target ne 'simulator'){
      acl::Common::mydie("Object target does not match 'simulator'");
    }
  }

  if ($target eq 'emulator') {
    $emulator_flow = 1;
  } elsif ($target eq 'emulator_fast') {
    $emulator_flow = 1;
    $emulator_fast = 1;
  } elsif ($target eq 'simulator') {
    $new_sim_mode = 1;
    $ip_gen_only = 1;
    $atleastoneflag = 1;
  } else {
    $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $bsp_path;
    if( $user_defined_board == 1 && $board_name ne $board_variant ) {
      acl::Common::mydie("Board specified '$board_variant' does not match the board '$board_name' in aoco package\n");
    } else {
      $board_variant = $board_name;
    }
  }

  my @cleanup_list = (@bc_temp_list, @ioc_obj_temp_list);

  if ($emulator_fast) {
    my $ioc_cmd = "-cmd=link";
    my $ioc_dev = "-device=fpga_fast_emu";
    my $ioc_inp = "-binary=".join(",", @ioc_obj_temp_list) ;
    my $ioc_out = "-ir=$linked_objfile";

    my @cmd_list = (
        $ioc_exe,
        $ioc_cmd,
        $ioc_dev,
        $ioc_inp,
        $ioc_out);

    $return_status = acl::Common::mysystem_full(
      { 'stdout' => 'ioc_link.log',
        'stderr' => 'ioc_link.err',
        'title' => 'Linking Emulator Files',
        'time' => 1,
        'time-label' => 'ioc link'},
        @cmd_list);

    acl::Report::append_to_err('ioc_link.err');
    if ($return_status==0 or $regtest_mode==0) { unlink 'ioc_link.err'; }
          
    if ($return_status != 0) {
      if ($regtest_mode) {
        acl::Common::move_to_log('!========== Fast Emulator - Link ==========', 'ioc_link.err', "$work_dir/../$regtest_errlog");
      }
      acl::Common::mydie("OpenCL kernel linking FAILED");
    }

    # Go through ioc_link.log and print any errors or warnings.
    open(INPUT,"<ioc_link.log") or acl::Common::mydie("Can't open ioc_link.log $!");
    my $start_printing = acl::Common::get_verbose() > 1;
    my $link_failed = 0;
    while (my $line = <INPUT>) {
      $link_failed = 1 if ($line =~ m/^Linkage failed!?$/);
      if (acl::Common::get_verbose() > 2) {
        print $line;
      } elsif ($line =~ m/^Linking started$/) {
        $start_printing = 1;
      } elsif ($line =~ m/^Linkage failed$/ and $start_printing == 0) {
        $start_printing = 1;
      } elsif ($line =~ m/^Linkage failed!?$/) {
        $start_printing = 0 unless acl::Common::get_verbose();
      } elsif ($line =~ m/^Linking done$/) {
        $start_printing = 0;
      } elsif ($start_printing) {
        print $line;
      }
    }
    close INPUT;

    acl::Common::mydie("OpenCL kernel linking FAILED") if ($link_failed);
    push @cleanup_list, "ioc_link.log" unless acl::Common::get_save_temps();
  } else {
    my @cmd_list = ();

    my $result_file = shift @bc_temp_list;
    my $next_res = undef;
    my $indexnum = 0;

    foreach (@bc_temp_list) {
      # Just add one file at the time since llvm-link has some issues
      # with unifying types otherwise. Introduces small overhead if 3
      # source files or more
      $next_res = $linked_objfile.'.'.$indexnum++;
      @cmd_list = (
          $link_exe,
          $result_file,
          $_,
          '-o',$next_res );

      acl::Common::mysystem_full( {'title' => 'Link IR'}, @cmd_list) == 0 or acl::Common::mydie();
      push @cleanup_list, $next_res;
      $result_file = $next_res;
    }

    my $opt_input = defined $next_res ? $next_res : $result_file;
    rename $opt_input, $linked_objfile;
  }

  #remove .bc.temp files. no longer needed
  foreach my $temp (@cleanup_list) {
    unlink $temp;
  }

}

sub create_system {
  my ($base,$final_work_dir, $obj, $all_aoc_args,$bsp_flow_name,$incremental_input_dir, $absolute_srcfile_list) = @_;
  my $pkg_file_final = $obj;
  (my $src_pkg_file_final = $obj) =~ s/aocr/source/;
  my $pkg_file = acl::Common::set_package_file_name($pkg_file_final.".tmp");
  my $src_pkg_file = acl::Common::set_source_package_file_name($src_pkg_file_final.".tmp");
  my $verbose = acl::Common::get_verbose();
  my $quiet_mode = acl::Common::get_quiet_mode();
  my $save_temps = acl::Common::get_save_temps();
  $fulllog = "$base.log"; #definition moved to global space
  my $run_copy_skel = 1;
  my $run_copy_ip = 1;
  my $run_opt = 1;
  my $run_verilog_gen = 1;
  my $fileJSON;
  my @move_files = ();
  my @save_files = ();
  if ($incremental_compile) {
    push (@save_files, 'qdb');
    push (@save_files, 'current_partitions.txt');
    push (@save_files, 'new_floorplan.txt');
    push (@save_files, 'io_loc.loc');
    push (@save_files, 'partition.*.qdb');
    push (@save_files, 'prev');
    push (@save_files, 'soft_regions.txt');
    push (@move_files, ('previous_partition_grouping_incremental.txt', '*_sys.v', '*_system.v', '*.bc.xml', 'reports', 'kernel_hdl', $marker_file));
  }
  my $finalize = sub {
     unlink( $pkg_file_final ) if -f $pkg_file_final;
     unlink( $src_pkg_file_final ) if -f $src_pkg_file_final;
     rename( $pkg_file, $pkg_file_final )
         or acl::Common::mydie("Can't rename $pkg_file to $pkg_file_final: $!");
     rename( $src_pkg_file, $src_pkg_file_final ) if -f $src_pkg_file;
     my $orig_dir = acl::Common::get_original_dir();
     chdir $orig_dir or acl::Common::mydie("Can't change back into directory $orig_dir: $!");
  };

  if ( $parse_only || $opt_only || $verilog_gen_only || $emulator_flow ) {
    $run_copy_ip = 0;
    $run_copy_skel = 0;
  }

  if ( $accel_gen_flow ) {
    $run_copy_skel = 0;
  }

  my $stage1_start_time = time();
  #Create the new direcory verbatim, then rewrite it to not contain spaces
  $work_dir = $final_work_dir;
  # If there exists a file with the same name as work_dir
  if (-e $work_dir and -f $work_dir) {
    acl::Common::mydie("Can't create project directory $work_dir because file with the same name exists\n");
  }
  #If the work_dir exists, check whether it was created by us
  if (-e $work_dir and -d $work_dir) {
  # If the marker file exists, this was created by us
  # Cleaning up the whole project directory to avoid conflict with previous compiles. This behaviour should change for incremental compilation.
    if (-e "$work_dir/$marker_file" and -f "$work_dir/$marker_file") {
      print "$prog: Cleaning up existing temporary directory $work_dir\n" if ($verbose >= 2);

      if ($incremental_compile && !$incremental_input_dir) {
        $acl::Incremental::warning = "$prog: Found existing directory $work_dir, basing incremental compile off this directory.\n";
        print $acl::Incremental::warning if ($verbose);
        $incremental_input_dir = $work_dir;
      }

      # If incremental, copy over all incremental files before removing anything (in case of failure or force stop)
      if ($incremental_compile && acl::File::abs_path($incremental_input_dir) eq acl::File::abs_path($work_dir)) {
        # Check if prev directory exists and that the marker file exists inside it. The marker file is added after all the necessary
        # previous files are copied over. This indicates that we have a valid set of previous files. The prev directory should automatically
        # be removed after a successful compile, so this directory should only be left over in the case where an incremental compile has failed
        # If an incremental compile has failed, then we should keep the contents of this directory since the kernel_hdl and .bc.xml file in the project 
        # directory may have been already been overwritten
        $incremental_input_dir = "$work_dir/prev";
        if (! -e $incremental_input_dir || ! -d $incremental_input_dir || ! -e "$incremental_input_dir/$marker_file") {
          acl::File::make_path($incremental_input_dir) or acl::Common::mydie("Can't create temporary directory $incremental_input_dir: $!");
          foreach my $reg (@move_files) {
            foreach my $f_match ( acl::File::simple_glob( "$work_dir/$reg") ) {
              my $file_base = acl::File::mybasename($f_match);
              acl::File::copy_tree( $f_match, "$incremental_input_dir/" );
            }
          }
        }
      }

      foreach my $file ( acl::File::simple_glob( "$work_dir/*", { all => 1 } ) ) {
        if ( $file eq "$work_dir/." or $file eq "$work_dir/.." or $file eq "$work_dir/$marker_file" ) {
          next;
        }
        my $next_check = undef;
        foreach my $reg (@save_files) {
          if ( $file =~ m/$reg/ ) { $next_check = 1; last; }
        }
        # if the file matches one of the regexps, skip its removal
        if( defined $next_check ) { next; }

        acl::File::remove_tree( $file )
          or acl::Common::mydie("Cannot remove files under temporary directory $work_dir: $!\n");
      }
    } else {
      acl::Common::mydie("Please rename the existing directory $work_dir to avoid name conflict with project directory\n");
    }
  }

  acl::File::make_path($work_dir) or acl::Common::mydie("Can't create temporary directory $work_dir: $!");
  if ($incremental_input_dir ne '' && $incremental_input_dir ne "$work_dir/prev") {
    foreach my $reg (@save_files) {
      foreach my $f_match ( acl::File::simple_glob( "$incremental_input_dir/$reg") ) {
        my $file_base = acl::File::mybasename($f_match);
        acl::File::copy_tree( $f_match, $work_dir."/" );
      }
    }
    $incremental_input_dir = acl::File::abs_path("$incremental_input_dir");
  }

  # Create a marker file
  my @cmd = acl::Env::is_windows() ? ("type nul > $work_dir/$marker_file"):("touch", "$work_dir/$marker_file");
  acl::Common::mysystem_full({}, @cmd);
  # First, try to delete the log file
  if (!unlink "$work_dir/$fulllog") {
    # If that fails, just try to erase the existing log
    open(LOG, ">$work_dir/$fulllog") or acl::Common::mydie("Couldn't open $work_dir/$fulllog for writing.");
    close(LOG);
  }
  open(my $TMPOUT, ">$work_dir/$fulllog") or acl::Common::mydie ("Couldn't open $work_dir/$fulllog to log version information.");
  print $TMPOUT "Compiler Command: " . $prog . " " . $all_aoc_args . "\n";
  if (defined $acl::Incremental::warning) {
    print $TMPOUT $acl::Incremental::warning;
  }
  if ($regtest_mode){
      acl::AOCDriverCommon::version($TMPOUT);
  }
  close($TMPOUT);
  my $acl_board_hw_path = acl::AOCDriverCommon::get_acl_board_hw_path($board_variant);

  # If just packaging an HDL library component, call 'aocl library' and be done with it.
  if ($hdl_comp_pkg_flow) {
    print "$prog: Packaging HDL component for library inclusion\n" if $verbose||$report;
    foreach my $absolute_srcfile (@absolute_srcfile_list){
      $return_status = acl::Common::mysystem_full(
        {'stdout' => "$work_dir/aocl_libedit.log", 
         'stderr' => "$work_dir/aocl_libedit.err",
         'time' => 1, 'time-label' => 'aocl library'},
        "$aocl_libedit_exe -c \"$absolute_srcfile\" -o \"$output_file\"");
      my $banner = '!========== [aocl library] ==========';
      acl::AOCDriverCommon::move_to_err_and_log($banner, "$work_dir/aocl_libedit.log", "$work_dir/$fulllog"); 
      acl::Report::append_to_log("$work_dir/aocl_libedit.err", "$work_dir/$fulllog");
      acl::Report::append_to_err("$work_dir/aocl_libedit.err");
      if ($return_status==0 or $regtest_mode==0) { unlink "$work_dir/aocl_libedit.err"; }
      if ($return_status != 0) {
        if ($regtest_mode) {
          acl::Common::move_to_log($banner, "$work_dir/aocl_libedit.err", "$work_dir/../$regtest_errlog");
        }
        acl::Common::mydie("Packing of HDL component FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");  
      }
    }
    
    return $return_status;
  }
  
  # Make sure the board specification file exists. This is needed by multiple stages of the compile.
  my $board_spec_xml = acl::AOCDriverCommon::find_board_spec($acl_board_hw_path);
  my $llvm_board_option = "-board $board_spec_xml";   # To be passed to LLVM executables.
  my $llvm_efi_option = (defined $absolute_efispec_file ? "-efi $absolute_efispec_file" : ""); # To be passed to LLVM executables
  my $llvm_profilerconf_option = (defined $absolute_profilerconf_file ? "-profile-config $absolute_profilerconf_file" : ""); # To be passed to LLVM executables
  my $llvm_library_option = join(' ',map { (qw(-libfile), "\"$_\"") } @resolved_lib_files);

  if(defined $absolute_efispec_file) {
    print "$prog: Selected EFI spec $absolute_efispec_file\n" if $verbose||$report;
  }

  if(defined $absolute_profilerconf_file) {
    print "$prog: Selected profiler conf $absolute_profilerconf_file\n" if $verbose||$report;
  }

  if ( $run_copy_skel ) {
    # Copy board skeleton, unconditionally.
    # Later steps update .qsf and .sopc in place.
    # You *will* get SOPC generation failures because of double-add of same
    # interface unless you get a fresh .sopc here.
    acl::File::copy_tree( $acl_board_hw_path."/*", $work_dir )
      or acl::Common::mydie("Can't copy Board template files: $acl::File::error");
    map { acl::File::make_writable($_) } (
      acl::File::simple_glob( "$work_dir/*.qsf" ),
      acl::File::simple_glob( "$work_dir/*.sopc" ) );
  }

  if ( $run_copy_ip ) {
    # Rather than copy ip files from the SDK root to the kernel directory, 
    # generate an opencl.ipx file to point Qsys to hw.tcl components in 
    # the IP in the SDK root when generating the system.
    acl::Env::create_opencl_ipx($work_dir);

    # Also generate an assignment in the .qsf pointing to this IP.
    # We need to do this because not all the hdl files required by synthesis
    # are necessarily in the hw.tcl (i.e., not the entire file hierarchy).
    #
    # For example, if the Qsys system needs A.v to instantiate module A, then
    # A.v will be listed in the hw.tcl. Every file listed in the hw.tcl also
    # gets copied to system/synthesis/submodules and referenced in system.qip,
    # and system.qip is included in the .qsf, therefore synthesis will be able
    # to find the file A.v. 
    #
    # But if A instantiates module B, B.v does not need to be in the hw.tcl, 
    # since Qsys still is able to find B.v during system generation. So while
    # the Qsys generation will still succeed without B.v listed in the hw.tcl, 
    # B.v will not be copied to submodules/ and will not be included in the .qip,
    # so synthesis will fail while looking for this IP file. This happens in the 
    # virtual fabric flow, where the full hierarchy is not included in the hw.tcl.
    #
    # Since we are using an environment variable in the path, move the
    # assignment to a tcl file and source the file in each qsf (done below).
    my $ip_include = "$work_dir/ip_include.tcl";
    open(my $fh, '>', $ip_include) or die "Cannot open file '$ip_include' $!";
    print $fh 'set_global_assignment -name SEARCH_PATH "$::env(INTELFPGAOCLSDKROOT)/ip"
';
    close $fh;

    if ( scalar @additional_ini ) {
      open (QUARTUS_INI_FILE, ">>$work_dir/quartus.ini");
      foreach my $add_i (@additional_ini) {
        open (INI_FILE, "<$add_i") or die "Couldn't open $add_i for read\n";
        print QUARTUS_INI_FILE "# Copied from $add_i:\n";
        print QUARTUS_INI_FILE (do {local $/; <INI_FILE> });
        print QUARUTS_INI_FILE "\n\n";
      }
      close (INI_FILE);
    }
    close (QUARTUS_INI_FILE);								        

    # Add Deterministic overuse avoidance INI
    # For incremental compiles, avoid using nodes that are likely to be congested and not routable
    # case:491598
    if ($incremental_compile) {
      if (open( QUARTUS_INI_FILE, ">>$work_dir/quartus.ini" )) {
        print QUARTUS_INI_FILE <<AOC_INCREMENTAL_INI;

# case:491598
aoc_incremental_aware_placer=on
AOC_INCREMENTAL_INI
        close (QUARTUS_INI_FILE);
      }
    }

    # Set soft region INI and exported qsf setting from previous compile to current one
    # Soft region is a Quartus feature to mitigate swiss cheese problem in incremental compile.
    # When below INIs and soft region qsf settings in ip/board/incremental are applied,
    # Fitter exports ATTRACTION_GROUP_SOFT_REGION qsf settings per partition.
    # This region is approximate area the partition's logic was placed in.
    # If these settings are then set in incremental compile, fitter will try to place the partition in the same area.
    if ( $soft_region_on ) {
      if (open( QUARTUS_INI_FILE, ">>$work_dir/quartus.ini" )) {
        if (! -e "$work_dir/soft_regions.txt") {
          print QUARTUS_INI_FILE <<SOFT_REGION_SETUP_INI;

# Apl blobby
apl_partition_gamma_factor=10
apl_ble_partition_bin_size=4
apl_cbe_partition_bin_size=6
apl_use_partition_based_spreading=on
SOFT_REGION_SETUP_INI
          # Create empty soft_regions.txt file so that
          # ip/board/incremental scripts set soft region qsf settings
          open( SOFT_REGION_FILE, ">$work_dir/soft_regions.txt" ) or die "Cannot open file 'soft_regions.txt' $!";
          print SOFT_REGION_FILE "";
          close (SOFT_REGION_FILE);
        } else {
          # Add exported soft region qsf settings from previous compile to current one
          push @additional_qsf, "$work_dir/soft_regions.txt";
        }

        print QUARTUS_INI_FILE <<SOFT_REGION_INI;

# Apl attraction groups
apl_floating_region_aspect_ratio_factor=100
apl_discrete_dp=off
apl_ble_attract_regions=on
apl_region_attraction_weight=100

# DAP attraction groups
dap_attraction_group_cost_factor=10
dap_attraction_group_use_soft_region=on
dap_attraction_group_v_factor=3.0

# Export soft regions filename
vpr_write_soft_region_filename=soft_regions.txt
SOFT_REGION_INI
        close (QUARTUS_INI_FILE);
      }
    }

    # append users qsf to end to overwrite all other settings
    my $final_append = '';
    if( scalar @additional_qsf ) {
      foreach my $add_q (@additional_qsf){
        open (QSF_FILE, "<$add_q") or die "Couldn't open $add_q for read\n";
        $final_append .= "# Contents automatically added from $add_q\n";
        $final_append .= do { local $/; <QSF_FILE> };
        $final_append .= "\n";
        close (QSF_FILE);
      }
    }

    my $qsys_file = ::acl::Env::aocl_boardspec("$board_spec_xml", "qsys_file".$bsp_flow_name);

    if ($fast_compile) {
      # env varaible will be used by scripts in acl/ip during BSP compile
      $ENV{'AOCL_FAST_COMPILE'} = 1;
      print "$prog: Adding Quartus fast-compile settings.\nWarning: Circuit performance will be significantly degraded.\n";
    }

    # Writing flags to *qsf files
    foreach my $qsf_file (acl::File::simple_glob( "$work_dir/*.qsf" )) {
      open (QSF_FILE, ">>$qsf_file") or die "Couldn't open $qsf_file for append!\n";

      if ($cpu_count ne -1) {
        print QSF_FILE "\nset_global_assignment -name NUM_PARALLEL_PROCESSORS $cpu_count\n";
      }

      # Add SEARCH_PATH for ip/$base and qip to the QSF file
      # .qip file contains all file dependencies listed in <foo>_sys_hw.tcl
      if ($qsys_file eq "none" and $bsp_version >= 18.0) {
        print QSF_FILE "\nset_global_assignment -name QIP_FILE kernel_system.qip\n";
      }

      # Source a tcl script which points the project to the IP directory
      print QSF_FILE "\nset_global_assignment -name SOURCE_TCL_SCRIPT_FILE ip_include.tcl\n";

      # Case:149478. Disable auto shift register inference for appropriately named nodes
      print "$prog: Adding wild-carded AUTO_SHIFT_REGISTER_RECOGNITION assignment to $qsf_file\n" if $verbose>1;
      print QSF_FILE "\nset_instance_assignment -name AUTO_SHIFT_REGISTER_RECOGNITION OFF -to *_NO_SHIFT_REG*\n";

      # allow for generate loops with bounds over 5000
      print QSF_FILE "\nset_global_assignment -name VERILOG_CONSTANT_LOOP_LIMIT 10000\n";

      if ($fast_compile) {
        # Adding fast-compile specific flags in *qsf
        open( QSF_FILE_READ, "<$qsf_file" ) or print "Couldn't open $qsf_file again - overwriting whatever INI_VARS are there\n";
        my $ini_vars = '';
        while( <QSF_FILE_READ> ) {
          if( $_ =~ m/INI_VARS\s+[\"|\'](.*)[\"|\']/ ) {
            $ini_vars = $1;
          }
        }
        close( QSF_FILE_READ );
        print QSF_FILE <<FAST_COMPILE_OPTIONS;
# The following settings were added by --fast-compile
# umbrella fast-compile setting
set_global_assignment -name OPTIMIZATION_TECHNIQUE Balanced
set_global_assignment -name OPTIMIZATION_MODE "Aggressive Compile Time"
FAST_COMPILE_OPTIONS

        my %new_ini_vars = (
        );
        if( $ini_vars ) {
          $ini_vars .= ";";
        }
        keys %new_ini_vars;
        while( my($k, $v) = each %new_ini_vars) {
          $ini_vars .= "$k=$v;";
        }
        if($ini_vars ne '') {
          print QSF_FILE "\nset_global_assignment -name INI_VARS \"$ini_vars\"\n";
        }
      }
      if ($high_effort_compile) {
        print QSF_FILE "\nset_global_assignment -name OPTIMIZATION_MODE \"High Performance Effort\"\n";
      }

      # Enable BBIC if doing incremental compile.
      if ($incremental_compile){
        print QSF_FILE <<INCREMENTAL_OPTIONS;
# Contents appended by -incremental flow
set_global_assignment -name FAST_PRESERVE AUTO
INCREMENTAL_OPTIONS
      }

      if( scalar @additional_qsf ) {
        print QSF_FILE "\n$final_append\n";
      }

      close (QSF_FILE);
    }
  }

  # Set up for incremental change detection
  my $devicemodel = uc acl::Env::aocl_boardspec( "$board_spec_xml", "devicemodel");
  ($devicemodel) = $devicemodel =~ /(.*)_.*/;
  my $devicefamily = acl::AOCDriverCommon::device_get_family_no_normalization($devicemodel);
  my $run_change_detection = $incremental_compile && $incremental_input_dir ne "" &&
                             !acl::Incremental::requires_full_recompile($incremental_input_dir, $work_dir, $base, $all_aoc_args,
                                                                        acl::Env::board_name(), $board_variant, $devicemodel, $devicefamily,
                                                                        acl::AOCDriverCommon::get_quartus_version_str(), $prog,
                                                                        "18.1.0", "222");
  warn $acl::Incremental::warning if (defined $acl::Incremental::warning && !$quiet_mode);
  if ($incremental_compile && $run_change_detection) {
    $llc_arg_after .= " -incremental-input-dir=$incremental_input_dir -incremental-project-name=$base ";
  }

  my $optinfile = "$base.1.bc";
  my $pkg = undef;
  my $src_pkg = undef;

  # OK, no turning back remove the result file, so no one thinks we succedded
  unlink $src_pkg_file_final;

  if ($ecc_protected == 1){
    $llc_arg_after .= " -ecc ";
  }

  # Late environment check IFF we are using the emulator
  my $is_msvc_2015_or_later = acl::AOCDriverCommon::check_if_msvc_2015_or_later();

  my @cmd_list = ();

  # Create package file in directory, and save compile options.
  $pkg = create acl::Pkg($pkg_file);

  if ( defined $program_hash ){ 
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.hash',$program_hash);
  }
  if ($emulator_flow) {
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.board',$emulatorDevice);
  } elsif ($new_sim_mode) {
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.board',"SimulatorDevice");
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.simulator_object',"");
  } else {
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.board',$board_variant);
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.board_package',acl::Board_env::get_board_path());
  }

  # Store a random hash, and the inputs to quartus hash, in pkg. Should be added before quartus adds new HDL files to the working dir.
  acl::AOCDriverCommon::add_hash_sections($work_dir,$board_variant,$pkg_file,$all_aoc_args,$bsp_flow_name);

  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.compileoptions',join(' ',@user_opencl_args));
  # Set version of the compiler, for informational use.
  # It will be set again when we actually produce executable contents.
  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());

  # Get a list of all source files from all the dependency files
  my @files = acl::Report::get_file_list_from_dependency_files(@all_dep_files);
  acl::AOCDriverCommon::remove_named_files(@all_dep_files) unless $save_temps;

  if ( $profile ) {
    $src_pkg = create acl::Pkg($src_pkg_file);
    acl::AOCDriverCommon::save_pkg_section($src_pkg,'.acl.version',acl::Env::sdk_version());
    my $index = 0;
    foreach my $file (@files) {
      # "Unknown" files are included when opaque objects (such as image objects) are in the source code
      if ($file =~ m/\<unknown\>$/ or $file =~ m/$ocl_header_filename$/) {
        next;
      }
      acl::AOCDriverCommon::save_pkg_section($src_pkg,'.acl.file.'.$index,$file);
      $src_pkg->add_file('.acl.source.'. $index,$file)
      or acl::Common::mydie("Can't save source into package file: $acl::Pkg::error\n");
      $index = $index + 1;
    }
    acl::AOCDriverCommon::save_pkg_section($src_pkg,'.acl.nfiles',$index);
  }

  my @patterns_to_skip = ($ocl_header_filename);
  $fileJSON = acl::Report::get_source_file_info_for_visualizer(\@files, \@patterns_to_skip, $dash_g);

  # For emulator and non-emulator flows, extract clang-ir for library components
  # that were written using OpenCL
  # Figure out the compiler triple for the current flow.
  my $fpga_triple = 'spir64-unknown-unknown-intelfpga';
  my $emulator_triple = ($emulator_arch eq 'windows64') ? 'x86_64-pc-windows-intelfpga' : 'x86_64-unknown-linux-intelfpga';
  my $cur_flow_triple = $emulator_flow ? $emulator_triple : $fpga_triple;
  if ($#resolved_lib_files > -1) {
    foreach my $libfile (@resolved_lib_files) {
      if ($verbose >= 2) { print "Executing: $aocl_libedit_exe extract_clang_ir \"$libfile\" $cur_flow_triple $work_dir\n"; }
      my $new_files = `$aocl_libedit_exe extract_clang_ir \"$libfile\" $cur_flow_triple $work_dir`;
      if ($? == 0) {
        if ($verbose >= 2) { print "  Output: $new_files\n"; }
        push @lib_bc_files, split /\n/, $new_files;
      }
    }
  }
  # do not enter to the work directory before this point, 
  # $pkg->add_file above may be called for files with relative paths
  chdir $work_dir or acl::Common::mydie("Can't change dir into $work_dir: $!");

  if ($emulator_flow) {
    print "$prog: Compiling for Emulation ....\n" if (!$quiet_mode);
        unless ($emulator_fast) {
      # Link with standard library.
      my $emulator_lib = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_emulation.bc");
      @cmd_list = (
          $link_exe,
          $linked_objfile,
          @lib_bc_files,
          $emulator_lib,
          '-o',
          $optinfile );
      $return_status = acl::Common::mysystem_full(
          {'stdout' => "$work_dir/clang-link.log", 
           'stderr' => "$work_dir/clang-link.err",
           'time' => 1, 'time-label' => 'link (early)'},
          @cmd_list);
      my $banner = '!========== [link] early link ==========';
      acl::Common::move_to_log($banner, "$work_dir/clang-link.log", "$work_dir/$fulllog");
      acl::Report::append_to_err("$work_dir/clang-link.err");
      if ($return_status==0 or $regtest_mode==0) { unlink "$work_dir/clang-link.err"; }
      acl::AOCDriverCommon::remove_named_files($linked_objfile) unless $save_temps;

      foreach my $lib_bc_file (@lib_bc_files) {
        acl::AOCDriverCommon::remove_named_files($lib_bc_file) unless $save_temps;
      }
      
      if ($return_status != 0) {
        if ($regtest_mode) {
          acl::Common::move_to_log($banner, "$work_dir/clang-link.err", "$work_dir/../$regtest_errlog");
        }
        acl::Common::mydie("OpenCL parser FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }

      my $debug_option = ( $debug ? '-debug' : '');
      my $opt_optimize_level_string = ($emu_optimize_o3) ? "-O3" : "";

      if ( !(($emu_ch_depth_model eq 'default' ) || ($emu_ch_depth_model eq 'strict') || ($emu_ch_depth_model eq 'ignore-depth')) ) {
        acl::Common::mydie("Invalid argument for option --emulator-channel-depth-model, must be one of <default|strict|ignore-depth>. \n");
      }

      #UPLIFT - this was the command on trunk
      #"$opt_exe -verify-get-compute-id -translate-library-calls -reverse-library-translation -lowerconv -scalarize -scalarize-dont-touch-mem-ops -insert-ip-library-calls -createemulatorwrapper -emulator-channel-depth-model $emu_ch_depth_model -generateemulatorsysdesc $opt_optimize_level_string $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option $opt_arg_after \"$optinfile\" -o \"$base.bc\" >>$fulllog 2>opt.err" );
      $return_status = acl::Common::mysystem_full(
          {'time' => 1, 
           'time-label' => 'opt (opt (emulator tweaks))'},
           "$opt_exe -translate-library-calls -reverse-library-translation -insert-ip-library-calls -create-emulator-wrapper -generate-emulator-sys-desc -emulDirCleanup $opt_optimize_level_string $llvm_library_option $debug_option $opt_arg_after \"$optinfile\" -o \"$base.bc\" >>$fulllog 2>opt.err" );
      acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
      $banner = '!========== [aocl-opt] Emulator specific messages ==========';
      acl::Common::move_to_log($banner, $fulllog);
      acl::Report::append_to_log('opt.err', $fulllog);
      acl::Report::append_to_err('opt.err');
      if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
      if ($return_status != 0) {
        if ($regtest_mode) {
          acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog");
        }
        acl::Common::mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }

      $pkg->set_file('.acl.llvmir',"$base.bc")
          or acl::Common::mydie("Can't save optimized IR into package file: $acl::Pkg::error\n");

      #Issue an error if autodiscovery string is larger than 4k (only for version < 15.1).
      my $bsp_version = acl::Env::aocl_boardspec( "$board_spec_xml", "version");
      if( (-s "sys_description.txt" > 4096) && ($bsp_version < 15.1) ) {
        acl::Common::mydie("System integrator FAILED.\nThe autodiscovery string cannot be more than 4096 bytes\n");
      }
      $pkg->set_file('.acl.autodiscovery',"sys_description.txt")
          or acl::Common::mydie("Can't save system description into package file: $acl::Pkg::error\n");

      my $arch_options = ();
      if ($emulator_arch eq 'windows64') {
        $arch_options = "-cc1 -triple x86_64-pc-win32 -emit-obj -o libkernel.obj";
      } else {
        $arch_options = "-fPIC -shared -Wl,-soname,libkernel.so -L\"$ENV{\"INTELFPGAOCLSDKROOT\"}/host/linux64/lib/\" -lacl_emulator_kernel_rt -o libkernel.so";
      }
      
      my $clang_optimize_level_string = ($emu_optimize_o3) ? '-O3' : '-O0';

      $return_status = acl::Common::mysystem_full(
          {'time' => 1, 
           'time-label' => 'clang (executable emulator image)'},
          "$clang_exe $arch_options $clang_optimize_level_string \"$base.bc\" >>$fulllog 2>opt.err" );
      acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
      $banner = '!========== [clang compile kernel emulator] Emulator specific messages ==========';
      acl::Common::move_to_log($banner, $fulllog);
      acl::Report::append_to_log('opt.err', $fulllog);
      acl::Report::append_to_err('opt.err');
      if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
      if ($return_status != 0) {
        if ($regtest_mode) {
          acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog");
        }
        acl::Common::mydie("Optimizer FAILED.\nRefer to $base/$fulllog for details.\n");
      }

      if ($emulator_arch eq 'windows64') {
        my $legacy_stdio_definitions = $is_msvc_2015_or_later ? 'legacy_stdio_definitions.lib' : '';
        $return_status = acl::Common::mysystem_full(
            {'time' => 1, 
             'time-label' => 'clang (executable emulator image)'},
            "link /DLL /EXPORT:__kernel_desc,DATA /EXPORT:__channels_desc,DATA /libpath:$ENV{\"INTELFPGAOCLSDKROOT\"}\\host\\windows64\\lib acl_emulator_kernel_rt.lib msvcrt.lib $legacy_stdio_definitions libkernel.obj>>$fulllog 2>opt.err" );
        acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
        $banner = '!========== [Create kernel loadbable module] Emulator specific messages ==========';
        acl::Common::move_to_log($banner, $fulllog);
        acl::Report::append_to_log('opt.err', $fulllog);
        acl::Report::append_to_err('opt.err');
        if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
        if ($return_status != 0) {
          if ($regtest_mode) {
            acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog");
          }
          acl::Common::mydie("Linker FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }

        $pkg->set_file('.acl.emulator_object.windows',"libkernel.dll")
            or acl::Common::mydie("Can't save emulated kernel into package file: $acl::Pkg::error\n");
      } else {
        $pkg->set_file('.acl.emulator_object.linux',"libkernel.so")
          or acl::Common::mydie("Can't save emulated kernel into package file: $acl::Pkg::error\n");
      }

      if(-f "kernel_arg_info.xml") {
        $pkg->set_file('.acl.kernel_arg_info.xml',"kernel_arg_info.xml");
        unlink 'kernel_arg_info.xml' unless $save_temps;
      } else {
        print "Cannot find kernel arg info xml.\n" if $verbose;
      }
    } else {
      if ($emulator_arch eq 'windows64') {
        $pkg->set_file('.acl.fast_emulator_object.windows',$linked_objfile)
          or acl::Common::mydie("Can't save emulated kernel into package file: $acl::Pkg::error\n");
      } else {     
        $pkg->set_file('.acl.fast_emulator_object.linux',$linked_objfile)
          or acl::Common::mydie("Can't save emulated kernel into package file: $acl::Pkg::error\n");
      }
      acl::AOCDriverCommon::remove_named_files($linked_objfile) unless $save_temps;
      foreach my $lib_bc_file (@lib_bc_files) {
        acl::AOCDriverCommon::remove_named_files($lib_bc_file) unless $save_temps;
      }
    }

    my $compilation_env = acl::AOCDriverCommon::compilation_env_string($work_dir,$board_variant,$all_aoc_args,$bsp_flow_name);
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

    # Compute runtime.
    my $stage1_end_time = time();
    acl::Common::log_time ("emulator compilation", $stage1_end_time - $stage1_start_time);

    print "$prog: Emulator Compilation completed successfully.\n" if $verbose;
    &$finalize();
    return;
  } 

  # Link with standard library.
  my $early_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_early.bc");
  @cmd_list = (
      $link_exe,
      $linked_objfile,
      @lib_bc_files,
      $early_bc,
      '-o',
      $optinfile );
  $return_status = acl::Common::mysystem_full(
      {'stdout' => "$work_dir/clang-link.log", 
       'stderr' => "$work_dir/clang-link.err",
       'time' => 1, 
       'time-label' => 'link (early)'},
      @cmd_list);
  my $banner = '!========== [link] early link ==========';
  acl::Common::move_to_log($banner, "$work_dir/clang-link.log", "$work_dir/$fulllog");
  acl::Report::append_to_err("$work_dir/clang-link.err");
  if ($return_status==0 or $regtest_mode==0) { unlink "$work_dir/clang-link.err"; }
  acl::AOCDriverCommon::remove_named_files($linked_objfile) unless $save_temps;
  foreach my $lib_bc_file (@lib_bc_files) {
    acl::AOCDriverCommon::remove_named_files($lib_bc_file) unless $save_temps;
  }
  if ($return_status != 0) {
    if ($regtest_mode) {
      acl::Common::move_to_log($banner, "$work_dir/clang-link.log", "$work_dir/../$regtest_errlog");
    }
    acl::Common::mydie("OpenCL linker FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
  }


  chdir $work_dir or acl::Common::mydie("Can't change dir into $work_dir: $!");

  my $yaml_file = 'pass-remarks.yaml';
  my $disabled_lmem_replication = 0;
  my $restart_acl = 1;  # Enable first iteration
  my $opt_passes = $dft_opt_passes;
  if ( $soft_ip_c_flow ) {
      $opt_passes = $soft_ip_opt_passes;
  }

  my $iterationlog="iteration.tmp";
  my $iterationerr="$iterationlog.err";
  unlink $iterationlog; # Make sure we don't inherit from previous runs
  if ($griffin_flow) {
    # For the Griffin flow, we need to enable a few passes and change a few flags.
    #UPLIFT - these args not supported on UPLIFT
    #$opt_arg_after .= " --grif --soft-elementary-math=false --fas=false --wiicm-disable=true";
    $opt_arg_after .= " --soft-elementary-math=false ";
  }

  # For FPGA, we need to rewrite the triple.  Unfortunately, we can't do this in the regular -O3 opt, as
  # there are immutable passes (TargetLibraryInfo) that check the triple before we can run.  Run this
  # pass first as a standalone pass.  The alternate (better compile time) would be to run this as the last
  # part of clang, but that would also need changes to cllib.  See FB568473.
  my $triple_output = "$base.fpga.bc";
  $return_status = acl::Common::mysystem_full(
      {'time' => 1, 'time-label' => 'opt', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
      "$opt_exe -rewritetofpga \"$optinfile\" -o \"$triple_output\"");
  acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
  $banner = '!========== [opt] fpga ==========';
  acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog") if $regtest_mode;
  acl::Common::mydie("Unable to switch to FPGA triples\n") if $return_status != 0;
  if ($disassemble) { acl::AOCDriverCommon::mysystem("llvm-dis \"$base.fpga.bc\" -o \"$base.fpga.ll\"" ) == 0 or acl::Common::mydie("Cannot disassemble: \"$base.bc\" \n"); }
  $optinfile = $triple_output;
  if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
  ## END FPGA Triple support.

  while ($restart_acl) { # Might have to restart with lmem replication disabled
    unlink $iterationlog unless $save_temps;
    unlink $iterationerr; # Always remove this guy or we will get duplicates to the the screen;
    unlink "llvm_warnings.log"; # Prevent duplicate errors in report
    $restart_acl = 0; # Don't restart compiling unless lmem replication decides otherwise

    if ( $run_opt ) {
      print "$prog: Optimizing and doing static analysis of code...\n" if (!$quiet_mode);
      my $debug_option = ( $debug ? '-debug' : '');
      my $profile_option = ( $profile ? "-profile $profile" : '');
      my $opt_remarks_option = "-pass-remarks-output=$yaml_file";

      # Opt run
      $return_status = acl::Common::mysystem_full(
          {'time' => 1, 'time-label' => 'opt', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
          "$opt_exe $opt_passes $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option $profile_option $opt_arg_after $opt_remarks_option \"$optinfile\" -o \"$base.kwgid.bc\"");
      acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
      acl::Report::append_to_log('opt.err', $iterationerr);
      $banner = '!========== [opt] optimize ==========';
      acl::Common::move_to_log($banner, 'opt.log', $iterationlog);
      acl::Report::append_to_log('opt.err', $iterationlog);
      if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
      if ($return_status != 0) {
        if ($regtest_mode) {
          acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog");
        }
        # The design might've failed because it was too big with local mem replication,
        # but it could still pass size wise without replication - attempt again without replication
        open(TMP, "<$iterationerr");
        my $too_big = 0;
        while(defined(my $l = <TMP>) && !$too_big) {
          if (index($l, "use the flag \"-dont-error-if-large-area-est\"") != -1) {
            $too_big = 1;
          }
        }
        if ($too_big && !$disabled_lmem_replication) {
          $opt_arg_after .= $lmem_disable_replication_flag;
          $llc_arg_after .= $lmem_disable_replication_flag;
          $disabled_lmem_replication = 1;
          redo;  # Restart the compile loop
        }
        acl::Common::move_to_log("", $iterationlog, $fulllog);
        acl::Report::move_to_err($iterationerr);
        acl::Common::mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }
      acl::Common::move_to_log("", $iterationlog, $fulllog);

      if ( $use_ip_library && $use_ip_library_override ) {
        print "$prog: Linking with IP library ...\n" if $verbose;
        # Lower instructions to IP library function calls
        $return_status = acl::Common::mysystem_full(
            {'time' => 1, 'time-label' => 'opt (ip library prep)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe -insert-ip-library-calls $opt_arg_after \"$base.kwgid.bc\" -o \"$base.lowered.bc\"");
        acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
        acl::Report::append_to_log('opt.err', $iterationerr);
        $banner = '!========== [opt] ip library prep ==========';
        acl::Common::move_to_log($banner, 'opt.log', $fulllog);
        acl::Report::append_to_log('opt.err', $fulllog);
        if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
        if ($return_status != 0) {
          if ($regtest_mode) {
            acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog");
          }
          acl::Common::move_to_log("", $iterationlog, $fulllog);
          acl::Report::move_to_err($iterationerr);
          acl::Common::mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        acl::AOCDriverCommon::remove_named_files("$base.kwgid.bc") unless $save_temps;

        # Link with the soft IP library 
        my $late_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_late.bc");
        $return_status = acl::Common::mysystem_full(
            {'time' => 1, 'time-label' => 'link (ip library)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$link_exe \"$base.lowered.bc\" $late_bc -o \"$base.linked.bc\"" );
        acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
        acl::Report::append_to_log('opt.err', $iterationerr);
        $banner = '!========== [link] ip library link ==========';
        acl::Common::move_to_log($banner, 'opt.log', $fulllog);
        acl::Report::append_to_log('opt.err', $fulllog);
        if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
        if ($return_status != 0) {
          if ($regtest_mode) {
            acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog");
          }
          acl::Common::move_to_log("", $iterationlog, $fulllog);
          acl::Report::move_to_err($iterationerr); 
          acl::Common::mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        acl::AOCDriverCommon::remove_named_files("$base.lowered.bc") unless $save_temps;

        # Inline IP calls, simplify and clean up
        # "$opt_exe $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk -rename-basic-blocks $opt_arg_after \"$base.linked.bc\" -o \"$base.bc\"");
        $return_status = acl::Common::mysystem_full(
            {'time' => 1, 'time-label' => 'opt (ip library optimize)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option -always-inline -dce -stripnk -rename-basic-blocks $opt_arg_after \"$base.linked.bc\" -o \"$base.bc\"");
        acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
        acl::Report::append_to_log('opt.err', $iterationerr);
        $banner = '!========== [opt] ip library optimize ==========';
        acl::Common::move_to_log($banner, 'opt.log', $fulllog);
        acl::Report::append_to_log('opt.err', $fulllog);
        if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
        if ($return_status != 0) {
          if ($regtest_mode) {
            acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog");
          }
          acl::Common::move_to_log("", $iterationlog, $fulllog);
          acl::Report::move_to_err($iterationerr); 
          acl::Common::mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        acl::AOCDriverCommon::remove_named_files("$base.linked.bc") unless $save_temps;
      } else {
        # In normal flow, lower the acl kernel workgroup id last
        $return_status = acl::Common::mysystem_full(
            {'time' => 1, 'time-label' => 'opt (post-process)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option \"$base.kwgid.bc\" -o \"$base.bc\"");
        acl::Report::filter_llvm_time_passes("opt.err", $time_passes);
        acl::Report::append_to_log('opt.err', $iterationerr);
        $banner = '!========== [opt] post-process ==========';
        acl::Common::move_to_log($banner, 'opt.log', $fulllog);
        acl::Report::append_to_log('opt.err', $fulllog);
        if ($return_status==0 or $regtest_mode==0) { unlink 'opt.err'; }
        if ($return_status != 0) {
          if ($regtest_mode) {
            acl::Common::move_to_log($banner, 'opt.err', "$work_dir/../$regtest_errlog");
          }
          acl::Common::move_to_log("", $iterationlog, $fulllog);
          acl::Report::move_to_err($iterationerr); 
          acl::Common::mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        acl::AOCDriverCommon::remove_named_files("$base.kwgid.bc") unless $save_temps;
      }
    }

    # Finish up opt-like steps.
    if ( $run_opt ) {
      if ( $disassemble || $soft_ip_c_flow ) { acl::AOCDriverCommon::mysystem("llvm-dis \"$base.bc\" -o \"$base.ll\"" ) == 0 or acl::Common::mydie("Cannot disassemble: \"$base.bc\" \n"); }
      if ( $pkg_save_extra ) {
        $pkg->set_file('.acl.llvmir',"$base.bc")
           or acl::Common::mydie("Can't save optimized IR into package file: $acl::Pkg::error\n");
      }
      if ( $opt_only ) { return; }
    }

    if ( $run_verilog_gen ) {
      my $debug_option = ( $debug ? '-debug' : '');
      my $profile_option = ( $profile ? "-profile $profile" : '');
      #UPLIFT uses different llc_option_macro
      #my $llc_option_macro = $griffin_flow ? '__ACL_GRIFFIN_LLC_OPTIONS__' : '__ACL_LLC_OPTIONS__';
      my $llc_option_macro = ' -march=fpga ';
      my $llc_remarks_option = "-pass-remarks-input=$yaml_file";

      # Run LLC
      $return_status = acl::Common::mysystem_full(
          {'time' => 1, 'time-label' => 'llc', 'stdout' => 'llc.log', 'stderr' => 'llc.err'},
          "$llc_exe $llc_option_macro $llvm_board_option $llvm_efi_option $llvm_library_option $llvm_profilerconf_option $debug_option $profile_option $llc_remarks_option $llc_arg_after \"$base.bc\" -o \"$base.v\"");
      acl::Report::filter_llvm_time_passes("llc.err", $time_passes);
      acl::Report::append_to_log('llc.err', $iterationerr);
      $banner = '!========== [llc] ==========';
      acl::Common::move_to_log($banner, 'llc.log', 'llc.err', $iterationlog);
      if ($return_status != 0) {
        # The design might've failed because it was too big with local mem replication, 
        # but it could still pass size wise without replication - attempt again without replication
        open (TMP, "<$iterationerr");
        my $too_big_in_llc = 0;
        while(defined(my $l = <TMP>) && !$too_big_in_llc) {
          if (index($l, "use the flag \"-dont-error-if-large-area-est\"") != -1){
            $too_big_in_llc = 1;
          }
        }
        if ($too_big_in_llc && !$disabled_lmem_replication) {
          $opt_arg_after .= $lmem_disable_replication_flag;
          $llc_arg_after .= $lmem_disable_replication_flag;
          $disabled_lmem_replication = 1;
          redo;  # Restart the compile loop
        }
        acl::Common::move_to_log("", $iterationlog, $fulllog);
        acl::Report::append_to_err($iterationerr);
        if ($regtest_mode==0) { unlink $iterationerr; }
        open (LOG, "<$fulllog");
        while (defined(my $line = <LOG>)) {
          print $win_longpath_suggest if (acl::AOCDriverCommon::win_longpath_error_llc($line) and acl::Env::is_windows());
        }
        if ($regtest_mode) {
          acl::Common::move_to_log($banner, $iterationerr, "$work_dir/../$regtest_errlog");
        }
        acl::Common::mydie("Verilog generator FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }
      #llc has been run already, so the yaml file used for reporting is not needed anymore. Cleanup
      acl::AOCDriverCommon::remove_named_files($yaml_file) unless $save_temps;

      # If estimate > $max_mem_percent_with_replication of block ram, rerun opt with lmem replication disabled
     print "Checking if memory usage is larger than $max_mem_percent_with_replication%\n" if $verbose && !$disabled_lmem_replication;
      my $area_rpt_file_path = $work_dir."/area.json";
      my $xml_file_path = $work_dir."/$base.bc.xml";
      my $restart_without_lmem_replication = 0;
      if (-e $area_rpt_file_path) {
        my @area_util = acl::AOCDriverCommon::get_area_percent_estimates();
        if ( $area_util[3] > $max_mem_percent_with_replication && !$disabled_lmem_replication ) {
          # Check whether memory replication was activate
          my $repl_factor_active = 0;
          if ( -e $xml_file_path ) {
            open my $xml_handle, '<', $xml_file_path or die $!;
            while ( <$xml_handle> ) {
              my $xml = $_;
              if ( $xml =~ m/.*LOCAL_MEM.*repl_fac="(\d+)".*/ ) {
                if ( $1 > 1 ) {
                  $repl_factor_active = 1;
                }
              }
            }
            close $xml_handle;
          }

          if ( $repl_factor_active ) {
            print "$prog: Restarting compile without lmem replication because of estimated overutilization!\n" if $verbose;
            $restart_without_lmem_replication = 1;
          }
        }
      } else {
        print "$prog: Cannot find area.json. Disabling lmem optimizations to be safe.\n";
        $restart_without_lmem_replication = 1;
      }
      if ( $restart_without_lmem_replication ) {
        $opt_arg_after .= $lmem_disable_replication_flag;
        $llc_arg_after .= $lmem_disable_replication_flag;
        $disabled_lmem_replication = 1;
        redo;  # Restart the compile loop
      }
    }
  } # End of while loop

  foreach my $qsf_file (acl::File::simple_glob( "$work_dir/*.qsf" )) {
      open (QSF_FILE, ">>$qsf_file") or die "Couldn't open $qsf_file for append!\n";
    # Workaround fix for ECC, since the memory init files will be instantiated through 
    # a wrapper, in the ip directory, causing the synthesis failing to find the .hex 
    # files for some reason. (FB:544479)
    if ($ecc_protected) {
      foreach my $dir ( acl::File::simple_glob( "$work_dir/kernel_hdl/*") ) {
        if (!(-d $dir)) {
          next;
        }
        $dir=~ s/$work_dir\///e; # Make it a relative path
        print QSF_FILE "set_global_assignment -name SEARCH_PATH \"$dir\"\n";
      }
    }
    close (QSF_FILE);
  }
  
  acl::Common::move_to_log("",$iterationlog,$fulllog);
  acl::Report::move_to_err($iterationerr);
  acl::AOCDriverCommon::remove_named_files($optinfile) unless $save_temps;

  #Put after loop so we only store once
  if ( $pkg_save_extra ) {
    $pkg->set_file('.acl.verilog',"$base.v")
      or acl::Common::mydie("Can't save Verilog into package file: $acl::Pkg::error\n");
  }

  # Save the profile XML file in the aocx
  if ( $profile ) {
    acl::AOCDriverCommon::save_profiling_xml($pkg,$base);
  }

  # Move over the Optimization Report to the log file
  if ( -e "opt.rpt" ) {
    acl::Report::append_to_log( "opt.rpt", $fulllog );
    unlink "opt.rpt" unless $save_temps;
  }

  unlink "report.out";
  if (( $estimate_throughput ) && ( !$accel_gen_flow ) && ( !$soft_ip_c_flow )) {
      print "Estimating throughput since \$estimate_throughput=$estimate_throughput\n";
    $return_status = acl::Common::mysystem_full(
        {'time' => 1, 'time-label' => 'opt (throughput)', 'stdout' => 'report.out', 'stderr' => 'report.err'},
        "$opt_exe -print-throughput -throughput-print $llvm_board_option $opt_arg_after \"$base.bc\" -o $base.unused" );
    acl::Report::filter_llvm_time_passes("report.err", $time_passes);
    acl::AOCDriverCommon::move_to_err_and_log("Throughput analysis","report.err",$fulllog);
  }
  unlink "$base.unused";

  # Guard probably deprecated, if we get here we should have verilog, was only used by vfabric
  if ( $run_verilog_gen) {

    # Round these numbers properly instead of just truncating them.
    my @all_util = acl::AOCDriverCommon::get_area_percent_estimates();

    open LOG, ">>report.out";
    printf(LOG "\n".
          "!===========================================================================\n".
          "! The report below may be inaccurate. A more comprehensive           \n".
          "! resource usage report can be found at $base/reports/report.html    \n".
          "!===========================================================================\n".
          "\n".
          "+--------------------------------------------------------------------+\n".
          "; Estimated Resource Usage Summary                                   ;\n".
          "+----------------------------------------+---------------------------+\n".
          "; Resource                               + Usage                     ;\n".
          "+----------------------------------------+---------------------------+\n".
          "; Logic utilization                      ; %4d\%                     ;\n".
          "; ALUTs                                  ; %4d\%                     ;\n".
          "; Dedicated logic registers              ; %4d\%                     ;\n".
          "; Memory blocks                          ; %4d\%                     ;\n".
          "; DSP blocks                             ; %4d\%                     ;\n".
          "+----------------------------------------+---------------------------;\n",
          $all_util[0], $all_util[1], $all_util[2], $all_util[3], $all_util[4]);
    close LOG;

    acl::Report::append_to_log ("report.out", $fulllog);
  }
  if ($report) {
    open LOG, "<report.out";
    print STDOUT <LOG>;
    close LOG;
  }
  unlink "report.out" unless $save_temps;

  if ($save_last_bc) {
    $pkg->set_file('.acl.profile_base',"$base.bc")
      or acl::Common::mydie("Can't save profiling base listing into package file: $acl::Pkg::error\n");
  }
  acl::AOCDriverCommon::remove_named_files("$base.bc") unless $save_temps or $save_last_bc;

  my $xml_file = "$base.bc.xml";
  my $sysinteg_debug .= ($debug ? "-v" : "" );

  if ($run_change_detection) {
    #pass previous _sys.v file as an argument to system integrator. used for incremental compile change detection
    my $prev_sysv = $base."_sys.v";
    $sysinteg_arg_after .= " --incremental-previous-systemv $incremental_input_dir/$prev_sysv";
    #also add previous bc.xml file as system integrator argument
    $sysinteg_arg_after .= " --incremental-previous-bcxml $incremental_input_dir/$xml_file";
    #add partition grouping file written out by system integrator during the previous compile
    $sysinteg_arg_after .= " --incremental-previous-partition-grouping $incremental_input_dir/previous_partition_grouping_incremental.txt";
  }

  my $version = ::acl::Env::aocl_boardspec( ".", "version");
  my $generic_kernel = ::acl::Env::aocl_boardspec( ".", "generic_kernel".$bsp_flow_name);
  my $qsys_file = ::acl::Env::aocl_boardspec( ".", "qsys_file".$bsp_flow_name);
  ( $generic_kernel.$qsys_file !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n");
  
  my $system_script = ($qsys_file eq "none") ? "none" : "system.tcl";
  my $kernel_system_script = (($new_sim_mode) or ($qsys_file ne "none") or ($bsp_version < 18.0)) ? "kernel_system.tcl" : "";
  my $sysinteg_arg_scripts = $system_script . " " . $kernel_system_script;

  #remove warning log generated by previous system integrator execution, if any.
  #this will prevent duplicated warning/error msg
  unlink "system_integrator_warnings.log";
  if ( $generic_kernel or ($version eq "0.9" and -e "base.qsf")) {
    $return_status = acl::Common::mysystem_full(
      {'time' => 1, 'time-label' => 'system integrator', 'stdout' => 'si.log', 'stderr' => 'si.err'},
      "$sysinteg_exe $sysinteg_debug $sysinteg_arg_after $board_spec_xml \"$xml_file\" $sysinteg_arg_scripts" );
  } else {
    if ($qsys_file eq "none") {
      acl::Common::mydie("A board with 'generic_kernel' set to \"0\" and 'qsys_file' set to \"none\" is an invalid combination in board_spec.xml! Please revise your BSP for errors!\n");  
    }
    $return_status = acl::Common::mysystem_full(
      {'time' => 1, 'time-label' => 'system integrator', 'stdout' => 'si.log', 'stderr' => 'si.err'},
      "$sysinteg_exe $sysinteg_debug $sysinteg_arg_after $board_spec_xml \"$xml_file\" system.tcl" );
  }
  $banner = '!========== [SystemIntegrator] ==========';
  acl::Common::move_to_log($banner, 'si.log', $fulllog);
  acl::Report::append_to_log('si.err', $fulllog);
  acl::Report::append_to_err('si.err');
  if ($return_status==0 or $regtest_mode==0) { unlink 'si.err'; }
  if ($return_status != 0) {
    if ($regtest_mode) {
      acl::Common::move_to_log($banner, 'si.err', "$work_dir/../$regtest_errlog");
    }
    acl::Common::mydie("System integrator FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
  }

  #Issue an error if autodiscovery string is larger than 4k (only for version < 15.1).
  if( (-s "sys_description.txt" > 4096) && ($bsp_version < 15.1) ) {
    acl::Common::mydie("System integrator FAILED.\nThe autodiscovery string cannot be more than 4096 bytes\n");
  }
  $pkg->set_file('.acl.autodiscovery',"sys_description.txt")
    or acl::Common::mydie("Can't save system description into package file: $acl::Pkg::error\n");

  if(-f "autodiscovery.xml") {
    $pkg->set_file('.acl.autodiscovery.xml',"autodiscovery.xml")
      or acl::Common::mydie("Can't save system description xml into package file: $acl::Pkg::error\n");    
  } else {
     print "Cannot find autodiscovery xml\n";
  }  

  if(-f "board_spec.xml") {
    $pkg->set_file('.acl.board_spec.xml',"board_spec.xml")
      or acl::Common::mydie("Can't save boardspec.xml into package file: $acl::Pkg::error\n");
  } else {
     print "Cannot find board spec xml\n";
  } 

  if(-f "kernel_arg_info.xml") {
    $pkg->set_file('.acl.kernel_arg_info.xml',"kernel_arg_info.xml");
    unlink 'kernel_arg_info.xml' unless $save_temps;
  } else {
     print "Cannot find kernel arg info xml.\n" if $verbose;
  }

  my $report_time = time();
  acl::AOCDriverCommon::create_reporting_tool($fileJSON, $base, $all_aoc_args, $board_variant, $disabled_lmem_replication, $devicemodel, $devicefamily);
  acl::Common::log_time("Generate static reports", time()-$report_time);

  # Move all JSON files to the reports directory.
  my $json_dir = "$work_dir/reports/lib/json";
  my @json_files = ("area_src", "area", "loops", "summary", "lmv", "mav", "info", "warnings", "quartus", "incremental.initial", "incremental.change", "schedule_info");
  foreach (@json_files) {
    my $json_file = $_.".json";
    if ( -e $json_file ) {
      # There is no acl::File::move, so copy and remove instead.
      acl::File::copy($json_file, "$json_dir/$json_file")
        or warn "Can't copy $_.json to $json_dir\n";
      acl::AOCDriverCommon::remove_named_files($json_file) unless $save_temps;
    }
  }
  
  # Get '.acl.target' from .aoco file, check if it is fpga, and save the target into .aocr file
  my $temp_obj = $objfile_list[0];
  my $obj_pkg = get acl::Pkg($temp_obj) or die "Can't find pkg file $temp_obj: $acl::Pkg::error\n";   
  my $obj_target = acl::AOCDriverCommon::get_pkg_section($obj_pkg,'.acl.target');
  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.target', $obj_target);
  
  if ($obj_target eq 'fpga') {
    # Save the cmd which invokes the quartus_html_report.tcl file into .aocr file
    my $update_html_script = acl::Env::sdk_root()."/share/lib/tcl/quartus_html_report.tcl";
    my @cmd_list = ();
    (my $mProg = $prog) =~ s/#//g;
    @cmd_list = (
        "quartus_sh", 
        "-t", 
        $update_html_script, 
        $mProg);
    acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.update_html_report',join(' ', @cmd_list));
  }

  my $compilation_env = acl::AOCDriverCommon::compilation_env_string($work_dir,$board_variant,$all_aoc_args,$bsp_flow_name);
  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

  print "$prog: First stage compilation completed successfully.\n" if (!$quiet_mode); 
  # Compute aoc runtime WITHOUT Quartus time or integration, since we don't control that
  my $stage1_end_time = time();
  acl::Common::log_time ("first compilation stage", $stage1_end_time - $stage1_start_time);

  if ($incremental_compile && -e "prev") {
    acl::File::remove_tree("prev")
      or acl::Common::mydie("Cannot remove files under temporary directory prev: $!\n");
  }

  if ( $verilog_gen_only || $accel_gen_flow ) { return; }

  &$finalize();
}
