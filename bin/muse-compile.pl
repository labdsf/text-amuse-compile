#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use Getopt::Long;
use Data::Dumper;
use Text::Amuse::Compile;
use File::Path qw/mkpath/;
use File::Spec::Functions qw/catfile/;
use Pod::Usage;
use Text::Amuse::Compile::Utils qw/append_file/;
use Text::Amuse::Compile::TemplateOptions;
use Encode;

binmode STDOUT, ':encoding(utf-8)';
binmode STDERR, ':encoding(utf-8)';

my %options;
GetOptions (\%options,
            qw/epub
               html
               bare-html
               a4-pdf
               lt-pdf
               tex
               sl-tex
               slides
               pdf
               zip
               ttdir=s
               fontspec=s
               webfontsdir=s
               output-templates
               log=s
               extra=s%
               no-cleanup
               recursive=s
               dry-run
               luatex
               version
               verbose
               purge
               help/) or die "Bad option passed!\n";

if ($options{help}) {
    pod2usage({ -exitval => 'NOEXIT' });
    if ($options{verbose}) {
        Text::Amuse::Compile::TemplateOptions->show_options;
    }
    exit 2;
}
if ($options{version}) {
    print Text::Amuse::Compile->version;
    exit 0;
}


=encoding utf8

=head1 NAME

muse-compile.pl - format your muse document using Text::Amuse

=head1 SYNOPSIS

  muse-compile.pl [ options ] file1.muse [ file2.muse  , .... ]

This program uses Text::Amuse to produce usable output in HTML, EPUB,
LaTeX and PDF format.

By default, all formats will be generated. You can specify which
format you want using one or more of the following options:

=over 4

=item --html

Full HTML output.

=item --epub

Full EPUB output.

=item --bare-html

HTML body alone (wrapped in a C<div> tag)

=item --tex

LaTeX output

=item --zip

Pack the tex, the source and the html with the attachments in a zip
file.

=item --pdf

PDF output.

=item --slides

PDF output. Extension is .sl.pdf and it is a Beamer PDF. File .sl.tex
is left in place.

Please note that the muse file must say that the slides are required.
The header for that is C<#slides> set to a value other than empty,
C<0>, C<no>, C<false>.

=item --sl-tex

Produce the beamer LaTeX file, using the same rule above.

=item --a4-pdf

PDF imposed on A4 paper, with a variable signature in the range of 40-80

=item --lt-pdf

As above, but on Letter paper.

=item --ttdir

The directory with the templates. Optional and somehow discouraged for
normal usage.

=item --webfontsdir

For EPUB output, embed the fonts in that directory.

In this directory the program expects to find 4 fonts, a regular, an
italic, a bold and a bold italic one. Given that the names are
arbitrary, we need an hint. For this you have to provide a file, in
the very same directory, with the specifications. The file B<must> be
named C<spec.txt> and need the following content:

E.g., for Droid fonts:

  family Droid Serif
  regular DroidSerif-Regular.ttf
  italic DroidSerif-Italic.ttf
  bold DroidSerif-Bold.ttf
  bolditalic DroidSerif-Bold.ttf
  size 10

The four TTF files must be placed in this directory as well. The
formats supported are TTF, OTF and WOFF.

The C<family> and C<size> specs are optional.

=item --output-templates

Option to populated the above directory with the built-in templates.

=item --log <file>

A file where we can append the report failures

=item --no-cleanup

Prevent the removing of the status file. This is turned on if you use
--recursive, to prevent multiple runs to compile everything again.

=item --extra key:value

This option can be repeated at will. The key/value pairs will be
passed to every template we process, regardless of the type, even if
only the built-in LaTeX template support them.

The input is assumed to be UTF-8 (if you pass non-ascii characters).
The values, before being passed to the templates, are interpreted as
L<Text::Amuse> strings. This normally doesn't have any side effects
for simple strings, while for text this has the sane behaviour to
escape special characters and to permit inline markup.

Example:

  muse-compile.pl --extra site=http://anarhija.net \
                  --extra papersize=a6 --extra division=15 --extra twoside=true \
                  --extra bcor=10mm --extra mainfont="Charis SIL" \
                  --extra sitename="Testsite" \
                  --extra siteslogan="Anticopyright" \
                  --extra logo=mylogo \
                  --extra cover=mycover.pdf \
                  --extra opening=any \
                  file.muse

