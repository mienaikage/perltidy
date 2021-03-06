#!/usr/bin/perl -w
use strict;
use warnings;

# This program stress-tests perltidy by running it repeatedly
# with random parameters on a variety of files.

my $usage = <<EOM;

Use 'perltidy_random_setup.pl' to setup a run in an empty temporary direct
(lots of temporary files may be created).

Follow the directions it gives.

Output is accumulated in file 'nohup.my'

You can stop the run any time by creating a file "stop.now"

You can restart by running './GO.sh' which is written
when this run stops.

EOM

# NOTE: A restart is controlled by a single arg to this routine.
# The restart format is
#
#    $0 [m.n]
#
# where m.n is an optional restart point:
#
#    m = integer file number to begin (start counting with 1)
#    n = integer first parameter case (start counting with 1)
#
#    A restart from '1.1' is the same as a start.

use Getopt::Std;
our %opts;
getopts( 'h', \%opts ) or die "$usage";
if ( $opts{h} ) { die "$usage" }

our $rsetup;    # the config info

my $config_file = "config.txt";
if ( !-e $config_file ) {
    die <<EOM;
Did not see '$config_file'
Please run 'perltidy_random_setup.pl' first
EOM
}

my $nf_beg    = 1;
my $np_beg = 1;
if ( @ARGV > 1 ) {
    print STDERR "Too many args\n";
    die $usage;
}
elsif ($ARGV[0]) {
    my $arg=$ARGV[0];
    if ( $arg && $arg =~ /^(\d+)\.(\d+)$/ ) {
        $nf_beg    = $1;
        $np_beg = $2;
        print STDERR "\nRestarting with arg $arg\n"
    }
    else {
        print STDERR "First arg '$arg' not of form m.n\n";
        die $usage;
    }
}

read_config($config_file);

my $chain_mode         = $rsetup->{chain_mode};
my $do_syntax_check    = $rsetup->{syntax_check};
my $delete_good_output = $rsetup->{delete_good_output};
my $FILES_file         = $rsetup->{files};
my $PROFILES_file      = $rsetup->{profiles};

$FILES_file         = "FILES.txt"    unless ($FILES_file);
$PROFILES_file      = "PROFILES.txt" unless ($PROFILES_file);
$chain_mode         = 0              unless defined($chain_mode);
$do_syntax_check    = 0              unless defined($do_syntax_check);
$delete_good_output = 1              unless defined($delete_good_output);

my $rfiles    = read_list($FILES_file);
my $rprofiles = read_list($PROFILES_file);

my @files = @{$rfiles};
my $nfiles = @files;
print STDOUT "got $nfiles files\n";
if ( !@files ) { die "No files found\n" }

if ( !@files ) { die "$usage" }

# look for profiles
my @profiles = @{$rprofiles};
if ( !@profiles ) {
    print STDOUT "No profiles found .. creating a default\n";
    my $fname = "profile.1";
    open OUT, ">", $fname || die "cannot open $fname: $!\n";
    my $rrandom_parameters = [""];
    foreach ( @{$rrandom_parameters} ) {
        print OUT "$_\n";
    }
    close OUT;
    push @profiles, $fname;
}

my $rsummary   = [];
my @problems;

my $stop_file = 'stop.now';
if ( -e $stop_file ) { unlink $stop_file }

my @chkfile_errors;
my @size_errors;
my @syntax_errors;
my @saved_for_deletion;

if ( $nf_beg < 1 ) { $nf_beg = 1 }
if ( $np_beg < 1 ) { $np_beg = 1 }
my $nf_end = @files;
my $np_end = @profiles;
if ( $nf_beg > $nf_end || $np_beg > $np_end ) {

    die <<EOM;
Exiting, nothing to do:
Requested range of files is $nf_beg to $nf_end
Requested range of profiles is $np_beg to $np_end
EOM
}

