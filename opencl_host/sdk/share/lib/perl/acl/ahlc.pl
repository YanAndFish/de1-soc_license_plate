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
require acl::Env;
require acl::File;

my $prog = 'ahlc';

# Directories
my $orig_dir = undef;

# Extensions
my $clang_suffix = "clang.bc";
my $extract_suffix = "extract.bc";
my $host_pre_suffix = "host.pre.bc";
my $translate_suffix = "trans.bc";
my $kernel_pre_suffix = "pre.bc";
my $host_opt_suffix = "host.bc";
my $host_asm_suffix = "s";
my $aoco_suffix = "aoco";
my $aocx_suffix = "aocx";

# Executables
my $clang_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/aocl-clang";
my $opt_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/aocl-opt";
my $llc_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/aocl-llc";
my $splitter_exe = $ENV{'INTELFPGAOCLSDKROOT'}."/linux64/bin"."/aocl-module-splitter";
my $aoc_exe = $ENV{INTELFPGAOCLSDKROOT}."/bin/aoc";

# Extraction opts
my @extraction_opts = (
  '-tbaa', '-basicaa',
  '-mem2reg',
  '-instcombine', '-always-remove-mem-intrinsics',
  '-altera-c-acceleration',
  '-loop-simplify',
  '-lcssa',
  '-meloop',
  '-accelerator-inline',
  '-break-constexprs',
  '-accelerator-extract'
  );

# Options
my $save_temps = 0;                         # Save temporary files
my $host_triple = "arm-none-linux-gnueabi"; # Host system triple
my $fpga_triple = "fpga64";                 # FPGA triple
my $float_abi = "hard";                     # ARM float abi
my $verbose = 0;                            # Verbosity
my $run_quartus = 1;                        # Whether or not to run Quartus
my @thumb = ('-march', 'thumb');            # Thumb option

my @args = ();
my @input_files = ();

my ($board_variant) = acl::Env::board_hardware_default();

sub mydie(@) {
  print STDERR "Error: ".join("\n",@_)."\n";
  chdir $orig_dir if defined $orig_dir;
  exit 1;
}

sub remove_named_files {
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose == 1 ? 0 : $verbose), dry_run => 0 } )
         or mydie("Cannot remove intermediate files under directory $fname: $acl::File::error.\n");
    }
}

sub is_arm_host
{
  return $host_triple =~ /^arm-/;
}

sub version()
{
  print "Altera High Level Compiler, 64-bit\n";
  print "Version 18.1 Build 222\n";
  print "Copyright (C) 2018 Intel Corporation\n";
}

sub usage()
{
  print <<USAGE;

ahlc -- Altera High Level Compiler

Usage: ahlc [<file>.c]+ <options>

Example:
  ahlc main.c foo.c

Outputs:
  An assembler file for each input C file. For each input file containing
  acceleration pragmas, an aocx file will also be produced.

Help Options:
--version Print out the version information and exit

-v        Verbose mode. Report progress of compilation

-h
--help    Show this message

Overall Options:
-c        Only perform the first stage of accelerator compile.

-I <directory>
          Add <directory> to the header search path

-D <name>
          Define macro <name>

Modifiers:
--board <board_name>
          Compile for the specified board. Default is c5soc.
          Note: Currently on c5soc is supported.

--float-abi <abi>
          Specify the float abi for ARM systems. Accept 'hard' or 'soft'.
          Default is 'hard'.

--thumb   
          Target ARM Thumb instructions.
--no-thumb
          Do not target ARM Thumb instructions.

--host-triple <triple>
          Specify the host system triple. Default is 'arm-none-linux-gnueabi'.
          Note: Currently only ARM targets are supported.

--fpga-triple <triple>
          Specify the triple for the FPGA. Default is 'fgpa64'.
          Note: Currently only fpga64 is supported.

USAGE

}

sub get_work_dir
{
  return $orig_dir."/".$_[0];
}

sub split_file
{
  my ($file) = @_;
  my $base = acl::File::mybasename($file);
  my $suffix = $base;
  $suffix =~ s/.*\.//;
  $base =~ s/\.$suffix//;
  $base =~ s/[^a-zA-Z0-9_]/_/g;

  return ($base, $suffix);
}

