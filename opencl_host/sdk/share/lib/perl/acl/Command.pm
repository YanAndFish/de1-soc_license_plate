=pod

=head1 NAME

acl::Command - Utility commands for the Intel(R) FPGA SDK for OpenCL(TM)

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


package acl::Command;
require Exporter;
@acl::Command::ISA        = qw(Exporter);
@acl::Command::EXPORT     = ();
@acl::Command::EXPORT_OK  = qw();
use strict;
use acl::Env;
use acl::Board_env;
use acl::Pkg;
use acl::Common;
our $AUTOLOAD;

my @_valid_cmd_list = qw(
   version
   help
   do
   compile-config
   cflags
   link-config
   linkflags
   ldflags
   ldlibs
   board-path
   board-hw-path
   board-mmdlib
   board-libs
   board-link-flags
   board-default
   board-version
   board-name
   board-xml-test
   reprogram
   program
   flash
   diagnostic
   diagnose
   setup-fcd
   install
   uninstall
   list-devices
   example-makefile
   makefile
   binedit
   hash
   report
   library
   env
);

my @_valid_list = @_valid_cmd_list, qw( pre_args args cmd prog );

my %_valid_cmd = map { ($_ , 1) } @_valid_cmd_list;

my %_valid = map { ($_ , 1) } @_valid_list;

# the 2*ith element is the physical device name, the 2*i+1th element is the board package path associated with the board
my @device_map_multiple_packages = ();
my @packages_without_devices = ();

my $acl_root = acl::Env::sdk_root();

sub populate_attached_devices {
  my ($self,@args) = @_;
  acl::Common::populate_installed_packages();
  # backward compatiblily, if no packages are saved, try AOCL_BOARD_PACKAGE_ROOT
  if ($#installed_packages < 0) {
    push @installed_packages, acl::Board_env::get_board_path();
  }

  # populate attached devices for each board package installed
  for (my $i=0; $i<scalar(@installed_packages); $i++) {
    my $board_package_path = @installed_packages[$i];
    my $num_of_devices = 0;
    $ENV{"AOCL_BOARD_PACKAGE_ROOT"} = $board_package_path;
    if ( acl::Board_env::get_board_version() < 15.1 ) {
      push(@packages_without_devices,$board_package_path);
      next;
    }
    my $utilbin = acl::Board_env::get_util_bin();
    my $util = ( acl::Board_env::get_board_version() < 14.1 ) ? "diagnostic" : "diagnose";
    check_board_utility_env($self) or return undef;
    my $probe_output = `$utilbin/$util -probe`;
    my @lines = split('\n', $probe_output); 
    foreach my $line (@lines) {
      if ( $line =~ /^DIAGNOSTIC_/ ) {
        next;
      } else {
        #windows always populate 32 devices, this is the workaround
        my $check = `$utilbin/$util -probe $line`;
        if ($check =~ "DIAGNOSTIC_PASSED") {
          push(@device_map_multiple_packages,$line);
          push(@device_map_multiple_packages,$board_package_path);
          $num_of_devices += 1;
        }
      }
    }
    if ($num_of_devices == 0) {
      push(@packages_without_devices,$board_package_path);
    }
	}
}
  
sub new {
   my ($proto,$prog,@args) = @_;
   my $class = ref $proto || $proto;

   my @pre_args = ();
   my @post_args = ();
   my $subcommand = undef;
   my $first_arg = undef;
   while ( $#args >=0 ) {
      my $arg = shift @args;
      $first_arg = $arg unless defined $first_arg;
      if ( $arg =~ m/^[a-z]/ ) {
         $subcommand = $arg;
         last;
      } else {
         push @pre_args, $arg;
      }
   }
   if ( $_valid_cmd{$subcommand} ) {
      $subcommand =~ s/-/_/g;
      return bless {
         prog => $prog, 
         pre_args => [ @pre_args ], 
         cmd => $subcommand, 
         args => [ @args ] 
         }, $class;
   } else {
      if ( defined $first_arg ) {
         $subcommand = $first_arg unless defined $subcommand;
         $subcommand = '' unless defined $subcommand;
         print STDERR "$prog: Unknown subcommand '$subcommand'\n";
      }
      return undef;
   }
}

sub do {
   my $self = shift;
   # Using "exec" would be more natural, but it doesn't work as expected on Windows.
   # http://www.perlmonks.org/?node_id=724701
   if ( $^O =~ m/Win32/ ) {
      system(@{$self->args});
      # Need to post-process $? because it's a mix of status bits, and 
      # it seems Windows only allows "main" to return up to 8b its.
      # The $? bottom 8 bits encodes signals, the upper bits encode return status.
      # So $? for the "false" program (returns 1), is actually 256, and then if we exit 256
      # then it's translated back into 0 by Windows. Thus making "false" look like it succeeded!
      my $raw_status = $?; 
      # Fold in the signal error into our 8 bit error range.
      my $processed_status = ($raw_status>>8) | ($raw_status&255);
      exit $processed_status;
   } else {
      exec(@{$self->args});
      # exec() returns only if a command is not found, so the error message below doesn't need a condition
      print STDERR "aocl do: Cannot execute '@{$self->args}'\n";
   }
}


sub run {
   my $self = shift;
   my $cmd = $self->cmd;
   my @args = @{$self->args};
   my $result = eval "\$self->$cmd(\@args)";
   if ($@) {
      print $@; #don't supress errors.
      return 0;
   } else {
      return $result;
   }
}

sub env {
   my ($self,@args) = @_;
   if ( $#args == 0 && ($args[0] =~ m/.aocx$/i || $args[0] =~ m/.aoco$/i ) ) {
      my $result = $self->binedit($args[0],'print','.acl.compilation_env');
      print "\n";  # "binedit print" does not append the newline
      return $result;
   }
   print STDERR $self->prog." env: Unrecognized options: @args\nAn input .aocx file is needed.\n";
   return undef;
}

