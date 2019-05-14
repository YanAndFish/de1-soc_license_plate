
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

acl::AOCDriverCommon.pm - Common functions and glob vars used by OpenCL compiler driver

=head1 VERSION

$Header: //acds/rel/18.1/acl/sysgen/lib/acl/AOCDriverCommon.pm#3 $

=head1 DESCRIPTION

Common functions and global vars used by OpenCL compiler driver

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


package acl::AOCDriverCommon;
use strict;
use Exporter;

require acl::Common;
require acl::Env;
require acl::File;
require acl::Pkg;
require acl::Report;
use acl::Report qw(escape_string);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw ( check_if_msvc_2015_or_later hard_routing_error win_longpath_error_llc 
                      win_longpath_error_quartus kernel_fit_error hard_routing_error_code
                      remove_duplicate save_profiling_xml mysystem move_to_err_and_log get_quartus_version_str
                      create_reporting_tool get_area_percent_estimates remove_named_files compilation_env_string
                      add_hash_sections save_pkg_section device_get_family_no_normalization version
                      find_board_spec get_acl_board_hw_path get_pkg_section get_pll_frequency get_kernel_list );

our @EXPORT = qw( $prog $emulatorDevice $return_status @given_input_files $output_file @srcfile_list
                  @objfile_list $linked_objfile $x_file $absolute_srcfile @absolute_srcfile_list
                  $absolute_efispec_file $absolute_profilerconf_file $marker_file $board_variant $work_dir
                  @lib_files @lib_paths @resolved_lib_files @lib_bc_files $created_shared_aoco
                  $ocl_header_filename $ocl_header $clang_exe $opt_exe $link_exe $llc_exe $sysinteg_exe
                  $aocl_libedit_exe $ioc_exe $fulllog $quartus_log $regtest_mode $regtest_errlog $parse_only
                  $opt_only $verilog_gen_only $ip_gen_only $high_effort $skip_qsys $compile_step
                  $aoco_to_aocr_aocx_only $aocr_to_aocx_only $griffin_flow $emulator_flow $emulator_fast
                  $soft_ip_c_flow $accel_gen_flow $run_quartus $standalone $hdl_comp_pkg_flow
                  $c_acceleration $new_sim_mode  $is_pro_mode $simulation_mode $no_automigrate
                  $emu_optimize_o3 $emu_ch_depth_model $fast_compile $high_effort_compile $incremental_compile $empty_kernel_flow
                  $save_partition_file $set_partition_file $user_defined_board $user_defined_flow
                  $soft_region_on $atleastoneflag $report_only $c_flag_only $optarea $force_initial_dir $orig_force_initial_dir
                  $use_ip_library $use_ip_library_override $do_env_check $dsploc $ramloc $cpu_count 
                  $report $estimate_throughput $debug $time_log_filename $time_passes $dotfiles $pipeline_viewer
                  $timing_slack_check $slack_value $tidy $pkg_save_extra $library_debug $save_last_bc
                  $disassemble $fit_seed $profile $program_hash $triple_arg $dash_g $user_dash_g $ecc_protected
                  $ecc_max_latency @user_clang_args @user_opencl_args $opt_arg_after $llc_arg_after
                  $clang_arg_after $sysinteg_arg_after $max_mem_percent_with_replication @additional_migrations
                  @blocked_migrations $efispec_file $profilerconf_file $dft_opt_passes $soft_ip_opt_passes
                  $device_spec $soft_ip_c_name $accel_name $lmem_disable_split_flag @additional_qsf @additional_ini
                  $lmem_disable_replication_flag $qbindir $exesuffix $tmp_dir $emulator_arch $acl_root
                  $bsp_version $target_model @all_files @all_dep_files @clang_warnings
                  $ACL_CLANG_IR_SECTION_PREFIX @CLANG_IR_TYPE_SECT_NAME $QUARTUS_VERSION $win_longpath_suggest );

# Global Variables
our $prog = 'aoc';
our $emulatorDevice = 'EmulatorDevice'; #Must match definition in acl.h
our $return_status = 0;

