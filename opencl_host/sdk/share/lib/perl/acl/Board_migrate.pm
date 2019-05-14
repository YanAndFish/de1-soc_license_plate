=pod

=head1 NAME

acl::Board_migrate - Utility to migrate platforms

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

package acl::Board_migrate;
require Exporter;
use strict;
use acl::Env;
use acl::File;

my $rpt = "automigration.rpt";

# Any successfully applied patch shoud display this:
my $success_string = "Successfully Implemented";

# Everything here assumes present working directory is in the Quartus project of the design

sub get_platform($@) {
  my ($type) = @_;

  if ( $type eq "s5_net" ) {
    return ( name     => "s5_net", 
             host     => "PCIe", 
             pgm      => "CvP", 
             flow     => "persona",
             family   => "STRATIX V",
           );
  } elsif ( $type eq "cvpqxp_13.x" ) {
      return ( name     => "cvpqxp_13.x", 
        host     => "PCIe", 
        pgm      => "CvP", 
        flow     => "qxp",
        family   => "STRATIX V",
      );
  } elsif ( $type eq "c5soc" ) {
      return ( name     => "c5soc", 
        host     => "ARM32", 
        pgm      => "ARM", 
        flow     => "unpreserved",
        family   => "CYCLONE V",
      );
  } elsif ( $type eq "a5soc" ) {
      return ( name     => "a5soc", 
        host     => "ARM32", 
        pgm      => "ARM", 
        flow     => "unpreserved",
        family   => "ARRIA V",
      );
  } elsif ( $type eq "a10_ref" ) {
      return ( name     => "a10_ref", 
        host     => "PCIe", 
        pgm      => "Partial Reconfiguration", 
        flow     => "QHD - Partial Reconfiguration",
        family   => "ARRIA 10",
      );
  } elsif ( $type eq "s10_ref" ) {
      return ( name     => "s10_ref",
        host     => "PCIe",
        pgm      => "Partial Reconfiguration",
        flow     => "QHD - Partial Reconfiguration",
        family   => "STRATIX 10",
      );
  } elsif ( $type eq "a10soc" ) {
      return ( name     => "a10soc",
        host     => "ARM32",
        pgm      => "Partial Reconfiguration",
        flow     => "QHD - Partial Reconfiguration",
        family   => "ARRIA 10",
      );
  } elsif ( $type eq "sil_jtag" ) {
      return ( name     => "sil_jtag", 
        host     => "JTAG", 
        pgm      => "JTAG", 
        flow     => "unpreserved",
        family   => "any",
      );
  } elsif ( $type eq "sil_pcie" ) {
      return ( name     => "sil_pcie", 
        host     => "PCIe", 
        pgm      => "JTAG", 
        flow     => "unpreserved",
        family   => "any",
      );
  }
  print "Warning: Unknown platform type: $type\n";
  return undef;
}

sub detect_platform {

  ####  Get FPGA Family ###
  my @lines = get_qsf_setting("top.qsf", "FAMILY");
  if ( 1 != scalar @lines ) {
    print "Warning: Expected 1 FAMILY assignment in top.qsf\n";
    return undef;
  }
  my $family = uc $lines[0];

  ####  Get Quartus Version last compiled in ###
  @lines = get_qsf_setting("top.qsf", "LAST_QUARTUS_VERSION");
  if ( 1 != scalar @lines ) {
    print "Warning found none or too many LAST_QUARTUS_VERSION settings in top.qsf\n";
    return undef;
  }
  my $last_quartus_version = $lines[0];

  if ( 13.0 > $last_quartus_version )
  {
    print "Warning unexpected value ($last_quartus_version) for setting LAST_QUARTUS_VERSION in top.qsf\n";
    return undef;
  }

  ####  Detect if an SoC design ####
  my $is_soc = 0;
  my @qsysfiles = (acl::File::simple_glob("*.qsys"),
                   acl::File::simple_glob("iface/*.qsys"));
  foreach my $q (@qsysfiles) {
    $is_soc = 1 if acl::File::grep_file($q, "altera_hps", 0);
  }    

  my %platform;

  if ( -e "base.qsf" and -e "persona/base.root_partition.personax" and $family eq "STRATIX V") {
    return get_platform( "s5_net" );
  } elsif ( -e "acl_iface_partition.qxp" and $family eq "STRATIX V" ) {
    return get_platform( "cvpqxp_13.x" );
  } elsif ( $is_soc and $family eq "CYCLONE V" ) {
      return get_platform( "c5soc" );
  } elsif ( $is_soc and $family eq "ARRIA V" ) {
      return get_platform( "a5soc" );
  } else {
    return undef;
  }
  $platform{last_quartus_version} = $last_quartus_version;
  $platform{qsf_family} = $family;
  return %platform;
}

