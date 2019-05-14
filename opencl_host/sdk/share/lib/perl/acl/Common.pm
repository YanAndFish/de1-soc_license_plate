=pod

=head1 NAME

acl::Common - Common utility functions and constants for aoc and acl perl libs

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

package acl::Common;
require Exporter;
use strict;
use acl::Env;
use acl::Board_env;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw ( is_fcd_present remove_fcd setup_fcd is_installed_present save_to_installed 
                      remove_from_installed populate_installed_packages populate_boards list_boards);

our @EXPORT = qw( $installed_bsp_list_dir $installed_bsp_list_file @installed_packages 
                  $installed_bsp_list_registry %board_boarddir_map);

# case:492127 need to explicitly exclude aoc options starting with -l
# from being considered a library name.
@acl::Common::l_opts_exclude = ('-list-deps', '-list-boards',
                                '-llc-arg', '-library-debug');

our $installed_bsp_list_dir = (defined $ENV{AOCL_INSTALLED_PACKAGES_ROOT}) ? $ENV{AOCL_INSTALLED_PACKAGES_ROOT} : '/opt/Intel/OpenCL';
$installed_bsp_list_dir =~ s/\/$//; # Remove the potential trailing backslash.
our $installed_bsp_list_file = $installed_bsp_list_dir."/installed_packages";
our @installed_packages = ();
our %board_boarddir_map = ();

my $installed_bsp_list_file_marker = $installed_bsp_list_dir."/.inst_pkg_busy.marker";
# Windows will use registry for tracking installed bsps unless custom location was provided through AOCL_INSTALLED_PACKAGES_ROOT
# In that case, file-based system will be used just as in Linux
my $custom_installed_bsp_list_location = defined $ENV{AOCL_INSTALLED_PACKAGES_ROOT};
our $installed_bsp_list_registry = 'HKEY_LOCAL_MACHINE\Software\Intel\OpenCL\installed_packages';


# global variables
my $orig_dir = undef;    # absolute path of original working directory.
my $time_log_fh = undef; # Time various stages of the flow; if not undef, it is a 
                         # file handle (could be STDOUT) to which the output is printed to.
my $pkg_file = undef;
my $src_pkg_file = undef;

# verbosity and temporary files controls
my $verbose = 0; # Note: there are two verbosity levels now 1 and 2
my $quiet_mode = 0; # No messages printed if quiet mode is on
my $save_temps = 0;


# Local Functions

# Creates a marker file so other processes will know a file is busy 
# This doesn't really lock a file, just creates a marker
sub _create_busy_marker($){
   if (acl::Env::is_linux() || $custom_installed_bsp_list_location) {
      my ($marker_file) = @_;
      if (-e $marker_file) {
         return 0;
      } else {
         # Create the marker file
         my @cmd = acl::Env::is_windows() ? ("type nul > $marker_file"):("touch", "$marker_file");
         system(@cmd);
         return 1;
      }
   }
}

# Removes the marker file, indicating the file is no more busy.
sub _remove_busy_marker($){
   if (acl::Env::is_linux() || $custom_installed_bsp_list_location) {
      my ($marker_file) = @_;
      return (unlink $marker_file);
   }
}

# Exported Functions

# Check if file exists on Linux
# Chech if registry exists on Windows unless AOCL_INSTALLED_PACKAGES_ROOT is provided
sub is_installed_present() {
   if (acl::Env::is_linux() || $custom_installed_bsp_list_location) {
      if (!(-e $installed_bsp_list_dir and -d $installed_bsp_list_dir)) {
         return 0;
      }

      if (-e $installed_bsp_list_file and -f $installed_bsp_list_file) {
        return 1;
      } else {
        return 0;
      }
   } elsif (acl::Env::is_windows()) {
      my $output = `reg query $installed_bsp_list_registry 2>&1`;
      if ($output !~ "^ERROR") {
        return 1;
      } else {
        return 0;
      }
   } else {
      return 0;
   }
}

