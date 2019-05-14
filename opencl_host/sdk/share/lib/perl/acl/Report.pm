
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

package acl::Report;
require acl::Env;
require acl::File;
require acl::Common;
require Exporter;
require acl::ACL_JSON;
@ISA        = qw(Exporter);
@EXPORT     = ();
@EXPORT_OK  = qw(
    get_file_list_from_dependency_files
    escape_string
    copy_files
    create_json_file_or_print_to_report
    print_json_files_to_report
    get_source_file_info_for_visualizer
    create_pipeline_viewer
);

use strict;


my $module = 'acl::Report';

my $temp_count = 0;

my $need_MLABs = 1;

sub log_string(@) { }  # Dummy

=head1 NAME

acl::Report - Reporting utilities

=head1 VERSION

$Header: //acds/rel/18.1/acl/sysgen/lib/acl/Report.pm#1 $

=head1 SYNOPSIS


=head1 DESCRIPTION

This module provides utilities for the HLD Reports.

All methods names may optionally be imported, e.g.:

   use acl::Report qw( create_pipeline_viewer );

=head1 METHODS

=head2 escape_string($string, $escape_quotes_and_newline)

Given a $string, replace all control characters with their octal equivalent or
escape them appropriately.  Optionally escape quotes and newlines.

=cut 

sub escape_string {
  my $string = shift;
  my $escape_quotes_and_newline = @_ ? shift : 1;

  $string =~ s/(\\(?!n))|(\\(?!t))|(\\(?!f))|(\\(?!b))|(\\(?!r))|(\\(?!"))/\\\\/g;
  $string =~ s/(\012|\015\012|\015\015\012?)/\\012/g if $escape_quotes_and_newline;
  $string =~ s/\015/\\012/g if $escape_quotes_and_newline;
  $string =~ s/(?<!\\)\\n/\\\\n/g;
  $string =~ s/(?<!\\)\\t/\\\\t/g;
  $string =~ s/(?<!\\)\\f/\\\\f/g;
  $string =~ s/(?<!\\)\\b/\\\\b/g;
  $string =~ s/(?<!\\)\\r/\\\\r/g;
  $string =~ s/\"/\\"/g if $escape_quotes_and_newline;

  return $string;
}


=head2 copy_files($work_dir)

Copy all the reporting files to the reports directory.
Returns 1 on success, 0 on failure.

=cut 

sub copy_files {
  my $work_dir = shift;
  acl::File::copy_tree(acl::Env::sdk_root()."/share/lib/acl_report/lib", "$work_dir/reports");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/Report.htm", "$work_dir/reports/report.html");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/main.js", "$work_dir/reports/lib/main.js");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/main.css", "$work_dir/reports/lib/main.css");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/spv/graph.js", "$work_dir/reports/lib/graph.js");

  # Create directory for JSON files (used by SDK)
  my $json_dir = "$work_dir/reports/lib/json";
  acl::File::make_path($json_dir) or return 0;

  return 1; # success
}


=head2 create_json_file_or_print_to_report($report, $name, $JSON_string, \@json_files, $work_directory) 

Create a new JSON file called $name.json with the content in $JOSN_string, or print
$JSON_string directly to $report if for some reason we can't create the json file.
If the json file was created, push the $name to @json_files.
$work_directory is optional, and is used for HLS because we are working in a
subdirectory.

=cut 

sub create_json_file_or_print_to_report {
  my $report = shift;
  my $name = shift;
  my $JSON_string = shift;
  my $json_files = shift;
  my $work_directory = @_ ? shift : ".";

  # Try writing $JSON_string to file, or to $report if we can't write to file.
  if (open (my $JSONfile, '>', $work_directory.'/'.$name.".json")) {
    print $JSONfile $JSON_string;
    close $JSONfile;
    push @{$json_files}, $name;
  } else {
    print $report "var ".$name."JSON=$JSON_string;\n";
  }
}


=head2 print_json_files_to_report($report, \@json_files, $work_directory)

Print each of the json files listed in @json_files to the $report.
$work_directory is optional, and is used for HLS because we are working in a
subdirectory.

=cut 

sub print_json_files_to_report{
  my $report = shift;
  my $json_files = shift;
  my $work_directory = @_ ? shift : ".";

  foreach (@{$json_files}) {
    # if file does not exist, create empty variable
    (my $var_name = $_) =~ s/\./_/g;
    print $report "var ".$var_name."JSON='";
    if ( -e $work_directory.'/'.$_.'.json' ) {
      open (my $file, '<', $work_directory.'/'.$_.'.json') or print $report "{}";

      if (defined $file) {
        my $JSON = <$file>;
        # Remove whitespace at beginning of line, and then all remaining newlines and carriage returns
        $JSON =~ s/\n\s+//g;
        $JSON =~ s/\n//g;
        $JSON =~ s/\r//g;
        $JSON = escape_string($JSON, 0); # don't escape double quotes and new lines
        # Ensure all sigle quotes are properly escaped
        $JSON =~ s/(?<!\\)(?>\\\\)*'/\\'/g;
        print $report $JSON;
        close($file);
      }
      print $report "';\n";
    } else {
      print $report "{}';\n";
    }
  }
}


=head2 get_file_list_from_dependency_files($dep_file, ...)

Parse each $dep_file, returning a list of all unique files given in the
dependency files.

=cut 

sub get_file_list_from_dependency_files {
  my %filelist;
  for my $dependency_file (@_) {
    if( -f $dependency_file and open (my $fin, '<', $dependency_file) ) {
      foreach my $line (<$fin>) {
        # File/path may contain spaces and/or tabs.  Replace them with special
        # tokens, then swap back after splitting.
        $line =~ s/\\ /INTEL_FPGA_THERE_IS_A_SPACE_HERE/g;
        $line =~ s/(?!^)\011/INTEL_FPGA_THERE_IS_A_TAB_HERE/g;
        $line =~ s/\015/INTEL_FPGA_THERE_IS_A_CR_HERE/g;
        foreach my $file (split '\s', $line) {
          $file =~ s/INTEL_FPGA_THERE_IS_A_SPACE_HERE/ /g;
          $file =~ s/INTEL_FPGA_THERE_IS_A_TAB_HERE/\011/g;
          $file =~ s/INTEL_FPGA_THERE_IS_A_CR_HERE/\015/g;
          $filelist{$file} = 1 if -f $file;
        }
      }
      close($fin);
    }
  }
  return keys %filelist;
}


