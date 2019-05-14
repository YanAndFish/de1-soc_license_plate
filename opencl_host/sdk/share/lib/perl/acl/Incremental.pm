=pod

=head1 NAME

acl::Incremental - Utility for incremental compile flows

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

package acl::Incremental;
require Exporter;
use strict;
use acl::Common;
use acl::File;
use acl::Report qw(escape_string);

$acl::Incremental::warning = undef;

my $warning_prefix = "Compiler Warning: Incremental Compilation:";
my $warning_suffix = "Performing full recompilation.\n";

# Check if full incremental recompile is necessary
sub requires_full_recompile($$$$$$$$$$$$) {
  $acl::Incremental::warning = undef;

  my ($input_dir, $work_dir, $base, $all_aoc_args, $board_name, $board_variant, $devicemodel,
      $devicefamily, $quartus_version, $program, $aclversion, $bnum) = @_;
  my $acl_version       = "$aclversion Build $bnum";
  my $qdb_dir = $input_dir eq "$work_dir/prev" ? "$work_dir/qdb" : "$input_dir/qdb";

  local $/ = undef;

  if (! -e "$input_dir/kernel_hdl") {
    $acl::Incremental::warning = "$warning_prefix change detection could not be completed because kernel_hdl ".
                                 "directory is missing in $input_dir. $warning_suffix";
    return 1;
  } elsif (! -e "$input_dir/$base.bc.xml") {
    $acl::Incremental::warning = "$warning_prefix change detection could not be completed because $base.bc.xml is ".
                                 "missing in $input_dir. $warning_suffix";
    return 1;
  } elsif (open(my $prev_info, "<$input_dir/reports/lib/json/info.json")) {
    my $info = <$prev_info>;
    close $prev_info;

    # Check project name
    my ($prev_proj_name) = $info =~ /Project Name.*?\[\"(.+?)\"\]/;
    if ($prev_proj_name ne escape_string($base)) {
      $acl::Incremental::warning = "$warning_prefix previous project name: $prev_proj_name differs ".
                                   "from current project name: ".escape_string($base).". $warning_suffix";
      return 1;
    }

    # Check target family, device, and board
    my ($prev_target_family, $prev_device, $prev_board_name) = $info =~ /Target Family, Device, Board.*?\[\"(.+?),\s+(.+?),\s+(.+?)\"\]/;
    if ($prev_target_family ne $devicefamily ||
        $prev_device ne $devicemodel ||
        $prev_board_name ne escape_string("$board_name:$board_variant")) {
      $acl::Incremental::warning = "$warning_prefix previous device information: $prev_target_family, $prev_device, $prev_board_name ".
                                   "differs from current device information: $devicefamily, $devicemodel, ".
                                   escape_string("$board_name:$board_variant").". $warning_suffix";
      return 1;
    }

    # Check ACDS version
    my ($prev_ACDS_version) = $info =~ /Quartus Version.*?\[\"(.+?)\"\]/;
    if ($prev_ACDS_version ne $quartus_version) {
      $acl::Incremental::warning = "$warning_prefix previous Quartus version: $prev_ACDS_version ".
                                   "differs from current Quartus version: $quartus_version. ".
                                   "$warning_suffix";
      return 1;
    }

    # Check AOC version
    my ($prev_AOC_version) = $info =~ /AOC Version.*?\[\"(.+?)\"\]/;
    if ($prev_AOC_version ne $acl_version) {
      $acl::Incremental::warning = "$warning_prefix previous AOC version: $prev_AOC_version differs from current ".
                                   "AOC version: $acl_version. $warning_suffix";
      return 1;
    }

    # Check command line flags
    $program =~ s/#//g;
    my ($prev_command) = $info =~ /Command.*?\[\"$program\s+(.+?)\s*\"\]/;
    my $prev_compile_rtl_only = index($prev_command, '-rtl') != -1;

    # Check if user deleted the qdb folder.
    if (!$prev_compile_rtl_only and ! -d $qdb_dir) {
      $acl::Incremental::warning = "$warning_prefix qdb directory missing in $work_dir. QDB files are required to perform ".
                                   "an incremental compilation. Files inside $work_dir should not be modified. $warning_suffix";
      return 1;
    } elsif (!$prev_compile_rtl_only and acl::File::is_empty_dir($qdb_dir)) {
      $acl::Incremental::warning = "$warning_prefix qdb directory in $work_dir is empty. QDB files are required to perform ".
                                   "an incremental compilation. Files inside $work_dir should not be modified. $warning_suffix";
      return 1;
    }

    my @prev_args = split(/\s+/, $prev_command);
    my @curr_args = split(/\s+/, escape_string($all_aoc_args));
    return 1 if (compare_command_line_flags(\@prev_args, \@curr_args));
  } else {
    $acl::Incremental::warning = "$warning_prefix change detection could not be completed because ".
                                 "$input_dir/reports/lib/json/info.json could not be opened. ".
                                 "$warning_suffix";
    return 1;
  }
  return 0;
}

# Check if important command line options/flags match.
# This check only needs to identify diffs in command line options/flags
# that won't be detected by other stages of change detection.
sub compare_command_line_flags($$) {
  my ($prev_args, $curr_args) = @_;

  my $index = 0;
  ++$index until $index == scalar @$prev_args || $prev_args->[$index] eq "-rtl";
  if ($index != scalar @$prev_args) {
    $index = 0;
    ++$index until $index == scalar @$curr_args || $curr_args->[$index] eq "-rtl";
    if ($index == scalar @$curr_args) {
      $acl::Incremental::warning = "$warning_prefix the previous compile was only run to the RTL stage. $warning_suffix";
      return 1;
    }
  }

  # incremental and incremental=aggressive are equivalent
  # when checking command line flags. The differences between the
  # two modes are handled in our full diff detection flow. Just need to check
  # that the previous compile ran one of the incremental modes.
  $index = 0;
  ++$index until $index == scalar @$prev_args || $prev_args->[$index] =~ /^(-)?-incremental(=aggressive)?$/;
  if ($index == scalar @$prev_args) {
    $acl::Incremental::warning = "$warning_prefix the previous compile was not an incremental compile. $warning_suffix";
    return 1;
  }

  my @ref = @$prev_args;
  my @cmp = @$curr_args;
  my $swapped = 0;
  my @libs = ();
  # Opt args are options with a mandatory argument.
  my @optargs_to_check = ('bsp-flow');
  while (scalar @ref) {
    my $arg  = shift @ref;

    # Check for matching library in both sets
    if ($arg =~ m!^-l(\S+)! || $arg eq '-l') {

      if ($arg =~ m!^-l(\S+)!) {
        # There are some aoc options that start with -l which are
        # detected as library filenames using the above regex
        # so need to skip checking those options.
        my $full_opt = '-l' . $1;
        foreach my $exclude_name (@acl::Common::l_opts_exclude) {
          if ($full_opt =~ m!^$exclude_name!) {
            goto END;
          }
        }
      }

      my $length = scalar @cmp;
      $index = 0;

      my $ref_lib = ($arg =~ m!^-l(\S+)!) ? $1 : shift @ref;
      my $cmp_lib = "";
      while ($index < $length) {
        ++$index until $index == $length || $cmp[$index] eq "-l" || $cmp[$index] =~ m!^-l(\S+)!;
        last if ($index == $length);
        $cmp_lib   = $cmp[$index+1]             if ($cmp[$index] eq "-l");
        ($cmp_lib) = $cmp[$index] =~ /^-l(\S+)/ if ($cmp[$index] =~ m/^-l\S+/);
        last if ($cmp_lib eq $ref_lib);
        ++$index;

      }

      if ($ref_lib ne $cmp_lib) {
        # Need to include the library name or else the warning will just say
        # '-l' flag is missing from one of the compiles which is not specific
        # enough.
        $arg .= " $ref_lib" if ($arg eq '-l');
        _add_differing_flag_warning($arg, $swapped);
        return 1;
      }

      push @libs, $ref_lib;
      splice(@cmp, $index, ($cmp[$index] eq '-l') ? 2 : 1);

    } else {
      # Check if important option/argument pairs match.
      foreach my $optarg (@optargs_to_check) {
        if ($arg eq "--$optarg" || $arg eq "-$optarg" || $arg =~ m!^-$optarg=(\S+)!) {
          my $full_arg = $arg;
          if ($arg eq "--$optarg" || $arg eq "-$optarg") {
            # Need to report the option name and the argument value
            # in the command line flag warning. $arg only contains
            # the option name.
            $full_arg .= " $ref[0]";
          }

          if (_compare_command_opt_arg($optarg, $arg, \@ref, \@cmp)) {
            _add_differing_flag_warning($full_arg, $swapped);
            return 1;
          }

          goto END;
        }
      }
    }

    # If we've checked all command line flags in @prev_args against @curr_args,
    # swap the arrays and check any left over command line flags in @curr_args
    END:
    if (! scalar @ref) {
      @ref = @cmp;
      @cmp = ();
      $swapped = 1;
    }
  }

  if (scalar @libs) {
    $acl::Incremental::warning .= "$warning_prefix the following libraries were used: " . join(', ', @libs) .
                                  ". Changes to libraries are not automatically detected in incremental compile.\n";
  }

  return 0;
}

# Get the previous project name
sub get_previous_project_name($) {
  $acl::Incremental::warning = undef;
  my ($json) = @_;
  my $info = _read_data_from_file($json);
  my ($prj_name) = $info =~ /Project Name.*?\[\"(.+?)\"\]/;
  $acl::Incremental::warning = "$warning_prefix the previous project name in $json is empty. $warning_suffix" if ($prj_name eq "");
  return $prj_name;
}

# Read in file
sub _read_data_from_file($) {
  my ($json) = @_;
  local $/=undef;
  open(my $data, "<$json") or return "";
  my $content = <$data>;
  close($data);
  return $content;
}

# Compare a command line option with an argument between @$rref and @$rcmp.
# (eg. compares command line options of the form '--option-name arg' or
# any equivalent form)
# Return 0 if the option/argument pair in @$rref also exists in @$rcmp or $opt is on
# the @$whitelist. Then remove the matching option/argument pair from @$rcmp.
# Return 1 if the option/argument pair differs between @$rref and @$rcmp.
sub _compare_command_opt_arg($$$$;$) {
  my ($opt_name, $opt, $rref, $rcmp, $whitelist) = @_;

  my $cmp_length = scalar @$rcmp;
  my $cmp_index = 0;

  my $ref_arg = ($opt =~ m!^-$opt_name=(\S+)!) ? $1 : shift @$rref;
  my $cmp_arg = undef;

  # Some options can be specified multiple times on the command line so we need to
  # compare all instances to find one with the same value.
  while ($cmp_index < $cmp_length) {
    # There are currently 3 equivalent formats an option/argument pair can be specified.
    # 1) --option-name arg
    # 2) -option-name arg
    # 3) -option-name=arg
    ++$cmp_index until $cmp_index == $cmp_length ||
                       $rcmp->[$cmp_index] eq "--$opt_name" ||
                       $rcmp->[$cmp_index] eq "-$opt_name" ||
                       $rcmp->[$cmp_index] =~ m!^-$opt_name=(\S+)!;

    # Did not find the same option argument pair in @$rcmp.
    last if ($cmp_index == $cmp_length);

    $cmp_arg = $rcmp->[$cmp_index+1] if ($rcmp->[$cmp_index] eq "--$opt_name" ||
                                         $rcmp->[$cmp_index] eq "-$opt_name");
    ($cmp_arg) = $rcmp->[$cmp_index] =~ /^-$opt_name=(\S+)/ if ($rcmp->[$cmp_index] =~ m/^-$opt_name=\S+/);

    # Found matching option/argument pair in @$rcmp.
    last if ($cmp_arg eq $ref_arg);
    ++$cmp_index;
  }

  my $on_whitelist = 0;
  if (defined $whitelist) {
    my @ref_arg_split = split(/\s/, $ref_arg);
    foreach my $whitelist_opt (@$whitelist) {
      # Some ref_arg on the whitelist may take their own argument values.
      # eg. --sysinteg-arg "--const-cache-bytes 32000" would have
      # ref_arg -> "--const-cache-bytes 32000". Strip out the internal argument
      # value before checking the whitelist
      if ($ref_arg_split[0] =~ /^$whitelist_opt$/) {
        $on_whitelist = 1;
        last;
      }
    }
  }

  return 1 if ($ref_arg ne $cmp_arg && !$on_whitelist);

  # Remove the matching option/argument pair from @$rcmp.
  my $num_to_splice = $rcmp->[$cmp_index] eq "-$opt_name" || $rcmp->[$cmp_index] eq "--$opt_name" ? 2 : 1;
  splice(@$rcmp, $cmp_index, $num_to_splice);

  return 0;
}

# Add a warning specifying the flag that differs between the current and previous compile.
sub _add_differing_flag_warning($$) {
  my ($arg, $swapped) = @_;
  my $curr = $swapped ? "current" : "previous";
  my $prev = $swapped ? "previous" : "current";

  $acl::Incremental::warning .= "$warning_prefix the $curr compile uses the command line " .
                                "flag $arg which is missing in the $prev compile. $warning_suffix";
}

1;