# Save the given board package path to storage file
# Write to the file on Linux
# Add value to the registry on Windows unless AOCL_INSTALLED_PACKAGES_ROOT is provided
sub save_to_installed {
   my $board_package_path = shift;
   my @lines = undef;
   my $is_present = 0;

   if (!is_installed_present()) {
      if (acl::Env::is_linux() || $custom_installed_bsp_list_location) {
         if (!(-e $installed_bsp_list_dir and -d $installed_bsp_list_dir)) {
            acl::File::make_path($installed_bsp_list_dir) or die "Unable to create  directory $installed_bsp_list_dir\n";
         }
         unless(open FILE, '>'.$installed_bsp_list_file) {
            die "Unable to create $installed_bsp_list_file\n";
         }
         # Use the marker file to avoid mulitple tools accessing $installed_bsp_list_file
         _create_busy_marker($installed_bsp_list_file_marker) or die "Unable to lock $installed_bsp_list_file\n";
         print FILE "$board_package_path\n";
         # Remove the marker, so other processes will know access is open for $installed_bsp_list_file
         _remove_busy_marker($installed_bsp_list_file_marker);
         close FILE;
      }
   }
   
   if (acl::Env::is_linux() || $custom_installed_bsp_list_location) {
      # read all the installed packages
      unless(open FILE, '<'.$installed_bsp_list_file) {
        die "Unable to open $installed_bsp_list_file\n";
      }
      _create_busy_marker($installed_bsp_list_file_marker) or die "Unable to lock $installed_bsp_list_file\n";
      @lines = <FILE>;
      chomp(@lines);
      _remove_busy_marker($installed_bsp_list_file_marker) or die "Unable to unlock $installed_bsp_list_file\n";
      close FILE;
   
      # write all the installed packages back to storage except for 
      unless(open FILE, '>'.$installed_bsp_list_file) {
        die "Unable to open $installed_bsp_list_file\n";
      }
      _create_busy_marker($installed_bsp_list_file_marker) or die "Unable to lock $installed_bsp_list_file\n";
      foreach my $line (@lines) {
        print FILE "$line\n";
        if ($line eq $board_package_path) {
          $is_present = 1;
        }
      }
      if (!$is_present) {
        print FILE "$board_package_path\n";
      }
      _remove_busy_marker($installed_bsp_list_file_marker) or die "Unable to unlock $installed_bsp_list_file\n";
      close FILE;
    } elsif (acl::Env::is_windows()) {
         # Replace forward slashes with back slashes:
         $board_package_path =~ s/\//\\/g;
       
         #Adds the registry entry.
         #/v $board_package_path to specify a value name (in this case, the name of the value is the path to the dll)
         #/t REG_DWORD to specify the value type
         #/d 0000 for the value data
         #/f to force overwrite in case the value already exists
         system ("reg add $installed_bsp_list_registry /v $board_package_path /f") == 0 or print "Unable to edit registry entry\n" and return;
    }
   
}

# Remove the given board package path from storage file on Linux
# Remove the given board package path from the registry on Windows unless AOCL_INSTALLED_PACKAGES_ROOT is provided
sub remove_from_installed {
   my $board_package_path = shift;
   my @lines = undef;

   if (!is_installed_present()) {
     return;
   }
   if (acl::Env::is_linux() || $custom_installed_bsp_list_location) {
      # read all the installed packages
      unless(open FILE, '<'.$installed_bsp_list_file) {
        die "Unable to open $installed_bsp_list_file\n";
      }
      _create_busy_marker($installed_bsp_list_file_marker) or die "Unable to lock $installed_bsp_list_file\n";
      @lines = <FILE>;
      chomp(@lines);
      _remove_busy_marker($installed_bsp_list_file_marker) or die "Unable to unlock $installed_bsp_list_file\n";
      close FILE;
   
      # write all the installed packages back to storage except for 
      # the one that has been uninstalled
      unless(open FILE, '>'.$installed_bsp_list_file) {
        die "Unable to open $installed_bsp_list_file\n";
      }
      _create_busy_marker($installed_bsp_list_file_marker) or die "Unable to lock $installed_bsp_list_file\n";
      foreach my $line (@lines) {
        print FILE "$line\n" unless ($line eq $board_package_path);
      }

      _remove_busy_marker($installed_bsp_list_file_marker) or die "Unable to unlock $installed_bsp_list_file\n";
      close FILE;
   } elsif (acl::Env::is_windows()) {
      # Replace forward slashes with back slashes:
       $board_package_path =~ s/\//\\/g;
  
       #Remove the registry entry.
       system ("reg delete  $installed_bsp_list_registry /v $board_package_path /f") == 0 or print "Unable to delete registry entry\n" and return;
     }
}   