sub version {
   my ($self,@args) = @_;
   if ( $#args < 0 ) {
      my $banner = acl::Env::is_sdk() ? 'Intel(R) FPGA SDK for OpenCL(TM), Version 18.1.0 Build 222 Pro Edition, Copyright (C) 2018 Intel Corporation' : 'Intel(R) FPGA Runtime Environment for OpenCL(TM), Version 18.1.0 Build 222 Pro Edition, Copyright (C) 2018 Intel Corporation';
      print $self->prog." 18.1.0.222 ($banner)\n";
   } else {
      if ( $#args == 0 && $args[0] =~ m/.aocx$/i ) {
         my $result = $self->binedit($args[0],'print','.acl.version');
         print "\n";  # "binedit print" does not append the newline
         return $result;
      }
      print STDERR $self->prog." version: Unrecognized options: @args\n";
      return undef;
   }
   return $self;
}

sub report {
   my ($self,@args) = @_;
   my $aocx = undef;
   my $mon = undef;
   my $source = undef;
   my @input_args;
   foreach my $arg ( @args ) {
      my ($ext) = $arg =~ /(\.[^.]+)$/;
      if ( $ext eq '.aocx' ) { $aocx = $arg;} 
      elsif ( $ext eq '.source' ) { $source = $arg;} 
      elsif ( $ext eq '.mon' ) { $mon = $arg; }
      else { push(@input_args, $arg); }
   }
   if ( defined $aocx && defined $mon ) {
      my $ACL_ROOT = acl::Env::sdk_root();
      if ( ! -e "$ACL_ROOT/share/lib/java/reportgui.jar" ) {
         print $self->prog." report: Intel(R) FPGA SDK for OpenCL(TM) report application not installed, please reinstall your Intel(R) FPGA SDK for OpenCL(TM).\n";
         return $self;
      }
      if ( ! -e $aocx ) {
         print $self->prog." report: Invalid aocx file supplied: $aocx\n";
         return $self;
      }
      if (! -e $mon ) {
         print $self->prog." report: Invalid profile.mon file supplied: $mon\n";
         return $self;
      }
      if ( defined $source && ! -e $source) {
         print $self->prog." report: Invalid .source file supplied: $source\n";
         return $self;
      }

      # Make sure Java is found and it's NOT from /usr/bin -- likely a wrong version
      my $java_location = acl::File::which_full ("java"); chomp $java_location;
      if ( not defined $java_location ) {
         print $self->prog." report: No java executable found!\n" . 
               $self->prog." report needs java that came with ACDS installation.\n" .
               "Add quartus bin directory to the front of the PATH to solve this problem.\n";
         return $self;
      }
      if ( $java_location =~ "/usr/bin" ) {
         my $java_relative_loc;
         if (acl::Env::is_windows()) {
            $java_relative_loc = "/bin64/jre64/bin";
         } else {
            $java_relative_loc = "/linux64/jre64/bin";
         }
         print $self->prog." report: Found Java is $java_location.\n" . 
               "Report needs java that came with ACDS installation.\n" .
               "Add <quartus_rootdir>" . $java_relative_loc . " to the PATH to solve this problem.\n";
         return $self;
      }

      # If .source file isn't specified, try to find it alongside the .aocx
      if (! defined $source) {
        (my $source_name = $aocx) =~ s/aocx$/source/;
        if ( -e $source_name ) {
          print "WARNING: Using automatically detected .source file '$source_name'.\n";
          print "Please specify the correct .source file if this one is not correct.\n";
          $source = $source_name;
        }
      }

      # Put source at beginning of input_args.
      unshift @input_args, $source if defined $source;

      # By now know that java is on the path and it's the one we need.
      system("java", "-jar", "$ACL_ROOT/share/lib/java/reportgui.jar", $aocx, $mon, @input_args );
   } else {
      print $self->prog." report: Report needs .aocx, .mon, and optionally .source\n";
      return undef;
   }
   return $self;
}



sub _print_or_unrecognized(@) {
   my ($self,$name,$printval,@args) = @_;
   if ( $#args >= 0 ) {
      print STDERR $self->prog." $name: Unrecognized option: $args[0]\n";
      return undef;
   }
   print $printval,"\n";
   return $self;
}


sub get_ldflags{
  acl::Common::populate_installed_packages();      
  my ($result, @args); 
  if(acl::Common::is_fcd_present()){
    if (acl::Env::is_linux()){
      $result = "-L".acl::Env::sdk_root()."/host/".acl::Env::get_arch(@_)."/lib";
    }else{
      $result = "/libpath:$acl_root/host/windows64/lib";
    }
    @args = @_;
  } else{
    if ($#installed_packages <= 0) {
      if ($#installed_packages == 0) {
        $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = shift @installed_packages;
      }
      ($result, @args) = acl::Env::host_ldflags(@_);
    } else {
      die "Cannot find any fcd files when multiple board packages are installed\n";
    }
  }
  return $result, @args;
}


sub get_ldlibs{
  acl::Common::populate_installed_packages();
  my ($result, @args); 
  if(acl::Common::is_fcd_present()){
    if (acl::Env::is_linux()) {
      $result = "-lOpenCL";
    } else {
      $result = "OpenCL.lib";
    }
    @args = @_;
  }else{
    if ($#installed_packages <= 0) {
      if ($#installed_packages == 0) {
        $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = shift @installed_packages;
      }
      ($result, @args) = acl::Env::host_ldlibs(@_);      
    } else {
      die "Cannot find any fcd files when multiple board packages are installed\n";
    }
  }
  return $result, @args;
}