=head2 get_source_file_info_for_visualizer($filelist, $patterns_to_skip, $debug_symbols_enabled)

Given the $filelist, create the fileJSON object that contains the source code
of all files in $filelist.

Returns an empty string if debug symbols are disabled.

=cut 

sub get_source_file_info_for_visualizer {
  my $filelist = shift;
  my $patterns_to_skip = shift;
  my $debug_symbols_enabled = shift;
  local $/ = undef;

  return "" unless $debug_symbols_enabled;

  my $fileJSON = "var fileJSON=[";
  my $count = 0;
  my $filefullpath = ""; #include the path and name
  my $filepath = ""; #only path, no file name included
  my $filename = "";

  #create a hash with the key using file paths, and the value using file names
  my %map_fullpath_to_name;
FILELIST_LOOP:
  foreach $filefullpath (@{$filelist}) {
    for my $pattern (@{$patterns_to_skip}) {
      if ($filefullpath =~ m/\Q$pattern\E$/ or $filefullpath eq "") {
        next FILELIST_LOOP;
      }
    }

    my $f = $filefullpath;
    
    $filefullpath = acl::File::file_slashes($filefullpath); # use Linux style path
    $filefullpath =~ s/^\.\///;
    $map_fullpath_to_name{$filefullpath} = acl::File::mybasename($filefullpath);
  }
  
  #sort file paths according to their names
  foreach $filefullpath ( sort { $map_fullpath_to_name{$a} cmp $map_fullpath_to_name{$b} or $a cmp $b } keys %map_fullpath_to_name ) {
    next if $filefullpath eq "";
    if ($count) { 
      $fileJSON .= ", {";
    } else {
      $fileJSON .= "{";
    }

    $fileJSON .= '"path":"'.escape_string($filefullpath).'"';
    $filename = $map_fullpath_to_name{$filefullpath};
    $fileJSON .= ', "name":"'.escape_string($filename).'"';

    $fileJSON .= ', "has_active_debug_locs":false';
    
    #print the full file name with absolute path
    $filepath = acl::File::mydirname($filefullpath);
    $filepath = acl::File::abs_path($filepath); # this is a \n at the end of the returned value
    $filepath =~ s/\n//g; 
    $filefullpath = $filepath.'/'.$filename;
    $fileJSON .= ', "absName":"'.escape_string($filefullpath).'"';
    
    my $filecontent;

    if ( -e $filefullpath ) {
      open (my $fin, '<', $filefullpath) or $filecontent = "";

      if (defined $fin) {
        $filecontent = <$fin>;
        close($fin);
      }
    } else {
      $filecontent = "";
    }

    # $filecontent needs to be escaped since this in an input string which may have
    # quotes, and special characters. These can lead to invalid javascript which will
    # break the reporting tool.
    # The input from area.json and mav.json is already valid JSON
    $fileJSON .= ', "content":"'.escape_string($filecontent).'"}';

    $count = $count + 1;
  }
  $fileJSON .= "];";
  return $fileJSON;
}


=head2 create_pipeline_viewer($work_directory, $hdl_directory_root, $verbose)

Create the files required for the pipeline viewer, given the appropriate
work directory.  Requires the graphviz 'dot' tool to be available.

=cut 

sub create_pipeline_viewer{
  my $work_dir = shift;
  my $hdl_root_dir = shift;
  my $verbose = @_ ? shift : 0;

  # Check for graphviz dot tool
  if (system("dot -V")) {
    print "WARNING: Graphviz 'dot' tool not found.  Pipeline viewer will be unavailable.\n";
    return;
  }
  print "Processing dot files for pipeline viewer.  ";
  print "This may take a long time for large designs.\n";

  # Copy HDL files
  # TODO: ideally we'd want to symlink these, but then Chrome complains.
  # Also, the HDL for each component/kernel should go in its own subdirectory.
  my $hdl_dir = "$work_dir/reports/lib/hdl";
  acl::File::make_path($hdl_dir) or return;
  my $return_status = system("find $work_dir/$hdl_root_dir/*/ -iname *.vhd | xargs -L1 -I{} cp {} $hdl_dir/");

  my $dot_dir = "$work_dir/reports/lib/dot_svg";
  acl::File::make_path($dot_dir) or return;

  # Time SVG creation
  my $svg_time_start = time();
  print "Start creating SVGs at: $svg_time_start\n" if ($verbose >= 2);

  # The top-level dot file is often (but not always) 1_module.dot.
  my $top_level_dot = "1_module";

  my @dirs = ();
  foreach my $dir (acl::File::simple_glob("$work_dir/*")) {
    push @dirs, $dir if $dir =~ m/dumpdot/;
  }
  if (scalar(@dirs)) {
    @dirs = sort @dirs;
    my $most_recent = $dirs[-1];
    # Sort by filesize - smallest to largest, so we can start viewing the report
    # before this finishes, since it could take a really long time for large dot files.
    # Sorting isn't strictly necessary, but we could theoretically end up
    # with one thread doing all the long-running jobs.  If this sort is slow,
    # maybe it'd be worthwile getting rid of it (especially if using many threads).
    my @dot_files = sort { -s $a <=> -s $b } acl::File::simple_glob("$most_recent/*");

    # Use fork to do dot -> svg conversion in parallel across $n threads
    my $n = 6; # Number of threads to fork
    for my $fork_id (1 .. $n) {
      my $pid = fork;
      if (not $pid) {
        for(my $i = $fork_id - 1; $i < scalar(@dot_files); $i += $n) {
            my $dot = $dot_files[$i];
            next if !$dot =~ m/\.dot/;
            my $svg = acl::File::mybasename($dot);
            $svg =~ s/\.dot$/\.svg/g;
            # These options speed up dot->svg conversion by about 10x,
            # depending on the graph structure, but do sacrifice graph quality
            # a bit.  The "faster" options should be even faster, and may be
            # necessary for large designs.
            # In the future, perhaps we could adjust these options depending on
            # the size of the graph.
            my $dot_args = "-Gnslimit=10 -Gsplines=line"; # fast
            #my $dot_args = "-Gnslimit=1 -Gnslimit1=1 -Gmaxiter=1 -Gmclimit=0.1 -Gsplines=line"; # faster
            my $cmd = "dot -Tsvg $dot_args $dot -o $dot_dir/$svg";
            print "$cmd\n" if ($verbose >= 3);
            system($cmd);
        }
        exit;
      }
    }
    # Rejoin threads.
    for (1 .. $n) {
      wait();
    }
    # Find top-level module (we can't pass back value from forked job, so we
    # must do that here in the main thread).
    foreach my $dot (@dot_files) {
      $dot = acl::File::mybasename($dot);
      if ($dot =~ m/\d+_module\.dot/) {
        ($top_level_dot = $dot) =~ s/\.dot//;
        last;
      }
    }
  }

  # Print variables to report_data.js
  open (my $report_data, ">>$work_dir/reports/lib/report_data.js") or return;
  print $report_data "\nvar enable_dot = 1;\n";
  print $report_data "\nvar dot_top = \"$top_level_dot\";";
  close($report_data);

  # Print elapsed time to create SVGs.
  my $svg_time_done = time(); my $svg_time_elapsed = $svg_time_done - $svg_time_start;
  print "Finished creating SVGs at: $svg_time_done (elapsed: $svg_time_elapsed)\n" if ($verbose >= 2);
}