sub setup_fcd {
   my $generic_error_message = "Unable to set up FCD. Please contact your board vendor or see section \"Linking Your Host Application to the Khronos ICD Loader Library\" of the Programming Guide for instructions on manual setup.\n";
   
   my $acl_board_path = acl::Board_env::get_board_path();
   my $mmdlib = acl::Board_env::get_mmdlib_if_exists();
   
   if(not defined $mmdlib) {
      print "Warning: 'mmdlib' is not defined in $acl_board_path/board_env.xml.\n$generic_error_message";
      return;
   }
   
   #split the paths out based on the comma separator, then insert the acl board path in place of '%b':
   my @lib_paths = split(/,/, $mmdlib);
   my $board_path_indicator = '%b';
   s/$board_path_indicator/$acl_board_path/ for @lib_paths;
   
   if (acl::Env::is_linux()) {
      #create the target path (if it doesn't exist) and move there:
      my @target_path = ('opt', 'Intel', 'OpenCL', 'Boards');
      chdir "/"; #start at the root
      my $full_dir = ""; #used for giving a sensible error message
      #build the target path:
      for my $dir (@target_path) {
         $full_dir = $full_dir . "/" . $dir;
         if(!(-d $dir)) {
            mkdir $dir or die "Couldn't create directory '$full_dir'\nERROR: $!\n$generic_error_message";
         }
         chdir $dir;
      }
      
      #now print the paths to the .fcd file:
      my $board_env_name = acl::Board_env::get_board_name();
      my $fcd_list_path = "$board_env_name.fcd";
      
      open(my $filehandle, ">", $fcd_list_path) or die "Couldn't open '$full_dir/$fcd_list_path' for output\n$generic_error_message";
      for my $lib_path (@lib_paths) {
         print $filehandle $lib_path . "\n";
      }
      close $filehandle;
      
   } elsif (acl::Env::is_windows()) {
      my $reg_key = 'HKEY_LOCAL_MACHINE\Software\Intel\OpenCL\Boards';
      
      #Add the library paths:
      for my $lib_path (@lib_paths) {
         
         # Replace forward slashes with back slashes:
         $lib_path =~ s/\//\\/g;
         
         if($lib_path) {
            #Adds the registry entry.
            #/v $lib_path to specify a value name (in this case, the name of the value is the path to the dll)
            #/t REG_DWORD to specify the value type
            #/d 0000 for the value data
            #/f to force overwrite in case the value already exists
            system ("reg add $reg_key /v $lib_path /t REG_DWORD /d 0000 /f") == 0 or die "Unable to edit registry entry\n$generic_error_message";
         }
      }
   } else {
      die "No FCD setup procedure defined for OS '$^O'.\n$generic_error_message";
      return;
   }
}

sub remove_fcd {
   my $acl_board_path = acl::Board_env::get_board_path();
   my $mmdlib = acl::Board_env::get_mmdlib_if_exists();
   if(not defined $mmdlib) {
      print "Warning: 'mmdlib' is not defined in $acl_board_path/board_env.xml.\n";
      return;
   }
   
   #split the paths out based on the comma separator, then insert the acl board path in place of '%b':
   my @lib_paths = split(/,/, $mmdlib);
   my $board_path_indicator = '%b';
   s/$board_path_indicator/$acl_board_path/ for @lib_paths;
   
   if (acl::Env::is_linux()){
      #The FCD directory
      my $full_dir = "/opt/Intel/OpenCL/Boards";
      #now remove the .fcd file:
      my $board_env_name = acl::Board_env::get_board_name();
      my $fcd_path = "$full_dir/$board_env_name.fcd";
      
      unlink $fcd_path or print "Cannot remove FCD file '$fcd_path': The file does not exist or is not accessible.\n";
      
   } elsif (acl::Env::is_windows()) {
      my $reg_key = 'HKEY_LOCAL_MACHINE\Software\Intel\OpenCL\Boards';
      
      #Add the library paths:
      foreach my $lib_path (@lib_paths){
         
         # Replace forward slashes with back slashes:
         $lib_path =~ s/\//\\/g;
         
         if($lib_path) {
            #Remove the registry entry.
            #/v $lib_path to specify a value name (in this case, the name of the value is the path to the dll)
            #/f to force remove, isntead of prompting for [y/n]
            system ("reg delete $reg_key /v $lib_path /f") == 0 or print "Unable to remove registry entry $reg_key\\$lib_path";
         }
      }
   } else {
      print "No FCD uninstall procedure defined for OS '$^O'.\n";
      return;
   }
}