#Filenames
our @given_input_files; # list of input files specified on command line.
our $output_file = undef; # -o argument
our @srcfile_list; # might be relative or absolute
our @objfile_list; # might be relative or absolute
our $linked_objfile = undef;
our $x_file = undef; # might be relative or absolute
our $absolute_srcfile = undef; # absolute path
our @absolute_srcfile_list = ();
our $absolute_efispec_file = undef; # absolute path of the EFI Spec file
our $absolute_profilerconf_file = undef; # absolute path of the Profiler Config file
our $marker_file = ".project.marker"; # relative path of the marker file to the project working directory
our $board_variant = undef;

#directories
our $work_dir = undef; # absolute path of the project working directory

#library-related
our @lib_files;
our @lib_paths;
our @resolved_lib_files;
our @lib_bc_files = ();
our $created_shared_aoco = undef;
our $ocl_header_filename = "opencl_lib.h";
our $ocl_header = $ENV{'INTELFPGAOCLSDKROOT'}."/share/lib/acl"."/".$ocl_header_filename;

# Executables
our $clang_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-clang";
our $opt_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-opt";
our $link_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-link";
our $llc_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/../../llvm/bin/aocl-llc";
our $sysinteg_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/system_integrator";
our $aocl_libedit_exe = "aocl library";
our $ioc_exe = "ioc64";

#Log files
our $fulllog = undef;
our $quartus_log = 'quartus_sh_compile.log';

our $regtest_mode = 0;
our $regtest_errlog = 'reg.err';

#Flow control
our $parse_only = 0; # Hidden option to stop after clang.
our $opt_only = 0; # Hidden option to only run the optimizer
our $verilog_gen_only = 0; # Hidden option to only run the Verilog generator
our $ip_gen_only = 0; # Hidden option to only run up until ip-generate, used by sim
our $high_effort = 0;
our $skip_qsys = 0; # Hidden option to skip the Qsys generation of "system"
our $compile_step = 0; # stop after generating .aoco
our $aoco_to_aocr_aocx_only = 0; # start with .aoco file(s) and run through till system Integrator or quartus
our $aocr_to_aocx_only = 0; # start with .aocr file and run through quartus only
our $griffin_flow = 1; # Use DSPBA backend instead of HDLGeneration
our $emulator_flow = 0;
our $emulator_fast = 0;
our $soft_ip_c_flow = 0;
our $accel_gen_flow = 0;
our $run_quartus = 0;
our $standalone = 0;
our $hdl_comp_pkg_flow = 0; #Forward args from 'aoc' to 'aocl library'
our $c_acceleration = 0; # Hidden option to skip clang for C Acceleration flow.
# TODO: Deprecate old simulation mode
our $new_sim_mode  = 0;
our $is_pro_mode = 0;
our $simulation_mode = 0; #Hidden option to generate full board verilogs targeted for simulation  (aoc -s foo.cl)
our $no_automigrate = 0; #Hidden option to skip BSP Auto Migration
our $emu_optimize_o3 = 0; #Apply -O3 optimizations for the emulator flow
our $emu_ch_depth_model = 'default'; #Channel depth mode in emulator flow 
our $fast_compile = 0; #Allows user to speed up compile times while suffering performance hit
our $high_effort_compile = 0; #Allow user to specify compile with high effort on performance
our $incremental_compile = ''; #Internal flag for forcing partitions to be saved in incremental compile
our $empty_kernel_flow = 0; #Internal flag for compiling with kernel set to empty in Quartus
our $save_partition_file = ''; #Internal flag for forcing partitions to be created in incremental compile
our $set_partition_file = ''; #Allows user to speed compile times while suffering performance hit
our $user_defined_board = 0; # True if the user specifies -board or -board-package option
our $user_defined_flow = 0; # True if the user specifies -simulate or -march=emulator
our $soft_region_on = ''; #Add soft region settings
our $atleastoneflag = 0;
our $report_only = 0;
our $c_flag_only = 0;

#Flow modifiers
our $optarea = 0;
our $force_initial_dir = ''; # Absolute path of original working directory the user told us to use.
                             # This variable may be modified by the AOC driver.
our $orig_force_initial_dir = ''; # Absolute path of original working directory the user told us to use.
                                  # This variable will not change from the value that the user passed in.
our $use_ip_library = 1; # Should AOC use the soft IP library
our $use_ip_library_override = 1;
our $do_env_check = 1;
our $dsploc = '';
our $ramloc = '';
our $cpu_count = -1;
our @additional_qsf = ();
our @additional_ini = ();