# Really shouldn't recreate qsf parsing, but instead should use tcl API
# But this will take a while to load tcl, load project, etc.  
sub get_qsf_setting($@) {
  my ($qsf, $setting ) = @_;
  my @lines = acl::File::grep_file( $qsf, $setting , 1);

  my @result;
  foreach my $l (@lines) {
    my $val = $l;
    $val =~ s/set_global_assignment //;
    $val =~ s/-name //;
    $val =~ s/$setting//;
    $val =~ s/\"//g;
    $val =~ s/^\s+//g;
    $val =~ s/\s+$//g;
    chomp($val);
    push (@result, $val);
  }
  return @result;
}

sub runtclmigration($@) {
  my $name = shift;
  my $rpt = shift;
  my $title = shift;
  my $args = '';
  if( scalar @_ ) {
    $args =  join " ", @_;
  }
  my $tcl = acl::File::abs_path("$ENV{INTELFPGAOCLSDKROOT}/ip/board/migrate/$name/$name.tcl");
  die "Migration Tcl script $tcl not found\n" unless -e $tcl;
  open( OUT,">>$rpt");
  print OUT "-------- $title (name: $name) ----------\n";
  close OUT;

  system("quartus_sh -t $tcl $args >>$rpt 2>&1");
  my $success = ($? != 0) ? 0 : 1;

  open( OUT,">>$rpt");
  print OUT "$success_string\n" if $success;
  print OUT "------------------------------\n\n";
  close OUT;
  return 1;
}

####################################################
# Perform the migration
####################################################
sub pre_migrate {
  my $flow_name = shift(@_);
  my $version = ::acl::Env::aocl_boardspec( ".", "version");
  my $automigrate_type = ::acl::Env::aocl_boardspec( ".", "automigrate_type".$flow_name);
  my $board = ::acl::Env::aocl_boardspec( ".", "name");

  my %platform;
  if ( $automigrate_type eq "auto" ) {
    %platform = detect_platform();
  } elsif ( $automigrate_type eq "none" ) {
    %platform = ();
  } else {
    %platform = get_platform($automigrate_type);
  }
 return ($version, $automigrate_type, $board, \%platform);
}

sub filter_excludes {
  my ($automigrate_exclude, $fix_ref) = @_;
  my @fixes = @$fix_ref;
  my @list_excludes = split(',', $automigrate_exclude);

  my @filtered_fixes;
  foreach my $f (@fixes) {
    my $found = scalar grep( /$f/, @list_excludes);
    push(@filtered_fixes, $f) if ( ! $found );
  }

  return @filtered_fixes;
}

sub get_pr_base_id {
  my ($base_id_file) = shift @_;
  open( my $pr_id_file, "<", $base_id_file ) or return -1;
  my $id;
  while( my $row = <$pr_id_file> ) {
    chomp $row;
    $id = $row;
  }
  return $id;
}

sub migrate_platform_postcompile {
  return if( ! -e "board_spec.xml" );
  my $flow_name = shift(@_);
  my $add_migrations = shift(@_);
  my $remove_migrations = shift(@_);
  my ($version, $automigrate_type, $board, $platform_ref) = pre_migrate($flow_name);
  my %platform = %$platform_ref;
  $platform{version} = $version;
  unless ( defined $platform{name} ) {
    print "Warning: Unknown platform type, no auto migration performed\n";
    return;
  }
  unless ( open( OUT,">>$rpt") ) {
    $acl::File::error = "Can't open $rpt for writing: $!";
    return;
  }
  print OUT "Post-Compile Automigration Report\n";

  my @fixes;
  my $automigrate_include = ::acl::Env::aocl_boardspec( ".", "automigrate_include".$flow_name);
  my $automigrate_exclude = ::acl::Env::aocl_boardspec( ".", "automigrate_exclude".$flow_name);
  @fixes = split(',', $automigrate_include);
  push @fixes, split(',', $add_migrations);
  if ( $platform{name} eq 'a10_ref' and $platform{version} >= 17.0 ) {
    $platform{pr_base_id} = get_pr_base_id( "pr_base.id" );
    push(@fixes, "post_skipbak");
  }

  if ( $platform{name} eq 'a10soc' and $platform{version} >= 17.0 ) {
    $platform{pr_base_id} = get_pr_base_id( "pr_base.id" );
    push(@fixes, "post_skipbak");
  }

  my @old_filtered_fixes = filter_excludes($automigrate_exclude, \@fixes);
  my @filtered_fixes = filter_excludes($remove_migrations, \@old_filtered_fixes);
  print OUT "----------- Fixes To Apply ---------\n";
  if ( scalar @filtered_fixes > 0 ) {
    foreach my $fix (@filtered_fixes) {
      print OUT "| $fix\n"
    }
  } else {
    print OUT "| none\n"
  }
  print OUT "------------------------------------\n\n";
  close OUT;
  process_fixes( \@filtered_fixes, \%platform, $board );
}