sub run_clang
{
  my ($file, $base, $work_dir) = @_;

  print "\n## Running Clang.\n" if $verbose;
  my @clang_cmd = (
    $clang_exe,
    '-cc1',
    '-x', 'c',
    '-altera-c-acceleration',
    '-triple', $host_triple,
    @args,
    '-emit-llvm-bc',
    $file,
    '-o', "$work_dir/$base.$clang_suffix"
  );
  print "@clang_cmd\n" if $verbose > 1;
  system(@clang_cmd);
  $? == 0 or mydie("Clang parser FAILED.");
}

sub extract_kernels
{
  my ($base, $work_dir) = @_;

  print "\n## Extracting '$base' accelerator kernels.\n" if $verbose;
  my @opt_cmd = (
    $opt_exe,
    @extraction_opts,
    '-accelerator-aocx', "$base.$aocx_suffix",
    "$work_dir/$base.$clang_suffix",
    '-o', "$work_dir/$base.$extract_suffix"
  );
  print "@opt_cmd\n" if $verbose > 1;
  system(@opt_cmd);
  $? == 0 or mydie("Kernel extraction FAILED.");

  $save_temps == 1 or remove_named_files("$work_dir/$base.$clang_suffix");
}

sub split_modules
{
  my ($base, $work_dir) = @_;

  print "\n## Splitting '$base' modules.\n" if $verbose;
  my @splitter_cmd = (
    $splitter_exe,
    '-verify',
    '-triple', $fpga_triple,
    "$work_dir/$base.$extract_suffix",
    '-o-host', "$work_dir/$base.$host_pre_suffix",
    '-o-kernel', "$work_dir/$base.$translate_suffix"
  );
  print "@splitter_cmd\n" if $verbose > 1;
  system(@splitter_cmd);
  $? == 0 or mydie("Module splitter FAILED.");

  $save_temps == 1 or remove_named_files("$work_dir/$base.$extract_suffix");
}

sub translate_library_calls
{
  my ($base, $work_dir) = @_;

  printf "\n## Translating '$base' library calls.\n" if $verbose;
  my @translate_cmd = (
    $opt_exe,
    '-translate-library-calls',
    '-verify',
    '-o', "$work_dir/$base.$kernel_pre_suffix",
    "$work_dir/$base.$translate_suffix"
  );
  print "@translate_cmd\n" if $verbose > 1;
  system(@translate_cmd);
  $? == 0 or mydie("Library call translation FAILED.");

  $save_temps == 1 or remove_named_files("$work_dir/$base.$translate_suffix");
}

sub optimize_host
{
  my ($base, $work_dir) = @_;

  print "\n## Optimizing '$base' host.\n" if $verbose;
  my @opt_cmd = (
    $opt_exe,
    '-std-compile-opts',
    '-std-link-opts',
    '-o', "$work_dir/$base.$host_opt_suffix",
    "$work_dir/$base.$host_pre_suffix"
    );
  print "@opt_cmd\n" if $verbose > 1;
  system(@opt_cmd);
  $? == 0 or mydie("Host optimization FAILED.");

  $save_temps == 1 or remove_named_files("$work_dir/$base.$host_pre_suffix");
}

sub generate_host_assembly
{
  my ($base, $work_dir) = @_;

  print "\n## Generating '$base' host assembly.\n" if $verbose;
  my @llc_args = ('-mtriple', $host_triple);
  # When other host systems are supported this will need changed.
  if (is_arm_host()) {
    push @llc_args, @thumb;
    push @llc_args, '-float-abi';
    push @llc_args, $float_abi;
    push @llc_args, '-O3';
    push @llc_args, '-mcpu=cortex-a9';
    push @llc_args, '-mattr=+neonfp,+vfp3,+v7,+d16,+thumb2';
  }
  my @llc_cmd = (
    $llc_exe,
    @llc_args,
    '-o', "$base.$host_asm_suffix",
    "$work_dir/$base.$host_opt_suffix"
  );
  print "@llc_cmd\n" if $verbose > 1;
  system(@llc_cmd);
  $? == 0 or mydie("Host assembly generation FAILED.");

  $save_temps == 1 or remove_named_files("$work_dir/$base.$host_opt_suffix");
}

sub run_aoc_dash_c
{
  my ($file, $base) = @_;

  print "\n## Running Altera Offline Compiler first stage.\n" if $verbose;
  my @aoc_cmd = (
    $aoc_exe,
    '-c',
    '--c-acceleration',
    '--board', $board_variant,
    '-o', "$base.$aoco_suffix",
    $file
  );
  print "@aoc_cmd\n" if $verbose > 1;
  system(@aoc_cmd);
  $? == 0 or mydie("Altera Offline Compiler first stage compile FAILED.");
}