# Outer loop over files
my $file_count = 0;
my $case       = 0;
MAIN_LOOP:
for (my $nf=$nf_beg; $nf<=$nf_end; $nf++) {
    my $file=$files[$nf-1];

    # remove any previously saved files
    if (@saved_for_deletion) {
        foreach (@saved_for_deletion) {
            unlink $_ if ( -e $_ );
        }
        @saved_for_deletion = ();
    }

    next unless -e $file;
    $file_count=$nf;
    my $ifile                 = $file;
    my $ifile_original        = $ifile;
    my $ifile_size            = -s $ifile;
    my $error_count_this_file = 0;

    my $error_count           = 0;
    my $missing_ofile_count   = 0;
    my $missing_chkfile_count = 0;
    my ( $ofile_size_min,   $ofile_size_max );
    my ( $ofile_case_min,   $ofile_case_max );
    my ( $efile_size_min,   $efile_size_max ) = ( 0,  0 );
    my ( $efile_case_min,   $efile_case_max ) = ( "", "" );
    my ( $chkfile_size_min, $chkfile_size_max );
    my ( $chkfile_case_min, $chkfile_case_max );
    my $ofile_size_min_expected = 0;

    my $error_flag    = 0;
    my $restart_count = 0;
    my $efile_count   = 0;
    my $has_starting_error;
    my $starting_syntax_ok = 1;

    # Inner loop over profiles for a given file
    for (my $np=$np_beg; $np<=$np_end; $np++) {
    my $profile=$profiles[$np-1];

        $case = $np;
        my $error_count_this_case = 0;

        my $ext = $case;
        if ( @files > 1 ) { $ext = "$file_count.$case" }

        my $ofile   = "ofile.$ext";
        my $chkfile = "chkfile.$ext";

        print STDERR "\n-----\nRun '$nf.$np' : profile='$profile', ifile='$ifile'\n";

        my $cmd = "perltidy <$ifile >$ofile -pro=$profile";
        print STDERR "$cmd\n";
        system $cmd;
        my $efile   = "perltidy.ERR";
        my $logfile = "perltidy.LOG";
        if ( -e $efile )   { rename $efile,   "ERR.$ext" }
        if ( -e $logfile ) { rename $logfile, "LOG.$ext" }

        if ( !-e $ofile ) {
            print STDERR "**Warning** missing output $ofile\n";
            $missing_ofile_count++;
            $error_flag = 1;
            $error_count_this_file++;
            $error_count_this_case++;
        }

        else {
            my $ofile_size = -s $ofile;
            if ( !defined($ofile_size_min) ) {
                $ofile_size_min = $ofile_size_max = $ofile_size;
                $ofile_case_min = $ofile_case_max = $ofile;
            }
            else {
                if ( $ofile_size < $ofile_size_min ) {
                    $ofile_size_min = $ofile_size;
                    $ofile_case_min = $ofile;
                }
                if ( $ofile_size > $ofile_size_max ) {
                    $ofile_size_max = $ofile_size;
                    $ofile_case_max = $ofile;
                }
            }

            # Min possible size is the min of cases 2 and 3
            # Save this to check other results for file truncation
            if    ( $case == 2 ) { $ofile_size_min_expected = $ofile_size }
            elsif ( $case == 3 ) {
                if ( $ofile_size < $ofile_size_min_expected ) {
                    $ofile_size_min_expected = $ofile_size;
                }
            }

            # Check for unexpectedly very small file size
            elsif ( $case > 3 && $ofile_size < 0.6 * $ofile_size_min_expected )
            {
                print STDERR
"**ERROR for ofile=$ofile: size = $ofile_size < $ofile_size_min_expected = min expected\n";
                push @size_errors, $ofile;
                $error_count_this_file++;
                $error_count_this_case++;
            }

        }

        my $efile_size = 0;
        if ( -e $efile ) {
            $efile_size = -s $efile;
            $efile_count++;
            if ( !defined($efile_size_min) ) {
                $efile_size_min = $efile_size_max = $efile_size;
                $efile_case_min = $efile_case_max = $efile;
            }
            else {
                if ( $efile_size < $efile_size_min ) {
                    $efile_size_min = $efile_size;
                    $efile_case_min = $efile;
                }
                if ( $efile_size > $efile_size_max ) {
                    $efile_size_max = $efile_size;
                    $efile_case_max = $efile;
                }
            }
        }

        # Do a syntax check if requested
        if ( $do_syntax_check && $starting_syntax_ok ) {
            my $synfile = "$ofile.syntax";
            my $cmd     = "perl -c $ofile 2>$synfile";
            system($cmd);
            my $fh;
            if ( open( $fh, '<', $synfile ) ) {
                my @lines     = <$fh>;
                my $syntax_ok = @lines && $lines[-1] =~ /syntax OK/i;
                if ( $case == 1 ) {
                    $starting_syntax_ok = $syntax_ok;
                    unlink $synfile;
                    if ($syntax_ok) { print STDERR "syntax OK for $ofile\n"; }
                }
                elsif ($syntax_ok) {
                    unlink $synfile;
                }
                else {
                    print STDERR "**ERROR syntax** see $synfile\n";
                    $error_count++;
                    push @syntax_errors, $synfile;
                    $error_count_this_file++;
                    $error_count_this_case++;
                }
                $fh->close();
            }
        }

        # run perltidy on the output to see if it can be reformatted
        # without errors
        my $cmd2 = "perltidy <$ofile >$chkfile";
        system $cmd2;
        print STDERR "$cmd2\n";
        my $err;
        if ( -e $efile ) {
            rename $efile, "$chkfile.ERR";
            $err = 1;
            if ( $case == 1 ) {
                $has_starting_error = 1;
            }
            elsif ( !$has_starting_error ) {
                print STDERR "**ERROR reformatting** see $chkfile.ERR\n";
                $error_count++;
                push @chkfile_errors, $chkfile;
                $error_count_this_file++;
                $error_count_this_case++;
            }
        }
        if ( !-e $chkfile ) {
            print STDERR "**WARNING** missing checkfile output $chkfile\n";
            $missing_chkfile_count++;
            $err = 1;
            $error_count_this_file++;
            $error_count_this_case++;
        }
        else {
            my $chkfile_size = -s $chkfile;
            if ( !defined($chkfile_size_min) ) {
                $chkfile_size_min = $chkfile_size_max = $chkfile_size;
                $chkfile_case_min = $chkfile_case_max = $chkfile;
            }
            else {
                if ( $chkfile_size < $chkfile_size_min ) {
                    $chkfile_size_min = $chkfile_size;
                    $chkfile_case_min = $chkfile;
                }
                if ( $chkfile_size > $chkfile_size_max ) {
                    $chkfile_size_max = $chkfile_size;
                    $chkfile_case_max = $chkfile;
                }
            }
        }

        # do not delete the ofile yet if it did not come from the original
        my $do_not_delete = $ifile ne $ifile_original;

        # Set input file for next run
        $ifile = $ifile_original;
        if ( $case < 4 ) {
            $ifile = $ofile;
        }
        elsif ( $chain_mode && !$err ) {
	    # 'Chaining' means the next run formats the output of the previous
	    # run instead of formatting the original file.
            # 0 = no chaining
            # 1 = always chain unless error
            # 2 = random chaining

            if ( $chain_mode == 1 || int( rand(1) + 0.5 ) ) {
                { $ifile = $ofile }
            }
        }

        # do not delete the ofile if it is the input for the next run
        $do_not_delete ||= $ifile eq $ofile;

        if ( $rsetup->{delete_good_output} ) {

            # Files created this run
            my @created =
              ( $ofile, $chkfile, "LOG.$ext", "ERR.$ext", "$chkfile.ERR" );

            # keep history if there was an error
            if ($error_count_this_file) {
                @saved_for_deletion = ();
            }

            # postpone deletion if next file depends upon it
            elsif ($do_not_delete) {
                foreach (@created)
                { #( $ofile, $chkfile, "LOG.$ext", "ERR.$ext", "$chkfile.ERR" ) {
                    push @saved_for_deletion, $_;
                }
            }

            # otherwise, delete these files and the history
            else {
                foreach (@created) {
                    unlink $_ if ( -e $_ );
                    ##print STDERR "deleting $_\n";
                }
                foreach (@saved_for_deletion) {
                    unlink $_ if ( -e $_ );
                    ##print STDERR "deleting $_\n";
                }
                @saved_for_deletion = ();
                print STDERR "deleting $ofile, not needed\n";
            }
        }

        if ( -e $stop_file ) {
            print STDERR "$stop_file seen; exiting\n";
            last MAIN_LOOP;
        }

        # give up on a file if too many errors
        if ( $error_count_this_file > 2 ) {
            print STDERR
"**ERROR** Giving up on file $file, error count = $error_count_this_file\n";
            last;
        }
    }

    # Summary for one file run with all profiles
    $rsummary->[$file_count] = {
        input_original_name   => $ifile_original,
        input_size            => $ifile_size,
        error_count           => $error_count,
        efile_count           => $efile_count,
        missing_ofile_count   => $missing_ofile_count,
        missing_chkfile_count => $missing_chkfile_count,
        minimum_output_size   => $ofile_size_min,
        maximum_output_size   => $ofile_size_max,
        minimum_output_case   => $ofile_case_min,
        maximum_output_case   => $ofile_case_max,
        minimum_rerun_size    => $chkfile_size_min,
        maximum_rerun_size    => $chkfile_size_max,
        minimum_rerun_case    => $chkfile_case_min,
        maximum_rerun_case    => $chkfile_case_max,
        minimum_error_size    => $efile_size_min,
        maximum_error_size    => $efile_size_max,
        minimum_error_case    => $efile_case_min,
        maximum_error_case    => $efile_case_max,
    };

    report_results( $rsummary->[$file_count] );

    # Note if it looks like results for this file needs attention
    if (

        # check file had an error but not with defaults
        $error_count

        # There were missing output files
        || $missing_ofile_count

        # There were missing output files when rerun with defaults
        || $missing_chkfile_count

        # an output file had zero size
        || $ofile_size_min == 0

        # an output file had zero size when rerun with defaults
        || $chkfile_size_min == 0
      )
    {
        push @problems, $file_count;
    }  ## end inner loop over profiles
}  ## end outer loop over files