=head2 append_to_log($filename, $filename, ..., $filename, $logfile)

Prints each of the givenfiles to the given logfile.

=cut

sub append_to_log {
  my $logfile= pop @_;
  open(LOG, ">>$logfile");
  foreach my $infile (@_) {
    open(TMP, "<$infile");
    while(my $l = <TMP>) {
      print LOG $l;
    }
    close TMP;
  }
  close LOG;
}


=head2 move_to_err($filename, $filename, $filename, ...)

Prints each file given in to stderr, and then unlinks the given files.

=cut

sub move_to_err {
  foreach my $infile (@_) {
    open(ERR, "<$infile"); ## We currently can't guarantee existence of $infile # or mydie("Couldn't open $infile for appending.");
    while(my $l = <ERR>) {
      print STDERR $l;
    }
    close ERR;
    unlink $infile;
  }
}


=head2 append_to_err($filename, $filename, $filename, ...)

Prints each file given in to stderr. Does NOT unlink the files

=cut

sub append_to_err {
  foreach my $infile (@_) {
    open(ERR, "<$infile"); ## We currently can't guarantee existence of $infile # or mydie("Couldn't open $infile for appending.");
    while(my $l = <ERR>) {
      print STDERR $l;
    }
    close ERR;
  }
}


=head2 append_to_out($filename, $filename, $filename, ...)

Prints each file given in to stdout. Does NOT unlink the files

=cut

sub append_to_out {
  foreach my $infile (@_) {
    open(OUT, "<$infile"); ## We currently can't guarantee existence of $infile # or mydie("Couldn't open $infile for appending.");
    while(my $l = <OUT>) {
      print STDOUT $l;
    }
    close OUT;
  }
}


=head2 filter_llvm_time_passes($logfile, $time_log, $time_passes)

This functions filters output from LLVM's --time-passes
into the time log. The source log file is modified to not
contain this output as well.
TODO: move this function to Util.pm when Util.pm created in FB:512992

=cut

sub filter_llvm_time_passes {
  my ($logfile) = shift;
  my ($time_passes) = shift;

  if ($time_passes) {
    open (my $L, '<', $logfile);
    my @lines = <$L>;
    close ($L);
    # Look for the specific output pattern that corresponds to the
    # LLVM --time-passes report.
    for (my $i = 0; $i <= $#lines;) {
      my $l = $lines[$i];
      if ($l =~ m/^\s+\.\.\. Pass execution timing report \.\.\.\s+$/ ||
          $l =~ m/LLVM IR Parsing/) {
        # We are in a --time-passes section.
        my $start_line = $i - 1; # -1 because there's a ===----=== line before that's part of the --time-passes output

        # The end of the section is the SECOND blank line.
        for(my $j = 0; $j < 2; ++$j) {
          for(++$i; $i <= $#lines && $lines[$i] !~ m/^$/; ++$i) {
          }
        }
        my $end_line = $i;

        my @time_passes = splice (@lines, $start_line, $end_line - $start_line + 1);
        acl::Common::write_time_log(join ("", @time_passes));

        # Continue processing the rest of the lines, taking into account that
        # a chunk of the array just got removed.
        $i = $start_line;
      }
      else {
        ++$i;
      }
    }

    # Now rewrite the log file without the --time-passes output.
    open ($L, '>', $logfile); 
    print $L join ("", @lines);
    close ($L);
  }
}


=head2 create_warningsJSON($error_file_name ..., $disable_lmem_repl)

Creates the contents for the warning.json file by reading the error files (whose names are passed in) to get
the compiler warnings and place them into a json file.

=cut 

