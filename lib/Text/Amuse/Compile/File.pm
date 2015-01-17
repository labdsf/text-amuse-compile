package Text::Amuse::Compile::File;

use strict;
use warnings;
use utf8;

# core
# use Data::Dumper;
use File::Copy qw/move/;
use Encode qw/decode_utf8/;

# needed
use Template::Tiny;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Copy;
use File::Spec;
use IO::Pipe;

# ours
use PDF::Imposition;
use Text::Amuse;
use Text::Amuse::Functions qw/muse_fast_scan_header/;

=encoding utf8

=head1 NAME

Text::Amuse::Compile::File - Object for file scheduled for compilation

=head1 SYNOPSIS

Everything here is pretty much private. It's used by
Text::Amuse::Compile in a forked and chdir'ed environment.

=head1 ACCESSORS AND METHODS

=head2 new(name => $basename, suffix => $suffix, templates => $templates)

Constructor. Accepts the following named parameters:

=over 4

=item name

=item virtual

If it's a virtual file which doesn't exit on the disk (a merged one)

=item suffix

=item templates

=item standalone

When set to true, the tex output will obey bcor and twoside/oneside.

=item options

An hashref with the options to pass to the templates. It's returned as
an hash, not as a reference, to protect it from mangling.

=back

=head1 INTERNALS

=over 4

=item is_deleted

=item status_file

=item check_status

=item purged_extensions

=item muse_file

=item document

The L<Text::Amuse> object

=item tt

The L<Template::Tiny> object

=item logger

The logger subroutine set in the constructor.

=item cleanup

Remove auxiliary files (like the complete file and the status file)

=back

=cut

sub new {
    my ($class, @args) = @_;
    die "Wrong number or args" if @args % 2;
    my $self = { @args };
    foreach my $k (qw/name suffix templates/) {
        die "Missing $k" unless $self->{$k};
    }
    bless $self, $class;
}

sub name {
    return shift->{name};
}

sub virtual {
    return shift->{virtual};
}

sub options {
    my $self = shift;
    my %out;
    if (my $ref = $self->{options}) {
        %out = %$ref;
    }
    # return a copy
    return { %out };
}

sub standalone {
    return shift->{standalone}
}

sub suffix {
    return shift->{suffix};
}

sub templates {
    return shift->{templates};
}

sub muse_file {
    my $self = shift;
    return $self->name . $self->suffix;
}

sub status_file {
    return shift->name . '.status';
}

sub is_deleted {
    return shift->{is_deleted};
}

sub _set_is_deleted {
    my $self = shift;
    $self->{is_deleted} = shift;
}

sub tt {
    my $self = shift;
    unless ($self->{tt}) {
        $self->{tt} = Template::Tiny->new;
    }
    return $self->{tt};
}

sub logger {
    return shift->{logger};
}

sub document {
    my $self = shift;
    # prevent parsing of deleted, bad file
    return if $self->is_deleted;
    # return Text::Amuse->new(file => $self->muse_file);

    # this implements caching. Does really makes sense? Maybe it's
    # better to have a fresh instance for each one. Speed is not an
    # issue. For a 4Mb document, it would take 4 seconds to produce
    # the output, and some minutes for LaTeXing.

    unless ($self->{document}) {
        my $doc = Text::Amuse->new(file => $self->muse_file);
        $self->{document} = $doc;
    }
    return $self->{document};
}

sub check_status {
    my $self = shift;
    my $deleted;
    # it could be virtual
    if (!$self->virtual) {
        my $header = muse_fast_scan_header($self->muse_file);
        $self->log_fatal("Not a muse file!") unless $header && %$header;
        $deleted = $header->{DELETED};
        # TODO maybe use storable?
    }
    $self->purge_all if $deleted;
    $self->_set_is_deleted($deleted);
}


=head2 purge_all

Remove all the output files related to basename

=head2 purge_latex

Remove files left by previous latex compilation

=head2 purge('.epub', ...)

Remove the files associated with this file, by extension.

=cut

sub purged_extensions {
    my $self = shift;
    my @exts = (qw/.pdf .a4.pdf .lt.pdf
                   .tex .log .aux .toc .ok
                   .html .bare.html .epub
                   .zip
                  /);
    return @exts;
}

