
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

acl::AOCInputParser.pm - Process user input

=head1 VERSION

$Header: //acds/rel/18.1/acl/sysgen/lib/acl/AOCInputParser.pm#3 $

=head1 DESCRIPTION

This module provides the method to parse user input. It also
contains the global variables that the compiler driver uses.

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


package acl::AOCInputParser;
use strict;
use Exporter;

require acl::Env;
require acl::File;
require acl::Simulator;
use acl::AOCDriverCommon;
use acl::Common;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw ( parse_args process_args );

# Helper Functions

# Deal with multiple specified source files
sub _process_input_file_arguments {
  my $num_extracted_c_model_files = shift;
  my $verbose = acl::Common::get_verbose();

  if ($#given_input_files == -1) {
    # No input files are given
    return "";
  }

  # Only multiple .cl or .aoco files are allowed. Can't mix
  my %suffix_cnt = ();
  foreach my $gif (@given_input_files) {
    my $suffix = $gif;
    $suffix =~ s/.*\.//;
    $suffix =~ tr/A-Z/a-z/;
    $suffix_cnt{$suffix}++;
  }

  # Error checks, even for one file
    
  if ($suffix_cnt{'c'} > 0 and !($soft_ip_c_flow || $c_acceleration)) {
    # Pretend we never saw it i.e. issue the same message as we would for 
    # other not recognized extensions. Not the clearest message, 
    # but at least consistent
    acl::Common::mydie("No recognized input file format on the command line");
  }
  
  # If multiple aocr file is given as input then error out
  if ($suffix_cnt{'aocr'} > 1) {
    acl::Common::mydie("Cannot compile more than one .aocr file. \n");
  }

  # If have multiple files, they should either all be .cl files or all be .aoco files
  if ($#given_input_files > 0 and 
      (($suffix_cnt{'cl'} < $#given_input_files+1) and ($suffix_cnt{'aoco'} < $#given_input_files+1))) {
    # Have some .cl files but not ALL .cl files. Not allowed.
    acl::Common::mydie("If multiple input files are specified, either all must be .cl files or all must be .aoco files .\n");
  }
  
  # Make sure aoco file is not an HDL component package
  if ($suffix_cnt{'aoco'} > 0) {
    $aoco_to_aocr_aocx_only = 1;
    foreach my $object (@given_input_files) {
      system(acl::Env::sdk_pkg_editor_exe(), $object, 'exists', '.comp_header');
      if ($? == 0) {
        acl::Common::mydie("$object is a HDL component package. It cannot be used by itself to do hardware compiles!\n");
      }
    }
  }

  # If aocr file is given as input then move directly to third step (quartus)
  if ($suffix_cnt{'aocr'} eq 1) {
    $aocr_to_aocx_only = 1;
  }

  # For emulation flow, if library(ies) are specified, 
  # extract all C model files and add them to the input file list.
  if ($emulator_flow and $#resolved_lib_files > -1) {
    
    # C model files from libraries will be extracted to this folder
    my $c_model_folder = ".emu_models";
    
    # If it already exists, clean it out.
    if (-d $c_model_folder) {
      chdir $c_model_folder or die $!;
        opendir (DIR, ".") or die $!;
        while (my $file = readdir(DIR)) {
          if ($file ne "." and $file ne "..") {
            unlink $file;
          }
        }
        closedir(DIR);
      chdir ".." or die $!;
    } else {
      mkdir $c_model_folder or die $!;
    }
    
    my @c_model_files;
    foreach my $libfile (@resolved_lib_files) {
      my $new_files = `$aocl_libedit_exe extract_c_models \"$libfile\" $c_model_folder`;
      push @c_model_files, split /\n/, $new_files;
    }

    # Add library files to the front of file list.
    if ($verbose) {
      print "All OpenCL C models were extracted from specified libraries and added to compilation\n";
    }
    $$num_extracted_c_model_files = scalar @c_model_files;
    @given_input_files = (@c_model_files, @given_input_files);
  }

  # Make 'base' name for all naming purposes (subdir, aoco/aocx files) to 
  # be based on the last source file. Otherwise, it will be __all_sources, 
  # which is unexpected.
  my $last_src_file = $given_input_files[-1];
  
  return acl::File::mybasename($last_src_file);
}

sub _usage() {
  my $default_board_text;
  my $board_env = &acl::Board_env::get_board_path() . "/board_env.xml";

  if (-e $board_env) {
    my $default_board;
    ($default_board) = &acl::Env::board_hardware_default();
    $default_board_text = "Default is $default_board.";
  } else {
    $default_board_text = "Cannot find default board location or default board name.";
  }
  print <<USAGE;

aoc -- Intel(R) FPGA SDK for OpenCL(TM) Kernel Compiler

Usage: aoc <options> <file>.[cl|aoco|aocr]

Example:
       # First generate an <file>.aoco file
       aoc -c mykernels.cl
       # Now compile the project to generate reports and to generate an
       <file>.aocr file
       aoc -rtl mykernels.c
       # Now compile the project into a hardware programming file <file>.aocx.
       aoc mykernels.aoco or aoc mykernels.aocr
       # Or generate all at once
       aoc mykernels.cl

Outputs:
       <file>.aocx and/or <file>.aocr and/or <file>.aoco 

Help Options:
-version
          Print out version infomation and exit

-v        
          Verbose mode. Report progress of compilation

-q
          Quiet mode. Progress of compilation is not reported

-report
          Print area estimates to screen after initial compilation. The report
          is always written to the log file.  This option only has an effect
          during the RTL generation stage (generally this means generating an
          '.aocr' or '.aocx' file).

-h
-help    
          Show this message

Overall Options:
-c        
          Stop after generating a <file>.aoco

-rtl
          Stop after generating reports and a <file>.aocr

-o <output> 
          Use <output> as the name for the output.
          If running with the '-c' option the output file extension should be
          '.aoco'; if running with the '-rtl' option the output file extension
          should be '.aocr'.  Otherwise the file extension should be '.aocx'.
          If no extension is specified, the appropriate extension will be added
          automatically.

-march=<emulator|simulator>
          emulator: create kernels that can be executed on x86
          simulator: create kernels that can be executed by ModelSim

-fast-emulator
          Target the fast emulator (preview).

-g        
          Add debug data to kernels. Also, makes it possible to symbolically
          debug kernels created for the emulator on an x86 machine (Linux only).
          This behavior is enabled by default. This flag may be used to override
          the -g0 flag.

-g0        
          Don't add debug data to kernels.

-profile(=<all|autorun|enqueued>)
          Enable profile support when generating aocx file:
          all: profile all kernels.
          autorun: profile only autorun kernels.
          enqueued: profile only non-autorun kernels.
          If there is no argument provided, then the mode defaults to 'all'.
          Note that this does have a small performance penalty since profile
          counters will be instantiated and take some FPGA resources.

-shared
          Compile OpenCL source file into an object file that can be included
          into a library. Implies -c. 

-ecc
          Enable ECC on all RAMS.

-I <directory> 
          Add directory to header search path.
          
-L <directory>
          Add directory to OpenCL library search path.
          
-l <library.aoclib>
          Specify OpenCL library file.

-D <name> 
          Define macro, as name=value or just name.

-W        
          Suppress warning.

-Werror   
          Make all warnings into errors.

-library-debug Generate debug output related to libraries.

Modifiers:
-board=<board name>
          Compile for the specified board. $default_board_text

-list-boards
          Print a list of available boards and exit.

-board-package=<board package path>
          Specify the path of board package to use for compilation. If none 
          given, the default board package is used. This argument is required 
          when multiple board packages are installed.
          
-bsp-flow=<flow name>
          Specify the bsp compilation flow by name. If none given, the board's
          default flow is used.

Incremental Compilation:

-incremental[=aggressive]
          Enable incremental compilation mode, preserving sections of the
          design in partitions for future compilations to reduce compile time.

          Incremental compilation reduces compilation time but degrades
          efficiency. Use this feature for internal development only.

          Aggressive incremental compilation mode enables more extensive
          preservation techniques to reduce compilation time at the cost of
          further efficiency degradation.

-incremental-input-dir=<path>
          Specify the location of the previous incremental compilation project
          directory, to be used as this compilation's base. If this flag is not
          specified, aoc will look in the default project directory.

-incremental-flow=[retry|no-retry]
          Control how the OpenCL compiler reacts to compilation failures in
          incremental compilation mode. Default: retry.

          retry:    In the event of a compilation failure, recompile the project
                    without using previously preserved kernel partitions.
                    
          no-retry: Do not retry upon experiencing a compilation failure.

-incremental-grouping=<partition file>
          Specify how aoc should group kernels into partitions. Each line
          specifies a new partition with a semicolon (;) delimited list of
          kernel names. Each unspecified kernel will be assigned its own
          partition.

Optimization Control:

-no-interleaving=<global memory name>
          Configure a global memory as separate address spaces for each
          DIMM/bank.  User should then use the Altera specific cl_mem_flags
          (E.g.  CL_CHANNEL_2_INTELFPGA) to allocate each buffer in one DIMM or
          the other. The argument 'default' can be used to configure the default
          global memory. Consult your board's documentation for the memory types
          available. See the Best Practices Guide for more details.

-const-cache-bytes=<N>
          Configure the constant cache size (rounded up to closest 2^n).
          If none of the kernels use the __constant address space, this 
          argument has no effect. 

-fp-relaxed
          Allow the compiler to relax the order of arithmetic operations,
          possibly affecting the precision

-fpc 
          Removes intermediary roundings and conversions when possible, 
          and changes the rounding mode to round towards zero for 
          multiplies and adds

-fast-compile
          Compiles the design with reduced effort for a faster compile time but
          reduced fmax and lower power efficiency. Compiled aocx should only be
          used for internal development and not for deploying in final product.

-high-effort
          Increases aocx compile effort to improve ability to fit
          kernel on the device.

-emulator-channel-depth-model=<default|strict|ignore-depth>
          Controls the depths of channels used by the emulator:
          default:      Channels with explicitly-specified depths will use the
                        specified depths.  Channels with unspecified depths will
                        use a depth >10000.
          strict:       As default except channels of unspecified depth will use
                        a depth of 1.
          ignore-depth: All channels will use a depth >10000.

-cl-single-precision-constant
-cl-denorms-are-zero
-cl-opt-disable
-cl-strict-aliasing
-cl-mad-enable
-cl-no-signed-zeros
-cl-unsafe-math-optimizations
-cl-finite-math-only
-cl-fast-relaxed-math
           OpenCL required options. See OpenCL specification for details


USAGE
#-initial-dir=<dir>
#          Run the parser from the given directory.  
#          The default is to run the parser in the current directory.

#          Use this option to properly resolve relative include 
#          directories when running the compiler in a directory other
#          than where the source file may be found.
#-save-extra
#          Save kernel program source, optimized intermediate representation,
#          and Verilog into the program package file.
#          By default, these items are not saved.
#
#-no-env-check
#          Skip environment checks at startup.
#          Use this option to save a few seconds of runtime if you 
#          already know the environment is set up to run the Intel(R) FPGA SDK
#          for OpenCL(TM) compiler.
#-dot
#          Dump out DOT graph of the kernel pipeline.

}


sub _powerusage() {
  print <<POWERUSAGE;

aoc -- Intel(R) FPGA SDK for OpenCL(TM) Kernel Compiler

Usage: aoc <options> <file>.[cl|aoco]

Help Options:

-powerhelp    
          Show this message

Modifiers:
-seed=<value>
          Run the Quartus compile with a seed value of <value>. Default is '1'.

-dsploc=<compile directory>
          Extract DSP locations from given <compile directory> post-fit netlist
          and use them in current Quartus compile

-ramloc=<compile directory>
          Extract RAM locations from given <compile directory> post-fit netlist
          and use them in current Quartus compile

-timing-threshold=<slackvalue>
          Allow the compiler to generate an error if the slack from quartus STA
          is more than the value specified

POWERUSAGE

}

# Some aoc args translate to args to many underlying exes.
sub _process_meta_args {
  my ($cur_arg, $argv) = @_;
  my $processed = 0;
  if ( ($cur_arg eq '--1x-clock-for-local-mem') or ($cur_arg eq '-1x-clock-for-local-mem') ) {
    if ($cur_arg eq '--1x-clock-for-local-mem') {
      print "Warning: Command has been deprecated. Please use -1x-clock-for-local-mem instead of --1x-clock-for-local-mem\n";
    }
    # TEMPORARY: don't actually enforce this flag
    #$opt_arg_after .= ' -force-1x-clock-local-mem';
    #$llc_arg_after .= ' -force-1x-clock-local-mem';
    $processed = 1;
  }
  elsif ( ($cur_arg eq '--sw_dimm_partition') or ($cur_arg eq '--sw-dimm-partition') or ($cur_arg eq '-sw_dimm_partition') or ($cur_arg eq '-sw-dimm-partition')) {
    
    if ($cur_arg eq '--sw_dimm_partition') {
      print "Warning: Command has been deprecated. Please use -sw_dimm_partition instead of --sw_dimm_partition\n";
    }

    if ($cur_arg eq '--sw-dimm-partition') {
      print "Warning: Command has been deprecated. Please use -sw-dimm-partition instead of --sw-dimm-partition\n";
    }
    # TODO need to do this some other way
    # this flow is incompatible with the dynamic board selection (--board)
    # because it overrides the board setting
    $sysinteg_arg_after .= ' --cic-global_no_interleave ';
    $llc_arg_after .= ' -use-swdimm=default';
    $processed = 1;
  }

  return $processed;
}

# Exported Functions

sub parse_args {

  my ( $args_ref,
       $bsp_variant_ref,
       $bsp_flow_name_ref,
       $regtest_bak_cache_ref,
       $incremental_input_dir_ref,
       $verbose_ref,
       $quiet_mode_ref,
       $save_temps_ref,
       $sim_accurate_memory_ref,
       $sim_kernel_clk_frequency_ref,
       @input_argv ) = @_;

  while (@input_argv) {
    my $arg = shift @input_argv;

    # case:492114 treat options that start with -l as a special case.
    # By putting this code at the top we enforce that all options
    # starting with -l must be added to the l_opts_exclude array or else
    # they won't work because they'll be treated as a library name.
    if ( ($arg =~ m!^-l(\S+)!) ) {
      my $full_opt = '-l' . $1;
      my $excluded = 0;

      # If you add an option that starts with -l you must update the
      # l_opts_exclude list.
      foreach my $opt_name (@acl::Common::l_opts_exclude) {
        if ( ($full_opt =~ m!^$opt_name!) ) {
          # Options on the exclusion list are parsed in the long
          # if/elsif chain below like every other option.
          $excluded = 1;
          last;
        }
      }

      # -l<libname>
      if (!$excluded) {
          push (@lib_files, $1);
          next;
      }
    }

    # -h / -help
    if ( ($arg eq '-h') or ($arg eq '-help') or ($arg eq '--help') ) {
      if ($arg eq '--help') {
        print "Warning: Command has been deprecated. Please use -help instead of --help\n";
      }
      _usage(); 
      exit 0; 
    }
    # -powerhelp
    elsif ( ($arg eq '-powerhelp') or ($arg eq '--powerhelp') ) {
      if ($arg eq '--powerhelp') {
        print "Warning: Command has been deprecated. Please use -powerhelp instead of --powerhelp\n";
      }
      _powerusage();
      exit 0;
    }
    # -version / -V
    elsif ( ($arg eq '-version') or ($arg eq '-V') or ($arg eq '--version') ) {
      if ($arg eq '--version') {
        print "Warning: Command has been deprecated. Please use -version instead of --version\n";
      }
      acl::AOCDriverCommon::version(\*STDOUT);
      exit 0;
    }
    # -list-deps
    elsif ( ($arg eq '-list-deps') or ($arg eq '--list-deps') ) {
      if ($arg eq '--list-deps') {
        print "Warning: Command has been deprecated. Please use -list-deps instead of --list-deps\n";
      }
      print join("\n",values %INC),"\n";
      exit 0;
    }
    # -list-boards
    elsif ( ($arg eq '-list-boards') or ($arg eq '--list-boards') ) {
      if ($arg eq '--list-boards') {
        print "Warning: Command has been deprecated. Please use -list-boards instead of --list-boards\n";
      }
      acl::Common::list_boards();
      exit 0;
    }
    # -v
    elsif ( ($arg eq '-v') ) {
      $$verbose_ref += 1;
      acl::Common::set_verbose($$verbose_ref);
      if ($$verbose_ref > 1) {
        $prog = "#$prog";
      }
    }
    # -q
    elsif ( ($arg eq '-q') ) {
      $$quiet_mode_ref = 1;
      acl::Common::set_quiet_mode($$quiet_mode_ref);
    }
    # -hw
    elsif ( ($arg eq '-hw') or ($arg eq '--hw') ) {
      if ($arg eq '--hw') {
        print "Warning: Command has been deprecated. Please use -hw instead of --hw\n";
      }
      $run_quartus = 1;
    }
    # -quartus
    elsif ( ($arg eq '-quartus') or ($arg eq '--quartus') ) {
      if ($arg eq '--quartus') {
        print "Warning: Command has been deprecated. Please use -quartus instead of --quartus\n";
      }
      $skip_qsys = 1;
      $run_quartus = 1;
    }
    # -standalone
    elsif ( ($arg eq '-standalone') or ($arg eq '--standalone') ) {
      if ($arg eq '--standalone') {
        print "Warning: Command has been deprecated. Please use -standalone instead of --standalone\n";
      }
      $standalone = 1;
    }
    # -d
    elsif ( ($arg eq '-d') ) {
      $debug = 1;
    }
    # -s
    elsif ( ($arg eq '-s') ) {
      $simulation_mode = 1;
      $ip_gen_only = 1;
      $atleastoneflag = 1;
    }
    # -simulate / -march=simulator / -march=io_channel_simulator
    elsif ( ($arg eq '-simulate') or ($arg eq '--simulate') or ($arg eq '-march=simulator')) {
      if ($arg eq '--simulate') {
        print "Warning: Command has been deprecated. Please use -march=simulator instead of --simulate\n";
      }
      elsif ($arg eq '-simulate') {
        print "Warning: Command has been deprecated. Please use -march=simulator instead of -simulate\n";
      }
      $new_sim_mode = 1;
      $user_defined_flow = 1;
      $ip_gen_only = 1;
      $atleastoneflag = 1;
    }
    # -ghdl / -ghdl=<value>
    elsif ($arg =~ /-ghdl(=(\S+))?/) {
      acl::Simulator::set_sim_debug(1);
      if (defined $2) {
        # error check for 0
        my $depth_val = $2;
        if ($depth_val =~ /\d+/ && $depth_val > 0) {
          acl::Simulator::set_sim_debug_depth($depth_val);
        }
        else {
          acl::Common::mydie("Option -ghdl= requires an integer argument greater than or equal to 1\n");
        }
      }
      else {
        acl::Simulator::set_sim_debug_depth(undef);
      }
    }
    # -sim-acc-mem  Hidden option for accurate memory model from the board
    elsif ( $arg eq '-sim-acc-mem' ) {
      $$sim_accurate_memory_ref = 1;
      acl::Simulator::set_sim_accurate_memory($$sim_accurate_memory_ref);
    }
    # -sim-clk-freq=<value>  Hidden option for simulating kernel system with a different frequency in MHz
    elsif ( $arg =~ /-sim-clk-freq(=(\d+))?/ ) {
      my $argument_value = $1;
      if (!defined($argument_value)) {
        acl::Common::mydie("Option -sim-clk-freq= requires an argument with value between 100 and 1000\n");
      } elsif ($2 < 100 || $2 > 1000) {
        # do some error checking, i.e. a number between 100 and 1000
        acl::Common::mydie("Option -sim-clk-freq= value must be between 100 and 1000\n");
      } else {
        $$sim_kernel_clk_frequency_ref = $2;
        acl::Simulator::set_sim_kernel_clk_frequency($$sim_kernel_clk_frequency_ref);
      }
    }
    elsif ( $arg eq '-sim-enable-warnings' ) {
      acl::Simulator::set_sim_enable_warnings(1);
    }
    # -sim-input-dir  Hidden option to avoid regenerating simulation files to save compile time
    elsif ( $arg =~ /-sim-input-dir(=(\S+))?/) {
      my $argument_value = $1;
      if (defined($argument_value)) {
        # overwrite the default simulation folder name
        my $sim_dir = $2;
        acl::Simulator::set_sim_dir_path($sim_dir);
      }
	  else {
		  acl::Simulator::set_sim_dir_path(undef);
	  }
    }
    # -high-effort
    elsif ( ($arg eq '-high-effort') or ($arg eq '--high-effort') ) {
      if ($arg eq '--high-effort') {
        print "Warning: Command has been deprecated. Please use -high-effort instead of --high-effort\n";
      }
      $high_effort = 1;
    }
    # -add-ini=file1,file2,file3,...
    elsif ( $arg =~ /^-add-ini=(.*)$/ ) {
      my @input_files = split(/,/, $1);
      $#input_files >= 0 or acl::Common::mydie("Option -add-ini= requires at least one argument");
      push @additional_ini, @input_files;
    }
    # -report
    elsif ( ($arg eq '-report') or ($arg eq '--report') ) {
      if ($arg eq '--report') {
        print "Warning: Command has been deprecated. Please use -report instead of --report\n";
      }
      $report = 1;
    }
    # -g
    elsif ( ($arg eq '-g') ) {
      $dash_g = 1;
      $user_dash_g = 1;
    }
    # -g0
    elsif ( ($arg eq '-g0') ) {
      $dash_g = 0;
    }
    # -profile
    elsif ( ($arg eq '-profile') or ($arg eq '--profile') ) {
      if ($arg eq '--profile') {
        print "Warning: Command has been deprecated. Please use -profile instead of --profile\n";
      }
      print "$prog: Warning: no argument provided for the option -profile, will enable profiling for all kernels by default\n";
      $profile = 'all'; # Default is 'all'
      $save_last_bc = 1;
    }
    # -profile=<name>
    elsif ( $arg =~ /^-profile=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -profile= requires an argument");
      } else {
        $profile = $argument_value;
        if ( !(($profile eq 'all' ) || ($profile eq 'autorun') || ($profile eq 'enqueued')) ) {
          print "$prog: Warning: invalid argument '$profile' for the option --profile, will enable profiling for all kernels by default\n";
          $profile = 'all'; # Default is "all"
        }
        $save_last_bc = 1;
      }
    }
    # -save-extra
    elsif ( ($arg eq '-save-extra') or ($arg eq '--save-extra') ) {
      if ($arg eq '--save-extra') {
        print "Warning: Command has been deprecated. Please use -save-extra instead of --save-extra\n";
      }
      $pkg_save_extra = 1;
    }
    # -no-env-check
    elsif ( ($arg eq '-no-env-check') or ($arg eq '--no-env-check') ) {
      if ($arg eq '--no-env-check') {
        print "Warning: Command has been deprecated. Please use -no-env-check instead of --no-env-check\n";
      }
      $do_env_check = 0;
    }
    # -no-auto-migrate
    elsif ( ($arg eq '-no-auto-migrate') or ($arg eq '--no-auto-migrate') ) {
      if ($arg eq '--no-auto-migrate') {
        print "Warning: Command has been deprecated. Please use -no-auto-migrate instead of --no-auto-migrate\n";
      }
      $no_automigrate = 1;
    }
    # -initial-dir=<value>
    elsif ( $arg =~ /^-initial-dir=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -initial-dir= requires an argument");
      } else {
        $force_initial_dir = $argument_value;
        # orig_force_initial_dir stores the original value of this argument given by the user since
        # $force_initial_dir is eventually modified in other places of the AOC driver.
        $orig_force_initial_dir = $force_initial_dir;
      }
    }
    # -o <value>
    elsif ( ($arg eq '-o') ) {
      # Absorb -o argument, and don't pass it down to Clang
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option $arg requires a file argument.");
      $output_file = shift @input_argv;
    }
    # -hash <value>
    elsif ( ($arg eq '-hash') or ($arg eq '--hash') ) {
      print "Warning: Command has been deprecated. Please use -hash=<value> instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option $arg requires an argument");
      $program_hash = shift @input_argv;
    }
    # -hash=<value>
    elsif ( $arg =~ /^-hash=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -hash= requires an argument");
      } else {
        $program_hash = $argument_value;
      }
    }    
    # -clang-arg <option>
    elsif ( ($arg eq '-clang-arg') or ($arg eq '--clang-arg') ) {
      print "Warning: Command has been deprecated. Please use -clang-arg=<options> instead of $arg <option>\n";
      $#input_argv >= 0 or acl::Common::mydie("Option $arg requires an argument");
      # Just push onto @$args_ref!
      push @$args_ref, shift @input_argv;
    }
    # -clang-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-clang-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or acl::Common::mydie("Option -clang-arg= requires at least one argument");
      push @$args_ref, @input_options;
    }
    # -opt-arg <option>
    elsif ( ($arg eq '-opt-arg') or ($arg eq '--opt-arg') ) {
      print "Warning: Command has been deprecated. Please use -opt-arg=<options> instead of $arg <option>\n";
      $#input_argv >= 0 or acl::Common::mydie("Option $arg requires an argument");
      $opt_arg_after .= " ".(shift @input_argv);
    }
    # -opt-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-opt-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or acl::Common::mydie("Option -opt-arg= requires at least one argument");
      while (@input_options) {
        my $input_option = shift @input_options;
        $opt_arg_after .= " ".$input_option;
      }
    }
    # -one-pass <value>
    elsif ( ($arg eq '-one-pass') or ($arg eq '--one-pass') ) {
      print "Warning: Command has been deprecated. Please use -one-pass=<value> instead of $arg <value>\n";
      $#input_argv >= 0 or acl::Common::mydie("Option $arg requires an argument");
      $dft_opt_passes = " ".(shift @input_argv);
      $opt_only = 1;
    }
    # -one-pass=<value>
    elsif ( $arg =~ /^-one-pass=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -one-pass= requires an argument");
      } else {
        $dft_opt_passes = " ".$argument_value;
        $opt_only = 1;
      }
    }  
    # -llc-arg <option>
    elsif ( ($arg eq '-llc-arg') or ($arg eq '--llc-arg') ) {
      print "Warning: Command has been deprecated. Please use -llc-arg=<options> instead of $arg <option>\n";
      $#input_argv >= 0 or acl::Common::mydie("Option $arg requires an argument");
      $llc_arg_after .= " ".(shift @input_argv);
    }
    # -llc-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-llc-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or acl::Common::mydie("Option -llc-arg= requires at least one argument");
      while (@input_options) {
        my $input_option = shift @input_options;
        $llc_arg_after .= " ".$input_option;
      }
    }
    # -short-names
    elsif ( ($arg eq '-short-names') or ($arg eq '--short-names') ) {
      if ($arg eq '--short-names') {
        print "Warning: Command has been deprecated. Please use -short-names instead of --short-names\n";
      }
      $llc_arg_after .= " --set-dspba-feature=maxFilenamePrefixLength,integer,8,maxFilenameSuffixLength,integer,8";
    }
    # -optllc-arg <option>
    elsif ( ($arg eq '-optllc-arg') or ($arg eq '--optllc-arg') ) {
      print "Warning: Command has been deprecated. Please use -optllc-arg=<options> instead of $arg <option>\n";
      $#input_argv >= 0 or acl::Common::mydie("Option $arg requires an argument");
      my $optllc_arg = (shift @input_argv);
      $opt_arg_after .= " ".$optllc_arg;
      $llc_arg_after .= " ".$optllc_arg;
    }
    # -optllc-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-optllc-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or acl::Common::mydie("Option -optllc-arg= requires at least one argument");
      while (@input_options) {
        my $input_option = shift @input_options;
        $opt_arg_after .= " ".$input_option;
        $llc_arg_after .= " ".$input_option;
      }
    }
    # -sysinteg-arg <option>
    elsif ( ($arg eq '-sysinteg-arg') or ($arg eq '--sysinteg-arg') ) {
      print "Warning: Command has been deprecated. Please use -sysinteg-arg=<options> instead of $arg <option>\n";
      $#input_argv >= 0 or acl::Common::mydie("Option $arg requires an argument");
      $sysinteg_arg_after .= " ".(shift @input_argv);
    }
    # -sysinteg-arg=option1,option2,option3,...
    elsif ( $arg =~ /^-sysinteg-arg=(.*)$/ ) {
      my @input_options = split(/,/, $1);
      $#input_options >= 0 or acl::Common::mydie("Option -sysinteg-arg= requires at least one argument");
      while (@input_options) {
        my $input_option = shift @input_options;
        $sysinteg_arg_after .= " ".$input_option;
      }
    }
    # -max-mem-percent-with-replication <value>
    elsif ( ($arg eq '-max-mem-percent-with-replication') or ($arg eq '--max-mem-percent-with-replication') ) {
      print "Warning: Command has been deprecated. Please use -max-mem-percent-with-replication=<value> instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option $arg requires an argument");
      $max_mem_percent_with_replication = (shift @input_argv);
    }
    # -max-mem-percent-with-replication=<value>
    elsif ( $arg =~ /^-max-mem-percent-with-replication=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -max-mem-percent-with-replication= requires an argument");
      } else {
        $max_mem_percent_with_replication = $argument_value;
      }
    }  
    # -c-acceleration
    elsif ( ($arg eq '-c-acceleration') or ($arg eq '--c-acceleration') ) {
      if ($arg eq '--c-acceleration') {
        print "Warning: Command has been deprecated. Please use -c-acceleration instead of --c-acceleration\n";
      }
      $c_acceleration = 1;
    }
    # -parse-only
    elsif ( ($arg eq '-parse-only') or ($arg eq '--parse-only') ) {
      if ($arg eq '--parse-only') {
        print "Warning: Command has been deprecated. Please use -parse-only instead of --parse-only\n";
      }
      $parse_only = 1;
      $atleastoneflag = 1;
    }
    # -opt-only
    elsif ( ($arg eq '-opt-only') or ($arg eq '--opt-only') ) {
      if ($arg eq '--opt-only') {
        print "Warning: Command has been deprecated. Please use -opt-only instead of --opt-only\n";
      }
      $opt_only = 1;
      $atleastoneflag = 1;
    }
    # -v-only
    elsif ( ($arg eq '-v-only') or ($arg eq '--v-only') ) {
      if ($arg eq '--v-only') {
        print "Warning: Command has been deprecated. Please use -v-only instead of --v-only\n";
      }
      $verilog_gen_only = 1;
      $atleastoneflag = 1;
    }
    # -ip-only
    elsif ( ($arg eq '-ip-only') or ($arg eq '--ip-only') ) {
      if ($arg eq '--ip-only') {
        print "Warning: Command has been deprecated. Please use -ip-only instead of --ip-only\n";
      }
      $ip_gen_only = 1;
      $atleastoneflag = 1;
    }
    # -dump-csr
    elsif ( ($arg eq '-dump-csr') or ($arg eq '--dump-csr') ) {
      if ($arg eq '--dump-csr') {
        print "Warning: Command has been deprecated. Please use -dump-csr instead of --dump-csr\n";
      }
      $llc_arg_after .= ' -csr';
    }
    # -skip-qsys
    elsif ( ($arg eq '-skip-qsys') or ($arg eq '--skip-qsys') ) {
      if ($arg eq '--skip-qsys') {
        print "Warning: Command has been deprecated. Please use -skip-qsys instead of --skip-qsys\n";
      }
      $skip_qsys = 1;
      $atleastoneflag = 1;
    }
    # -c
    elsif ( ($arg eq '-c') ) {
      $compile_step = 1;
      $atleastoneflag = 1;
      $c_flag_only = 1;
    }
    # -report-only
    elsif ( ($arg eq '-rtl') ) {
      $report_only = 1;
      $atleastoneflag = 1;
    }
    # -incremental[=aggressive]
    elsif( ($arg =~ /^-incremental(=aggressive)?$/) or ($arg =~ /^--incremental(=aggressive)?$/) ){
      if ($arg =~ /=aggressive$/) {
        $incremental_compile = 'aggressive';
      } else {
        $incremental_compile = 'default';
      }
      $ENV{'AOCL_INCREMENTAL_COMPILE'} = $incremental_compile;
    }    
    # -dis
    elsif ( ($arg eq '-dis') or ($arg eq '--dis') ) {
      if ($arg eq '--dis') {
        print "Warning: Command has been deprecated. Please use -dis instead of --dis\n";
      }
      $disassemble = 1;
    }
    # -tidy
    elsif ( ($arg eq '-tidy') or ($arg eq '--tidy') ) {
      if ($arg eq '--tidy') {
        print "Warning: Command has been deprecated. Please use -tidy instead of --tidy\n";
      }
      $tidy = 1;
    }
    # -save-temps
    elsif ( ($arg eq '-save-temps') or ($arg eq '--save-temps') ) {
      if ($arg eq '--save-temps') {
        print "Warning: Command has been deprecated. Please use -save-temps instead of --save-temps\n";
      }
      $$save_temps_ref = 1;
      acl::Common::set_save_temps($$save_temps_ref);
    }
    # -use-ip-library
    elsif ( ($arg eq '-use-ip-library') or ($arg eq '--use-ip-library') ) {
      if ($arg eq '--use-ip-library') {
        print "Warning: Command has been deprecated. Please use -use-ip-library instead of --use-ip-library\n";
      }
      $use_ip_library = 1;
    }
    # -no-link-ip-library
    elsif ( ($arg eq '-no-link-ip-library') or ($arg eq '--no-link-ip-library') ) {
      if ($arg eq '--no-link-ip-library') {
        print "Warning: Command has been deprecated. Please use -no-link-ip-library instead of --no-link-ip-library\n";
      }
      $use_ip_library = 0;
    }
    # -regtest_mode
    elsif ( ($arg eq '-regtest_mode') or ($arg eq '--regtest_mode') ) {
      if ($arg eq '--regtest_mode') {
        print "Warning: Command has been deprecated. Please use -regtest_mode instead of --regtest_mode\n";
      }
      $regtest_mode = 1;
    }
    # -regtest-bsp-bak-cache
    elsif ( ($arg eq '-regtest-bsp-bak-cache') or ($arg eq '--regtest-bsp-bak-cache') ) {
      if ($arg eq '--regtest-bsp-bak-cache') {
        print "Warning: Command has been deprecated. Please use -regtest-bsp-bak-cache instead of --regtest-bsp-bak-cache\n";
      }
      $$regtest_bak_cache_ref = 1;
    }
    # -no-read-bsp-bak-cache
    elsif ( ($arg eq '-no-read-bsp-bak-cache') or ($arg eq '--no-read-bsp-bak-cache') ) {
      if ($arg eq '--no-read-bsp-bak-cache') {
        print "Warning: Command has been deprecated. Please use -no-read-bsp-bak-cache instead of --no-read-bsp-bak-cache\n";
      }
      push @blocked_migrations, 'pre_skipbak';
    }
    # -incremental-input-dir=<path>
    elsif ( $arg =~ /^-incremental-input-dir=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -incremental-input-dir= requires a path to a previous compile directory");
      } else {
        $$incremental_input_dir_ref = $argument_value;
        ( -e $$incremental_input_dir_ref && -d $$incremental_input_dir_ref ) or acl::Common::mydie("Option -incremental-input-dir= must specify an existing directory");
      }
    } 
    # -incremental-save-partitions <filename>
    elsif ( ($arg eq '-incremental-save-partitions') or ($arg eq '--incremental-save-partitions') ) {
      print "Warning: Command has been deprecated. Please use -incremental-save-partitions=<filename> instead of $arg <filename>\n";
      # assume target dir is the incremental dir
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -incremental-save-partitions requires a file containing partitions you wish to partition");
      $save_partition_file = shift @input_argv;
      $incremental_compile = 'default';
      ( -e $save_partition_file && -f $save_partition_file ) or acl::Common::mydie("Option -incremental-save-partitions must specify an existing file");
    }
    # -incremental-save-partitions=<filename>
    elsif ( $arg =~ /^-incremental-save-partitions=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option incremental-save-partitions= requires a file containing partitions you wish to partition");
      } else {
        $save_partition_file = $argument_value;
        $incremental_compile = 'default';
        ( -e $save_partition_file && -f $save_partition_file ) or acl::Common::mydie("Option -incremental-save-partitions= must specify an existing file");
      }
    }
    # -incremental-set-partitions <filename>
    elsif ( ($arg eq '-incremental-set-partitions') or ($arg eq '--incremental-set-partitions') ) {
      print "Warning: Command has been deprecated. Please use -incremental-set-partitions=<filename> instead of $arg <filename>\n";
      # assume target dir is the incremental dir
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -incremental-set-partitions requires a file containing partitions you wish to partition");
      $set_partition_file = shift @input_argv;
      $incremental_compile = 'default';
      ( -e $set_partition_file && -f $set_partition_file ) or acl::Common::mydie("Option -incremental-set-partitions must specify an existing file");
    }
    # -incremental-set-partitions=<filename>
    elsif ( $arg =~ /^-incremental-set-partitions=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option incremental-set-partitions= requires a file containing partitions you wish to partition");
      } else {
        $set_partition_file = $argument_value;
        $incremental_compile = 'default';
        ( -e $set_partition_file && -f $set_partition_file ) or acl::Common::mydie("Option -incremental-set-partitions= must specify an existing file");
      }
    }
    # -floorplan <filename>
    elsif ( ($arg eq '-floorplan') or ($arg eq '--floorplan') ) {
      print "Warning: Command has been deprecated. Please use -floorplan=<filename> instead of $arg <filename>\n";
      my $floorplan_file = acl::File::abs_path(shift @input_argv);
      ( -e $floorplan_file && -f $floorplan_file ) or acl::Common::mydie("Option --floorplan must specify an existing file");
      $sysinteg_arg_after .= ' --floorplan '.$floorplan_file;
    }
    # -floorplan=<filename>
    elsif ( $arg =~ /^-floorplan=(.*)$/ ) {
      my $floorplan_file = acl::File::abs_path($1);
      ( -e $floorplan_file && -f $floorplan_file ) or acl::Common::mydie("Option --floorplan must specify an existing file");
      $sysinteg_arg_after .= ' --floorplan '.$floorplan_file;
    }
    # -incremental-flow=<flow-name>
    elsif ( $arg =~ /^-incremental-flow=(.*)$/ ) {
      my $retry_option = $1;
      my %incremental_flow_strats = (
        'retry' => 1,
        'no-retry' => 1
      );
      $retry_option ne "" or acl::Common::mydie("Usage: -incremental-flow=<" . join("|", keys %incremental_flow_strats) . ">");
      if (exists $incremental_flow_strats{$retry_option}) {
        $ENV{'INCREMENTAL_RETRY_STRATEGY'} = $retry_option;
      } else {
        die "$retry_option is not a valid -incremental-flow selection! Select from: <" . join("|", keys %incremental_flow_strats) . ">";
      }
    }
    # -parallel=<num_procs>
    elsif ( ($arg =~ /^-parallel=(\d+)$/) ) {
      $cpu_count = $1;
    }
    # -add-qsf "file1 file2 file3 ..."
    elsif ( ($arg eq '-add-qsf') or ($arg eq '--add-qsf') ) {
      print "Warning: Command has been deprecated. Please use -add-qsf=<filenames> instead of $arg <filenames>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -add-qsf requires a space-separated list of files");
      my @qsf_files = split(/ /, (shift @input_argv));
      push @additional_qsf, @qsf_files;
    }
    # -add-qsf=file1,file2,file3,...
    elsif ( $arg =~ /^-add-qsf=(.*)$/ ) {
      my @input_files = split(/,/, $1);
      $#input_files >= 0 or acl::Common::mydie("Option -add-qsf= requires at least one argument");
      push @additional_qsf, @input_files;
    }
    # -empty-kernel=<filename>
    # Use Quartus to remove logic inside the kernel while preserving its input and output ports
    # File should contain names of kernels separated by newline
    elsif ( $arg =~ /^-empty-kernel=(.*)$/ ) {
      my $quartus_emptied_kernel_file = acl::File::abs_path($1);
      ( -e $quartus_emptied_kernel_file && -f $quartus_emptied_kernel_file ) or acl::Common::mydie("Option -empty-kernel must specify an existing file");
      $empty_kernel_flow = 1;
      $sysinteg_arg_after .= ' --empty-kernel '.$quartus_emptied_kernel_file;
    }
    # -high-effort-compile
    elsif ( ($arg eq '-high-effort-compile') ) {
      $high_effort_compile = 1;
    }
    # -fast-compile
    elsif ( ($arg eq '-fast-compile') or ($arg eq '--fast-compile') ) {
      if ($arg eq '--fast-compile') {
        print "Warning: Command has been deprecated. Please use -fast-compile instead of --fast-compile\n";
      }
      $fast_compile = 1;
    }
    # power related flags
    elsif ( ($arg eq '-power') ) {
      $ENV{'Q_POW'} = 1;
    }
    elsif ( ($arg =~ '^-power-toggle-rate=(.*)$')) {
      $ENV{'Q_POW_TOGGLE_RATE'} = $1;
    }
    elsif ( ($arg =~ '^-power-io-toggle-rate=(.*)$')) {
      $ENV{'Q_POW_IO_TOGGLE_RATE'} = $1;
    }
    # -1x-clk-for-const-cache
    elsif ( ($arg eq '-1x-clk-for-const-cache') ) {
      $sysinteg_arg_after .= ' --cic-1x-const-cache';
    }
    # -incremental-soft-region
    elsif ( ($arg eq '-incremental-soft-region') ) {
      $soft_region_on = 1;
    }
    # -fmax <value>
    elsif ( ($arg eq '-fmax') or ($arg eq '--fmax') ) {
      print "Warning: Command has been deprecated. Please use -fmax=<value> instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -fmax requires an argument");
      $opt_arg_after .= ' -scheduler-fmax=';
      $llc_arg_after .= ' -scheduler-fmax=';
      my $fmax_constraint = (shift @input_argv);
      $opt_arg_after .= $fmax_constraint;
      $llc_arg_after .= $fmax_constraint;
    }
    # -fmax=<value>
    elsif ( $arg =~ /^-fmax=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -fmax= requires an argument");
      } else {
        $opt_arg_after .= " -scheduler-fmax=$argument_value";
        $llc_arg_after .= " -scheduler-fmax=$argument_value";
      }
    }
    # -dont-error-if-large-area-est
    elsif ( ($arg eq '-dont-error-if-large-area-est') ) {
      $opt_arg_after .= ' -cont-if-too-large';
      $llc_arg_after .= ' -cont-if-too-large';
    }
    # -seed <value>
    elsif ( ($arg eq '-seed') or ($arg eq '--seed') ) {
      print "Warning: Command has been deprecated. Please use -seed=<value> instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -seed requires an argument");
      $fit_seed = (shift @input_argv);
    }
    # -seed=<value>
    elsif ( $arg =~ /^-seed=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -seed= requires an argument");
      } else {
        $fit_seed = $argument_value;
      }
    }  
    # -no-lms
    elsif ( ($arg eq '-no-lms') or ($arg eq '--no-lms') ) {
      if ($arg eq '--no-lms') {
        print "Warning: Command has been deprecated. Please use -no-lms instead of --no-lms\n";
      }
      $opt_arg_after .= " ".$lmem_disable_split_flag;
    }
    # -fp-relaxed
    # temporary fix to match broke documentation
    elsif ( ($arg eq '-fp-relaxed') or ($arg eq '--fp-relaxed') ) {
      if ($arg eq '--fp-relaxed') {
        print "Warning: Command has been deprecated. Please use -fp-relaxed instead of --fp-relaxed\n";
      }
      $opt_arg_after .= " -fp-relaxed=true";
    }
    # -Os
    # enable sharing flow
    elsif ( ($arg eq '-Os') ) {
       $opt_arg_after .= ' -opt-area=true';
       $llc_arg_after .= ' -opt-area=true';
    }
    # -fpc
    # temporary fix to match broke documentation
    elsif ( ($arg eq '-fpc') or ($arg eq '--fpc') ) {
      if ($arg eq '--fpc') {
        print "Warning: Command has been deprecated. Please use -fpc instead of --fpc\n";
      }
      $opt_arg_after .= " -fpc=true";
    }
    # -const-cache-bytes <value>
    elsif ( ($arg eq '-const-cache-bytes') or ($arg eq '--const-cache-bytes') ) {
      print "Warning: Command has been deprecated. Please use -const-cache-bytes=<value> instead of $arg <value>\n";
      $sysinteg_arg_after .= ' --cic-const-cache-bytes';
      $opt_arg_after .= ' --cic-const-cache-bytes=';
      $llc_arg_after .= ' --cic-const-cache-bytes=';
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -const-cache-bytes requires an argument");
      my $const_cache_size = (shift @input_argv);
      my $actual_const_cache_size = 16384;
      # Allow for positive Real Numbers Only
      if (!($const_cache_size =~ /^\d+(?:\.\d+)?$/)) {
        acl::Common::mydie("Invalid argument for option --const-cache-bytes,<N> must be a positive real number.");      
      }
      while ($actual_const_cache_size < $const_cache_size ) {
        $actual_const_cache_size = $actual_const_cache_size * 2;
      }
      $sysinteg_arg_after .= " ".$actual_const_cache_size;
      $opt_arg_after .= $actual_const_cache_size;
      $llc_arg_after .= $actual_const_cache_size;
    }
    # -const-cache-bytes=<value>
    elsif ( $arg =~ /^-const-cache-bytes=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -const-cache-bytes= requires an argument");
      } else {
        my $const_cache_size = $argument_value;
        my $actual_const_cache_size = 16384;
        while ($actual_const_cache_size < $const_cache_size ) {
          $actual_const_cache_size = $actual_const_cache_size * 2;
        }
        $sysinteg_arg_after .= " --cic-const-cache-bytes $actual_const_cache_size";
        $opt_arg_after .= " --cic-const-cache-bytes=$actual_const_cache_size";
        $llc_arg_after .= " --cic-const-cache-bytes=$actual_const_cache_size";
      }
    }   
    # -board <value>
    elsif ( ($arg eq '-board') or ($arg eq '--board') ) {
      print "Warning: Command has been deprecated. Please use -board=<value> instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -board requires an argument");
      ($board_variant) = (shift @input_argv);
      $user_defined_board = 1;
    }
    # -board=<value>
    elsif ( $arg =~ /^-board=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -board= requires an argument");
      } else {
        $board_variant = $argument_value;
        $user_defined_board = 1;
      }
    } 
    # -board-package=<path>
    elsif ( $arg =~ /^-board-package=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -board-package= requires an argument");
      } else {
        $$bsp_variant_ref = $argument_value;
        $user_defined_board = 1;
      }
    } 
    # -efi-spec <value>
    elsif ( ($arg eq '-efi-spec') or ($arg eq '--efi-spec') ) {
      print "Warning: Command has been deprecated. Please use -efi-spec=<value> instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -efi-spec requires a path/filename");
      !defined $efispec_file or acl::Common::mydie("Too many EFI Spec files provided\n");
      $efispec_file = (shift @input_argv);
    }
    # -efi-spec=<value>
    elsif ( $arg =~ /^-efi-spec=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -efi-spec= requires an argument");
      } else {
        !defined $efispec_file or acl::Common::mydie("Too many EFI Spec files provided\n");
        $efispec_file = $argument_value;
      }
    }
    # -L <path>
    elsif ($arg eq '-L') {
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -L requires a directory name");
      push (@lib_paths, (shift @input_argv));
    }
    # -L<path>
    elsif ($arg =~ m!^-L(\S+)!) {
      push (@lib_paths, $1);
    }
    # -l <libname>
    elsif ($arg eq '-l') {
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -l requires a path/filename");
      push (@lib_files, (shift @input_argv));
    }
    # -library-debug
    elsif ( ($arg eq '-library-debug') or ($arg eq '--library-debug') ) {
      if ($arg eq '--library-debug') {
        print "Warning: Command has been deprecated. Please use -library-debug instead of --library-debug\n";
      }
      $opt_arg_after .= ' -debug-only=libmanager';
      $library_debug = 1;
    }
    # -shared
    elsif ( ($arg eq '-shared') or ($arg eq '--shared') ) {
      if ($arg eq '--shared') {
        print "Warning: Command has been deprecated. Please use -shared instead of --shared\n";
      }
      $created_shared_aoco = 1;
      $compile_step = 1; # '-shared' implies '-c'
      $atleastoneflag = 1;
      # Enabling -g causes problems when compiling resulting
      # library for emulator (crash in 2nd clang invocation due
      # to debug info inconsistencies). Disabling for now.
      #push @$args_ref, '-g'; #  '-shared' implies '-g'

    }
    # -profile-config <file>
    elsif ( ($arg eq '-profile-config') or ($arg eq '--profile-config') ) {
      print "Warning: Command has been deprecated. Please use -profile-config=<filename> instead of $arg <filename>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -profile-config requires a path/filename");
      !defined $profilerconf_file or acl::Common::mydie("Too many profiler config files provided\n");
      $profilerconf_file = (shift @input_argv);
    }
    # -profile-config=<file>
    elsif ( $arg =~ /^-profile-config=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -profile-config= requires a path/filename");
      } else {
        !defined $profilerconf_file or acl::Common::mydie("Too many profiler config files provided\n");
        $profilerconf_file = $argument_value;
      }
    } 
    # -bsp-flow <flow-name>
    elsif ( ($arg eq '-bsp-flow') or ($arg eq '--bsp-flow') ) {
      print "Warning: Command has been deprecated. Please use -bsp-flow=<flow-name> instead of $arg <flow-name>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -bsp-flow requires a flow-name\n");
      !defined $$bsp_flow_name_ref or acl::Common::mydie("Too many bsp-flows defined.\n");
      $$bsp_flow_name_ref = (shift @input_argv);
      $sysinteg_arg_after .= " --bsp-flow $$bsp_flow_name_ref";
      $$bsp_flow_name_ref = ":".$$bsp_flow_name_ref;
    }
    # -bsp-flow=<flowname>
    elsif ( $arg =~ /^-bsp-flow=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -bsp-flow= requires a flow-name");
      } else {
        !defined $$bsp_flow_name_ref or acl::Common::mydie("Too many bsp-flows defined.\n");
        $$bsp_flow_name_ref = $argument_value;
        $sysinteg_arg_after .= " --bsp-flow $$bsp_flow_name_ref";
        $$bsp_flow_name_ref = ":".$$bsp_flow_name_ref;
      }
    } 
    # -oldbe
    elsif ( ($arg eq '-oldbe') or ($arg eq '--oldbe') ) {
      if ($arg eq '--oldbe') {
        print "Warning: Command has been deprecated. Please use -oldbe instead of --oldbe\n";
      }
      $griffin_flow = 0;
      $sysinteg_arg_after .= " --oldbe";
    }
    # -ggdb / -march=emulator
    elsif ($arg eq '-ggdb' || $arg eq '-march=emulator') {
      $emulator_flow = 1;
      $user_defined_flow = 1;
      if ($arg eq '-ggdb') {
        $dash_g = 1;
      }
    }
    # -fast-emulator
    elsif ($arg eq '-fast-emulator') {
      $emulator_fast = 1;
    }
    # -ecc
    elsif ($arg eq '-ecc') {
      $ecc_protected = 1;
    }
    # -ecc-max-latency <value>
    elsif ($arg eq '-ecc-max-latency') {
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -ecc-max-latency requires a value");
      if ($ecc_protected != 1){
        acl::Common::mydie("Option -ecc-max-latency requires an -ecc flag provided");
      } else {
        $ecc_max_latency = (shift @input_argv);
      }
    }
    # -ecc-max-latency=<value>
    elsif ( $arg =~ /^-ecc-max-latency=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -ecc-max-latency= requires a value");
      } elsif ($ecc_protected != 1){
        acl::Common::mydie("Option -ecc-max-latency requires an -ecc flag provided");
      } else {
        $ecc_max_latency = $argument_value;
      }
    }
    # -soft-ip-c <function-name>
    elsif ( ($arg eq '-soft-ip-c') or ($arg eq '--soft-ip-c') ) {
      print "Warning: Command has been deprecated. Please use -soft-ip-c=<function-name> instead of $arg <function-name>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -soft-ip-c requires a function name");
      $soft_ip_c_name = (shift @input_argv);
      $soft_ip_c_flow = 1;
      $verilog_gen_only = 1;
      $dotfiles = 1;
      print "Running soft IP C flow on function $soft_ip_c_name\n";
    }
    # -soft-ip-c=<function-name>
    elsif ( $arg =~ /^-soft-ip-c=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -soft-ip-c= requires a function name");
      } else {
        $soft_ip_c_name = $argument_value;
        $soft_ip_c_flow = 1;
        $verilog_gen_only = 1;
        $dotfiles = 1;
        print "Running soft IP C flow on function $soft_ip_c_name\n";
      }
    } 
    # -accel <function-name>
    elsif ( ($arg eq '-accel') or ($arg eq '--accel') ) {
      print "Warning: Command has been deprecated. Please use -accel=<function-name> instead of $arg <function-name>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -accel requires a function name");
      $accel_name = (shift @input_argv);
      $accel_gen_flow = 1;
      $llc_arg_after .= ' -csr';
      $compile_step = 1;
      $atleastoneflag = 1;
      $sysinteg_arg_after .= ' --no-opencl-system';
    }
    # -accel=<function-name>
    elsif ( $arg =~ /^-accel=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -accel= requires a function name");
      } else {
        $accel_name = $argument_value;
        $accel_gen_flow = 1;
        $llc_arg_after .= ' -csr';
        $compile_step = 1;
        $atleastoneflag = 1;
        $sysinteg_arg_after .= ' --no-opencl-system';
      }
    } 
    # -device-spec <filename>
    elsif ( ($arg eq '-device-spec') or ($arg eq '--device-spec') ) {
      print "Warning: Command has been deprecated. Please use -device-spec=<filename> instead of $arg <filename>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -device-spec requires a path/filename");
      $device_spec = (shift @input_argv);
    }
    # -device-spec=<filename>
    elsif ( $arg =~ /^-device-spec=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -device-spec= requires a path/filename");
      } else {
        $device_spec = $argument_value;
      }
    }
    # -dot
    elsif ( ($arg eq '-dot') or ($arg eq '--dot') ) {
      if ($arg eq '--dot') {
        print "Warning: Command has been deprecated. Please use -dot instead of --dot\n";
      }
      $dotfiles = 1;
    }
    # -pipeline-viewer
    elsif ( ($arg eq '-pipeline-viewer') or ($arg eq '--pipeline-viewer') ) {
      $dotfiles = 1;
      $pipeline_viewer = 1;
    }
    # -timing-threshold=<value>
    elsif ( $arg =~ /^-timing-threshold=(.*)$/ ) {
      my $argument_value = $1;
      #check for argument value to be a valid number. (C float)
      if ($argument_value=~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/ ) {
          $timing_slack_check = 1;
          $ENV{AOCL_TIMING_SLACK}= $argument_value;
      } else {
        acl::Common::mydie("Option -timing-threshold=<value> requires a valid positive number in nano seconds");
      }
    }
    # -time
    elsif ( ($arg eq '-time') or ($arg eq '--time') ) {
      if ($arg eq '--time') {
        print "Warning: Command has been deprecated. Please use -time instead of --time\n";
      }
      if($#input_argv >= 0 && $input_argv[0] !~ m/^-./) {
        $time_log_filename = shift(@input_argv);
      }
      else {
        $time_log_filename = "-"; # Default to stdout.
      }
    }
    # -time=<file>
    elsif ( $arg =~ /^-time=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -time requires a filename");
      } else {
        $time_log_filename = $argument_value;
      }
    }
    # -time-passes
    elsif ( ($arg eq '-time-passes') or ($arg eq '--time-passes') ) {
      if ($arg eq '--time-passes') {
        print "Warning: Command has been deprecated. Please use -time-passes instead of --time-passes\n";
      }
      $time_passes = 1;
      $opt_arg_after .= ' --time-passes';
      $llc_arg_after .= ' --time-passes';
      if(!$time_log_filename) {
        $time_log_filename = "-"; # Default to stdout.
      }
    }
    # -un
    # Temporary test flag to enable Unified Netlist flow.
    elsif ( ($arg eq '-un') or ($arg eq '--un') ) {
      if ($arg eq '--un') {
        print "Warning: Command has been deprecated. Please use -un instead of --un\n";
      }
      $opt_arg_after .= ' --un-flow';
      $llc_arg_after .= ' --un-flow';
    }
    # -no-interleaving <name>
    elsif ( ($arg eq '-no-interleaving') or ($arg eq '--no-interleaving') ) {
      print "Warning: Command has been deprecated. Please use -no-interleaving=<name> instead of $arg <name>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -no-interleaving requires a memory name or 'default'");
      $llc_arg_after .= ' -use-swdimm=';
      if($input_argv[0] ne 'default' ) {
        my $argument_value = shift(@input_argv);
        $sysinteg_arg_after .= ' --no-interleaving '.$argument_value;
        $llc_arg_after .= $argument_value;
      }
      else {
        #non-heterogeneous sw-dimm-partition behaviour
        #this will target the default memory
        shift(@input_argv);
        $sysinteg_arg_after .= ' --cic-global_no_interleave ';
        $llc_arg_after .= 'default';        
      }
    }
    # -no-interleaving=<name>
    elsif ( $arg =~ /^-no-interleaving=(.*)$/ ) {
      my $argument_value = $1;
      $llc_arg_after .= ' -use-swdimm=';
      if ($argument_value eq "") {
        acl::Common::mydie("Option -no-interleaving requires a memory name or 'default'");
      } elsif ($argument_value eq 'default') {
        $sysinteg_arg_after .= ' --cic-global_no_interleave ';
        $llc_arg_after .= 'default';        
      } else {
        $sysinteg_arg_after .= ' --no-interleaving '.$argument_value;
        $llc_arg_after .= $argument_value;
      }
    }   
    # -global-tree
    elsif ( ($arg eq '-global-tree') or ($arg eq '--global-tree') ) {
      if ($arg eq '--global-tree') {
        print "Warning: Command has been deprecated. Please use -global-tree instead of --global-tree\n";
      }
      $sysinteg_arg_after .= ' --global-tree';
      $llc_arg_after .= ' -global-tree';
    } 
    # -global-ring
    elsif ( ($arg eq '-global-ring') or ($arg eq '--global-ring') ) {
      if ($arg eq '--global-ring') {
        print "Warning: Command has been deprecated. Please use -global-ring instead of --global-ring\n";
      }
      $sysinteg_arg_after .= ' --global-ring';
    }     
    # -duplicate-ring
    elsif ( ($arg eq '-duplicate-ring') or ($arg eq '--duplicate-ring') ) {
      if ($arg eq '--duplicate-ring') {
        print "Warning: Command has been deprecated. Please use -duplicate-ring instead of --duplicate-ring\n";
      }
      $sysinteg_arg_after .= ' --duplicate-ring';
    } 
    # -num-reorder <value>
    elsif ( ($arg eq '-num-reorder') or ($arg eq '--num-reorder') ) {
      print "Warning: Command has been deprecated. Please use -num-reorder=<value> instead of $arg <value>\n";
      $sysinteg_arg_after .= ' --num-reorder '.(shift @input_argv);
    }
    #-incremental-grouping=<path>
    elsif( $arg =~ /^-incremental-grouping=(.*)$/ ){
      my $partition_file = $1;
      if ($partition_file eq "") {
        acl::Common::mydie("Option -incremental-grouping= requires a path to the partition grouping file");
      } else {
        $partition_file = acl::File::abs_path($partition_file);
        (-e $partition_file) or acl::Common::mydie("-incremental-grouping file $partition_file does not exist.");
        $sysinteg_arg_after .= ' --incremental-grouping '.$partition_file;
      }
    }
    # -num-reorder=<value>
    elsif ( $arg =~ /^-num-reorder=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -num-reorder= requires an argument");
      } else {
        $sysinteg_arg_after .= ' --num-reorder '.$argument_value;
      }
    }
    elsif ( _process_meta_args ($arg, \@input_argv) ) { }
    # -input=kernel_1.cl,kernel_2.cl,kernel_3.cl,...
    elsif ( $arg =~ /^-input=(.*)$/ ) {
      my @input_files = split(/,/, $1);
    }
    elsif ( $arg =~ m/\.cl$|\.c$|\.aoco|\.aocr|\.xml/ ) {
      push @given_input_files, $arg;
    }
    elsif ( $arg =~ m/\.aoclib/ ) {
      acl::Common::mydie("Library file $arg specified without -l option");
    }
    # -dsploc <value>
    elsif ( ($arg eq '-dsploc') or ($arg eq '--dsploc') ) {
      print "Warning: Command has been deprecated. Please use -dsploc=<value> instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -dsploc requires an argument");
      $dsploc = (shift @input_argv);
    }
    # -dsploc=<value>
    elsif ( $arg =~ /^-dsploc=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -dsploc= requires an argument");
      } else {
        $dsploc = $argument_value;
      }
    }
    # -ramloc <value>
    elsif ( ($arg eq '-ramloc') or ($arg eq '--ramloc') ) {
      print "Warning: Command has been deprecated. Please use -ramloc=<value> instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -ramloc requires an argument");
      $ramloc = (shift @input_argv);
    }
    # -ramloc=<value>
    elsif ( $arg =~ /^-ramloc=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -ramloc= requires an argument");
      } else {
        $ramloc = $argument_value;
      }
    }
    # -O3
    elsif ($arg eq '-O3') {
      $emu_optimize_o3 = 1;
    }
    # -emulator-channel-depth-model <value>
    elsif ( ($arg eq '-emulator-channel-depth-model') or ($arg eq '--emulator-channel-depth-model') ) {
      print "Warning: Command has been deprecated. Please use -emulator-channel-depth-model instead of $arg <value>\n";
      ($#input_argv >= 0 and $input_argv[0] !~ m/^-./) or acl::Common::mydie("Option -emulator-channel-depth-model requires an argument");
      $emu_ch_depth_model = (shift @input_argv);
    }
    # -emulator-channel-depth-model=<value>
    elsif ( $arg =~ /^-emulator-channel-depth-model=(.*)$/ ) {
      my $argument_value = $1;
      if ($argument_value eq "") {
        acl::Common::mydie("Option -emulator-channel-depth-model= requires an argument");
      } else {
        $emu_ch_depth_model = $argument_value;
      }
    }
    # -D__IHC_USE_DEPRECATED_NAMES
    elsif ($arg eq '-D__IHC_USE_DEPRECATED_NAMES') {
      print "$prog: Warning: Turning on use of deprecated names!\n";
      push @$args_ref, $arg;
    }
    # Unrecognized Option
    else {
      push @$args_ref, $arg;
    }
  }
}