sub migrate_platform_preqsys {

  return if ( ! -e "board_spec.xml" );
  my $flow_name = shift(@_);
  # automigrations added from aoc
  my $add_migrations = shift(@_);
  my $remove_migrations = shift(@_);
  my ($version, $automigrate_type, $board, $platform_ref) = pre_migrate($flow_name);
  my %platform = %$platform_ref;
  unless ( defined $platform{name} ) {
    print "Warning: Unknown platform type, no auto migration performed\n";
    return;
  }

  $platform{version} = $version;

  unless ( open( OUT,">$rpt") ) {
    $acl::File::error = "Can't open $rpt for writing: $!";
    return;
  }

  print OUT "OpenCL Auto Migration Report\n\n";
  print OUT "To disable auto migration compile with flag: --no-auto-migrate\n\n";
  print OUT "Alternatively, you can enable/disable individual fixes\n";
  print OUT "by adding them to the include/exclude field in board_spec.xml.\n\n";

  print OUT "----------- Platform ---------\n";
  print OUT "| Board $board with auto migration type $automigrate_type and \n";
  print OUT "| board_spec version $version has the following properties:\n";
  print OUT "|   $_ = $platform{$_}\n" for (sort keys %platform);
  print OUT "------------------------------\n\n";

  my @fixes;

  my $automigrate_include = ::acl::Env::aocl_boardspec( ".", "automigrate_include".$flow_name);

  @fixes = split(',', $automigrate_include);
  push  @fixes, split(',', $add_migrations);
  if ( $platform{pgm} eq 'CvP' and $platform{flow} eq 'persona' and $version < 14.1 ) {
    push (@fixes, "cvphrcfix");
    push (@fixes, "cvpdanglinginputs");
  }
  if ( $platform{host} eq 'PCIe' and $version < 14.0 ) {
    push (@fixes, "pciemaximum");
  }
  if ( $platform{pgm} eq 'CvP' and $version < 14.1 ) {
    push (@fixes, "cvpenable");
  }

  if ( $platform{flow} eq 'persona' and $version < 14.1 ) {
    push (@fixes, "peripheryhash");
  }
 
  if ( $platform{name} eq 'a10_ref' ) { 
    my $quartus_output = `quartus_sh --version`;
    (my $quartus_version) = $quartus_output =~ /Version (.*?) /s;

    # a10_ref 15.1 and 16.0 BSPs are not forward compatible with newer ACDS versions
    if ( ($platform{version} eq 15.1 and $quartus_version >= 16.0) ||
         ($platform{version} eq 16.0 and $quartus_version >= 16.1) ) {
      my $error_string = "Error: The A10 BSP being used is from Quartus $platform{version} and cannot be used with this version of Quartus ($quartus_version)!\n";
      print OUT "$error_string\n";
      print $error_string;
      exit 1; 
    }

    # a10_ref 16.0 BSP should only use kernel clock generator and temperature in SDK
    # checking for potential local copies and in that case erroring out
    if ( $platform{version} >= 16.0 ) {

      if ( -e "ip/acl_kernel_clk_a10/acl_kernel_clk_a10.qsys" ) {
        my $error_string = "Error: local copy of kernel clock generator found in the BSP!\nError: this IP should have been removed from the BSP by the vendor when migrating a 15.1 BSP to a newer release!\n";
        print OUT "$error_string\n";
        print $error_string;
        exit 1;
      }

      if ( -e "ip/acl_temperature_a10/acl_temperature_a10_hw.tcl" ) {
        my $error_string = "Error: local copy of temperature sensor found in the BSP!\nError: this IP should have been removed from the BSP by the vendor when migrating a 15.1 BSP to a newer release!\n";
        print OUT "$error_string\n";
        print $error_string;
        exit 1;
      }

    }

    if( $platform{version} >= 17.0 ) {
      $platform{pr_base_id} = get_pr_base_id( "pr_base.id" );
      push(@fixes, "pre_skipbak");
    }

    if( $platform{version} eq 17.0 ) {
      push(@fixes, "vpr_route_m20k_lim_fanout_limit");
    }

  }

  if ( $platform{name} eq 'a10soc' and $platform{version} >= 17.0 ) {
    $platform{pr_base_id} = get_pr_base_id( "pr_base.id" );
    push(@fixes, "pre_skipbak");
  }

  my $automigrate_exclude = ::acl::Env::aocl_boardspec( ".", "automigrate_exclude".$flow_name);
  my @filtered_fixes = filter_excludes($automigrate_exclude, \@fixes);
  @filtered_fixes = filter_excludes($remove_migrations, \@filtered_fixes);
  if ( length $automigrate_include > 0 and length $automigrate_include > 0 ) {
    print OUT "----------- Inclusions/Exclusions ---------\n";
    print OUT "| Inclusions from board_spec.xml: $automigrate_include\n";
    print OUT "| Exclusions from board_spec.xml: $automigrate_exclude\n";
    print OUT "-------------------------------------------\n\n";
  }
  print OUT "----------- Fixes To Apply ---------\n";
  if ( scalar @filtered_fixes > 0 ) {
    foreach my $fix (@filtered_fixes) {
      print OUT "| $fix\n"
    }
  } else {
    print OUT "| none\n"
  }
  print OUT "------------------------------------\n\n";
  close OUT;

  process_fixes( \@filtered_fixes, \%platform, $board );
}