if (@saved_for_deletion) {
    foreach (@saved_for_deletion) {
        unlink $_ if ( -e $_ );
    }
    @saved_for_deletion = ();
}

# Summarize results..
if (@problems) {
    print STDERR <<EOM;

=============================
SUMMARY OF POSSIBLE PROBLEMS:
=============================
EOM

    foreach my $nf (@problems) {
        report_results( $rsummary->[$nf] );
    }
    if (@chkfile_errors) {
        local $" = ')(';
        my $num = @chkfile_errors;
        $num = 20 if ( $num > 20 );
        print STDERR <<EOM;
Some check files with errors (search above for '**ERROR'):
(@chkfile_errors[1..$num-1])
EOM
    }
    if (@size_errors) {
        local $" = ')(';
        my $num = @size_errors;
        $num = 20 if ( $num > 20 );
        print STDERR <<EOM;
Some files with definite size errors (search above for '**ERROR'):
(@size_errors[1..$num-1])
EOM
    }
    if (@syntax_errors) {
        local $" = ')(';
        my $num = @syntax_errors;
        $num = 20 if ( $num > 20 );
        print STDERR <<EOM;
Some files with definite size errors (search above for '**ERROR'):
(@syntax_errors[1..$num-1])
EOM
    }
}
else {
    print STDERR <<EOM;

========================
No obvious problems seen
========================
EOM

}