#Output control
our $report = 0; # Show Throughput and area analysis
our $estimate_throughput = 0; # Show Throughput guesstimate
our $debug = 0; # Show debug output from various stages
our $time_log_filename = undef; # Filename from --time arg
our $time_passes = 0; # Time LLVM passes. Requires $time_log_fh to be valid.
# Should we be tidy? That is, delete all intermediate output and keep only the output .aclx file?
# Intermediates are removed only in the --hw flow
our $dotfiles = 0;
our $pipeline_viewer = 0;
our $timing_slack_check = 0; #Detect slack timing violation and error out
our $slack_value = undef; #Default slack value is undefined
our $tidy = 0; 
our $pkg_save_extra = 0; # Save extra items in the package file: source, IR, verilog
our $library_debug = 0;

# Yet unclassfied
our $save_last_bc= 0; #don't remove final bc if we are generating profiles
our $disassemble = 0; # Hidden option to disassemble the IR
our $fit_seed = undef; # Hidden option to set fitter seed
our $profile = 0; # Option to enable profiling
our $program_hash = undef; # SHA-1 hash of program source, options, and board.
our $triple_arg = '';
our $dash_g = 1;      # Debug info enabled by default. Use -g0 to disable.
our $user_dash_g = 0; # Indicates if the user explictly compiled with -g.
our $ecc_protected = 0;
our $ecc_max_latency = 0;

# Regular arguments.  These go to clang, but does not include the .cl file.
our @user_clang_args = ();

# The compile options as provided by the clBuildProgram OpenCL API call.
# In a standard flow, the ACL host library will generate the .cl file name, 
# and the board spec, so they do not appear in this list.
our @user_opencl_args = ();

our $opt_arg_after = ''; # Extra options for opt, after regular options.
our $llc_arg_after = '';
our $clang_arg_after = '';
our $sysinteg_arg_after = '';
our $max_mem_percent_with_replication = 100;
our @additional_migrations = ();
our @blocked_migrations = ();

our $efispec_file = undef;
our $profilerconf_file = undef;
our $dft_opt_passes = undef;
our $soft_ip_opt_passes = undef;

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
our $device_spec = "";
our $soft_ip_c_name = "";
our $accel_name = "";

our $lmem_disable_split_flag = '-no-lms=1';
our $lmem_disable_replication_flag = ' -no-local-mem-replication=1';

# On Windows, always use 64-bit binaries.
# On Linux, always use 64-bit binaries, but via the wrapper shell scripts in "bin".
our $qbindir = ( $^O =~ m/MSWin/ ? 'bin64' : 'bin' );

# For messaging about missing executables
our $exesuffix = ( $^O =~ m/MSWin/ ? '.exe' : '' );

# temporary app data directory
our $tmp_dir = ( $^O =~ m/MSWin/ ? "$ENV{'USERPROFILE'}\\AppData\\Local\\aocl" : "/var/tmp/aocl/$ENV{USERNAME}" );

our $emulator_arch = acl::Env::get_arch();

our $acl_root = acl::Env::sdk_root();

# Variables used multiple times in aoc.pl 
our $bsp_version = undef;
our $target_model = undef;

our @all_files = ();
our @all_dep_files = ();
our @clang_warnings = ();

# Types of IR that we may have
# AOCO sections in shared mode will have names of form:
#    $ACL_CLANG_IR_SECTION_PREFIX . $CLANG_IR_TYPE_SECT_NAME[ir_type]
our $ACL_CLANG_IR_SECTION_PREFIX = ".acl.clang_ir";
our @CLANG_IR_TYPE_SECT_NAME = (
  'spir64-unknown-unknown-intelfpga',
  'x86_64-unknown-linux-intelfpga',
  'x86_64-pc-windows-intelfpga'
);

our $QUARTUS_VERSION = undef; # Saving the output of quartus_sh --version globally to save time.
our $win_longpath_suggest = "\nSUGGESTION: Windows has a 260 limit on the length of a file name (including the full path). The error above *may* have occurred due to the compiler generating files that exceed that limit. Please trim the length of the directory path you ran the compile from and try again.\n\n";

# Family used by simulator qsys-generate. Value from Quartus get_part_info API
my $family_from_quartus = undef;

# Local Functions

