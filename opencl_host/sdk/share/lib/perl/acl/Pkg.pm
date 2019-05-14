
=pod

=head1 NAME

acl::Pkg - Manage package files for ACL

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



=head1 SYNOPSIS

   use acl::Pkg;

   # Create an empty package file, or empty an existing one.
   my $pkg = create acl::Pkg('foo.acl')
      or die "Can't create pkg file foo.acl: $acl::Pkg::error\n";
   my $pkg = get acl::Pkg('foo.acl');
      or die "Can't find pkg file foo.acl: $acl::Pkg::error\n";

   # Operating on a package file.

   # Add named section, contents from file.  
   # Fails and returns undef if the section exists.
   $pkg->add_file('source','foo.cl');     

   # Update named section, contents from file.
   # Fails and returns undef if the section does not exist.
   $pkg->update_file('source','boo.cl');

   # Set contents of named section from file.
   # Works whether or not the section already exists.
   $pkg->set_file('source','boo.cl');

   # Write contents of named section to file.
   $pkg->get_file('source','destination.cl');

=cut

package acl::Pkg;
require Exporter;
@acl::Pkg::ISA        = qw(Exporter);
@acl::Pkg::EXPORT     = ();
@acl::Pkg::EXPORT_OK  = qw();
use strict;

require acl::Env;
our $AUTOLOAD;

$acl::Pkg::error = undef;

sub get($$) {
   my ($proto,$file) = @_;
   unless ($file) { $acl::Pkg::error = "File argument required"; return undef; }
   unless ( -f $file && -r $file ) {
      $acl::Pkg::error = "Invalid package file $file: $!";
      return undef;
   }
   return bless( { file => $file, (verbose => $ENV{'ACL_PKG_VERBOSE'}||0) }, (ref($proto)||$proto));
}


sub create($$) {
   my ($proto,$file) = @_;
   unless ($file) { $acl::Pkg::error = "File argument is missing"; return undef; }
   system(acl::Env::sdk_pkg_editor_exe(),$file,'create');
   return bless( {file=>$file, (verbose => $ENV{'ACL_PKG_VERBOSE'}||0)}, (ref($proto)||$proto) ) if $? == 0;
   $acl::Pkg::error = "'pkg_editor $file create' failed";
   return undef;
}

sub pkg_editor_args($) {
   my $self = shift;
   my @parts = (acl::Env::sdk_pkg_editor_exe());
   push(@parts, "-v") if $self->verbose;
   return @parts;
}

sub add_file($$$$) {
   my ($self,$section,$data_file) = @_;
   unless ( $section ) { $acl::Pkg::error = "Section argument is missing"; return undef; }
   unless ( $data_file ) { $acl::Pkg::error = "Data file argument is missing"; return undef; }
   system($self->pkg_editor_args(),$self->file,'add',$section,$data_file);
   return $self if $? == 0;
   $acl::Pkg::error = "'pkg_editor $data_file add $section $data_file' failed";
   return undef;
}

sub update_file($$$$) {
   my ($self,$section,$data_file) = @_;
   unless ( $section ) { $acl::Pkg::error = "Section argument is missing"; return undef; }
   unless ( $data_file ) { $acl::Pkg::error = "Data file argument is missing"; return undef; }
   system($self->pkg_editor_args(),$self->file,'update',$section,$data_file);
   return $self if $? == 0;
   $acl::Pkg::error = "'pkg_editor $data_file update $section $data_file' failed";
   return undef;
}

sub set_file($$$$) {
   my ($self,$section,$data_file) = @_;
   unless ( $section ) { $acl::Pkg::error = "Section argument is missing"; return undef; }
   unless ( $data_file ) { $acl::Pkg::error = "Data file argument is missing"; return undef; }
   system($self->pkg_editor_args(),$self->file,'set',$section,$data_file);
   return $self if $? == 0;
   $acl::Pkg::error = "'pkg_editor $data_file set $section $data_file' failed";
   return undef;
}

sub get_file($$$$) {
   my ($self,$section,$data_file) = @_;
   unless ( $section ) { $acl::Pkg::error = "Section argument is missing"; return undef; }
   unless ( $data_file ) { $acl::Pkg::error = "Data file argument is missing"; return undef; }
   system($self->pkg_editor_args(),$self->file,'get',$section,$data_file);
   return $self if $? == 0;
   $acl::Pkg::error = "'pkg_editor $data_file get $section $data_file' failed";
   return undef;
}

sub exists_section($$$$) {
   my ($self,$section) = @_;
   unless ( $section ) { $acl::Pkg::error = "Section argument is missing"; return undef; }
   system($self->pkg_editor_args(),$self->file,'exists',$section);
   return 0==$?;
}

sub section_sizes($) {
   # Return a list of pairs: section name and size in bytes
   my ($self) = @_;
   my $cmd = join(" ", 
      map { my $str = $_; (( $str =~ m/\s/ ) ? "\"$str\"" : $str); } 
         ( $self->pkg_editor_args(), $self->file,"list" ) );
   my @captured = qx/$cmd/;
   my @result = ();
   if ( 0==$? ) { 
      foreach my $line (@captured) {
         push @result, $1, $2 if $line =~ m/^  (\S+), (\d+) bytes/;
      }
      return @result;
   }
   $acl::Pkg::error = "Failed to list sections in file $self"; 
   return undef;
}

sub print($$) {
   my ($self,$section) = @_;
   unless ( $section ) { $acl::Pkg::error = "Section argument is missing"; return undef; }
   system($self->pkg_editor_args(),$self->file,'print',$section);
   return 0==$?;
}

sub package($$@) {
   my $self = shift;
   my $filename = shift;
   unless ($filename) { $acl::Pkg::error = "Output filename argument is missing"; return undef; }
   system($self->pkg_editor_args(),$filename,'package',@_);
   return 0==$?;
}

sub AUTOLOAD {
   my $self = shift;
   my $class = ref($self) or die "$self is not an object";
   my $name = $AUTOLOAD;

   $name =~ s/^.*:://;

   if (@_) {
      return $self->{$name} = shift;
   } else {
      return $self->{$name};
   }
}

1;