sub compile
{
  my ($file) = @_;

  my ($base, $suffix) = split_file($file);
  my $work_dir = get_work_dir($base);
  acl::File::make_path($work_dir) or mydie("Cannot create dir $work_dir: $!");

  print "# $prog: Compiling $file\n" if $verbose;
  run_clang($file, $base, $work_dir);
  extract_kernels($base, $work_dir);
  split_modules($base, $work_dir);
  optimize_host($base, $work_dir);
  generate_host_assembly($base, $work_dir);
  if (-e "$work_dir/$base.$translate_suffix") {
    translate_library_calls($base, $work_dir);
    run_aoc_dash_c($file, $base);
  }
}

sub hardware_compile
{
  my ($file) = @_;

  my ($base, $suffix) = split_file($file);
  if (-e "$base.$aoco_suffix") {
    print "\n## Running '$base' hardware compile.\n" if $verbose;
    my @aoc_cmd = (
      $aoc_exe,
      "$base.$aoco_suffix"
    );
    print "@aoc_cmd\n" if $verbose > 1;
    system(@aoc_cmd);
    $? == 0 or mydie("Altera Offline Compiler hardware compile FAILED.");

    $save_temps == 1 or remove_named_files("$base.$aoco_suffix", get_work_dir($base));
  }
}

sub main() {
  while ( $#ARGV >= 0 ) {
    my $arg = shift @ARGV;
    if ( ($arg eq '-h') or ($arg eq '--help') ) { usage(); exit 0; }
    elsif ( ($arg eq '--version') ) { version(); exit 0; }
    elsif ($arg eq '--float-abi') {
      $#ARGV >= 0 or mydie("Option --float-abi requires an argument.");
      $float_abi = shift @ARGV;
      ($float_abi eq 'hard') or ($float_abi eq 'soft') or mydie("Option --float-abi requires 'hard' or 'soft'.");
    }
    elsif ($arg eq '--host-triple') {
      $#ARGV >= 0 or mydie("Option --host-triple requires an argument.");
      $host_triple = shift @ARGV;
      is_arm_host() or mydie("Only ARM host targets are supported currently.");
    }
    elsif ($arg eq '--fpga-triple') {
      $#ARGV >= 0 or mydie("Option --fpga-triple requires an argument.");
      $fpga_triple = shift @ARGV;
      $fpga_triple eq "fpga64" or mydie("Only fpga64 target triple is currently supported.");
    }
    elsif ($arg eq '--thumb') {
      @thumb = ('-march', 'thumb');
    }
    elsif ($arg eq '--no-thumb') {
      @thumb = ();
    }
    elsif ($arg eq '-c') {
      $run_quartus = 0;
    }
    elsif ($arg =~ m/\.c$/) {
      push @input_files, $arg;
    }
    elsif ($arg eq '-v') {
      $verbose += 1;
    }
    elsif ($arg eq '--board') {
      $board_variant = shift @ARGV;
    }
    elsif ($arg eq '--save-temps') {
      $save_temps = 1;
    }
    else {
      # Forward to clang
      push @args, $arg;
    }
  }

  $board_variant eq 'c5soc' or mydie("c5soc is the only currently supported board variant.");
  $#input_files >= 0 or mydie("No input files specified on the command line.");

  $orig_dir = acl::File::abs_path('.');

  # Steps
  #
  # compile()
  # 1. create the workdir
  # 2. run clang
  # 3. module splitting
  # 4. aoc -c kernel --c-acceleration
  #    This mainly would address the fact that if we compiled an aocx
  #    immediately then simple syntax errors in subsequent files would not be
  #    caught for hours. --c-acceleration is a hidden option in aoc that
  #    skips clang.
  # 5. llc host
  #
  # compile_hardware()
  # 1. aoc kernel.aoco (approximately)
  #    This should be controlled by a flag. It should be possible to not run a
  #    full compile at least for our own internal flows.
  foreach my $file (@input_files) {
    compile($file);
  }
  if ($run_quartus eq 1) {
    foreach my $file (@input_files) {
      hardware_compile($file);
    }
  }

  print "Compiled successfully!\n";
  print "Please assemble .s files into objects and "
       ."link them into an executable. Be sure to supply "
       ."'aocl link-config --altera-c-acceleration' output to the linker.\n"
}

main();
exit 0