sub link_config {
  my ($ldflagsVal, @ldflagsArgs) = get_ldflags(@_);
  my ($ldlibsVal, @ldlibsArgs) = get_ldlibs(@_);
  shift->_print_or_unrecognized('link-config', $ldflagsVal." ".$ldlibsVal, @ldlibsArgs[ 1 .. $#ldlibsArgs ]);
}

sub linkflags {
  # This function produce the same result as link-config. 
  my ($ldflagsVal, @ldflagsArgs) = get_ldflags(@_);
  my ($ldlibsVal, @ldlibsArgs) =  get_ldlibs(@_);
  shift->_print_or_unrecognized('linkflags', $ldflagsVal." ".$ldlibsVal, @ldlibsArgs[ 1 .. $#ldlibsArgs ]);
}

sub ldflags {
  my ($ldflagsVal, @ldflagsArgs) = get_ldflags(@_);
  shift->_print_or_unrecognized('ldflags', $ldflagsVal, @ldflagsArgs[ 1 .. $#ldflagsArgs ]);
}

sub ldlibs {
  my ($ldlibsVal, @ldlibsArgs) = get_ldlibs(@_);
  shift->_print_or_unrecognized('ldlibs', $ldlibsVal, @ldlibsArgs[ 1 .. $#ldlibsArgs ]);
}


sub board_hw_path {
   my ($self,$variant,@args) = @_;
   unless ( $variant ) {
      print STDERR $self->prog." board-hw-path: Missing a board variant argument\n";
      return undef;
   }
   $self->_print_or_unrecognized('board-hw-path',acl::Env::board_hw_path($variant,@args));
}
sub board_path { shift->_print_or_unrecognized('board-path',acl::Env::board_path(@_)); }
sub board_mmdlib { shift->_print_or_unrecognized('board-mmdlib',acl::Env::board_mmdlib(@_)); }
sub board_libs { shift->_print_or_unrecognized('board-libs',acl::Env::board_libs(@_)); }
sub board_link_flags { shift->_print_or_unrecognized('board-libs',acl::Env::board_link_flags(@_)); }
sub board_default { shift->_print_or_unrecognized('board-default',acl::Env::board_hardware_default(@_)); }
sub board_version { shift->_print_or_unrecognized('board-version',acl::Env::board_version(@_)); }
sub board_name { shift->_print_or_unrecognized('board-version',acl::Env::board_name(@_)); }


sub board_xml_test {
   my $self = shift;
   my $aocl = acl::Env::sdk_aocl_exe();
   print " board-path       = ".`$aocl board-path`."\n";
   my $board_version = `$aocl board-version`;
   print " board-version    = $board_version\n";
   print " board-name       = ".`$aocl board-name`."\n";
   my $bd_default = `$aocl board-default`;
   print " board-default    = ".$bd_default."\n";
   print " board-hw-path    = ".`$aocl board-hw-path $bd_default`."\n";
   print " board-link-flags = ".`$aocl board-link-flags`."\n";
   print " board-libs       = ".`$aocl board-libs`."\n";
   print " board-util-bin   = ".acl::Board_env::get_util_bin()."\n";
   if ( $board_version >= 15.1 ) {
     print " board-mmdlib     = ".`$aocl board-mmdlib`."\n";
   }
   return $self;
}



sub check_board_utility_env {
  my ($self) = @_;

  # Check that BSP is <= SDK version number
  # This call will force an exit if the version is illegal
  my $bsp_version =  acl::Board_env::get_board_version();

  # Check that we're not in emulator mode
  if (defined $ENV{CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA})
  {
    printf "%s %s: Can't run board utilities with CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA set\n", $self->prog, $self->cmd;
    return 0;
  }
  if (defined $ENV{CL_CONTEXT_EMULATOR_DEVICE_ALTERA})
  {
    printf "Warning: CL_CONTEXT_EMULATOR_DEVICE_ALTERA is deprecated. Use CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA instead\n";
    printf "%s %s: Can't run board utilities with CL_CONTEXT_EMULATOR_DEVICE_ALTERA set\n", $self->prog, $self->cmd;
    return 0;
  }
  return 1;
}

sub program {
  my ($self,@args) = @_;
  my $result = reprogram(@_);
  if ( $? ) { return undef; }
  if ( not defined $result ) { return undef; }
  return $self;
}

# checks if fpga.bin is fast-compile'd or not
sub check_fast_compile {
  my $binfile = shift @_;
  my $pkg = get acl::Pkg($binfile);
  if ( !defined($pkg) ) {
    print "Failed to open file: $binfile\n";
    return -1;
  }
  my $fast_compile_section = '.acl.fast_compile';
  if ($pkg->exists_section($fast_compile_section)) {
    if (`aocl binedit $binfile print $fast_compile_section` == 1) {
      return 1;
    }
  }
  return 0
}

# Return full path to fpga_temp.bin
sub get_fpga_temp_bin {
   my $arg = shift @_;
   my $pkg = get acl::Pkg($arg);
   if ( !defined($pkg) ) {
     print "Failed to open file: $arg\n";
     return -1;
   }
   my $hasbin = $pkg->exists_section('.acl.fpga.bin');
   if (not $hasbin )
   {  return ""; }
   my $tmpfpgabin = acl::File::mktemp();
   my $fpgabin = $tmpfpgabin;
   if ( length $tmpfpgabin == 0 ) {
     # In case we fail to get a temp file, use local dir.  Using PID
     # as a uniqifier is safe here since this function is called only
     # once by flash, or once by program, and not both in the same process.
     $fpgabin = "fpga_temp_$$.bin";
   } else {
     $fpgabin .= '_fpga_temp.bin';
   }
   my $gotbin = $pkg->get_file('.acl.fpga.bin', $fpgabin);
   if ( !defined( $gotbin )) {
     print "Failed to extract binary section from file: $arg\n";
     print "  Tried: $fpgabin and $tmpfpgabin\n";
     return "";
   }
   return $fpgabin;
}

sub reprogram {
   my ($self, @args) = @_;
   # Parse the arguments
   my $device = undef;
   my $aocx = undef;
   my $board_package_root = undef;
   my $num_args = @args;

   populate_attached_devices($self);
   my $is_old_board = 0;
   # Need to know the whether the board version is <15.1
   if ($#installed_packages == 0) {
     $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = @installed_packages[0];
     if ( acl::Board_env::get_board_version() < 15.1 ) {
       $is_old_board = 1;
     }
   }
   foreach my $arg ( @args ) {
     my ($ext) = $arg =~ /(\.[^.]+)$/;
     if ( $ext eq '.aocx' ) { 
       $aocx = $arg;
     } else { 
       my ($acl_num) = $arg =~ /^acl(\d+)$/;
       if ($is_old_board) {
         $device = $arg;
         $board_package_root = @installed_packages[0];
       }else{
         if ( !defined($acl_num) or $acl_num < 0) {
            print STDERR "Missing or invalid device \'$acl_num\'\n";
            my $help = new acl::Command($self->prog, qw(help program));
            $help->run();
            return undef;
         }
         
         if($acl_num < scalar(@device_map_multiple_packages)/2){
             $device = @device_map_multiple_packages[$acl_num * 2];
             $board_package_root = @device_map_multiple_packages[$acl_num * 2 + 1];
         }else{
           print STDERR "Device \'$acl_num\' not part of known packages.\n";
           diagnostic();
           return undef;
         }
       }
     }
   }
   $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $board_package_root;
   # If arguments not valid, print help/usage message.
   if ( $num_args != 2 or !defined($aocx) or !defined($device) or !defined($board_package_root)) {
      my $help = new acl::Command($self->prog, qw(help program));
      $help->run();
      return undef;
   }
   my $utilbin = acl::Board_env::get_util_bin(); 
   my $util = ( acl::Board_env::get_board_version() < 14.1 ) ? "reprogram" : "program";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );
   if ( defined $command ) {
     print $self->prog." program: Running $util from $utilbin\n";
     # Get .bin from the AOCX file and call reprogram with that
     my $fpgabin = get_fpga_temp_bin($aocx);
     if ( length $fpgabin == 0 ) { printf "%s program: Program failed. Error reading aocx file.\n", $self->prog; return undef; }

     if ( acl::Board_env::get_board_version() > 15.0)
     { 
       # new 15.1 boards 
       delete $ENV{CL_CONTEXT_COMPILER_MODE_INTELFPGA};
       delete $ENV{CL_CONTEXT_COMPILER_MODE_ALTERA}; # Delete the deprecated name also since developers may be using it
       # setting the environment variable below is for A10 boards, it will cause the runtime environment to ignore the board name when attempting to reprogram
       $ENV{ACL_PCIE_PROGRAM_SKIP_BOARDNAME_CHECK}='1';
       system("$utilbin/$util","$device",$fpgabin,$aocx);
     } else {
       # old pre-15.1 boards
       system("$utilbin/$util","$device",$fpgabin);
     }         
     #remove the file we ouput
     unlink $fpgabin;

     if ( $? ) { printf "%s program: Program failed.\n", $self->prog; return undef; }
     return $self;
   } else { 
     print "--------------------------------------------------------------------\n";
     print "No programming routine supplied.                                    \n";
     print "Please consult your board manufacturer's documentation or support   \n";
     print "team for information on how to load a new image on to the FPGA.     \n";
     print "--------------------------------------------------------------------\n";
     return undef;
   }
   return $self;
}

sub flash {
   my ($self, @args) = @_;
   # Parse the arguments
   my $device = undef;
   my $aocx = undef;
   my $board_package_root = undef;
   my $num_args = @args;

   populate_attached_devices($self);
   my $is_old_board = 0;
   # Need to know the whether the board version is <15.1
   if ($#installed_packages == 0) {
     $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = @installed_packages[0];
     if ( acl::Board_env::get_board_version() < 15.1 ) {
       $is_old_board = 1;
     }
   }
   foreach my $arg ( @args ) {
     my ($ext) = $arg =~ /(\.[^.]+)$/;
     if ( $ext eq '.aocx' ) { 
       $aocx = $arg;
     } else { 
       my ($acl_num) = $arg =~ /^acl(\d+)$/;
       if ($is_old_board) {
         $device = $arg;
         $board_package_root = @installed_packages[0];
       }else{
         if ( !defined($acl_num) or $acl_num < 0) {
            print STDERR "Missing or invalid device.\n";
            my $help = new acl::Command($self->prog, qw(help program));
            $help->run();
            return undef;
         }
         
         if($acl_num < scalar(@device_map_multiple_packages)/2){
             $device = @device_map_multiple_packages[$acl_num * 2];
             $board_package_root = @device_map_multiple_packages[$acl_num * 2 + 1];
         }else{
           print STDERR "Device not part of know packages.\n";
           diagnostic();
           return undef;
         }
       }
     }
   }
   # If arguments not valid, print help/usage message.
   if ( $num_args != 2 or !defined($aocx) or !defined($device) or !defined($board_package_root)) {
      my $help = new acl::Command($self->prog, qw(help flash));
      $help->run();
      return undef;
   }
   $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $board_package_root;
   my $utilbin = acl::Board_env::get_util_bin(); 
   my $util = "flash";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );
   if ( defined $command ) {
     print $self->prog." flash: Running $util from $utilbin\n";
     # Get .bin from the AOCX file and call flash with that
     my $fpgabin = get_fpga_temp_bin($aocx);
     my $fast_compile = check_fast_compile($fpgabin);
     if ( length $fpgabin == 0 || $fast_compile == -1 ) { printf "%s flash: Flashing failed. Error reading aocx file.\n", $self->prog; return undef; }
     if ( $fast_compile == 1 ) { printf "%s flash: Flashing failed. Cannot flash fast-compile'd aocx file.\n", $self->prog; return undef; }

     system("$utilbin/$util","$device",$fpgabin);
     #remove the file we ouput
     unlink $fpgabin;

     if ( $? ) { printf "%s flash: Program failed.\n", $self->prog; return undef; }
     return $self;
     print $self->prog." flash: Running flash from $utilbin\n";
     system("$utilbin/$util",$device,@args);
     if ( $? ) { printf "%s flash: Program failed.\n", $self->prog; return undef; }
   } else { 
     print "--------------------------------------------------------------------\n";
     print "No flash routine supplied.                                    \n";
     print "Please consult your board manufacturer's documentation or support   \n";
     print "team for information on how to load a new image on to the FPGA.     \n";
     print "--------------------------------------------------------------------\n";
   }
   return $self;
}

sub diagnose {
  my ($self,@args) = @_;
  diagnostic(@_);
  if ( $? ) { return undef; }
  return $self;
}

sub diagnostic {
   my ($self,@args) = @_;
   # If no arguments, just list all the attached boards with their board packages
   if (scalar@args == 0) {
     list_devices(@_, "diagnose");
     print "\nCall \"aocl diagnose <device-names>\" to run diagnose for specified devices\n";
     print "Call \"aocl diagnose all\" to run diagnose for all devices\n";
   } else {
     populate_attached_devices($self);
     my $is_old_board = 0;
     # Need to know the whether the board version is <15.1
     if ($#installed_packages == 0) {
       $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = @installed_packages[0];
       if ( acl::Board_env::get_board_version() < 15.1 ) {
         $is_old_board = 1;
       }
     }
     # if aocl all, push all devices to @args
     if (scalar@args == 1 and @args[0] eq "all") {
       if ($is_old_board) {
         my $old_bsp = @installed_packages[0];
         die "\"diagnose all\" is not supported for $old_bsp\n";
       }
       shift @args;
       for (my $i=0;$i < scalar(@device_map_multiple_packages)/2;$i++) {
         push @args, "acl$i";
       }
     }
     # run diagnose for every device in @args
     while (@args) {
       my $logical_device = shift @args;
       my $phys_device = undef;
       my $package_root = undef;
       my ($acl_num) = $logical_device =~ /^acl(\d+)$/;

       # if acl(num) and num is within the range, logical device name
       if ( (!$is_old_board) and (defined $acl_num) and $acl_num >= 0 and $acl_num < scalar(@device_map_multiple_packages)/2 ) {
         $phys_device = @device_map_multiple_packages[$acl_num * 2];
         $package_root = @device_map_multiple_packages[$acl_num * 2 + 1];
         $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $package_root;
       # If old board, this is the physical device name
       } elsif ( $is_old_board ) {
         $phys_device = $logical_device;
         $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = @installed_packages[0];
       # else, physical device name
       } else {
         print "--------------------------------------------------------------------\n";
         print "$logical_device is not a valid device name.                         \n";
         print "--------------------------------------------------------------------\n";
         next;
       }
       my $utilbin = acl::Board_env::get_util_bin();
       my $util = ( acl::Board_env::get_board_version() < 14.1 ) ? "diagnostic" : "diagnose";
       check_board_utility_env($self) or return undef;
       my $command = acl::File::which( "$utilbin","$util" );
       if ( ! defined $command ) {
         print "--------------------------------------------------------------------\n";
         print "No board diagnose routine supplied.                                 \n";
         print "Please consult your board manufacturer's documentation or support   \n";
         print "team for information on how to debug board installation problems.   \n";
         print "--------------------------------------------------------------------\n";
         next;
       }
       system("$utilbin/$util", $phys_device);
     }
   }
   return $self;
}


sub install {
   my ($self,@args) = @_;
   my $board_package_path = "";
   # If the user specifies a board package root
   if ($#args == 0) {
     $board_package_path = shift @args;
   # If the user specifies too many board package roots
   } elsif ($#args > 0) {
     print "Too many board package paths provided\n";
     return undef;
   # If the user does not specify a board package root
   } else {
     # get AOCL_BOARD_PACKAGE_ROOT
     my $acl_board_path = $ENV{'AOCL_BOARD_PACKAGE_ROOT'};
     # If the environment variable is not set or is empty, prompt the user to provide a board package root
     if (!defined $acl_board_path or $acl_board_path eq "") {
       print "Please specify a board package root to install:\n";
       $board_package_path = <STDIN>;
       chomp $board_package_path;
     # Otherwise, check whether the user wants to install the bsp specified in AOCL_BOARD_PACKAGE_ROOT
     } else {
       print "Do you want to install $acl_board_path? [y/n] ";
       my $user_input = <STDIN>;
       chomp $user_input;
       if ($user_input eq 'y') {
         $board_package_path = $acl_board_path;
       } elsif ($user_input eq 'n') {
         print "Please specify a board package root to install:\n";
         $board_package_path = <STDIN>;
         chomp $board_package_path;
       } else {
         print "Invalid user input\n";
         return undef;
       }
     }
   }
   acl::Common::populate_installed_packages();
   $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = acl::File::abs_path($board_package_path);
   my $board_package_full_path = acl::Board_env::get_board_path();

   # If more than 1 bsp installed, need to make sure that versions of all installed bsp are >=15.1
   push @installed_packages, $board_package_full_path;
   if ($#installed_packages > 0) {
     foreach my $bsp (@installed_packages) {
       $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $bsp;
       if ( acl::Board_env::get_board_version() < 15.1 ) {
         die "Mutiple board packages are not supported for $bsp\n";
       }
     }
   }

   # FCD and installed packages
   my $utilbin = acl::Board_env::get_util_bin();
   my $util = "install";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );
   print $self->prog." $util: Adding the board package $board_package_full_path to the list of installed pckages\n";
   acl::Common::save_to_installed($board_package_full_path);
   print $self->prog." $util: Setting up FCD\n";
   acl::Common::setup_fcd();

   # Install binary
   if ( defined $command ) {
     print $self->prog." $util: Running $util from $utilbin\n";
     system("$utilbin/$util",@args);
     if ( $? ) { 
       printf "%s $util: failed.\n", $self->prog; 
       print $self->prog." $util: Removing the board package $board_package_full_path from the list of installed packages\n";
       acl::Common::remove_from_installed($board_package_full_path);
       print $self->prog." $util: Removing FCD\n";
       acl::Common::remove_fcd();
       return undef; 
     } 
   } else { 
     print "--------------------------------------------------------------------\n";
     print "Warning: No board installation routine supplied.                    \n";
     print "Please consult your board manufacturer's documentation or support   \n";
     print "team for information on how to properly install your board.         \n";
     print "--------------------------------------------------------------------\n";
   }
   return $self;
}

sub uninstall {
   my ($self,@args) = @_;
   my $board_package_path = "";
   # If the user specifies a board package root
   if ($#args == 0) {
     $board_package_path = shift @args;
   # If the user specifies too many board package roots
   } elsif ($#args > 0) {
     print "Too many board package paths provided\n";
     return undef;
   # If the user does not specify a board package root
   } else {
     # list the installed packages
     print "Please call aocl uninstall <board-package-path> to uninstall the bsp\n";
     print "Installed board packages list:\n";
     acl::Common::populate_installed_packages();
     if ($#installed_packages < 0) {
       print "No packages installed\n";
     } else {
       foreach my $package (@installed_packages) {
         print "$package\n";
       }
     }
     return $self;
   }
   $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = acl::File::abs_path($board_package_path);
   my $board_package_full_path = acl::Board_env::get_board_path();
   my $utilbin = acl::Board_env::get_util_bin();
   my $util = "uninstall";
   check_board_utility_env($self) or return undef;
   my $command = acl::File::which( "$utilbin","$util" );

   # FCD and installed_packages
   print $self->prog." $util: Removing the board package $board_package_full_path from the list of installed packages\n";
   acl::Common::remove_from_installed($board_package_full_path);
   print $self->prog." $util: Removinacl::Common::g FCD\n";
   acl::Common::remove_fcd();

   # Uninstall binary
   if ( defined $command ) {
     print $self->prog." $util: Running $util from $utilbin\n";
     system("$utilbin/$util",@args);
     if ( $? ) { 
       printf "%s $util: failed.\n", $self->prog; 
       return undef; 
     }
   } else { 
     print "--------------------------------------------------------------------\n";
     print "No board uninstallation routine supplied.                           \n";
     print "Please consult your board manufacturer's documentation or support   \n";
     print "team for information on how to properly uninstall your board.       \n";
     print "--------------------------------------------------------------------\n";
   }
   return $self;
}

sub binedit {
   my ($self,@args) = @_;
   system(acl::Env::sdk_pkg_editor_exe(),@args);
   return undef if $?;
   return $self;
}

# List available boards
sub list_devices {
   my ($self,@args) = @_;
   populate_attached_devices($self);
   for (my $i=0; $i<scalar(@device_map_multiple_packages)/2; $i++) {
     my $logical_device = "acl$i";
     my $phys_device = @device_map_multiple_packages[2 * $i];
     my $package_root = @device_map_multiple_packages[2 * $i +1];

     $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $package_root;
     my $utilbin = acl::Board_env::get_util_bin();
     my $util = ( acl::Board_env::get_board_version() < 14.1 ) ? "diagnostic" : "diagnose";
     check_board_utility_env($self) or next;
     my $probe_out = `$utilbin/$util -probe $phys_device`;

     print("--------------------------------------------------------------------\n");
     print("Device Name:\n");
     print("$logical_device\n\n");
     print("BSP Install Location:\n");
     print("$package_root\n\n");
     print("$probe_out");
     print("--------------------------------------------------------------------\n");
   }

   for (my $i=0; $i<scalar(@packages_without_devices); $i++) {
     my $package_root = @packages_without_devices[$i];
     $ENV{"AOCL_BOARD_PACKAGE_ROOT"} = $package_root;
     print("--------------------------------------------------------------------\n");
     print("Warning:\n");
     print("No devices attached for package:\n");
     print("$package_root\n");
     print("--------------------------------------------------------------------\n");

     if (scalar@args == 1 and @args[0] eq "diagnose") {
       my $utilbin = acl::Board_env::get_util_bin();
       my $util = ( acl::Board_env::get_board_version() < 14.1 ) ? "diagnostic" : "diagnose";
       check_board_utility_env($self) or next;
       my $probe_out = `$utilbin/$util`;
       print $probe_out;
       print("--------------------------------------------------------------------\n");
      }
   }
   return $self;
}

sub library {
   my ($self,@args) = @_;
   system(acl::Env::sdk_libedit_exe(),@args);
   return undef if $?;
   return $self;
}

sub hash {
   my ($self,@args) = @_;
   system(acl::Env::sdk_hash_exe(),@args);
   return undef if $?;
   return $self;
}


sub _cflags_include_only {
   my $ACL_ROOT = acl::Env::sdk_root();
   return "-I$ACL_ROOT/host/include";
}

sub _get_cross_compiler_include_directories {
   my ($cross_compiler) = @_;

   my $includes = undef;
   my $ACL_ROOT = acl::Env::sdk_root();
   my $output = `$cross_compiler -v -c $ACL_ROOT/share/lib/c/includes.c -o /dev/null 2>&1`;
   $? == 0 or print STDERR "Error determing cross compiler default include directories\n";
   my $add_includes = 0;
   my @lines = split('\n', $output); 
   foreach my $line (@lines) {
      if ($line =~ /^#include <\.\.\.> search starts here:/) {
         $add_includes = 1;
      } elsif ($line =~ /^End of search list./) {
         $add_includes = 0;
      } elsif ($add_includes) {
         $includes .= " -I".$line;
      }
   }
   return $includes." ";
}

sub compile_config {
   my ($self,@args) = @_;
   my $extra_flags = undef;
   while ( $#args >= 0 ) {
      my $arg = shift @args;
      if ( $arg eq '--arm-cross-compiler' ) {
         if (acl::Env::is_windows()) {
            print STDERR $self->prog." compile-config: --arm-cross-compiler is not supported on Windows.\n";
            return undef;
         }
         if ($#args >= 0) {
            my $cross_compiler = shift @args;
            $extra_flags = _get_cross_compiler_include_directories($cross_compiler);
         } else {
            print STDERR $self->prog." compile-config: --arm-cross-compiler requires an argument.\n";
            return undef;
         }
      } elsif ( $arg eq '--arm' ) {
         # Just swallow the arg.
      } else {
         print STDERR $self->prog." compile-config: unknown option $arg.\n"; 
         return undef;
      }
   }

   my $board_flags = "";
   acl::Common::populate_installed_packages();

   if (!acl::Common::is_fcd_present()) {
     if ($#installed_packages < 0) {
       $board_flags = acl::Board_env::get_xml_platform_tag_if_exists("compileflags");
     } elsif ($#installed_packages == 0) {
       $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = shift @installed_packages;
       $board_flags = acl::Board_env::get_xml_platform_tag_if_exists("compileflags");
     } else {
       die "Cannot find any fcd files when multiple board packages are installed\n";
     }
   }
   print $extra_flags . _cflags_include_only(). " $board_flags" . "\n";
   return $self;
}

sub cflags {
   my ($self,@args) = @_;
   compile_config(@_);
   return $self;
}


sub example_makefile {
   my ($self,@args) = @_;
   my $help = new acl::Command($self->prog, qw(help example-makefile), @args);
   $help->run();
   return $self;
}


sub makefile {
   my ($self,@args) = @_;
   my $help = new acl::Command($self->prog, qw(help example-makefile), @args);
   $help->run();
   return $self;
}

sub AUTOLOAD {
   my $self = shift;
   my $class = ref($self) or die "$self is not an object";
   my $name = $AUTOLOAD;
   $name =~ s/^.*:://;
   my $result = $${self}{$name};
   return $result;
}


sub help {
   my ($self,$topic,@args) = @_;
   my $prog = $self->prog;

   my $sdk_root_name = acl::Env::sdk_root_name();
   my $is_sdk = acl::Env::is_sdk();
   my $sdk = $is_sdk ? "SDK" : "RTE";
   my $sdk_first_mention = $is_sdk ? "SDK" : "Runtime Environment (RTE)";
   my $target_arm = ($#args >= 0) and ($args[0] eq '--arm');

   my $use_aoc_note= <<USE_AOC_NOTE;
Note: Use the separate "aoc" command to compile your OpenCL(TM) kernel programs.
USE_AOC_NOTE
   my $use_aoc_in_rte_note= <<USE_AOC_IN_RTE_NOTE;
Note: Use the "aoc" command from the Intel(R) FPGA SDK for OpenCL(TM) to compile
your OpenCL(TM) kernel programs.
USE_AOC_IN_RTE_NOTE
   my $aoc_note = $is_sdk ? $use_aoc_note : $use_aoc_in_rte_note;

   my $loader_advice =<<LOADER_ADVICE;
   Additionally, at runtime your host program must run in an enviornment
   where it can find the shared libraries provided by the Intel(R) FPGA $sdk for
   OpenCL(TM).  

   For example, on Windows the PATH environment variable should include
   the directory %$sdk_root_name%/host/windows64/bin.

   For example, on Linux the LD_LIBRARY_PATH environment variable should
   include the directory \$$sdk_root_name/host/linux64/lib.

See also: $prog example-makefile
LOADER_ADVICE

   my $host_compiler_options = <<HOST_COMPILER_OPTIONS;
   --msvc, --windows       Show link line for Microsoft Visual C/C++.
   --gnu, -gcc, --linux    Show link line for GCC toolchain on Linux.
   --arm                   Show link line for cross-compiling to arm.
HOST_COMPILER_OPTIONS

my $makefile_help_arm = <<MAKEFILE_EXAMPLE_HELP_ARM_ONLY;

Example GNU makefile cross-compiling to ARM SoC from Linux or Windows, with 
Linaro GCC cross-compiler toolchain:

CROSS-COMPILER=arm-linux-gnueabihf-
AOCL_COMPILE_CONFIG=\$(shell $prog compile-config --arm)
AOCL_LINK_CONFIG=\$(shell $prog link-config --arm)

host_prog : host_prog.o
	\$(CROSS-COMPILER)g++ -o host_prog host_prog.o \$(AOCL_LINK_CONFIG)

host_prog.o : host_prog.cpp
	\$(CROSS-COMPILER)g++ -c host_prog.cpp \$(AOCL_COMPILE_CONFIG)


MAKEFILE_EXAMPLE_HELP_ARM_ONLY

my $makefile_help = <<MAKEFILE_EXAMPLE_HELP;

The following are example Makefile fragments for compiling and linking
a host program against the host runtime libraries included with the 
Intel(R) FPGA $sdk for OpenCL(TM).


Example GNU makefile on Linux, with GCC toolchain:

AOCL_COMPILE_CONFIG=\$(shell $prog compile-config)
AOCL_LINK_CONFIG=\$(shell $prog link-config)

host_prog : host_prog.o
	g++ -o host_prog host_prog.o \$(AOCL_LINK_CONFIG)

host_prog.o : host_prog.cpp
	g++ -c host_prog.cpp \$(AOCL_COMPILE_CONFIG)


Example GNU makefile on Windows, with Microsoft Visual C++ command line compiler:

AOCL_COMPILE_CONFIG=\$(shell $prog compile-config)
AOCL_LINK_CONFIG=\$(shell $prog link-config)

host_prog.exe : host_prog.obj
	link -nologo /OUT:host_prog.exe host_prog.obj \$(AOCL_LINK_CONFIG)

host_prog.obj : host_prog.cpp
	cl /MD /Fohost_prog.obj -c host_prog.cpp \$(AOCL_COMPILE_CONFIG)


MAKEFILE_EXAMPLE_HELP

   my %_help_topics = (

     'example-makefile', ($target_arm ? $makefile_help_arm : $makefile_help . $makefile_help_arm),

     'compile-config', <<COMPILE_CONFIG_HELP,

$prog compile-config - Show compilation flags for host programs


Usage: $prog compile-config


Example use in a GNU makefile on Linux:

   AOCL_COMPILE_CONFIG=\$(shell $prog compile-config)
   host_prog.o :
   	g++ -c host_prog.cpp \$(AOCL_COMPILE_CONFIG)

See also: $prog example-makefile

COMPILE_CONFIG_HELP


      'link-config', <<LINK_CONFIG_HELP,

$prog link-config - Show linker flags and libraries for host programs.


Usage: $prog link-config [options]

   By default the link line for the current platform are shown.


Description:

   This subcommand shows the linker flags and the list of libraries
   required to link a host program with the runtime libraries provided
   by the Intel(R) FPGA $sdk for OpenCL(TM).

   This subcommand combines the functions of the "ldflags" and "ldlibs"
   subcommands.

$loader_advice

Options:
$host_compiler_options

LINK_CONFIG_HELP


      'ldflags', <<LDFLAGS_HELP,

$prog ldflags - Show linker flags for building a host program.


Usage: $prog ldflags [options]

   By default the linker flags for the current platform are shown.


Description:

   This subcommand shows the general linker flags required to link 
   your host program with the runtime libraries provied by the 
   Intel(R) FPGA $sdk for OpenCL(TM).

   Your link line also must include the runtime libraries from the Intel(R) FPGA
   $sdk for OpenCL(TM) as listed by the "ldlibs" subcommand.

$loader_advice

Options:
$host_compiler_options

LDFLAGS_HELP


      'ldlibs', <<LDLIBS_HELP,

$prog ldlibs - Show list of runtime libraries for building a host program.


Usage: $prog ldlibs [options]

   By default the libraries for the current platform are shown.


Description:

   This subcommand shows the list of libraries provided by the 
   Intel(R) FPGA $sdk for OpenCL(TM) that are required link a host program.

   Your link line also must include the linker flags as listed by 
   the "ldlfags" subcommand.

$loader_advice

Options:
$host_compiler_options

LDLIBS_HELP

      'program', <<BOARD_PROGRAM_HELP,

$prog program - Configures a new FPGA design onto your board


Usage: $prog program <device_name> <file.aocx>

   Supply the .aocx file for the design you wish to configure onto 
   the FPGA.  You need to provide <device_name> to specify the FPGA 
   device to configure with. 

Description:

   This command downloads a new design onto your FPGA.
   This utility should not normally be used, users should instead use 
   clCreateProgramWithBinary to configure the FPGA with the .aocx file.

BOARD_PROGRAM_HELP

      'flash', <<BOARD_FLASH_HELP,

$prog flash - Initialize the FPGA with a specific startup configuration.


Usage: $prog flash <device_name> <file.aocx>

   Supply the .aocx file for the design you wish to set as the default
   configuration which is loaded on power up.

Description:

   This command initializes the board with a default configuration
   that is loaded onto the FPGA on power up.  Not all boards will 
   support this, check with your board vendor documentation.

BOARD_FLASH_HELP

      'diagnose', <<BOARD_DIAGNOSTIC_HELP,

$prog diagnose - Run your board vendor's test program for the board.


Usage: $prog diagnose
       $prog diagnose <device_name_1> [<device_name_2> ... ]
       $prog diagnose all

Description:

   This command executes a board vendor test utility to verify the 
   functionality of the device specified by <device-names>.  

   If <device-names> is not specified, it will show a list of currently 
   installed devices that are supported by all the installed board packages.

   The utility should output the text DIAGNOSTIC_PASSED as the final 
   line of output.  If this is not the case (either that text is absent, 
   the test displays DIAGNOSTIC_FAILED, or the test doesn't terminate),
   then there may be a problem with the board.


BOARD_DIAGNOSTIC_HELP

      'list-devices', <<BOARD_LIST_HELP,

$prog list-devices -  Lists all installed devices currently installed devices
                      that are supported by all the installed board packages.


Usage: $prog list-devices

Description:

   This command lists all the currently installed devices that are supported
   by the installed board packages.

BOARD_LIST_HELP

      'install', <<BOARD_INSTALL_HELP,

$prog install -  Installs a board onto your host system.


Usage: $prog install
       $prog install <path>

Description:

   This command installs a board's drivers and other necessary
   software for the host operating system to communicate with the
   board. For example this might install PCIe drivers. 

BOARD_INSTALL_HELP

      'uninstall', <<BOARD_UNINSTALL_HELP,

$prog uninstall -  Installs a board onto your host system.


Usage: $prog uninstall
       $prog uninstall <path>

Description:

   This command uninstalls a board's drivers and other necessary
   software for the host operating system to communicate with the
   board. For example this might uninstall PCIe drivers.

BOARD_UNINSTALL_HELP

      'report', <<PROFILE_REPORT_HELP,

$prog report - Parse the profiled aocx, source, and mon file and
               display the profiler GUI.


Usage: $prog report <file.aocx> <profile.mon> [file.source]

Description:

   Supply the .aocx file for the design that was profiled and
   the generated .mon file from the host execution. It is
   assumed that --profile was enabled when generating the
   .aocx file (see aoc options for information on --profile).

   The .source file is an optional argument, but is necessary if
   you wish to view the source code of the profiled application
   annotated with profiling information. The .source file contains
   the source code of the profiled application and is generated
   when then --profile flag is used when invoking the aoc compiler.

PROFILE_REPORT_HELP

      'env', <<ENV_HELP,

$prog env - Show the compilation environment of a binary.


Usage: $prog env <file.aoco/aocx>

Description:

   This command takes the aoco or aocx file provided and displays
   the compiler's input arguments and environment for that design.

ENV_HELP

      help => <<GENERAL_HELP,

$prog - Intel(R) FPGA $sdk_first_mention for OpenCL(TM) utility command.


$aoc_note

Subcommands for building your host program:

   $prog example-makefile  Show Makefile fragments for compiling and linking
                          a host program.
   $prog makefile          Same as the "example-makefile" subcommand.

   $prog compile-config    Show the flags for compiling your host program.
   $prog link-config       Show the flags for linking your host program with the
                          runtime libraries provided by the Intel(R) FPGA $sdk for OpenCL(TM).
                          This combines the function of the "ldflags" and "ldlibs"
                          subcomands.
   $prog linkflags         Same as the "link-config" subcommand.

   $prog ldflags           Show the linker flags used to link your host program
                          to the host runtime libraries provided by the Intel(R) FPGA $sdk
                          for OpenCL(TM).  This does not list the libraries themselves.

   $prog ldlibs            Show the list of host runtime libraries provided by the 
                          Intel(R) FPGA $sdk for OpenCL(TM).

Subcommands for managing an FPGA board:

   $prog program           Configure a new FPGA image onto the board.  

   $prog flash             [If supported] Initialize the FPGA with a specified
                          startup configuration.

   $prog install           Install your board into the current host system.

   $prog uninstall         Uninstall your board from the current host system.

   $prog diagnose          Run your board vendor's test program for the board.

   $prog list-devices      Lists all installed devices.

General:

   $prog report            Parse the profile data and display GUI.
   $prog library           Manage OpenCL(TM) libraries. Run "$prog library help" for more info.
   $prog env               Show the compilation environment of a binary
   $prog version           Show version information.
   $prog help              Show this help.
   $prog help <subcommand> Show help for a particular subcommand.
 
GENERAL_HELP
   );

   $_help_topics{'linkflags'} = $_help_topics{'link-config'};
   $_help_topics{'linkflags'} =~ s/link-config/linkflags/g;

   $_help_topics{'cflags'} = $_help_topics{'compile-config'};
   $_help_topics{'cflags'} =~ s/compile-config/cflags/g;

   $_help_topics{'makefile'} = $_help_topics{'example-makefile'};

   if ( defined $topic ) {
      my $output = $_help_topics{$topic};
      if ( defined $output ) { print $output; }
      else { print $_help_topics{'help'}; return undef; }
   } else {
      print $_help_topics{'help'};
   }
   return $self;
}

1;