sub create_warningsJSON {
  my $disabled_lmem_repl = pop @_;
  my @row_array;
  if ($disabled_lmem_repl) {
    push(@row_array, {name => 'Local memory replication disabled', data => [1], details => ['Local memory replication was disabled due to estimated overutilization of RAM blocks.'],});
  }

  my $line_limit = 1000;
  foreach my $error_file_name (@_){
    if (open (my $file, "<$error_file_name")) {
      my @lines = split("\n", <$file>);
      my $line_count = 0;
      for my $line (@lines) {
        if($line_count++ >= $line_limit) {
          my $message = "WARNING: To conserve space only $line_count warnings were printed here.";
          push(@row_array, {name => escape_string($message), details => [escape_string($message)],});
          last;
        }
        my $llvm_search_string = "Compiler Warning: "; 
        my $clang_search_string = " warning: "; 
        if ($line =~ m/$llvm_search_string/) {
          # Look for LLVM-style warnings
          my $start_index = index($line, $llvm_search_string);
          $line =~ s/\n|\r//g;
          my ($filename, $line_number) = $line =~ /(\S+\.\w+):(\d+)/;
          if ( defined($filename) && defined($line_number) ) {
            $filename = escape_string($filename);
            $line_number = escape_string($line_number);
            my @debug_array;
            push(@debug_array, {filename => $filename, line => $line_number,});
            push(@row_array, {name => escape_string(substr($line, $start_index + 18, length($line)-($start_index + 18))), details => [escape_string($line)], debug => [\@debug_array],});
          } else {
            push(@row_array, {name => escape_string(substr($line, $start_index + 18, length($line)-($start_index + 18))), details => [escape_string($line)],});
          }
        } elsif ($line =~ m/$clang_search_string/) {
          # Look for Clang-style warnings
          my $start_index = index($line, $clang_search_string);
          $line =~ s/\n|\r//g;
          my ($filename, $line_number) = $line =~ /(\S+\.\w+):(\d+):.*/;
          if ( defined($filename) && defined($line_number) ) {
            $filename = escape_string($filename);
            $line_number = escape_string($line_number);
            my @debug_array;
            push(@debug_array, {filename => $filename, line => $line_number,});
            push(@row_array, {name => escape_string(substr($line, $start_index + 10, length($line)-($start_index + 10))), details => [escape_string($line)], debug => [\@debug_array],});
          } else {
            push(@row_array, {name => escape_string(substr($line, $start_index + 10, length($line)-($start_index + 10))), details => [escape_string($line)],});
          }
        }
      }
      close $file;
    }
  }
  my %warningsJSONHash = (rows => \@row_array);
  my $warningsJSONstring = try_to_encode(\%warningsJSONHash);
  # TODO: Instead of formatting by adding spaces like this, return the pretty-print functionality of ACL_JSON.pm and use that
  $warningsJSONstring =~ s/,/\n,/g;
  $warningsJSONstring =~ s/\},\{/\},\n\{/g;
  $warningsJSONstring =~ s/\:\[/\:\[\n/;
  $warningsJSONstring =~ s/\}\]\}/\}\n\]\}/g;
  return $warningsJSONstring;
}


=head2 create_infoJSON($is_aoc, $proj_name, $target_family, $target_device, $quartus_version, $command, $board)

Creates the contents for the info.json file using the information passed in.

=cut 

sub create_infoJSON {
  my ($is_aoc, $proj_name, $target_family, $target_device, $quartus_version, $command, $board) = @_;
  my @row_array;
  my $time = localtime;
  my $version = "18.1.0 Build 222";
  push(@row_array, {name => 'Project Name', data => [$proj_name], classes => ['info-table'],});
  my %push_row = ($is_aoc == 1) ? (name => 'Target Family, Device, Board', data => ["$target_family, $target_device, $board"],) : (name => 'Target Family, Device', data => ["$target_family, $target_device"],);
  push(@row_array, \%push_row);
  my %push_row2 = ($is_aoc == 1) ? (name => 'AOC Version', data => [$version],) : (name => 'i++ Version', data => [$version],);
  push(@row_array, \%push_row2);
  push(@row_array, {name => 'Quartus Version', data => [$quartus_version],});
  push(@row_array, {name => 'Command', data => [$command],});
  push(@row_array, {name => 'Reports Generated At', data => [$time],});
  my %infoJSONHash = (name => "Info", rows => \@row_array);
  my $infoJSONstring = try_to_encode(\%infoJSONHash);
  # TODO: Instead of formatting by adding spaces like this, return the pretty-print functionality of ACL_JSON.pm and use that
  $infoJSONstring =~ s/\},\{/\},\n\{/g;
  $infoJSONstring =~ s/\:\[/\:\[\n/;
  $infoJSONstring =~ s/\}\]\}/\}\n\]\}/g;
  return $infoJSONstring;
}


=head2 create_quartusJSON($quartus_text)

Creates the contents for the quartus.json file using the information passed in.

=cut 

sub create_quartusJSON {
  my ($quartus_text) = @_;
  my %details_hash = (type => 'text', text => $quartus_text,);
  my @children;
  push (@children, {name => 'Run Quartus compile to populate this section. See details for more information.', details => [\%details_hash]});
  my %quartusJSONHash = (quartusFitClockSummary => {name => 'Quartus Fit Summary', children => \@children,});
  return try_to_encode(\%quartusJSONHash);
}


=head2 data_add(%section)

Adds the two inputted arrays together element by element, 
returning a reference to the output array.

=cut 

sub data_add {
  my ($data1_ref, $data2_ref) = @_;
  if ($data1_ref and $data2_ref){
    my @data1 = @$data1_ref; my @data2 = @$data2_ref;
    # continue to add data until one of the arrays ends
    foreach my $i (0 .. $#data1){
      if (exists $data1[$i] and exists $data2[$i]){
        $data1[$i] += $data2[$i];
      } else {
        return \@data1;
      }
    }
    $data1_ref = \@data1;
  }
  return $data1_ref;
}


=head2 get_data_overhead(%section)

This function calculates the data overhead (Cluster Logic + Feedback) for
the sent in function. The only input is a reference of the hash of the function. 
The output is the data of the overhead, in the order of ALUT, FF, RAM, DSP.

=cut 

sub get_data_overhead {
  my %section = @_;
  #if already at "Feedback" or "Cluster logic", return this layer's data
  if (%section and exists $section{'name'} and exists $section{'data'} and ($section{'name'} eq 'Feedback' or $section{'name'} eq 'Cluster logic')){
    return @{$section{'data'}};
  # otherwise go through all the children and look for "Feedback" or "Cluster logic" in their branches
  } elsif (%section and exists $section{'children'}) {
    my @data_array = (0, 0, 0, 0, 0);
    foreach my $child (@{$section{'children'}}){
      if ($child){
        my @sect_data = get_data_overhead(%$child);
        if (@sect_data){
          @data_array = @{data_add(\@data_array, \@sect_data)}
        }
      } else {
        next;
      }
    }
    return @data_array;
  }
  # returning 5 zeroes instead of 4 in case mlabs get introduced to the report
  # currently the places that call this function only get 4 of these
  return (0, 0, 0, 0, 0);
}