sub _mysystem_redirect($@) {
  # Run command, but redirect standard output to $outfile.
  my ($outfile,@cmd) = @_;
  return acl::Common::mysystem_full ({'stdout' => $outfile}, @cmd);
}

# Exported Functions

sub check_if_msvc_2015_or_later() {
  my $is_msvc_2015_or_later = 0;
  if (($emulator_arch eq 'windows64') && ($emulator_flow == 1) && ($emulator_fast == 0) ) {
    my $msvc_out = `LINK 2>&1`;
    chomp $msvc_out; 

    if ($msvc_out !~ /Microsoft \(R\) Incremental Linker Version/ ) {
      acl::Common::mydie("$prog: Can't find VisualStudio linker LINK.EXE.\nEither use Visual Studio x64 Command Prompt or run %INTELFPGAOCLSDKROOT%\\init_opencl.bat to setup your environment.\n");
    }
    my ($linker_version) = $msvc_out =~ /(\d+)/;
    if ($linker_version >= 14 ){
      #FB:441273 Since VisualStudio 2015, the way printf is dealt with has changed.
      $is_msvc_2015_or_later = 1;
    }
  }
  return $is_msvc_2015_or_later;
}

#remove duplicate words in a strings
sub remove_duplicate {
  my ($word) = @_;
  my @words = split / /, $word;
  my @newwords;
  my %done;
  for (@words) {
  push(@newwords,$_) unless $done{$_}++;
  }
  join ' ', @newwords;
}

sub hard_routing_error_code($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /Error\s*\(170113\):/ ) {
    return 1;
  }
  return 0;
}

sub kernel_fit_error($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /Error\s*\(11802\):/ ) {
    return 1;
  }
  return 0;
}

sub win_longpath_error_quartus($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /Error\s*\(14989\):/ ) {
    return 1;
  }
  if( $error_string =~ /Error\s*\(19104\):/ ) {
    return 1;
  }
  if( $error_string =~ /Error\s*\(332000\):/ ) {
    return 1;
  }
  return 0;
}

sub win_longpath_error_llc($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /Error:\s*Could not open file/ ) {
    return 1;
  }
  return 0;
}

sub hard_routing_error($@)
 { #filename
     my $infile = shift @_;
     open(ERR, "<$infile");  ## if there is no $infile, we just return 0;
     while( <ERR> ) {
       if( hard_routing_error_code( $_ ) ) {
         return 1;
       }
     }
     close ERR;
     return 0;
 }

sub save_profiling_xml($$) {
  my ($pkg,$basename) = @_;
  # Save the profile XML file in the aocx
  $pkg->add_file('.acl.profiler.xml',"$basename.bc.profiler.xml")
      or acl::Common::mydie("Can't save profiler XML $basename.bc.profiler.xml into package file: $acl::Pkg::error\n");
}

sub mysystem(@) {
  return _mysystem_redirect('',@_);
}

# This is called between a system call and check child error so
# it can NOT do system calls
sub move_to_err_and_log { #String filename ..., logfile
  my $string = shift @_;
  my $logfile = pop @_;
  foreach my $infile (@_) {
    open ERR, "<$infile"  or acl::Common::mydie("Couldn't open $infile for reading.");
    while(my $l = <ERR>) {
      print STDERR $l;
    }
    close ERR;
    acl::Common::move_to_log($string, $infile, $logfile);
  }
}

sub get_quartus_version_str() {
  # capture Version info (starting with "Version") and Edition info (ending up with "Edition")
  my ($quartus_version_str1) = $QUARTUS_VERSION =~ /Version (.* Build \d*)/;
  my ($quartus_version_str2) = $QUARTUS_VERSION =~ /( \w+) Edition/;
  my $quartus_version = $quartus_version_str1 . $quartus_version_str2;
  return $quartus_version;
}

