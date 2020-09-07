#!/usr/bin/perl -w
use strict;
use warnings;

# This is a script which can try to fix a formatting problem which could have
# been introduced by perltidy if certain versions of perltidy were run with the
# particular parameter combination -scbb -csc.  

# The problem occurred in versions 20200110, 20200619, and 20200822 when the
# parameter combination -scbb -csc was used.  

# This seems to be a fairly rare combination but could certainly happen.  The
# problem was found during random testing of perltidy.  It is fixed in the latest
# version.

# What happened is that two consecutive lines which had closing braces
# and side comments generated by the -csc parameter were missing a
# separating newline.  So for example the following two lines:

#   } ## end if (...
# } ## end while (<STYLES>...

# were actually combined like this:
#   } ## end if (...} ## end while (<STYLES>...

# If this happened to your script you could insert the line breaks by hand.  An
# alternative is to run this script on the bad file. It runs as a filter and
# looks for the special patterns and inserts the missing newlines.

# This will probably work on a script which has just been run once with these
# parameters. But it will probably not work if the script has been reformatted
# with these parameters multiple times, or if iterations have been done.
# Unfortunately in that case key comment information will have been lost.

# The script can be modified if a special side comment prefix other than '##
# end' was used.

# usage:
#   fix-scbb-csc-bug.pl <infile >ofile

# This is what we are looking for: a closing brace followed by csc prefix
my $pattern = '} ## end';

while ( my $line = <> ) {
    chomp $line;

    if ( $line && $line =~ /$pattern/ ) {

        my $leading_spaces = "";
        my $text;
        if ( $line =~ /^(\s*)(.*)$/ ) { $leading_spaces = $1; $text = $2 }
        my @parts = split /$pattern/, $text;

        # just print the line for an exact match
        if ( !@parts ) { print $line, "\n"; next }

        my $csc     = "";
        my $braces  = "";
        my @lines;
        while ( @parts > 1 ) {

            # Start at the end and work back, saving lines in @lines
            # If we see something with trailing braces, like } ## end }}
            # then we will break before the trailing braces.
            my $part = pop(@parts);
            $csc    = $part;
            $braces = "";

            # it's easiest to reverse the string, match multiple braces, and
            # reverse again
            my $rev = reverse $part;
            if ( $rev =~ /^([\}\s]+)(.*)$/ ) {
                $csc    = reverse $2;
                $braces = reverse $1;
            }
            push @lines, $pattern . $csc;
            push @lines, $braces if ($braces);
        }

        # The first section needs leading whitespace
        if (@parts) {
            my $part = pop(@parts);
            if ($part) {
                my $line = $leading_spaces . $part;
                push @lines, $line;
            }
            elsif (@lines) {
                my $i = -1;
                if ($braces) { $i = -2 }
                $lines[$i] = $leading_spaces . $lines[$i];
            }
        }
        while ( my $line = shift @lines ) {
            print $line . "\n";
        }
        next;
    }
    print $line. "\n";
}