=head2 add_layer_of_hierarchy_if_needed(\%section)

If a resource name in the form of "filename1:line1 > filename2:line2" is found,
create a layer of heirachy, turning it into:
  filename1:line1
      filename1:line1 > filename2:line2
It also ensures appropriate debug statements are inserted.

=cut 

sub add_layer_of_hierarchy_if_needed {
  my ($section_ref) = @_;
  if (!($section_ref)){
    return undef;
  }
  my %section = %$section_ref;
  # look for the '>' symbol
  if (exists $section{'name'} && index($section{'name'}, " >") != -1) {
    my @split_name = split(' >', $section{'name'});
    delete $section{'detail'};
    # create a child with the full name of the line, the same data as the parent, and the same children
    my %child_hash = (name => $section{'name'}, type => 'resource',);
    my $unused;
    ($section{'name'}, $unused) = get_name_from_debug($section{'debug'}, $split_name[0]);
    if (exists $section{'data'}){
      $child_hash{'data'} = $section{'data'};
    }
    # add the children of the heirachy
    if (exists $section{'children'}){
      $child_hash{'children'} = $section{'children'};
    }
    # add the debug of the heirachy
    if (exists $section{'debug'}){
      $child_hash{'debug'} = $section{'debug'};
    }
    # change the name of the original section to just filename1:line1, and set its children to be the newly created layer
    my @children_array;
    push(@children_array, \%child_hash);
    $section{'children'} = \@children_array;
  }
  return \%section;
}


=head2 append_child(\@array_of_children, \%child)

This function adds the child into the array of children. It searches for 
another object in the array with the same name as the child - if found, this child's 
data is added to object of the same name, and their children are combined. 
Otherwise the child is pushed directly onto the array.

=cut 

sub append_child {
  my ($array_to_push_to_ref, $section_ref) = @_;
  my @array_to_push_to = @$array_to_push_to_ref;
  my $section_child_found_in_array = 0;
  # if the section inputted is invalid, just return the array
  if (!($section_ref)){
    return \@array_to_push_to;
  }
  my %section = %$section_ref;
  # if the inputted array is empty, push the section into it and return
  if (not @array_to_push_to){
    push(@array_to_push_to, $section_ref);
    return \@array_to_push_to;
  }
  if (exists $section{'debug'} and exists $section{'type'} and exists $section{'name'} and ($section{'type'} eq "resource") and (index($section{'name'}, ">") == -1) and exists $section{'children'}){
    my $unused;
    ($section{'name'}, $unused) = get_name_from_debug($section{'debug'}, $section{'name'});
  }
  # otherwise search through the array to see if a section with this name already exists in the children
  foreach my $in_array (@array_to_push_to){
    if ($in_array and exists $in_array->{'name'} and exists $section{'name'} and exists $in_array->{'data'} and exists $section{'data'} and ($in_array->{'name'} eq $section{'name'})){
      # if the section already exists in the array, it will be combined with the existing section, so their children and data need to be combined
      if (exists $section{'children'}) {
        %section = %{process_children(\%section)};
        foreach my $child (@{$section{'children'}}){
          my @data_array = @{data_add($in_array->{'data'}, $child->{'data'})};
          $in_array->{'children'} = append_child($in_array->{'children'}, $child);
          $in_array->{'data'} = \@data_array;
        }
      # if the section exists but there is no children to combine (but there may be counts to combine)
      } else {
        if (exists $in_array->{'count'}){
          my $sect_count = (exists $section{'count'}) ? $section{'count'} : 1;
          $in_array->{'count'} += $sect_count;
        }
        my @data_array = @{data_add($in_array->{'data'}, $section{'data'})};
        $in_array->{'data'} = \@data_array;
      }
      $section_child_found_in_array = 1;
    } 
  }
  # if the section was never found in the array, it is new and should just be pushed in 
  if ($section_child_found_in_array == 0) {
    %section = %{process_children(\%section)};
    push(@array_to_push_to, \%section);
  }
  return \@array_to_push_to;
}


=head2 get_debug_from_parent_name($parent_name)

This function creates a debug section out of the parent name; 
the debug section includes the parent's filename and line number.
It is used by children of resources and newly created heirarchies to 
ensure that the debug only contains one relevant debug filename and line #.

=cut 

sub get_debug_from_parent_name {
  my ($parent_name) = @_;
  # if the parent name does not contain ':', it cannot be turned into a debug (unless it is No Source Line)
  if (index($parent_name, ":") == -1 and !($parent_name eq "No Source Line")){
    return undef;
  }
  # if the parent has a standard name, store the filename as everything before ':', 
  # and the line number as everything between ':' and '>' (if it exists)
  my @parent_split = split(':', $parent_name);
  if (! exists $parent_split[1]){
    @parent_split = split(':', $parent_name);
  }
  my $filename = $parent_split[0];
  my $line_num = (index($parent_name, ">") != -1) ? ((split(' >', $parent_split[1]))[0]) : $parent_split[1];
  # if the parent is No Source Line, return "" and 0 in  the debug
  if ($parent_name eq "No Source Line"){
    $filename = "";
    $line_num = 0;
  }
  # appropriately nest the debug info
  my @debug_array = [{filename => $filename, line => $line_num, }];
  return \@debug_array;
}


=head2 process_children(\%section)

This function goes through the the section's children and either adds debug statements
(to the children without any children of their own), or changes their names to the 
one derived from their debug statement. It processes every child in the section's heirachy.

=cut 