sub process_args {

  my ( $args_ref,
       $using_default_board_ref,
       $dirbase_ref,
       $base_ref,
       $sim_accurate_memory,
       $sim_kernel_clk_frequency,
       $bsp_variant,
       $regtest_bak_cache,
       $verbose,
       $incremental_input_dir) = @_;

  my $old_board_package_root = $ENV{'AOCL_BOARD_PACKAGE_ROOT'};
  if (! defined $old_board_package_root) {
    $old_board_package_root = "";
  }

  # Add incremental flags here instead of when parsing the AOC flag because we want to allow
  # users to specify the incremental mode multiple times and use the last value.
  # The boolean flags cannot be turned off after they're turned on so we only
  # add the internal flags once after parsing all the AOC flags.
  if ($incremental_compile) {
    $sysinteg_arg_after .= ' --incremental ';
    $llc_arg_after .= ' -incremental ';
    if ($incremental_compile eq 'aggressive') {
      $sysinteg_arg_after .= ' --use-partial-arbitration ';
      $llc_arg_after .= ' -incremental-cdi-recompile-off ';
    }
  }

  if ($fast_compile and $timing_slack_check) {
    acl::Common::mydie("Cannot have timing slack check when fast-compile is set"); 
  }

  if (!$sim_accurate_memory && defined($sim_kernel_clk_frequency)) {
    # Issue warning as sim-clk-freq will not take any effect for sim flow with no clock crosser.
    print "$prog: Warning: -sim-clk-freq=$sim_kernel_clk_frequency is ignored because -sim-acc-mem is not used.\n";
  }

  # Process $time_log_filename. If defined, then treat it as a file name 
  # (including "-", which is stdout).
  # Do this right after argument parsing, so that following code is able to log times.
  if ($time_log_filename) {
    acl::Common::open_time_log($time_log_filename, $run_quartus);
  }

  # Don't add -g to user_opencl_args because -g is now enabled by default.
  # Instead add -g0 if the user explicitly disables debug info.
  push @user_opencl_args, @$args_ref;
  if (!$dash_g) {
    push @user_opencl_args, '-g0';
  }

  if ($c_flag_only) {
    my $mixed_args = $opt_arg_after.$llc_arg_after.$sysinteg_arg_after;
    $mixed_args = acl::AOCDriverCommon::remove_duplicate($mixed_args);
    if ($mixed_args) {
      print "$prog: Warning: The following linker args will be ignored in this flow:$mixed_args \n";   
    }
  }

  # Propagate -g to clang, opt, and llc
  if ($dash_g || $profile) {
    if ($emulator_flow && ($emulator_arch eq 'windows64')){
      print "$prog: Debug symbols are not supported in emulation mode on Windows, ignoring -g.\n" if $user_dash_g;
    } elsif ($created_shared_aoco) {
      print "$prog: Debug symbols are not supported for shared object files, ignoring -g.\n" if $user_dash_g;
    } else {
      push @$args_ref, '-g' if ($emulator_fast and $user_dash_g);
      push @$args_ref, ('-debug-info-kind=limited', '-dwarf-version=4') unless ($emulator_fast);
    }
    $opt_arg_after .= ' -dbg-info-enabled';
    $llc_arg_after .= ' -dbg-info-enabled';
  }

  # -board-package provided
  if (defined $bsp_variant) {
    $ENV{"AOCL_BOARD_PACKAGE_ROOT"} = $bsp_variant;
    # if no board variant was given by the --board option fall back to the default board
    if (!defined $board_variant) {
      ($board_variant) = acl::Env::board_hardware_default();
      $$using_default_board_ref = 1;
    # treat EmulatorDevice as undefined so we get a valid board
    } elsif ($board_variant eq $emulatorDevice) {
      ($board_variant) = acl::Env::board_hardware_default();
    } 
  # -board-package not provided
  } else {
    if (!defined $board_variant) {
      ($board_variant) = acl::Env::board_hardware_default();
      $$using_default_board_ref = 1;
    # treat EmulatorDevice as undefined so we get a valid board
    } elsif ($board_variant eq $emulatorDevice) {
      ($board_variant) = acl::Env::board_hardware_default();
    # Try to get the corresponding bsp
    } else {
      my @bsp_candidates = ();
      acl::Common::populate_boards();
      foreach my $b (keys %board_boarddir_map) {
        my ($board_name, $bsp_path) = split(';',$b);
        if ($board_variant eq $board_name) {
          push @bsp_candidates, $bsp_path; 
        }
      }
      if ($#bsp_candidates == 0) {
        $ENV{"AOCL_BOARD_PACKAGE_ROOT"} = shift @bsp_candidates;
      } elsif ($#bsp_candidates > 0) {
        print "Error: $board_variant exists in multiple board packages:\n";
        foreach my $bsp_path (@bsp_candidates) {
          print "$bsp_path\n";
        }
        print "Please use -board-package=<bsp-path> to specify board package\n";
        exit(1);
      # backward compatibility
      # if the specified board is not in the list, try with AOCL_BOARD_PACKAGE_ROOT
      } else {
        $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $old_board_package_root; 
      }  
    }
  }

  push (@$args_ref, "-Wunknown-pragmas") unless $emulator_fast;
  @user_clang_args = @$args_ref;

  if ($regtest_mode){
      my $save_temps = 1;
      acl::Common::set_save_temps($save_temps);
      $report = 1;
      $sysinteg_arg_after .= ' --regtest_mode ';
      # temporary app data directory
      if (defined $ENV{"ARC_PICE"}) {
        $tmp_dir = ( $^O =~ m/MSWin/ ? "P:/psg/flows/sw/aclboardpkg/.platform/BAK_cache/windows": "/p/psg/flows/sw/aclboardpkg/.platform/BAK_cache/linux" );
      } else {
        $tmp_dir = ( $^O =~ m/MSWin/ ? "S:/tools/aclboardpkg/.platform/BAK_cache/windows": "/tools/aclboardpkg/.platform/BAK_cache/linux" );
      }
      if(!$regtest_bak_cache) {
        push @blocked_migrations, 'post_skipbak';
      }
      $llc_arg_after .= " -dump-hld-area-debug-files";
  }

  if ($dotfiles) {
    $opt_arg_after .= ' --dump-dot ';
    $llc_arg_after .= ' --dump-dot ';
    $sysinteg_arg_after .= ' --dump-dot ';
  }

  # $orig_dir = acl::File::abs_path('.');
  my $orig_dir = acl::Common::set_original_dir( acl::File::abs_path('.') );
  $force_initial_dir = acl::File::abs_path( $force_initial_dir || '.' );

  # get the absolute path for the EFI Spec file
  if(defined $efispec_file) {
      chdir $force_initial_dir or acl::Common::mydie("Can't change into dir $force_initial_dir: $!\n");
      -f $efispec_file or acl::Common::mydie("Invalid EFI Spec file $efispec_file: $!");
      $absolute_efispec_file = acl::File::abs_path($efispec_file);
      -f $absolute_efispec_file or acl::Common::mydie("Internal error. Can't determine absolute path for $efispec_file");
      chdir $orig_dir or acl::Common::mydie("Can't change into dir $orig_dir: $!\n");
  }
  
  # Resolve library args to absolute paths
  if($#lib_files > -1) {
     if ($verbose or $library_debug) { print "Resolving library filenames to full paths\n"; }
     foreach my $libpath (@lib_paths, ".") {
        if (not defined $libpath) { next; }
        if ($verbose or $library_debug) { print "  lib_path = $libpath\n"; }
        
        chdir $libpath or next;
          for (my $i=0; $i <= $#lib_files; $i++) {
             my $libfile = $lib_files[$i];
             if (not defined $libfile) { next; }
             if ($verbose or $library_debug) { print "    lib_file = $libfile\n"; }
             if (-f $libfile) {
               my $abs_libfile = acl::File::abs_path($libfile);
               if ($verbose or $library_debug) { print "Resolved $libfile to $abs_libfile\n"; }
               push (@resolved_lib_files, $abs_libfile);
               # Remove $libfile from @lib_files
               splice (@lib_files, $i, 1);
               $i--;
             }
          }
        chdir $orig_dir;
     }
     
     # Make sure resolved all lib files
     if ($#lib_files > -1) {
        acl::Common::mydie ("Cannot find the following specified library files: " . join (' ', @lib_files));
     }
  }

  my $num_extracted_c_model_files;
  $$base_ref = _process_input_file_arguments(\$num_extracted_c_model_files);

  if ($aoco_to_aocr_aocx_only && @user_opencl_args) {
    print "$prog: Warning: The following parser args will be ignored in this flow: @user_opencl_args \n";
  }

  my $suffix = $$base_ref;
  $suffix =~ s/.*\.//;
  $$base_ref =~ s/\.$suffix//;
  $$base_ref =~ s/[^a-z0-9_]/_/ig;

  # default name of the .aocx file and final project directory
  $linked_objfile = $$base_ref.".linked.aoco.bc";
  $x_file = $$base_ref.".aocx";
  $$dirbase_ref = $$base_ref;

  if($#given_input_files eq -1){
    acl::Common::mydie("No input file detected");
  }
  
  #in emulator flow we add the library files to the list of given_input_files and thus need an additional check when we are in the emulator flow
  my $diff_input_files = scalar @given_input_files - $num_extracted_c_model_files;

  if ($output_file and ($#given_input_files gt 0 ) and !$aoco_to_aocr_aocx_only and !($emulator_flow and ($diff_input_files eq 1)) ){
    acl::Common::mydie("Cannot specify -o with multiple input files\n");
  }
 
  foreach my $input_file (@given_input_files) {
    my $input_base = acl::File::mybasename($input_file);
    my $input_suffix = $input_base;
    $input_suffix =~ s/.*\.//;
    $input_base=~ s/\.$input_suffix//;
    $input_base =~ s/[^a-z0-9_]/_/ig;

    if ( $input_suffix =~ m/^cl$|^c$/ ) {
      push @srcfile_list, $input_file;
      push @objfile_list, $input_base.".aoco";
    } elsif ( $input_suffix =~ m/^aoco$/ ) {
      push @objfile_list, acl::File::abs_path($input_file);
    } elsif ( $input_suffix =~ m/^aocr$/ ) {
      $run_quartus = 1;
      push @objfile_list, acl::File::abs_path($input_file);
    } elsif ( $input_suffix =~ m/^xml$/ ) {
      # xml suffix is for packaging RTL components into aoco files, to be
      # included into libraries later.
      # The flow is the same as for "aoc -shared -c" for OpenCL components
      # but currently handled by "aocl-libedit" executable
      $hdl_comp_pkg_flow = 1;
      $run_quartus = 0;
      $compile_step = 1;
      push @srcfile_list, $input_file;
      push @objfile_list, $input_base.".aoco";
    } else {
      acl::Common::mydie("No recognized input file format on the command line : $input_file");
    }  
  }

  if ( $output_file ) {
    my $outsuffix = $output_file;
    $outsuffix =~ s/.*\.//;
    # Did not find a suffix. Use default for option.
    if ($outsuffix ne "aocx" && $outsuffix ne "aocr" && $outsuffix ne "aoco") {
      if ($compile_step == 0 && $report_only == 0) {
        $outsuffix = "aocx";
      } elsif ($report_only == 1 && $hdl_comp_pkg_flow == 0){
        $outsuffix = "aocr";
      } else {
        $outsuffix = "aoco";
      }
      $output_file .= "."  . $outsuffix;
    }
    my $outbase = $output_file;
    $outbase =~ s/\.$outsuffix//;
    if ($outsuffix eq "aoco") {
        ($run_quartus == 0 && $compile_step != 0) or acl::Common::mydie("Option -o argument cannot end in .aoco when used to name final output");
        # At this point, we know that there is only one item in @objfile_list
        $objfile_list[0] = acl::File::abs_path($outbase.".".$outsuffix);
        $$dirbase_ref = undef;
        $x_file = undef;
        $linked_objfile = undef;
    } elsif ($outsuffix eq "aocr"){
        ($compile_step == 0) or acl::Common::mydie("Option -o argument cannot end in .aocr when used with -c");
        # We still need to either generate an aoco package for first step or read from aoco for second step so objfile_list will still have aoco
        if ($suffix ne "aoco") {
          $objfile_list[0] = acl::File::abs_path($outbase.".aoco");
        }
        $$dirbase_ref = $outbase;
        $linked_objfile = $outbase.".linked.aoco.bc";
        $x_file = $output_file;
    } elsif ($outsuffix eq "aocx") {
        $compile_step == 0 or acl::Common::mydie("Option -o argument cannot end in .aocx when used with -c");
        $report_only == 0 or  acl::Common::mydie("Option -o argument cannot end in .aocx when used with -rtl");

        if ($suffix ne "aoco" && $suffix ne "aocr" ) {
          $objfile_list[0] = acl::File::abs_path($outbase.".aoco");
          $$dirbase_ref = $outbase;
        }elsif ($suffix ne "aocr"){
          $$dirbase_ref = $outbase;  
        }
        
        $linked_objfile = $outbase.".linked.aoco.bc";
        $x_file = $output_file;
    } elsif ($compile_step == 0) {
      acl::Common::mydie("Option -o argument must be a filename ending in .aocx when used to name final output");
    } else {
      acl::Common::mydie("Option -o argument must be a filename ending in .aoco when used with -c");
    }
     $output_file = acl::File::abs_path( $output_file );
  }

  # For incremental compile to preserve partitions correctly, project name ($base) must be the same as
  # the previous compile. The $base name will be used in the hpath, so it is required to preserve the
  # previous partitions.
  # The $dirbase, .aoco, and .aocx file names will not be changed.
  if ($incremental_compile) {
    my $prev_info = "";
    if ($incremental_input_dir && -e "$incremental_input_dir/reports/lib/json/info.json") {
      $prev_info = "$incremental_input_dir/reports/lib/json/info.json";
    } elsif ($$dirbase_ref && -e "$$dirbase_ref/reports/lib/json/info.json") {
      $prev_info = "$$dirbase_ref/reports/lib/json/info.json";
    }
    $$base_ref = acl::Incremental::get_previous_project_name($prev_info) if $prev_info;
  }

  for (my $i = 0; $i <= $#objfile_list; $i++) {     
    $objfile_list[$i] = acl::File::abs_path($objfile_list[$i]);
  }
  $x_file = acl::File::abs_path( $x_file );
  $linked_objfile = acl::File::abs_path( $linked_objfile );
    
  if ($#srcfile_list >= 0) { # not necesaarily set for "aoc file.aoco" 
    chdir $force_initial_dir or acl::Common::mydie("Can't change into dir $force_initial_dir: $!\n");
    foreach my $src (@srcfile_list) {
      -f $src or acl::Common::mydie("Invalid kernel file $src: $!");
      my $absolute_src = acl::File::abs_path($src);
      -f $absolute_src or acl::Common::mydie("Internal error. Can't determine absolute path for $src");
      push @absolute_srcfile_list, $absolute_src;
    }
    chdir $orig_dir or acl::Common::mydie("Can't change into dir $orig_dir: $!\n");
  }

  if (acl::Env::is_windows() and $#absolute_srcfile_list >= 0) {
    foreach my $abs_src (@absolute_srcfile_list) {
      # Check file first line, if equal to new encryption line then error out
      my $check_str = "`pragma protect begin_protected";
      open my $abs_src_file, '<', $abs_src; 
      my $first_line = <$abs_src_file>;
      chomp($first_line);
      if ($check_str eq $first_line) {
        acl::Common::mydie("Your design contains encrypted source not supported by this version. Please contact your sales support team to ensure you are using the correct software version to support this flow.");
      }
      close $abs_src_file;
    }
  }

  # get the absolute path for the Profiler Config file
  if(defined $profilerconf_file) {
      chdir $force_initial_dir or acl::Common::mydie("Can't change into dir $force_initial_dir: $!\n");
      -f $profilerconf_file or acl::Common::mydie("Invalid profiler config file $profilerconf_file: $!");
      $absolute_profilerconf_file = acl::File::abs_path($profilerconf_file);
      -f $absolute_profilerconf_file or acl::Common::mydie("Internal error. Can't determine absolute path for $profilerconf_file");
      chdir $orig_dir or acl::Common::mydie("Can't change into dir $orig_dir: $!\n");
  }
  
  # Output file must be defined for this flow
  if ($hdl_comp_pkg_flow) {
    defined $output_file or acl::Common::mydie("Output file must be specified with -o for HDL component packaging step.\n");
  }
  if ($created_shared_aoco and $emulator_flow) {
    acl::Common::mydie("-shared is not compatible with emulator flow.");
  }
  if ($emulator_fast and !$emulator_flow) {
    acl::Common::mydie("-march=emulator must be specified when targeting the fast emulator.");
  }
  if ($compile_step == 1 and $incremental_compile) {
    acl::Common::mydie("-c flow not compatible with incremental flow");
  }
  # some restrictions on third stage of compilation
  if ( ($aocr_to_aocx_only == 1 && $user_defined_board == 1 ) ) {
    acl::Common::mydie("-board and -board-package can not be used in this flow");
  }
  if ($aocr_to_aocx_only == 1 && $user_defined_flow == 1) {
    acl::Common::mydie("-march=emulator can not be used in this flow");
  }

  # Can't do multiple flows at the same time
  if ($soft_ip_c_flow + $compile_step + $run_quartus + $aoco_to_aocr_aocx_only > 1 ) {
      acl::Common::mydie("Cannot have more than one of -c, --soft-ip-c --hw on the command line,\n cannot combine -c with *.aoco or *.aocr and -rtl with *.aocr either\n");
  }

  # Can't do -c and -rtl at the same time
  if ($c_flag_only + $report_only + $run_quartus > 1 ) {
      acl::Common::mydie("Cannot have more than one of -c, -rtl, -hw on the command line,\n cannot combine -rtl with *.aocr either\n");
  }

  # Griffin exclusion until we add further support
  # Some of these (like emulator) should probably be relaxed, even today
  if($griffin_flow == 1 && $soft_ip_c_flow == 1){
    acl::Common::mydie("Backend not compatible with soft-ip flow");
  }
  if($griffin_flow == 1 && $accel_gen_flow == 1){
    acl::Common::mydie("Backend not compatible with C acceleration flow");
  }

}

1;