# Write a script to automate search for errors
write_runme();

# Write a restart file
my ($nf, $np);
if ( $case < $np_end ) {
    $nf = $file_count;
    $np = $case + 1;
    write_GO($nf, $np); 
}
elsif ( $file_count < $nf_end ) {
    $nf = $file_count + 1;
    $np = 1;
    write_GO($nf, $np); 
}

print STDERR <<EOM;
Next: run 'RUNME.pl' or do this by hand:
Look for lines longer than 80 characters
grep 'Thank you' and 'bug in perltidy' in all .ERR files
Search STDERR for 'uninitialized' and other warnings
EOM

sub report_results {

    my ($rh) = @_;

    my $ifile_original        = $rh->{input_original_name};
    my $ifile_size            = $rh->{input_size};
    my $error_count           = $rh->{error_count};
    my $efile_count           = $rh->{efile_count};
    my $missing_ofile_count   = $rh->{missing_ofile_count};
    my $missing_chkfile_count = $rh->{missing_chkfile_count};
    my $ofile_size_min        = $rh->{minimum_rerun_size};
    my $ofile_size_max        = $rh->{maximum_rerun_size};
    my $ofile_case_min        = $rh->{minimum_rerun_case};
    my $ofile_case_max        = $rh->{maximum_rerun_case};
    my $chkfile_size_min      = $rh->{minimum_output_size};
    my $chkfile_size_max      = $rh->{maximum_output_size};
    my $chkfile_case_min      = $rh->{minimum_output_case};
    my $chkfile_case_max      = $rh->{maximum_output_case};
    my $efile_size_min        = $rh->{minimum_error_size};
    my $efile_size_max        = $rh->{maximum_error_size};
    my $efile_case_min        = $rh->{minimum_error_case};
    my $efile_case_max        = $rh->{maximum_error_case};

    print STDERR <<EOM;
------------------------------------------------
Original input file: $ifile_original
ifile size : $ifile_size
$error_count files had errors when reformatted
$missing_ofile_count output files were missing 
$missing_chkfile_count check output files were missing
EOM

    print STDERR <<EOM if ( defined($ofile_size_min) );

Minimum output size: $ofile_size_min for case $ofile_case_min
Maximum output size: $ofile_size_max for case $ofile_case_max
EOM

    print STDERR <<EOM if ( defined($chkfile_size_min) );

Minimum rerun size: $chkfile_size_min for case $chkfile_case_min
Maximum rerun size: $chkfile_size_max for case $chkfile_case_max
EOM

    print STDERR <<EOM if ( defined($efile_size_min) );

Number of error files: $efile_count 
Minimum error file size: $efile_size_min for case $efile_case_min
Maximum error file size: $efile_size_max for case $efile_case_max
EOM
    return;
}