sub process_children {
  my ($section_ref, $use_this_debug) = @_;
  if (!($section_ref)){
    return {};
  }
  my %section = %$section_ref;
  if (exists $section{'children'}) {
    foreach my $child (@{$section{'children'}}){
      # if the section child doesn't have children, it's name shouldn't be changed, but a debug should be added
      if (!(exists $child->{'children'})){
        if ($section{'type'} eq "resource" and exists $child->{'details'}){
          delete $child->{'details'};
        }
        my $temp_debug = ($use_this_debug) ? $use_this_debug : get_debug_from_parent_name($section{'name'});
        if ($temp_debug){
          $child->{'debug'} = $temp_debug;
        }
      # if the child has children, change it's name, then process it's children
      } else {
        if (exists $child->{'debug'} and index($child->{'name'}, ">") == -1){
          ($child->{'name'}, $child->{'debug'}) = get_name_from_debug($child->{'debug'}, $child->{'name'});
        }
        # if an extra heirachy was created, the debug of all of the children is equal to the debug of the parent
        if (index($child->{'name'}, ">") != -1){
          my $temp_debug = get_debug_from_parent_name($section{'name'});
          $child = ($temp_debug) ? process_children($child, $temp_debug) : process_children($child);
          $child->{'replace_name'} = $acl::ACL_JSON::true;
        } else {
          $child = process_children($child);
        }
      }
    }
  }
  return \%section;
}


=head2 get_name_from_debug(\@debug_array, $section{'name'})

This function goes into the given debug array, and tries to make a new section name
by combining the full filename in the debug with the line number. If something in the debug
is invalid or not present, it returns back the given $section{'name'}. It also cleans up the 
debug statement so that only the first filename-line combination is left.

=cut 

sub get_name_from_debug {
  my ($debug_ref, $name) = @_;
  if (!$debug_ref or !(exists $debug_ref->[0]) or !(exists $debug_ref->[0]->[0]) or !($debug_ref->[0]->[0])){
    if (!$name){
      return "";
    }
    return $name;
  }
  my @debug_deref1 = @$debug_ref;
  my @debug_deref2 = @{$debug_deref1[0]};
  my %debug = %{$debug_deref2[0]};
  my $output_name = $name;
  my @debug_out;
  if (exists $debug{'filename'} and exists $debug{'line'} and $debug{'filename'} and $debug{'line'}){
    $output_name = "$debug{'filename'}:$debug{'line'}";
    # this section is to remove unnecessary sections from debug statements 
    # only the first filename and line are kept
    @debug_out = {filename=>$debug{'filename'}, line=>$debug{'line'}};
  }
  if (@debug_out){
    $debug_deref1[0] = \@debug_out;
  }
  return $output_name, \@debug_deref1;
}


=head2 append_children(\@array_to_push_to, \%section)

If the section is not named "many returned children", pushes the section onto the array after 
ensuring all the correct hierarchy is added and all of the children are merged as needed (append_child does this). 
If section is named "many returned children", instead follow this procedure for each child of the section.
Return the array with the section(s) pushed onto it appropriately. 

=cut 

sub append_children {
  my ($array_to_push_to_ref, $section) = @_;
  my @array_to_push_to = @$array_to_push_to_ref;
  if (!($section)){
    return @array_to_push_to;
  }
  # if the section is called many returned children, append each of its children
  if ($section->{'name'} eq 'many_returned_children'){
    foreach my $section_child (@{$section->{'children'}}){
      @array_to_push_to = @{append_child(\@array_to_push_to, add_layer_of_hierarchy_if_needed($section_child))};
    }
  # otherwise, append the section
  } else {
    @array_to_push_to = @{append_child(\@array_to_push_to, add_layer_of_hierarchy_if_needed($section))};
  }
  return @array_to_push_to;
}


=head2 get_data_from_children(\@children_array)

Sums all of the data from each child in the inputted children_array
unless it is a partition (do not sum those).

=cut

sub get_data_from_children {
  my ($children_array) = @_;
  my @output_data = ($need_MLABs) ? (0, 0, 0, 0, 0) : (0, 0, 0, 0);
  my @temp_data;
  if ($children_array) {
    foreach my $child (@$children_array){
      @temp_data = (0, 0, 0, 0, 0);
      # if the child has data, add it to the sum
      if ($child and exists $child->{'data'} and exists $child->{'type'} and !($child->{'type'} eq 'partition')){
        @temp_data = @{$child->{'data'}};
      # if the child doesn't have data but does have children, add the children's data to the sum
      } elsif ($child and exists $child->{'children'} and exists $child->{'type'} and !($child->{'type'} eq 'partition')){
        @temp_data = @{get_data_from_children($child->{'children'})};
      }
      @output_data = @{data_add(\@output_data, \@temp_data)};
    }
  }
  return \@output_data;
}


=head2 create_many_children(\%section, $is_state, $is_bb)

This function is for section which should not be inserted themselves, but all of their
children should be analysed (by using parse_system_section_to_get_source_section) and returned.
The input includes the section and whether the parent that sent in this section is State or is 
a Basic Block. The output is a hash with two sections: name ("many returned children") and 
the children, which are in an array.

=cut

sub create_many_children {
  my ($section, $is_state, $is_bb) = @_;
  if ($section and exists $section->{'children'}) {
    my @children = @{$section->{'children'}};
    my %output_hash = (name=>'many_returned_children');
    my @output_children;
    #each child is processed, and the output src code is added to the array
    foreach my $child (@children){
      @output_children = append_children(\@output_children, parse_system_section_to_get_source_section($is_state, $is_bb, %$child));
    }
    $output_hash{'children'} = \@output_children;
    return \%output_hash;
  } else {
    return $section;
  }
}


=head2 parse_system_section_to_get_source_section($state_parent, $bb_parent, %section)

This function takes in a area.json segment and outputs the equivalent segment in area_src.json.
The other inputs are only set to 1 if the segment is being sent in from a State or a Basic Block respectively.

=cut