sub purge {
    my ($self, @exts) = @_;
    my $basename = $self->name;
    foreach my $ext (@exts) {
        $self->log_fatal("wtf?") if ($ext eq '.muse');
        my $target = $basename . $ext;
        if (-f $target) {
            # $self->log_info("Removing $target\n");
            unlink $target or $self->log_fatal("Couldn't unlink $target $!");
        }
    }
}

sub purge_all {
    my $self = shift;
    $self->purge($self->purged_extensions);
}

sub purge_latex {
    my $self = shift;
    $self->purge(qw/.log .aux .toc .pdf/);
}



sub _write_file {
    my ($self, $target, @strings) = @_;
    open (my $fh, ">:encoding(utf-8)", $target)
      or $self->log_fatal("Couldn't open $target $!");

    print $fh @strings;

    close $fh or $self->log_fatal("Couldn't close $target");
    return;
}


=head1 METHODS

=head2 Formats

Emit the respective format, saving it in a file. Return value is
meaningless, but exceptions could be raised.

=over 4

=item html

=item bare_html

=item pdf

=item epub

=item lt_pdf

=item a4_pdf

=item zip

The zipped sources. Beware that if you don't call html or tex before
this, the attachments (if any) are ignored if both html and tex files
exist. Hence, the muse-compile.pl scripts forces the --tex and --html
switches.

=cut


sub html {
    my $self = shift;
    $self->purge('.html');
    my $outfile = $self->name . '.html';
    $self->_process_template($self->templates->html,
                             {
                              doc => $self->document,
                              css => ${ $self->templates->css },
                              options => $self->options,
                             },
                             $outfile);
}

sub bare_html {
    my $self = shift;
    $self->purge('.bare.html');
    my $outfile = $self->name . '.bare.html';
    $self->_process_template($self->templates->bare_html,
                             {
                              doc => $self->document,
                              options => $self->options,
                             },
                             $outfile);
}

sub a4_pdf {
    my $self = shift;
    $self->_compile_imposed('a4');
}

sub lt_pdf {
    my $self = shift;
    $self->_compile_imposed('lt');
}

sub _compile_imposed {
    my ($self, $size) = @_;
    $self->log_fatal("Missing size") unless $size;
    # the trick: first call tex with an argument, then pdf, then
    # impose, then rename.
    $self->tex(papersize => "half-$size");
    my $pdf = $self->pdf;
    my $outfile = $self->name . ".$size.pdf";
    if ($pdf) {
        my $imposer = PDF::Imposition->new(
                                           file => $pdf,
                                           schema => '2up',
                                           signature => '40-80',
                                           cover => 1,
                                           outfile => $outfile
                                          );
        $imposer->impose;
    }
    else {
        $self->log_fatal("PDF was not produced!");
    }
    return $outfile;
}


=item tex

This method is a bit tricky, because it's called with arguments
internally by C<lt_pdf> and C<a4_pdf>, and with no arguments before
C<pdf>.

With no arguments, this method enforces the options C<twoside=true>
and C<bcor=0mm>, effectively ignoring the global options which affect
the imposed output, unless C<standalone> is set to true.

This means that the twoside and binding correction options follow this
logic: if you have some imposed format, they are ignored for the
standalone PDF but applied for the imposed ones. If you have only
the standalone PDF, they are applied to it.

=back

=cut

sub tex {
    my ($self, @args) = @_;
    my $texfile = $self->name . '.tex';
    $self->log_fatal("Wrong usage") if @args % 2;
    my %arguments = @args;

    unless (scalar(@args) || $self->standalone) {
        %arguments = (
                      twoside => 0,
                      oneside => 1,
                      bcor    => '0mm',
                     );
    }

    my %params = %{ $self->options };
    # arguments can override the global options, so they don't mess up
    # too much when calling pdf-a4, for example. This will also
    # override twoside, oneside, bcor for default one.

    foreach my $k (keys %arguments) {
        $params{$k} = $arguments{$k};
    }

    $self->purge('.tex');
    $self->_process_template($self->templates->latex,
                             $self->_prepare_tex_tokens($self->document, %params),
                             $texfile);
}