sub create_reporting_tool {
  my $fileJSON = shift;
  my $base = shift;
  my $all_aoc_args = shift;
  my $board_variant = shift;
  my $disabled_lmem_repl = shift;
  my $devicemodel = shift;
  my $devicefamily = shift;

  my $verbose = acl::Common::get_verbose();

  # Need to call board_name() before modifying $/
  my ($board_name) = acl::Env::board_name();

  local $/ = undef;

  acl::File::make_path("$work_dir/reports") or return;
  acl::Report::copy_files($work_dir) or return;

  # Collect information for infoJSON, and print it to the report
  (my $mProg = $prog) =~ s/#//g;
  my $infoJSON = acl::Report::create_infoJSON(1, escape_string($base), $devicefamily, $devicemodel, get_quartus_version_str(), "$mProg ".escape_string($all_aoc_args), escape_string("$board_name:$board_variant"));

  # warningsJSON
  my @log_files = ("llvm_warnings.log", "system_integrator_warnings.log");
  # Create clang_warnings file
  if (open(OUTPUT,">", "clang_warnings.log")) {
    unshift @log_files, "clang_warnings.log";
    foreach my $line (@clang_warnings) {
      print OUTPUT "$line";
    }
    close OUTPUT;
  }
  my $warningsJSON = acl::Report::create_warningsJSON(@log_files, $disabled_lmem_repl);
  unlink @log_files;
  
  # quartusJSON
  my $quartus_text = "This section contains a summary of the area and fmax data generated by compiling the kernels through Quartus. \n".
                     "To generate the data, run a Quartus compile on the project created for this design. \n".
                     "To run the Quartus compile, please run command without flag -c, -rtl or -march=emulator";
  my $quartusJSON = acl::Report::create_quartusJSON($quartus_text);

  # create the area_src json file
  acl::Report::parse_to_get_area_src($work_dir);
  # List of JSON files to print to report_data.js
  my @json_files = ("area", "area_src", "mav", "lmv", "loops", "summary");
  open (my $report, ">$work_dir/reports/lib/report_data.js") or return;

  acl::Report::create_json_file_or_print_to_report($report, "info", $infoJSON, \@json_files);
  acl::Report::create_json_file_or_print_to_report($report, "warnings", $warningsJSON, \@json_files);
  acl::Report::create_json_file_or_print_to_report($report, "quartus", $quartusJSON, \@json_files);

  # Add incremental JSON files if they exist
  push @json_files, "incremental.initial" if -e "incremental.initial.json";
  push @json_files, "incremental.change" if -e "incremental.change.json";

  # Add schduler report
  push @json_files, "schedule_info" if -e "schedule_info.json";

  acl::Report::print_json_files_to_report($report, \@json_files);

  print $report $fileJSON;
  close($report);

  # create empty verification data file to avoid browser console error
  open (my $verif_report, ">$work_dir/reports/lib/verification_data.js") or return;
  print $verif_report "";
  close($verif_report);

  if ($pipeline_viewer) {
    acl::Report::create_pipeline_viewer($work_dir, "kernel_hdl", $verbose);
  }
}

sub get_area_percent_estimates {
  # Get utilization numbers (in percent) from area.json.
  # The file must exist when this function is called.

  open my $area_json, '<', $work_dir."/area.json";
  my $util = 0;
  my $les = 0;
  my $ffs = 0;
  my $rams = 0;
  my $dsps = 0;

  while (my $json_line = <$area_json>) {
    if ($json_line =~ m/\[([.\d]+), ([.\d]+), ([.\d]+), ([.\d]+), ([.\d]+)\]/) {
      # Round all percentage values to the nearest whole number.
      $util = int($1 + 0.5);
      $les = int($2 + 0.5);
      $ffs = int($3 + 0.5);
      $rams = int($4 + 0.5);
      $dsps = int($5 + 0.5);
      last;
    }
  }
  close $area_json;

  return ($util, $les, $ffs, $rams, $dsps);
}

sub remove_named_files {
    my $verbose = acl::Common::get_verbose();
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose == 1 ? 0 : $verbose), dry_run => 0 } )
         or acl::Common::mydie("Cannot remove intermediate files under directory $fname: $acl::File::error\n");
    }
}