# This "tries" to find if fcd is installed. Note that ACL_BOARD_VENDOR_PATH workaournd will not be detected by this
sub is_fcd_present {
   if (acl::Env::is_linux()) {
      my @fcd_files = acl::File::simple_glob("/opt/Intel/OpenCL/Boards/*.fcd");
   if ($#fcd_files >= 0) {
        return 1;
      } else {
        return 0;
      }
   } elsif (acl::Env::is_windows()) {
      my $reg_key = 'HKEY_LOCAL_MACHINE\Software\Intel\OpenCL\Boards';
      my $output = `reg query $reg_key 2>&1`;
      if ($output !~ "^ERROR") {
        return 1;
      } else {
        return 0;
      }
   } else {
      return 0;
   }
}

# Read the installed packages storage file on Linux
# Read the installed packages registry on Windows unless AOCL_INSTALLED_PACKAGES_ROOT is provided
sub populate_installed_packages {

   if (!is_installed_present()) {
     return;
   }

   if (acl::Env::is_linux() || $custom_installed_bsp_list_location) {
      # read all the installed packages
      unless(open FILE, '<'.$installed_bsp_list_file) {
        die "Unable to open $installed_bsp_list_file\n";
      }
      @installed_packages = <FILE>;
      chomp(@installed_packages);
      close FILE;
   } elsif (acl::Env::is_windows()) {
        my $output = `reg query  $installed_bsp_list_registry /s 2>&1`;
        if ($output !~ "^ERROR") {
           @installed_packages =  split /\n/, $output;
           shift @installed_packages;
           shift @installed_packages;
           # Parse the output of reg query
           foreach my $bsp (@installed_packages) {
              $bsp =~ s/^\s+//;
              $bsp = (split /\s+/, $bsp)[0];
           }
        }
    }
}

sub populate_boards {
  populate_installed_packages();

  # if not bsps installed, use AOCL_BOARD_PACKAGE_ROOT
  if  ($#installed_packages < 0) {
    my $default_bsp = acl::Board_env::get_board_path();
    push @installed_packages, $default_bsp;
  }

  foreach my $bsp (@installed_packages) {
    $ENV{'AOCL_BOARD_PACKAGE_ROOT'} = $bsp;
    my %boards = acl::Env::board_hw_list();
    for my $b ( sort keys %boards ) {
      my $boarddir = $boards{$b};
      $board_boarddir_map{"$b;$bsp"} = $boarddir;
    }
  }
}

# List installed boards.
sub list_boards {
  populate_boards();

  print "Board list:\n";

  if( keys( %board_boarddir_map ) == -1 ) {
    print "  none found\n";
  } else {
      for my $b ( sort keys %board_boarddir_map ) {
      my $boarddir = $board_boarddir_map{$b};
      my ($name,$bsp) = split(';',$b);
      print "  $name\n";
      print "     Board Package: $bsp\n";
      if ( ::acl::Env::aocl_boardspec( $boarddir, "numglobalmems") > 1 ) {
        my $gmemnames = ::acl::Env::aocl_boardspec( $boarddir, "globalmemnames");
        print "     Memories:      $gmemnames\n";
      }
      my $channames = ::acl::Env::aocl_boardspec( $boarddir, "channelnames");
      if ( length $channames > 0 ) {
        print "     Channels:      $channames\n";
      }
      print "\n";
    }
  }
}

# system utilities:
# set and get original directory
# set package file and source packge file names
# set and get verbose, quiet mode and save temps
# mydie
# move_to_log
sub set_original_dir($) {
  $orig_dir = shift;
  return $orig_dir;
}

sub get_original_dir {
  return $orig_dir;
}

sub set_package_file_name($) {
  $pkg_file = shift;
  return $pkg_file;
}