sub pdf {
    my $self = shift;
    my $source = $self->name . '.tex';
    my $output = $self->name . '.pdf';
    unless (-f $source) {
        $self->tex;
    }
    $self->log_fatal("Missing source file $source!") unless -f $source;
    $self->purge_latex;
    # maybe a check on the toc if more runs are needed?
    # 1. create the toc
    # 2. insert the toc
    # 3. adjust the toc. Should be ok, right?
    foreach my $i (1..3) {
        my $pipe = IO::Pipe->new;
        # parent swallows the output
        $pipe->reader(xelatex => '-interaction=nonstopmode', $source);
        $pipe->autoflush(1);
        my $shitout;
        while (<$pipe>) {
            my $line = $_;
            if ($line =~ m/^[!#]/) {
                $shitout++;
            }
            if ($shitout) {
                $self->log_info($line);
            }
        }
        wait;
        my $exit_code = $? >> 8;
        if ($exit_code != 0) {
            $self->log_info("XeLaTeX compilation failed with exit code $exit_code\n");
            if (-f $self->name  . '.log') {
                # if we have a .pdf file, this means something was
                # produced. Hence, remove the .pdf
                unlink $self->name . '.pdf';
                $self->log_fatal("Bailing out\n");
            }
            else {
                $self->log_info("Skipping PDF generation\n");
                return;
            }
        }
    }
    $self->parse_tex_log_file;
    return $output;
}



sub zip {
    my $self = shift;
    $self->purge('.zip');
    my $zipname = $self->name . '.zip';
    my $tempdir = File::Temp->newdir;
    my $tempdirname = $tempdir->dirname;
    foreach my $todo (qw/tex html/) {
        my $target = $self->name . '.' . $todo;
        unless (-f $target) {
            $self->$todo;
        }
        $self->log_fatal("Couldn't produce $target") unless -f $target;
        copy($target, $tempdirname)
          or $self->log_fatal("Couldn't copy $target in $tempdirname $!");
    }
    copy ($self->name . '.muse', $tempdirname);

    my $text = $self->document;
    foreach my $attach ($text->attachments) {
        copy($attach, $tempdirname)
          or $self->log_fatal("Couldn't copy $attach to $tempdirname $!");
    }
    my $zip = Archive::Zip->new;
    $zip->addTree($tempdirname, $self->name) == AZ_OK
      or $self->log_fatal("Failure zipping $tempdirname");
    $zip->writeToFileNamed($zipname) == AZ_OK
      or $self->log_fatal("Failure writing $zipname");
    return $zipname;
}


sub epub {
    my $self = shift;
    $self->purge('.epub');
    my $epubname = $self->name . '.epub';

    my $text = $self->document;

    my @pieces = $text->as_splat_html;
    my @toc = $text->raw_html_toc;
    my $missing = scalar(@pieces) - scalar(@toc);
    # this shouldn't happen

    # print Dumper(\@toc);

    if ($missing > 1 or $missing < 0) {
        $self->log_info(Dumper(\@pieces), Dumper(\@toc));
        $self->log_fatal("This shouldn't happen: missing pieces: $missing");
    }
    elsif ($missing == 1) {
        unshift @toc, {
                       index => 0,
                       level => 0,
                       string => "start body",
                      };
    }
    require EBook::EPUB;
    my $epub = EBook::EPUB->new;

    # embedded CSS
    $epub->add_stylesheet("stylesheet.css" => ${ $self->templates->css });

    # build the title page and some metadata
    my $header = $text->header_as_html;

    my $titlepage = '';

    if ($text->header_defined->{author}) {
        my $author = $header->{author};
        $epub->add_author($self->_clean_html($author));
        $titlepage .= "<h2>$author</h2>\n";
    }

    if ($text->header_defined->{title}) {
        my $t = $header->{title};
        $epub->add_title($self->_clean_html($t));
        $titlepage .= "<h1>$t</h1>\n";
    }
    else {
        $epub->add_title('Untitled');
    }

    if ($text->header_defined->{subtitle}) {
        my $st = $header->{subtitle};
        $titlepage .= "<h2>$st</h2>\n"
    }
    if ($text->header_defined->{date}) {
        if ($header->{date} =~ m/([0-9]{4})/) {
            $epub->add_date($1);
        }
        $titlepage .= "<h3>$header->{date}</h3>"
    }

    $epub->add_language($text->language_code);

    if ($text->header_defined->{source}) {
        my $source = $header->{source};
        $epub->add_source($self->_clean_html($source));
        $titlepage .= "<p>$source</p>";
    }

    if ($text->header_defined->{notes}) {
        my $notes = $header->{notes};
        $epub->add_description($self->_clean_html($notes));
        $titlepage .= "<p>$notes</p>";
    }

    # create the front page
    my $firstpage = '';
    $self->tt->process($self->templates->minimal_html,
                       {
                        title => $self->_remove_tags($header->{title}),
                        text => $titlepage,
                        options => $self->options,
                       },
                       \$firstpage)
      or $self->log_fatal($self->tt->error);

    my $tpid = $epub->add_xhtml("titlepage.xhtml", $firstpage);
    my $order = 0;
    $epub->add_navpoint(label => "titlepage",
                        id => $tpid,
                        content => "titlepage.xhtml",
                        play_order => ++$order);

    # main loop
    while (@pieces) {
        my $fi =    shift @pieces;
        my $index = shift @toc;
        my $xhtml = "";
        # print Dumper($index);
        my $filename = "piece" . $index->{index} . '.xhtml';
        my $title = $index->{level} . " " . $index->{string};

        $self->tt->process($self->templates->minimal_html,
                           {
                            title => $self->_remove_tags($title),
                            options => $self->options,
                            text => $fi,
                           },
                           \$xhtml)
          or $self->log_fatal($self->tt->error);

        my $id = $epub->add_xhtml($filename, $xhtml);

        $epub->add_navpoint(label => $self->_clean_html($index->{string}),
                            content => $filename,
                            id => $id,
                            play_order => ++$order);
    }

    # attachments
    foreach my $att ($text->attachments) {
        $self->log_fatal("$att doesn't exist!") unless -f $att;
        my $mime;
        if ($att =~ m/\.jpe?g$/) {
            $mime = "image/jpeg";
        }
        elsif ($att =~ m/\.png$/) {
            $mime = "image/png";
        }
        else {
            $self->log_fatal("Unrecognized attachment $att!");
        }
        $epub->copy_file($att, $att, $mime);
    }

    # finish
    $epub->pack_zip($epubname);
    return $epubname;
}

sub _remove_tags {
    my ($self, $string) = @_;
    return "" unless defined $string;
    $string =~ s/<.+?>//g;
    return $string;
}

sub _clean_html {
    my ($self, $string) = @_;
    return "" unless defined $string;
    $string =~ s/<.+?>//g;
    $string =~ s/&lt;/</g;
    $string =~ s/&gt;/>/g;
    $string =~ s/&quot;/"/g;
    $string =~ s/&#x27;/'/g;
    $string =~ s/&amp;/&/g;
    return $string;
}

=head2 Logging

While the C<logger> accessor holds a reference to a sub, but could be
very well be empty, the object uses these two methods:

=over 4

=item log_info(@strings)

If C<logger> exists, it will call it passing the strings as arguments.
Otherwise print to the standard output.

=item log_fatal(@strings)

Calls C<log_info>, remove the lock and dies.

=item parse_tex_log_file

(Internal) Parse the produced logfile for missing characters.

=back

=cut

sub log_info {
    my ($self, @info) = @_;
    my $logger = $self->logger;
    if ($logger) {
        $logger->(@info);
    }
    else {
        print @info;
    }
}

sub log_fatal {
    my ($self, @info) = @_;
    $self->log_info(@info);
    die "Fatal exception\n";
}

sub parse_tex_log_file {
    my $self = shift;
    my $logfile = $self->name . '.log';
    if (-f $logfile) {
        # if you're wandering why we open this in raw mode: The log
        # file produced by XeLaTeX is utf8, but it splits the output
        # at 80 bytes or so. This of course sometimes, expecially
        # working with cyrillic scripts, cut the multibyte character
        # in half, producing invalid utf8 octects.
        open (my $fh, '<:raw', $logfile)
          or $self->log_fatal("Couldn't open $logfile $!");
        while (my $line = <$fh>) {
            if ($line =~ m/^missing character/i) {
                chomp $line;
                # if we get the warning, nothing we can do about it,
                # but shouldn't happen.
                $self->log_info(decode_utf8($line) . "...\n");
            }
        }
        close $fh;
    }
}

sub cleanup {
    my $self = shift;
    if (my $f = $self->status_file) {
        if (-f $f) {
            unlink $f or $self->log_fatal("Couldn't unlink $f $!");
        }
        else {
            $self->log_info("Couldn't find " . File::Spec->rel2abs($f));
        }
    }
}

sub _process_template {
    my ($self, $template_ref, $tokens, $outfile) = @_;
    eval {
        my $out = '';
        die "Wrong usage" unless ($template_ref && $tokens && $outfile);
        $self->tt->process($template_ref, $tokens, \$out);
        open (my $fh, '>:encoding(UTF-8)', $outfile) or die "Couldn't open $outfile $!";
        print $fh $out, "\n";
        close $fh;
    };
    if ($@) {
        $self->log_fatal("Error processing template for $outfile: $@");
    };
    return $outfile;
}


# method for options to pass to the tex template
sub _prepare_tex_tokens {
    my ($self, $doc, %tokens) = @_;

    # defaults
    my %parsed = (
                  papersize => '210mm:11in', # the generic
                  class => 'scrbook',
                  division => 12,
                  fontsize => 10,
                  mainfont => 'Linux Libertine O',
                  paging => 'oneside',
                  bcor => '0mm',
                  cover => '',
                  coverwidth => 1,
                 );

    my $tex_measure = qr{[0-9]+(\.[0-9]+)?(cm|mm|in|pt)};

    # paper size parsing
    if (my $size = $tokens{papersize}) {
        my %sizes = (
                     'half-a4' => 'a5',
                     'half-lt' => '5.5in:8.5in',
                     generic => '210mm:11in',
                     a4 => 'a4',
                     a5 => 'a5',
                     a6 => 'a6',
                     letter => 'letter',
                    );
        if (my $real_size = $sizes{$size}) {
            $parsed{papersize} = $real_size;
        }
        elsif ($size =~ m/($tex_measure:$tex_measure)/) {
            $parsed{papersize} = $1;
        }
        else {
            warn "Unrecognized paper size $size, usign the default\n";
        }
    }

    # no cover page
    unless ($doc->wants_toc) {
        if ($doc->header_as_latex->{nocoverpage} || $tokens{nocoverpage}) {
            $parsed{nocoverpage} = 1;
            $parsed{class} = 'scrartcl';
        }
    }
    # division
    if (my $div = $tokens{division}) {
        my %divs = map { $_ => 1 } (9..15);
        if ($divs{$div}) {
            $parsed{division} = $div;
        }
        else {
            warn "Bad value for division: $div\n";
        }
    }
    # fontsize
    if (my $fontsize = $tokens{fontsize}) {
        my %sizes = map { $_ => 1 } (9..12);
        if ($sizes{$fontsize}) {
            $parsed{fontsize} = $fontsize;
        }
    }
    if ($tokens{mainfont}) {
        # just copy it over, we can't know which fonts we have
        # installed.
        $parsed{mainfont} = $tokens{mainfont};
    }

    # oneside or twoside
    if ($tokens{oneside} && $tokens{twoside}) {
        warn "Passed oneside and twoside at the same time, using oneside (default)\n";
    }
    elsif ($tokens{oneside}) {
        $parsed{paging} = 'oneside';
    }
    elsif ($tokens{twoside}) {
        $parsed{paging} = 'twoside';
    }

    # bcor
    if ($tokens{bcor}) {
        if ($tokens{bcor} =~ m/($tex_measure)/) {
            $parsed{bcor} = $1;
        }
    }

    return {
            options => \%tokens,
            safe_options => \%parsed,
            doc => $doc,
           };
}

1;
