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


=cut

package acl::File;
require Exporter;
@ISA        = qw(Exporter);
@EXPORT     = ();
@EXPORT_OK  = qw(
   file_slashes
   dir_slashes

   file_backslashes
   dir_backslashes

   make_path_to_file
   make_path

   copy_tree
   copy

   remove_tree

   make_writable

   grep_file
   which

   mktemp

   is_empty_dir
);

use strict;

my $module = 'acl::File';
my $temp_count = 0;
sub log_string(@) { }  # Dummy

# Control the number of warnings printed during remove_tree.
$acl::File::max_warnings = 10;

=head1 NAME

acl::File - File handling utilities

=head1 VERSION

$Header: //acds/rel/18.1/acl/sysgen/lib/acl/File.pm#1 $

=head1 SYNOPSIS

   use acl::File qw(make_path_to_file file_slashes);

   my $file = file_slashes( 'c:\tmp\my\own\file' );
   make_path_to_file( $file )
      or die "Can't make path to file $file";
   open FILE, ">$file";
   print FILE "ha!\n";
   close FILE;

   print "The first sh.exe on the path is: ",
         acl::File::find_on_path('sh.exe',$ENV{'PATH'},"\n";


=head1 DESCRIPTION

This module provides general file handling utilities.

By convention, we use forward slashes (B</>) for the path separator.
To convert among slash styles, use
C<file_slashes>, C<dir_slashes>,
C<file_backslashes>, and C<dir_backslashes>.

This module will eventually grow to include other methods, beginning
with C<make_path_to_file>.

All methods names may optionally be imported, e.g.:

   use acl::File qw( file_slashes dir_slashes );

=head1 METHODS

=head2 file_slashes($filename)

Return the given $filename, changing all backslashes
to forward slashes.  Remove any trailing slashes (of either direction).

=cut

sub file_slashes {
   my ($file) = @_;
   return $file unless $file;  # Catch no-arg error, being silent.

   $file =~ s/\\/\//g;  # Convert backslash to forward slash
   $file =~ s/\/+$//;   # Remove trailing slashes
   return $file;
}

=head2 dir_slashes($dirname)

Return the given $dirname, changing all backslashes
to forward slashes.  Ensure that there is a single trailing slash.

=cut

sub dir_slashes {
   my ($dir) = @_;
   return $dir unless $dir;  # Catch no-arg error, being silent.

   return file_slashes($dir)."/";
}

=head2 file_backslashes($filename)

Do the same as C<file_slashes($filename)>, except the result has
backslashes instead of forward slashes.

=cut

sub file_backslashes {
   my ($file) = @_;
   return $file unless $file;  # Catch no-arg error, being silent.

   my $new_name = file_slashes($file);
   $new_name =~ s/\//\\/g;
   return $new_name;
}

=head2 dir_backslashes($filename)

Do the same as C<dir_slashes($filename)>, except the result has
backslashes instead of forward slashes.

=cut

sub dir_backslashes {
   my ($dir) = @_;
   return $dir unless $dir;  # Catch no-arg error, being silent.

   my $new_name = dir_slashes($dir);
   $new_name =~ s/\//\\/g;
   return $new_name;
}

=head2 make_path_to_file($filename,[$mode])

Ensure that the directories leading up to C<$filename> exist.

Return true if the alreay directory exists or we were able to
make the directory exist.  Return false otherwise, and set
C<$acl::File::error> to the error string.

If you want to make just a plain directory, then append "/.", for example:

   $dir = 'c:/tmp';
   make_path_to_file($dir.'/.');

If supplied, C<$mode> is used as the permissions settings when
making new directories.

Note: This piggybacks on module C<File::Path>, which
is available in even fairly old Perl distributions.  If that module
is missing, then we'll just have to hand code an alternative.
We also have the side effect of calling C<File::Basename::fileparse_set_fstype>
to C<UNIX>, so beware.

=cut

$acl::File::error = undef;

# Avoid requiring File::Path;
# Assume Unix style name.
sub mydirname($) {
   my ($filename) = shift;
   if ( $filename =~ s'/[^/]*$'' ) {
      return $filename.'/';
   } else {
      return "./";
   }
}
# Avoid requiring File::Basename
sub mybasename($) {
   my ($filename) = shift;
   $filename = file_slashes($filename);
   if ( $filename =~ m'/.' ) { $filename =~ s'.*/''; }
   return $filename;
}

sub make_path_to_file {
   my ($file,$mode) = file_slashes(@_);

   $acl::File::error = undef;
   unless ( $file ) {
      $acl::File::error = "No filename argument supplied to $module"."::make_path_to_file";
      return 0;
   }

   my $dir = mydirname($file);

   my @dir_parts = split(m'/',$dir);
   my @so_far = ();
   foreach my $part ( @dir_parts ) {
      push @so_far, $part;
      my $cur_dir = join('/',@so_far);
      if ( $cur_dir ) {
         unless ( -d $cur_dir || mkdir $cur_dir ) {
            $acl::File::error = "Can't make directory $cur_dir: $!";
            return 0;
         }
      }
   }

   return -d $dir;
}

=head2 make_path($dirname,[$mode])

Make a directory path, including its parents.  This is just like C<mkdir -p>
on the Unix command line.
(It's also similar to C<acl::File::make_path_to_file($dirname."/foo")>.

The optional C<$mode> argument is used to set permissions on newly created
directories.  See L<"make_path_to_file($filename,[$mode])">.

=cut

sub make_path {
   my ($dirname,$mode) = dir_slashes(@_);

   $acl::File::error = undef;
   unless ( $dirname ) {
      $acl::File::error = "No directory argument supplied to $module"."::make_path_to_file";
      return 0;
   }

   unless ( -d $dirname ) {
      return make_path_to_file($dirname."/foo");
   }
   return -d $dirname;
}

=head2 simple_glob($pattern)

=cut

# Work around lack of File::Glob in the Quartus embedded Perl.
# glob() automatically requires File::Glob
sub simple_glob($@) {
   my ($arg,$options) = @_;
   #print "simple_glob: <<$arg\n";
   $arg = file_slashes($arg);
   my $dir = mydirname($arg);
   my $pattern = mybasename($arg);

   #print "dir = $dir\n";
   #print "pat = $pattern\n";

   # Do simple remap to Perl regexp.
   $pattern =~ s/\./\\./g; # Convert explicit dots first
   $pattern =~ s/\*/.*/g;
   $pattern =~ s/\?/./g;

   opendir(DIR,$dir);
   my (@candidates) = (readdir(DIR));
   closedir DIR;
   # Skip dotfiles, including curdir and parent dir, unless 'all' option is provided.
   unless ( ${$options}{'all'} ) {
      @candidates = (grep { ! /^\./ } @candidates);
   }
   my @result = map { $dir.$_ } (grep { m/^$pattern$/ } @candidates);
   #print "simple_globl:>>".join(" ",@result)."\n";
   return @result;
}

=head2 copy($src_file,$dest_file)

=cut

sub copy($$@) {
   my ($src_file,$dest_file,$options) = @_;
   $src_file = file_slashes($src_file);
   $dest_file = file_slashes($dest_file);

   if ( $$options{'verbose'} ) {
      print "Copying $src_file -> $dest_file\n";
   }
   unless ( make_path_to_file( $dest_file ) ) {
      return 0;
   }
   unless ( open( IN,"<$src_file") ) {
      $acl::File::error = "Can't open $src_file for read: $!";
      return 0;
   }
   unlink $dest_file if -e $dest_file;
   unless ( open( OUT,">$dest_file" ) ) {
      $acl::File::error = "Can't open $dest_file for write: $!";
      return 0;
   }
   binmode IN;
   binmode OUT;
   unless ( print OUT <IN> ) {
      $acl::File::error = "Can't copy data from $src_file to $dest_file: $!";
      return 0;
   }
   close OUT;
   close IN;
   return 1;
}

=head2 copy_tree($src,$dest)

=cut

sub copy_tree($$@) {
   my ($src,$dest_root,$options) = @_;
   $src = file_slashes($src);
   $dest_root = dir_slashes($dest_root);

   my $srcroot = mydirname($src);
   my $srcrootlen = length($srcroot);
   my @src_files = simple_glob($src);
   foreach my $src_file ( @src_files ) {
      if ( -f $src_file ) {
         my $dest_file = $dest_root.substr($src_file,$srcrootlen);
         if ( ${$options}{'dry_run'} ) {
            print "$src_file -> $dest_file\n";
         } else {
            my $ok = acl::File::copy($src_file,$dest_file,$options);
            return 0 if !$ok;
         }
      } elsif ( -d $src_file ) {
         if (opendir DIR,$src_file ) {
            my (@new_files) = map { $src_file."/$_" } (grep { ! /^\./ } readdir(DIR));
            push @src_files, @new_files;
            closedir DIR;
         } else {
            $acl::File::error = "Can't open directory $src_file for read: $!";
            return 0;
         }
      }
   }
   return 1;
}

=head2 remove_tree($file_or_dir)

=cut

sub remove_tree($@) {
   my ($path,$options) = @_;
   $options = {} unless defined $options;

   my $dry_run = ${$options}{'dry_run'};
   my $verbose = ${$options}{'verbose'};

   if ( -f $path ) {
      print "remove $path\n" if $verbose;
      unless ( $dry_run ) {
         unless ( unlink $path ) {
            $acl::File::error = "Can't remove file $path: $!";
            return 0;
         }
      }
   } elsif ( -d $path ) {
      my @subfiles = simple_glob("$path/*", { all => 1 } );
      foreach my $subfile ( @subfiles ) {
         my $base = mybasename($subfile);
         next if $base eq '.' or $base eq '..';
         unless( remove_tree($subfile,$options) ) {
            $acl::File::error = "Can't remove file $subfile: $!";
            return 0;
         }
      }
      print "remove dir $path\n" if $verbose;
      unless ( $dry_run ) {
         unless ( rmdir $path ) {
            $acl::File::error = "Can't remove directory $path: $!";
            return 0;
         }
      }
   }
   return 1;
}

=head2 make_writable($filename)

=cut

sub make_writable($) {
   my ($file) = shift;
   my $mode = (stat $file)[2];
   my $new_mode = $mode | 0400;
   chmod $mode, $file;
}

=head2 grep_file($file,$match)

=cut

sub grep_file($@) {
  my ($file,$match, $caseinsensitive) = @_;
  my @result;
  unless ( open( IN,"<$file") ) {
    $acl::File::error = "Can't open $file for read: $!";
    return 0;
  }
  LINE: while(my $l = <IN>) {
    if ( $caseinsensitive ) {
      if ( $l =~ m/$match/i ) {
        push (@result,$l);
        next LINE;
      }
    } else {
      if ( $l =~ $match ) {
        push (@result,$l);
        next LINE;
      }
    }
  }
  return @result;
}

=head2 which()

=cut

# Replicate "which $cmd" for a specific directory
# If $cmd is exectuable in the given directory, then return the full path.
# Otherwise return undef;
sub which ($$) {
   my ($dir,$cmd) = @_;

   # Linux case, and if cmd already includes its extension.
   return "$dir/$cmd" if -x "$dir/$cmd";

   if ( $^O =~ m/MSWin/ ) {
      # Windows case.
      foreach my $ext ( split(/;/,$ENV{'PATHEXT'}||'') ) {
         # -x handles case differences already.
         my $candidate = "$dir/$cmd$ext";
         return $candidate if -x $candidate;
      }
   }

   return undef;
}

=head2 which_full()

=cut

# Just like 'which' in Linux -- searches all directories in PATH for given cmd
sub which_full ($) {
   my ($cmd) = @_;
   my $path_sep;
   if ( $^O =~ m/MSWin/ ) {
      $path_sep = ";";
   } else {
      $path_sep = ":";
   }
   my $found = undef;
   foreach my $dir ( split(/$path_sep/,$ENV{'PATH'}||'') ) {
       # calling two-argument which with current dir
       $found = which ($dir, $cmd);
       if (defined $found) {
          return $found;
       }
    }
    # not found
    return undef;
}

=head2 mktemp()

=cut

sub mktemp {
  my $temp="";

  if ( $^O =~ m/Win/ ) {
    #Windows
    if ( defined $ENV{TEMP} ) {
      $temp = $ENV{TEMP};
    } elsif ( defined $ENV{TMP} ) {
      $temp = $ENV{TMP};
    } else {
      return "";
    }
  } else {
    #Linux
    if ( defined $ENV{TMPDIR} ) {
      $temp = $ENV{TMPDIR};
    } else {
      $temp = "/tmp";
    }
  }
  # Pseudo Uniqification - is there a cross platform mktemp, or can't we
  # just ship File::Temp?
  my ( $package, $filename, $line ) = caller(1);
  $filename = mybasename($filename);
  $filename =~ s/\.//g;
  my $seconds = time();
  $temp .= "/$$"."$filename$line"."_$seconds"."_$temp_count";
  $temp_count = $temp_count + 1;
  return $temp;
}

=head2 abs_path($filename)

Would really love to just use Cwd::abs_path. But we hack it instead.

=cut

sub abs_path($) {
   # Return absolute path form of argument, in slashes form.
   # Return undef if we failed in any way.
   my $path = shift;

   # Make canonical
   # And strip trailing slashes
   $path = file_slashes($path);
   if ( $^O =~ m/Win/ ) {
      # Handle something like "c:foobar"
      # While still having "c:" become "c:/"
      if ( $path =~ m'^([a-z]:)([^/]+)$' ) { $path = "$1./$2"; }
   }
   unless ( -d $path ) {
      if ( $path =~ m'(.*)/([^/]+)$' ) {
         my ($dir,$file) = ($1,$2);
         if ($dir) {
            my $subresult = abs_path($dir);
            if ( defined $subresult ) {
               my $result = "$subresult/$file";
               $result =~ s'/+'/'g;
               return $result;
            } else {
               return undef;
            }
         } else {
            # It's already absolute
            return $path;
         }
      } else {
         # No slashes at all
         return abs_path("./$path");
      }
   }

   if ( $^O =~ m/Win/ ) {
      require Cwd;
      if ( $path =~ m/^[a-z]:$/i ) { $path .= '/' };
      my $dir = Cwd::abs_path($path);
      if ( $dir =~ m/([a-z]:)(.*)/i ) {
         if ( $2 ) { return file_slashes(lcfirst($1.$2)); }
         else { return lcfirst($1).'/'; }
      }
   } else {
      # Cheesy, and doesn't check result of cd or pwd.
      my @output = `cd "$path" ; pwd`;
      my $the_dir = $output[$#output];
      chomp $the_dir;
      return file_slashes($the_dir) if $the_dir;
   }
   return undef;
}

=head2 is_empty_dir($dirname)

=cut

sub is_empty_dir($) {
  my $dirname = shift;

  if (! -d $dirname) {
    return 0;
  }

  opendir(my $fh, $dirname);
  while (my $child_entry = readdir($fh)) {
    if ($child_entry ne '.' and $child_entry ne '..') {
      # At least one entry inside the directory so it's not empty.
      closedir($fh);
      return 0;
    }
  }
  closedir($fh);

  return 1;
}

sub _testbench() {
   # A little test bench.
   # It takes a while to run on Windows because abs_path spawns an external process.

   my $ok = 1;
   my %tb = qw( abc abc /tmp/foo foo bar/bz bz bz/* * bx* bx* );
   while ( my($key,$val) = each %tb ) {
      $ok = $ok && ( mybasename( $key ) eq $val );
   }

   foreach my $d ( qw( x ./x ../x /x . ), $$ ) {
      my $ap = abs_path( $d );
      $ok = $ok && ( $ap =~ m '/' );  # Always have slash
      $ok = $ok && ( ($ap =~ m'^[a-z]:/$') || ($ap !~ m '/$') ); # Trailing slash only if drive lettero only.
      $ok = $ok && ( $ap !~ m '/\.\.?/' ); # Never relative directory
   }

   return $ok;
}

1;