sub set_source_package_file_name($) {
  $src_pkg_file = shift;
  return $src_pkg_file;
}

sub set_verbose($) {
  $verbose = shift;
}

sub get_verbose {
  return $verbose;
}

sub set_quiet_mode($) {
  $quiet_mode = shift;
}

sub get_quiet_mode {
  return $quiet_mode;
}

sub set_save_temps($) {
  $save_temps = shift;
}

sub get_save_temps {
  return $save_temps;
}

sub mydie(@) {
  # consider updating this API to pass in $pkg_file and $src_pkg_file instead of keeping a global variable here
  print STDERR "Error: ".join("\n",@_)."\n";
  chdir $orig_dir if defined $orig_dir;
  unlink $pkg_file;
  unlink $src_pkg_file;
  exit 1;
}

sub move_to_log { #string, filename ..., logfile
  my $string = shift @_;
  my $logfile= pop @_;
  open(LOG, ">>$logfile") or mydie("Couldn't open $logfile for appending.");
  print LOG $string."\n" if ($string && ($verbose > 1 || $save_temps));
  foreach my $infile (@_) {
    open(TMP, "<$infile") or mydie("Couldn't open $infile for reading.");;
    while(my $l = <TMP>) {
      print LOG $l;
    }
    close TMP;
    unlink $infile;
  }
  close LOG;
}

# Functions to execute external commands, with various wrapper capabilities:
#   1. Logging
#   2. Time measurement
# Arguments:
#   @_[0] = { 
#       'stdout' => 'filename',   # optional
#       'stderr' => 'filename',   # optional
#       'time' => 0|1,            # optional
#       'time-label' => 'string'  # optional
#     }
#   @_[1..$#@_] = arguments of command to execute
sub mysystem_full($@) {
  my $opts = shift(@_);
  my @cmd = @_;

  my $out = $opts->{'stdout'};
  my $err = $opts->{'stderr'};

  if ($verbose >= 2) {
    print join(' ',@cmd)."\n";
  }

  # Replace STDOUT/STDERR as requested.
  # Save the original handles.
  if($out) {
    open(OLD_STDOUT, ">&STDOUT") or mydie "Couldn't open STDOUT: $!";
    open(STDOUT, ">$out") or mydie "Couldn't redirect STDOUT to $out: $!";
    $| = 1;
  }
  if($err) {
    open(OLD_STDERR, ">&STDERR") or mydie "Couldn't open STDERR: $!";
    open(STDERR, ">$err") or mydie "Couldn't redirect STDERR to $err: $!";
    select(STDERR);
    $| = 1;
    select(STDOUT);
  }

  # Run the command.
  my $start_time = time();
  system(@cmd);
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
  if ($time_log_fh && $opts->{'time'}) {
  # if ($time_log_filename && $opts->{'time'}) {
    my $time_label = $opts->{'time-label'};
    if (!$time_label) {
      # Just use the command as the label.
      $time_label = join(' ',@cmd);
    }

    log_time ($time_label, $end_time - $start_time);
  }
  return $?
}

# time log utilties
sub open_time_log($$) {
  my $time_log_filename = shift;
  my $run_quartus = shift;

    my $fh;
    if ($time_log_filename ne "-") {
      # If this is an initial run, clobber time_log_filename, otherwise append to it.
      if (not $run_quartus) {
        open ($fh, '>', $time_log_filename) or mydie ("Couldn't open $time_log_filename for time output.");
      } else {
        open ($fh, '>>', $time_log_filename) or mydie ("Couldn't open $time_log_filename for time output.");
      }
    }
    else {
      # Use STDOUT.
      open ($fh, '>&', \*STDOUT) or mydie ("Couldn't open stdout for time output.");
    }

    # From this point forward, $time_log_fh holds the file handle!
    $time_log_fh = $fh;
}

sub close_time_log {
  if ($time_log_fh) {
    close ($time_log_fh);
  }
}

sub write_time_log($) {
  my $s = shift;
  print $time_log_fh $s;
}

sub log_time($$) {
  my ($label, $time) = @_;
  if ($time_log_fh) {
    printf ($time_log_fh "[time] %s ran in %ds\n", $label, $time);
  }
}

1;