sub parse_system_section_to_get_source_section {
  my ($state_parent, $bb_parent, %section) = @_;
  if (!%section or !(exists $section{'type'})){
    return {};
  }
  my %output_hash;
  # behavior for module and function segments:
  if ($section{'type'} eq 'module' or $section{'type'} eq 'function' or $section{'type'} eq 'group'){
    foreach my $key (keys %section){
      my @output_children;
      my $min_debug_line = undef;
      my $min_debug;
      # parse the children 
      # if the section is a module, go through all the children 
      #   - if they have no children of their own, they are pushed on directly
      #   - if they have children, they are sent into this parser, and the output is appended with the append_children function
      # the same is done for functions, except a new element called Data control overhead is also added
      if ($key eq 'children'){
        if ($section{'type'} eq 'function'){
          my ($overhead_alut, $overhead_ff, $overhead_ram, $overhead_dsp, $overhead_mlab) = get_data_overhead(%section);
          my $data_overhead_data = ($need_MLABs) ? [$overhead_alut, $overhead_ff, $overhead_ram, $overhead_dsp, $overhead_mlab] : [$overhead_alut, $overhead_ff, $overhead_ram, $overhead_dsp];
          my %data_overhead = (name => 'Data control overhead', type=>'resource', data=>$data_overhead_data,);
          my %detail_hash = (type => 'text', text => 'Feedback + Cluster logic', type => 'brief', text => 'Feedback+Cluster logic',);
          my @detail_array = (\%detail_hash);
          $data_overhead{'details'} = \@detail_array;
          push(@output_children, \%data_overhead);
        }
        foreach my $child (@{$section{'children'}}){
          # children are run through this function again - now $temp_child stores the src code for the child 
          my $temp_child = parse_system_section_to_get_source_section(0, 0, %$child);
          # this adds a debug to the function by finding the lowest line number used inside the function
          if ($section{'type'} eq 'function' and $temp_child and exists $temp_child->{'debug'} and exists $temp_child->{'debug'}->[0] and exists $temp_child->{'debug'}->[0]->[0] and exists $temp_child->{'debug'}->[0]->[0]->{'line'}) {
            my $temp_line_num = $temp_child->{'debug'}->[0]->[0]->{'line'};
            if (!($min_debug_line) or ($temp_line_num and $temp_line_num < $min_debug_line)){
              $min_debug_line = $temp_line_num;
              $min_debug = [[{filename => $temp_child->{'debug'}->[0]->[0]->{'filename'}, line => $min_debug_line, }]];
            }
          }
          # if a child doesn't have any children of it's own and is directly under a function or module,
          # it gets pushed into the output directly without any processing
          if (!(exists($child->{'children'})) and ($child->{'type'} eq 'resource') and !($child->{'name'} eq 'Feedback' or $child->{'name'} eq 'Cluster logic')){
            if ($section{'type'} eq 'function') {
              delete $child->{'debug'};
            }
            push(@output_children, $child);
          # Split memory should also just get pushed to the output directly without processing
          # Whether or not the memory is split is determined using the detail string added at the bottom of the addLocalMemResources function in ACLAreaUtils.cpp
          } elsif ((exists $child->{'details'} and exists $child->{'details'}->[0] and exists $child->{'details'}->[0]->{'text'} and (index($child->{'details'}->[0]->{'text'}, "was split into multiple parts due to optimizations") != -1)) or (exists $child->{'children'} and exists $child->{'children'}->[0] and index($child->{'children'}->[0]->{'name'}, "Part 1") != -1)) {
            push(@output_children, $child);
          } else {
            # children that have other children first run through this same function to see if they need to be appended,
            # and then the output of this is appended using the append_children function in case of merging
            @output_children = append_children(\@output_children, $temp_child);
          }
        }
        # this removes extra debug statements from children (should only have one filename and line)
        for my $child (@output_children){
          if (exists $child->{'debug'} and exists $child->{'debug'}->[0] and exists $child->{'debug'}->[0]->[0]){
            $child->{'debug'} = [[{filename => $child->{'debug'}->[0]->[0]->{'filename'}, line => $child->{'debug'}->[0]->[0]->{'line'}}]];
          }
        }
        if ($section{'type'} eq 'function' and $min_debug and exists $min_debug->[0] and exists $min_debug->[0]->[0] and exists $min_debug->[0]->[0]->{'line'} and $min_debug->[0]->[0]->{'line'}) {
          $output_hash{'debug'} = $min_debug;
        }
        # if the above for loop results in something, the data for this element is changed to the sum of the data from its children
        $output_hash{'children'} = (@output_children) ? \@output_children : $section{'children'};
        $output_hash{'data'} = (@output_children) ? get_data_from_children(\@output_children) : $section{'data'};
      # the rest of the keys (except data, which depends on the children) are the same in the output as in the section
      } elsif (not $key eq 'data') {
        $output_hash{$key} = $section{$key}; 
      }
    }
    return \%output_hash;
  # if the section is a partition, it should be returned without changes
  } elsif ($section{'type'} eq 'partition'){
    return \%section;
  # if the section is a resource, there are several options depending on the parents and the children
  } elsif ($section{'type'} eq 'resource'){
    # if the parent was a State ($state_parent == 1), state should be set as a new child 
    # also need to check if ">" is in the name; if it is, an extra layer of heirachy needs to be added as well
    if ($state_parent == 1){
      delete $section{'detail'};
      my @children_array;
      if (index($section{'name'}, " >") == -1) {
        @children_array = {name=>'State', type=>'resource', data=>$section{'data'}, count=>'1',};
      }else{
        my @split_name = split(' >', $section{'name'});
        @children_array = {name=>$section{'name'}, type=>'resource', data=>$section{'data'}, debug=>$section{'debug'},};
        my @children_array2 = {name=> 'State', type=>'resource', data=>$section{'data'}, count=>'1',};
        my $unused;
        ($section{'name'}, $unused) = get_name_from_debug($section{'debug'}, $split_name[0]);
        $children_array[0]->{'children'} = \@children_array2;
      }
      $section{'children'} = \@children_array;
      %section = %{process_children(\%section)};
      return \%section;
    # Computation and resource objects which are not the children of basic blocks and are not Cluster logic, Feedback or State just pass their children back directly  
    } elsif ((!$bb_parent and ! ($section{'name'} eq 'Feedback' or $section{'name'} eq 'Cluster logic' or $section{'name'} eq 'State')) or $section{'name'} eq 'Computation'){
      if (exists $section{'children'}) {
        my %output_hash = (name=>'many_returned_children', children=>$section{'children'},);
        return \%output_hash;
      }
      return \%section;
    # if the section is a State, use the create many children function, specifying a state parent
    } elsif ($section{'name'} eq 'State'){
      return create_many_children(\%section, 1, 0);
    }
  # if the section is a Basic Block, use the create many children function, specifying a basic block parent
  } elsif ($section{'type'} eq 'basicblock'){
    return create_many_children(\%section, 0, 1);
  # if there is some unexpected input, just return it back out
  } else {
    return \%section;
  }
}