sub compilation_env_string($$$$){
  my ($work_dir,$board_variant,$input_args,$bsp_flow_name) = @_;
  #Case:354532, not handling relative address for AOCL_BOARD_PACKAGE_ROOT correctly.
  my $starting_dir = acl::File::abs_path('.');  #keeping to change back to this dir after being done.
  my $orig_dir = acl::Common::get_original_dir();
  chdir $orig_dir or acl::Common::mydie("Can't change back into directory $orig_dir: $!");

  # Gathering all options and tool versions.
  my $acl_board_hw_path = acl::AOCDriverCommon::get_acl_board_hw_path($board_variant);
  my $board_spec_xml = acl::AOCDriverCommon::find_board_spec($acl_board_hw_path);
  my $build_number = "222";
  my $acl_Version = "18.1.0";
  my $clang_version; my $llc_version; my $sys_integrator_version; my $ioc_version;
  if ($emulator_fast) {
    $ioc_version = `$ioc_exe -version`;
    $ioc_version =~ s/\s+/ /g; #replacing all white spaces with space
  } else {
    $clang_version = `$clang_exe --version`;
    $clang_version =~ s/\s+/ /g; #replacing all white spaces with space
    $llc_version = `$llc_exe --version`;
    $llc_version =~ s/\s+/ /g; #replacing all white spaces with space
    $sys_integrator_version = `$sysinteg_exe --version`;
    $sys_integrator_version =~ s/\s+/ /g; #replacing all white spaces with space
  }
  my $lib_path = "$ENV{'LD_LIBRARY_PATH'}";
  my $board_pkg_root = "$ENV{'AOCL_BOARD_PACKAGE_ROOT'}";
  if (!$QUARTUS_VERSION) {
    $QUARTUS_VERSION = `quartus_sh --version`;
  }
  my $quartus_version = $QUARTUS_VERSION;
  $quartus_version =~ s/\s+/ /g; #replacing all white spaces with space

  # Quartus compile command
  my $synthesize_cmd = ::acl::Env::aocl_boardspec( $acl_board_hw_path, "synthesize_cmd".$bsp_flow_name);
  ( $target_model.$synthesize_cmd !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n");
  my $acl_qsh_compile_cmd="$ENV{'ACL_QSH_COMPILE_CMD'}"; # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default quartus compile command (internal use only).

  # Concatenating everything
  my $res = "";
  $res .= "INPUT_ARGS=".$input_args."\n";
  $res .= "BUILD_NUMBER=".$build_number."\n";
  $res .= "ACL_VERSION=".$acl_Version."\n";
  $res .= "OPERATING_SYSTEM=$^O\n";
  $res .= "BOARD_SPEC_XML=".$board_spec_xml."\n";
  $res .= "TARGET_MODEL=".$target_model."\n";
  if ($emulator_fast) {
    $res .= "IOC_VERSION=".$ioc_version."\n";
  } else {
    $res .= "CLANG_VERSION=".$clang_version."\n";
    $res .= "LLC_VERSION=".$llc_version."\n";
    $res .= "SYS_INTEGRATOR_VERSION=".$sys_integrator_version."\n";
  }
  $res .= "LIB_PATH=".$lib_path."\n";
  $res .= "AOCL_BOARD_PKG_ROOT=".$board_pkg_root."\n";
  $res .= "QUARTUS_VERSION=".$quartus_version."\n";
  $res .= "QUARTUS_OPTIONS=".$synthesize_cmd."\n";
  $res .= "ACL_QSH_COMPILE_CMD=".$acl_qsh_compile_cmd."\n";

  chdir $starting_dir or acl::Common::mydie("Can't change back into directory $starting_dir: $!"); # Changing back to the dir I started with
  return $res;
}

# Adds a unique hash for the compilation, and a section that contains 3 hashes for the state before quartus compile.
sub add_hash_sections($$$$$) {
  my ($work_dir,$board_variant,$pkg_file,$input_args,$bsp_flow_name) = @_;
  my $pkg = get acl::Pkg($pkg_file) or acl::Common::mydie("Can't find package file: $acl::Pkg::error\n");

  #Case:354532, not handling relative address for AOCL_BOARD_PACKAGE_ROOT correctly.
  my $starting_dir = acl::File::abs_path('.');  #keeping to change back to this dir after being done.
  my $orig_dir = acl::Common::get_original_dir();
  chdir $orig_dir or acl::Common::mydie("Can't change back into directory $orig_dir: $!");

  my $compilation_env = compilation_env_string($work_dir,$board_variant,$input_args,$bsp_flow_name);

  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

  # Random unique hash for this compile:
  my $hash_exe = acl::Env::sdk_hash_exe();
  my $temp_hashed_file="$work_dir/hash.tmp"; # Temporary file that is used to pass in strings to aocl-hash
  my $ftemp;
  my $random_hash_key;
  open($ftemp, '>', $temp_hashed_file) or die "Could not open file $!";
  my $rand_key = rand;
  print $ftemp "$rand_key\n$compilation_env";
  close $ftemp;


  $random_hash_key = `$hash_exe \"$temp_hashed_file\"`;
  unlink $temp_hashed_file;
  
  chomp $random_hash_key;
  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.rand_hash',$random_hash_key);
  $sysinteg_arg_after .= " --rand-hash $random_hash_key";

  # The hash of inputs and options to quartus + quartus versions:
  my $before_quartus;

  my $acl_board_hw_path = acl::AOCDriverCommon::get_acl_board_hw_path($board_variant);
  if (!$QUARTUS_VERSION) {
    $QUARTUS_VERSION = `quartus_sh --version`;
  }
  my $quartus_version = $QUARTUS_VERSION;
  $quartus_version =~ s/\s+/ /g; #replacing all white spaces with space

  # Quartus compile command
  my $synthesize_cmd = ::acl::Env::aocl_boardspec( $acl_board_hw_path, "synthesize_cmd".$bsp_flow_name);
  ( $bsp_flow_name !~ /error/ ) or acl::Common::mydie("BSP compile-flow $bsp_flow_name not found\n");
  my $acl_qsh_compile_cmd="$ENV{'ACL_QSH_COMPILE_CMD'}"; # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default quartus compile command (internal use only).

  open($ftemp, '>', $temp_hashed_file) or die "Could not open file $!";
  print $ftemp "$quartus_version\n$synthesize_cmd\n$acl_qsh_compile_cmd\n";
  close $ftemp;

  $before_quartus.= `$hash_exe \"$temp_hashed_file\"`; # Quartus input args hash
  $before_quartus.= `$hash_exe -d \"$acl_board_hw_path\"`; # All bsp directory hash
  $before_quartus.= `$hash_exe -d \"$work_dir\" --filter .v --filter .sv --filter .hdl --filter .vhdl`; # HDL files hash

  unlink $temp_hashed_file;
  acl::AOCDriverCommon::save_pkg_section($pkg,'.acl.quartus_input_hash',$before_quartus);
  chdir $starting_dir or acl::Common::mydie("Can't change back into directory $starting_dir: $!"); # Changing back to the dir I started with.
}

sub save_pkg_section($$$) {
   my ($pkg,$section,$value) = @_;
   # The temporary file should be in the compiler work directory.
   # The work directory has already been created.
   my $file = $work_dir.'/value.txt';
   open(VALUE,">$file") or acl::Common::mydie("Can't write to $file: $!");
   binmode(VALUE);
   print VALUE $value;
   close VALUE;
   $pkg->set_file($section,$file)
       or acl::Common::mydie("Can't save value into package file: $acl::Pkg::error\n");
   unlink $file;
}

# Copied from i++.pl
sub device_get_family_no_normalization {  # DSPBA needs the original Quartus format
    my $local_start = time();
    my $qii_family_device = shift;

    return $family_from_quartus if (defined($family_from_quartus));

    # only query when we don't have one
    $family_from_quartus = `quartus_sh --tcl_eval get_part_info -family $qii_family_device`;
    if ($family_from_quartus !~ /\{.+\}/) {
      # s10 specific problem: there is no 1sg280lu3f50e1vgs1 device, instead it is 1sg280lu3f50e1vg (without the "s1" at the end)
      # $family_from_quartus will be empty if an unrecognized device is provided, try again by cutting off the last 2 chars
      ($qii_family_device) = substr($qii_family_device, 0, -2);
      $family_from_quartus = `quartus_sh --tcl_eval get_part_info -family $qii_family_device`;
    }
    # Return only what's between the braces, without the braces
    ($family_from_quartus) = ($family_from_quartus =~ /\{(.*)\}/);
    chomp $family_from_quartus;
    # Error out when we couldn't get anything, i.e. licence server not available
    acl::Common::mydie("$prog: Can't get family from Quartus for device: $qii_family_device.\n") if ($family_from_quartus eq "");
    # log_time ('Get device family', time() - $local_start) if ($time_log_fh);
    acl::Common::log_time ('Get device family', time() - $local_start) if ($time_log_filename);
    return $family_from_quartus;
}

sub version($) {
  my $outfile = $_[0];
  print $outfile "Intel(R) FPGA SDK for OpenCL(TM), 64-Bit Offline Compiler\n";
  print $outfile "Version 18.1.0 Build 222 Pro Edition\n";
  print $outfile "Copyright (C) 2018 Intel Corporation\n";
}

# Make sure the board specification file exists. Return directory of board_spec.xml
sub find_board_spec {
  my ($acl_board_hw_path) = @_;
  my ($board_spec_xml) = acl::File::simple_glob( $acl_board_hw_path."/board_spec.xml" );
  my $xml_error_msg = "Cannot find Board specification!\n*** No board specification (*.xml) file inside ".$acl_board_hw_path.". ***\n" ;
  if ( $device_spec ne "" ) {
    my $full_path =  acl::File::abs_path( $device_spec );
    $board_spec_xml = $full_path;
    $xml_error_msg = "Cannot find Device Specification!\n*** device file ".$board_spec_xml." not found.***\n";
  }
  -f $board_spec_xml or acl::Common::mydie( $xml_error_msg );
  return $board_spec_xml;
}

sub get_acl_board_hw_path {
  my $bv = shift @_;
  my ($result) = acl::Env::board_hw_path($bv);
  return $result;
}

sub get_pkg_section($$) {
  my ($pkg,$section) = @_;
  my $file = 'value.txt';
  my $value = undef;
  $pkg->get_file($section,$file)
      or acl::Common::mydie("Can't get value into file: $acl::Pkg::error\n");
  open(VALUE,"<$file") or acl::Common::mydie("Can't read from $file: $!");
  $value = <VALUE>;
  close VALUE;
  unlink $file;
  chomp $value;
  return $value;
}

# Parse acl_quartus_report.txt file to get frequencies
# $a_kmax is the actual kernel fmax, $k_fmax is the theoretical kernel fmax, $fmax2 is 2x clock fmax
# Since $k_fmax would always be either $fmax1 or $fmax2/2 in OpenCL, it would be enough to tell if 2x clock is being used and if it is limiting the kernel fmax with $k_fmax and $fmax2 only
sub get_pll_frequency() {
  my $infile = 'acl_quartus_report.txt';
  my $verbose = acl::Common::get_verbose();
  open(IN, "<$infile") or acl::Common::mydie("Failed to open $infile");  
  my $a_fmax = -1;
  my $k_fmax = -1;
  my $fmax2 = -1;
  # Get the printed message
  while( <IN> ) {
    if( $_ =~ /Actual clock freq: (.*)/) {
      $a_fmax = $1;
    } elsif( $_ =~ /Kernel fmax: (.*)/ ) {
      $k_fmax = $1;
    } elsif( $_ =~ /2x clock fmax: (.*)/ ) {
      $fmax2 = $1;
      last;
    }
  }
  close IN;
  if (($a_fmax == -1) || ($k_fmax == -1)) {
    print "$prog: Warning: Missing fmax in $infile\n";
  } elsif ($fmax2 eq "Unused") {
    $fmax2 = -1;
  }

  return ($a_fmax, $k_fmax, $fmax2);
}

sub get_kernel_list($) {
  # read the comma-separated list of components from a file
  my $base = $_[0];
  my $project_bc_xml_filename = "${base}.bc.xml";
  my $BC_XML_FILE;
  
  open (BC_XML_FILE, "<${project_bc_xml_filename}") or acl::Common::mydie "Couldn't open ${project_bc_xml_filename} for read!\n";
  my @kernel_array;
  my $num = 0;
  my $counter = 0;
  while(my $var =<BC_XML_FILE>) {
    if ($var =~ /<KERNEL_BUNDLE name="(.*)" compute_units="(.*)"/) {
      $num = $2;
      $counter = 0;
    } elsif ($var =~ /<KERNEL name="(.*)" filename=/) {
      if ($counter < $num) {
        my $kernel_str = $1 . "," . $counter;
        $counter++;
        push(@kernel_array,$kernel_str);
      } else {
        acl::Common::mydie( "The number of compute unit is wrong for ${1}, please check ${project_bc_xml_filename} for more details!\n" );
      }
    }
  }
  
  close BC_XML_FILE;
  return @kernel_array;
}

1;