sub process_fixes($@) {
  my ($fix_ref, $platform_ref, $board) = @_;
  my @fixes = @$fix_ref;

  foreach my $fix (@fixes) {

    #### FIX: CVP update HRC fix - assume fix was localized
    if ( $fix eq "cvphrcfix" ) {
      my $targetdir = "scripts/cvpupdatefix";
      open( OUT,">>$rpt");
      print OUT "-------- CvP HRC Fix (name: cvphrcfix) ----------\n";
      if ( -d $targetdir ) {
        acl::File::copy_tree( $ENV{"INTELFPGAOCLSDKROOT"}."/ip/board/migrate/cvpupdatefix/*", $targetdir);

        print OUT "Replaced files in $targetdir\n";
        print OUT "$success_string\n";
      } else {
        print OUT "Error: Auto migration expected to find directory $targetdir \n";
      }
      print OUT "-------------------------------------------------\n\n";
      close OUT;
    }

    #### FIX: PCIe removed Maximum setting for credit allocation
    if ( $fix eq "pciemaximum" ) {
      runtclmigration("pciemaximum",$rpt,"PCIe Maximum RX Credit Allocation");
    }

    #### FIX: Enable CvP support despite it being deprecated
    if ( $fix eq "cvpenable" ) {
      runtclmigration("cvpenable",$rpt,"CvP Enable");
    }

    #### FIX: Dangling inputs handling in 14.1 breaks 14.0 personas (232736)
    if ( $fix eq "cvpdanglinginputs" ) {
      open( OUT,">>$rpt");
      print OUT "-------- Periphy Hash Fix (name: peripheryhash) ----------\n";
      if ( open( INI,">>quartus.ini") ) {
        print INI "fitcc_disable_dangling_cvp_input_wireluts=on\n";
        close INI;
        print OUT "$success_string\n"; 
      } else {
        print OUT "Failed to open quartus.ini for write append\n"; 
      }
      print OUT "----------------------------------------------------------\n\n";
      close OUT;
    }
    
    #### FIX: Disable periphery hash gating CvP
    if ( $fix eq "peripheryhash" ) {
      open( OUT,">>$rpt");
      print OUT "-------- Periphy Hash Fix (name: peripheryhash) ----------\n";
      unlink "scripts/create_hash_hex.tcl";
      if ( acl::File::copy( $ENV{"INTELFPGAOCLSDKROOT"}."/ip/board/migrate/peripheryhash/create_hash_hex.tcl", "./scripts/create_hash_hex.tcl")) {
        print OUT "Replaced scripts/create_hash_hex.tcl\n";
        print OUT "$success_string\n"; 
      }else {
        print OUT "Error: Failed to replace scripts/create_hash_hex.tcl\n";
      }
      print OUT "----------------------------------------------------------\n\n";
      close OUT;
    }

    #### FIX: Add INI to enable BAK flow from 17.0 BSPs in 17.1
    if ( $fix eq "vpr_route_m20k_lim_fanout_limit" ) {
      open( OUT,">>$rpt");
      print OUT "-------- Fix 17.0 BSP static region in 17.1 (name: vpr_route_m20k_lim_fanout_limit) ----------\n";
      if ( open( INI,">>quartus.ini") ) {
        print INI "vpr_route_m20k_lim_fanout_limit=-1\n";
        close INI;
        print OUT "$success_string\n"; 
      } else {
        print OUT "Failed to open quartus.ini for write append\n"; 
      }
      print OUT "----------------------------------------------------------\n\n";
      close OUT;
    }

    if ( $fix eq "pre_skipbak" ) {
      runtclmigration("pre_skipbak", $rpt, "Skipping BAK flow - Copy-Over", $platform_ref->{name}, $board, $platform_ref->{pr_base_id});
    }

    if ( $fix eq "post_skipbak" ) {
      runtclmigration("post_skipbak", $rpt, "Skipping BAK flow - Copy-Back", $platform_ref->{name}, $board, $platform_ref->{pr_base_id});
    }
  }
}