=head2 parse_to_get_area_src ($work_dir)

This function takes in the work directory where the json files are, opens the 
area.json file and a new area_src.json file, then sends these off to try_to_parse. 
It then closes all the relevant files and returns. 

=cut
  
sub parse_to_get_area_src {
  my ($work_dir) = @_;
  my $src_workspace_file = "$work_dir/area_src.json";
  open my $workspace_SRC_file, '>'.$src_workspace_file;
  open my $area_json, '<'.$work_dir."/area.json";
  my $return_val = try_to_parse($area_json, $workspace_SRC_file);
  if (!$return_val){
    print $workspace_SRC_file "{\n};";
  }
  close $area_json;
  close $workspace_SRC_file;
  return 0;
}


=head2 try_to_parse ($work_dir)

The relevant open files are inputted into this subroutine, and it tries to 
create the json file, returning 0 upon any form of failure. Among its tasks, it decodes area.json into perl, 
sends it into parse_system_section_to_get_source_section, encodes it back to json, and prints it out 
in a file named area_src.json (in the work_dir).

=cut

sub try_to_parse {
  my ($area_json, $workspace_SRC_file) = @_;
  my $json_txt = do {
    local $/;
    <$area_json>
  };
  
  use acl::ACL_JSON;
  my $json_to_perl;
  eval {
    $json_to_perl = acl_decode_json $json_txt;
  };
  if ($@ or !($json_to_perl)) {
    return 0;
  }
  my $while_loop_condition = 1;
  my %current_section = %{$json_to_perl};
  my ($temp) = parse_system_section_to_get_source_section(0, 0, %current_section);
  if (!($temp)){
    return 0;
  }
  my $back_to_json = try_to_encode($temp);
  if ($back_to_json eq "{}"){
    return 0;
  }
  print $workspace_SRC_file $back_to_json;
  return 1;
}


=head2 try_to_encode ($ref_of_obj_to_encode)

Tries to encode the object into JSON using the ACL_JSON.pm encode method.
Upon failure, returns "{}", otherwise returns the encoded string.

=cut

sub try_to_encode {
  my ($ref_of_obj_to_encode) = @_;
  my $to_json;
  eval {
    $to_json = acl_encode_json $ref_of_obj_to_encode;
  };
  if ($@ or !($to_json)){
    return "{}";
  }
  return $to_json;
}


=head2 display_hls_error_message ($title, $out, $err, $keep_log, $logs_are_temporary, $retcode, $time_passes, $cleanup_list_ref)

This function displays the error message (if any) for the HLS flow. The message
depends on whether stdout/stderr have been redirected to $err and $out and
whether we have asked to keep them around or not. If we ask to delete them, we
redirect their content back to stderr/stdout and we push them to a cleanup list
to be deleted later. The function also calls filter_llvm_time_passes() if
needed (when --time-passes is used)

=cut

sub display_hls_error_message {
  my ($title, $out, $err, $keep_log, $out_is_temporary, $err_is_temporary, $move_err_to_out, $retcode, $time_passes, $cleanup_list_ref) = @_;
  my $loginfo = "";
  my $message = "";

  # Handle time-passes report
  if ($time_passes && $err) {
    acl::Report::filter_llvm_time_passes($err, $time_passes); #Will only execute in regtest_mode
  }

  # Handle File deletion/appendation
  if ($move_err_to_out && $err && $out && ($err ne $out)) {
    acl::Common::move_to_log('', $err, $out);
  } elsif ($err_is_temporary && $err) {
    acl::Report::append_to_err($err);
    push @$cleanup_list_ref, $err;
  }
 
  if ($out_is_temporary && $out && ($err ne $out)) {
    acl::Report::append_to_out($out);
    push @$cleanup_list_ref, $out;
  }

  # Handle error message
  if (!$out_is_temporary && !$err_is_temporary) {
    if ($retcode != 0) {
      if($err && $out && ($err ne $out)) {
        $keep_log = 1;
        $loginfo = "\nSee $err and $out for details.";
      } elsif ($err) {
        $keep_log = 1;
        $loginfo = "\nSee $err for details.";
      } elsif ($out) {
        $keep_log = 1;
        $loginfo = "\nSee $out for details.";
      }
      $message = "HLS $title FAILED.$loginfo\n";
      print $message;
    }
  } elsif (!$out_is_temporary && $err_is_temporary) {
    if ($retcode != 0) {
      if ($out) {
        $keep_log = 1;
        $loginfo = "\nSee $out for details.";
        $message = "HLS $title FAILED.$loginfo\n";
      } else {
        $message = "HLS $title FAILED.\n";
      }
      print $message;
    }
  }
  elsif ($out_is_temporary && !$err_is_temporary) {
    if ($retcode != 0) {
      if ($err) {
        $keep_log = 1;
        $loginfo = "\nSee $err for details.";
        $message = "HLS $title FAILED.$loginfo\n";
      } else {
        $message = "HLS $title FAILED.\n";
      }
      print $message;
    }
  } else {
    if ($retcode != 0) {
      $message = "HLS $title FAILED.\n";
      print $message;
    }
  }

  $_[3] = $keep_log; #update the actual reference
  return $message;
}


1;