See muse-compile.pl --help --verbose for the full description of
meaning of these options.

=item --recursive <directory>

Using this options, the target directory and a recursive compiling is
started, finding all the .muse files without a newer status file, and
compiling them accordingly to the options.

No target files can be specified.

=item --dry-run

For recursive compile, you can pass this option to just list the files
which would be compiled.

=item --luatex

Use lualatex instead of xelatex.

=item --purge

Purge old files before compiling. Not supported for recursive compilation.

=back

=cut

my %args;

my $output_templates = delete $options{'output-templates'};
my $logfile = delete $options{log};
my $purge = delete $options{purge};

if ($options{extra}) {
    my $extras = delete $options{extra};
    foreach my $k (keys %$extras) {
        $extras->{$k} = decode('utf-8', $extras->{$k});
    }
    # also handle the booleans here
    foreach my $boolean (qw/oneside twoside nocoverpage
                            notoc/) {
        if (exists $extras->{$boolean}) {
            if ($extras->{$boolean} and
                $extras->{$boolean} !~ m/^(no|false)$/i) {
                $extras->{$boolean} = 1;
            }
            else {
                $extras->{$boolean} = 0;
            }
        }
    }
    $args{extra} = $extras;
}

# manage some dependencies

if ($options{zip}) {
    $options{tex} = $options{html} = 1;
}

if ($options{pdf}) {
    $options{tex} = 1;
}

my $recursive  = delete $options{recursive};
my $cleanup = 1;
my $dry_run = delete $options{'dry-run'};

if ($dry_run && !$recursive) {
    die "dry-run is supported only for recursive compile\n";
}


if (delete($options{'no-cleanup'}) || $recursive) {
    $cleanup = 0;
}

foreach my $k (keys %options) {
    my $newk = $k;
    $newk =~ s/-/_/g;
    $args{$newk} = $options{$k};
}


if ($output_templates and exists $options{ttdir}) {
    if (! -d $options{ttdir}) {
        mkpath($options{ttdir}) or die "Couldn't create $options{ttdir} $!";
    }
}

my $compiler = Text::Amuse::Compile->new(%args, cleanup => $cleanup);

$compiler->report_failure_sub(sub {
                                  print "Failure to compile $_[0]\n";
                              });

if ($logfile) {
    if ($logfile !~ m/\.log$/) {
        warn "Appending log to $logfile\n";
    }
    print "Logging output in $logfile\n";
    $compiler->logger(sub { print @_; append_file($logfile, @_ ) });
}

print $compiler->version;

if ($output_templates) {
    my $viewdir = $compiler->templates->ttdir;
    if (defined $viewdir) {
        foreach my $template ($compiler->templates->names) {
            my $target = catfile($viewdir, $template . '.tt');
            if (-f $target) {
                warn "Refusing to overwrite $target\n";
            }
            else {
                warn "Creating $target\n";
                open (my $fh, '>:encoding(utf-8)', $target)
                  or die "Couldn't open $target $!";
                print $fh ${ $compiler->templates->$template };
                close $fh or die "Couldn't close $target $!";
            }
        }
    }
    else {
        warn "You didn't specify a directory for the templates! Ignoring\n";
    }
}

if ($recursive) {
    die "Too many arguments passed with compile!" if @ARGV;
    die "$recursive is not a directory" unless -d $recursive;
    print "Starting recursive compilation against $recursive\n";
    my @results;
    if ($dry_run) {
        @results = $compiler->find_new_muse_files($recursive);
        print "[dry-run mode, nothing will be done]\n";
    }
    else {
        @results = $compiler->recursive_compile($recursive);
    }
    if (@results) {
        print "Found and compiled the following files:\n"
          . join("\n", @results) . "\n";
    }
    else {
        print "Nothing to do\n";
    }
}
else {
    $compiler->purge(@ARGV) if $purge;
    $compiler->compile(@ARGV);
}

if (@{$compiler->errors}) {
    $logfile ||= "above";
    die "Compilation finished with errors, see $logfile!\n";
}