sub write_GO {

    my ($nf, $np) = @_;
    my $runme = "GO.sh";
    unlink $runme if (-e $runme);
    my $fh;
    open( $fh, '>', $runme ) || die "cannot open $runme: $!\n";
    $fh->print(<<EOM);
#!/bin/sh

# This script can run perltidy with random parameters
# usage: perltidy_random.sh file1 file2 ... N
# where N is the number of random cases
echo "Perltidy random run ..."
echo "NOTE: Create a file named 'stop.now' to force an early exit"
sleep 2
nohup nice -n19 perltidy_random_run.pl $nf.$np >>nohup.my 2>>nohup.my
EOM
    system("chmod +x $runme");
    print STDOUT "To restart, enter ./$runme\n";
}

sub write_runme {

    # Write a script RUNME.pl which can find problems in nohup.my
    my $runme = 'RUNME.pl';
    if ( open( RUN, '>', $runme ) ) {
        print RUN <<'EOM';
#!/usr/bin/perl -w
my $nohup = "nohup.my";
my $ofile = "nohup.my.err";
open( IN,  '<', $nohup ) || die "cannot open $nohup: $!\n";
open( OUT, '>', $ofile ) || die "cannot open $ofile: $!\n";
my $lno   = 0;
my $count = 0;
my @lines=<IN>;
my $nlines=@lines;
foreach my $line (@lines) {
    $lno++;
    if (   $line =~ /uninitialized/
        || $line =~ /A fault was/
        || length($line) > 80 )
    {

        # ignore last few lines
        next if ( $lno > $nlines - 4 );
        $count++;
        print OUT "$lno: $line";
        print STDERR "$lno: $line";
    }
}
close IN;
close OUT;
my $gfile="nohup.my.grep";
my $cmd1 = "grep 'Thank you' ERR.* >>$gfile";
my $cmd2 = "grep 'Thank you' *.ERR >>$gfile";
system ($cmd1);
system ($cmd2);
print STDERR "$count problems seen in $nohup\n";
if ($count) {
    print STDERR "please see $ofile\n";
}
if (-s $gfile) {
   print STDERR "please see $gfile\n";
}
EOM
        close RUN;
        system("chmod +x $runme");
        print "Wrote '$runme'\n";
        return;
    }
}

sub read_config {

    my ($ifile) = @_;
    $rsetup = undef;

    # be sure the file has correct perl syntax
    my $syntax_check = qx/perl -cw $ifile 2>&1/;
    if ( $syntax_check !~ /syntax OK/ ) {
        print STDERR <<EOM;
-----------------------------------
$syntax_check
-----------------------------------
The above syntax errors are in File '$ifile'
EOM
        die;
    }

    print STDOUT "$ifile:\n";

    # read the config file
    do $ifile;

    return;
}

sub read_list {
    my ($fname) = @_;
    my $rlist;

    # read a single column list of files
    # remove blank lines and comments
    my $fh;
    if ( !open( $fh, "<", $fname ) ) {
        query("Cannot open $fname: $!\n");
        return $rlist;
    }
    while ( my $line = <$fh> ) {
        $line         =~ s/^\s+//;
        $line         =~ s/\s+$//;
        next if $line =~ /^#/;
        push @{$rlist}, $line;
    }
    $fh->close();
    return $rlist;
}
