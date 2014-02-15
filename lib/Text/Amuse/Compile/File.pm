package Text::Amuse::Compile::File;

use strict;
use warnings;
use utf8;

# core
# use Data::Dumper;
use File::Copy qw/move/;

# needed
use Template;
use EBook::EPUB;

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

Constructor.

=head1 INTERNALS

=over 4

=item name

=item suffix

=item templates

=item is_deleted

=item complete_file

=item mark_as_closed

=item mark_as_open

=item purged_extensions

=item lockfile

=item muse_file

=item document

The L<Text::Amuse> object

=item tt

The L<Template> object

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

sub suffix {
    return shift->{suffix};
}

sub templates {
    return shift->{templates};
}

sub lockfile {
    return shift->name . '.lock';
}

sub muse_file {
    my $self = shift;
    return $self->name . $self->suffix;
}

sub complete_file {
    return shift->name . '.ok';
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
        $self->{tt} = Template->new;
    }
    return $self->{tt};
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

sub mark_as_open {
    my $self = shift;
    my $lockfile = $self->lockfile;
    if ($self->_lock_is_valid) {
        warn "Locked: $lockfile\n";
        return 0;
    }
    else {
        my $header = muse_fast_scan_header($self->muse_file);
        die "Not a muse file!" unless $header && %$header;
        # TODO maybe use storable?
        $self->_write_file($lockfile, $$ . ' ' . localtime . "\n");
        $self->_set_is_deleted($header->{DELETED});
        if ($self->is_deleted) {
            $self->purge_all;
        }
        return 1;
    }
}

sub mark_as_closed {
    my $self = shift;
    my $lockfile = $self->lockfile;
    unlink $lockfile or die "Couldn't unlink $lockfile!";
    # TODO maybe use storable?
    $self->_write_file($self->complete_file, $$ . ' ' . localtime . "\n");
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
                   .html .bare.html .epub/);
    return @exts;
}

sub purge {
    my ($self, @exts) = @_;
    my $basename = $self->name;
    foreach my $ext (@exts) {
        die "wtf?" if ($ext eq '.muse');
        my $target = $basename . $ext;
        if (-f $target) {
            # warn "Removing $target\n";
            unlink $target or die "Couldn't unlink $target $!";
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
      or die "Couldn't open $target $!";

    print $fh @strings;

    close $fh or die "Couldn't close $target";
    return;
}

sub _lock_is_valid {
    my $self = shift;
    my $lockfile = $self->lockfile;
    return unless -f $lockfile;
    # TODO use storable instead
    open (my $fh, '<', $lockfile) or die $!;
    my $pid;
    my $string = <$fh>;
    if ($string =~ m/^(\d+)/) {
        $pid = $1;
    }
    else {
        die "Bad lockfile!\n";
    }
    close $fh;
    return unless $pid;
    if (kill 0, $pid) {
        return 1;
    }
    else {
        return;
    }
}

=head1 METHODS

Emit the respective format, saving it in a file. Return value is
meaningless, but exceptions could be raised.

=head2 html

=head2 bare_html

=head2 tex

=head2 pdf

=head2 epub

=cut

sub html {
    my $self = shift;
    $self->purge('.html');
    $self->tt->process($self->templates->html,
                       {
                        doc => $self->document,
                        css => ${ $self->templates->css },
                       },
                       $self->name . '.html',
                       { binmode => ':encoding(utf-8)' })
      or die $self->tt->error;

}

sub bare_html {
    my $self = shift;
    $self->purge('.bare.html');
    $self->tt->process($self->templates->bare_html,
                       {
                        doc => $self->document,
                       },
                       $self->name . '.bare.html',
                       { binmode => ':encoding(utf-8)' })
      or die $self->tt->error;
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
    die "Missing size" unless $size;
    # the trick: first call tex with an argument, then pdf, then
    # impose, then rename.
    $self->tex(size => "half-$size");
    my $pdf = $self->pdf;
    if ($pdf) {
        my $outfile = $self->name . ".$size.pdf";
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
        die "PDF was not produced!";
    }
}


sub tex {
    my ($self, @args) = @_;
    die "Wrong usage" if @args % 2;
    unless (@args) {
        @args = (size => 'default');
    }
    $self->purge('.tex');
    $self->tt->process($self->templates->latex,
                       {
                        doc => $self->document,
                        @args,
                       },
                       $self->name . '.tex',
                       { binmode => ':encoding(utf-8)' })
      or die $self->tt->error;
}

sub pdf {
    my $self = shift;
    my $source = $self->name . '.tex';
    my $output = $self->name . '.pdf';
    unless (-f $source) {
        $self->tex;
    }
    die "Missing source file $source!" unless -f $source;
    $self->purge_latex;
    # maybe a check on the toc if more runs are needed?
    # 1. create the toc
    # 2. insert the toc
    # 3. adjust the toc. Should be ok, right?
    for (1..3) {
        my $pid = open(my $kid, "-|");
        defined $pid or die "Can't fork: $!";

        # parent swallows the output
        if ($pid) {
            my $shitout;
            while (<$kid>) {
                my $line = $_;
                if ($line =~ m/^[!#]/) {
                    $shitout++;
                }
                if ($shitout) {
                    print $line;
                }
            }
            close $kid or warn "Compilation failed\n";
            my $exit_code = $? >> 8;
            if ($exit_code != 0) {
                warn "XeLaTeX compilation failed with exit code $exit_code\n";
                if (-f $self->name  . '.log') {
                    # if we have a .log file, this means something was
                    # produced. Hence, remove the .pdf
                    unlink $self->name . '.pdf';
                    die "Bailing out!";
                }
                else {
                    warn "Skipping PDF generation\n";
                    return;
                }
            }
        }
        else {
            open(STDERR, ">&STDOUT");
            exec(xelatex => '-interaction=nonstopmode', $source)
              or die "Can't exec xelatex $source $!";
        }
    }
    return $output;
}

sub epub {
    my $self = shift;
    $self->purge('.epub');
    my $epubname = $self->name . '.epub';
    unlink $epubname if -f $epubname;

    my $text = $self->document;

    my @pieces = $text->as_splat_html;
    my @toc = $text->raw_html_toc;
    my $missing = scalar(@pieces) - scalar(@toc);
    # this shouldn't happen

    # print Dumper(\@toc);

    if ($missing > 1 or $missing < 0) {
        print Dumper(\@pieces), Dumper(\@toc);
        die "This shouldn't happen: missing pieces: $missing";
    }
    elsif ($missing == 1) {
        unshift @toc, {
                       index => 0,
                       level => 0,
                       string => "start body",
                      };
    }
    my $epub = EBook::EPUB->new;

    # embedded CSS
    $epub->add_stylesheet("stylesheet.css" => ${ $self->templates->css });

    # build the title page and some metadata
    my $header = $text->header_as_html;

    my $titlepage = '';

    if (my $author = $header->{author}) {
        $epub->add_author($self->_clean_html($author));
        $titlepage .= "<h2>$author</h2>\n";
    }

    if (my $t = $header->{title}) {
        $epub->add_title($self->_clean_html($t));
        $titlepage .= "<h1>$t</h1>\n";
    }
    else {
        $epub->add_title('Untitled');
    }

    if (my $st = $header->{subtitle}) {
        $titlepage .= "<h2>$st</h2>\n"
    }

    if ($header->{date}) {
        if ($header->{date} =~ m/([0-9]{4})/) {
            $epub->add_date($1);
            $titlepage .= "<h3>$header->{date}</h3>"
        }
    }

    $epub->add_language($text->language_code);

    if (my $source = $header->{source}) {
        $epub->add_source($self->_clean_html($source));
        $titlepage .= "<p>$source</p>";
    }

    if (my $notes = $header->{notes}) {
        $epub->add_description($self->_clean_html($notes));
        $titlepage .= "<p>$notes</p>";
    }

    # create the front page
    my $firstpage = '';
    $self->tt->process($self->templates->minimal_html,
                       {
                        title => $self->_clean_html($header->{title}),
                        text => $titlepage
                       },
                       \$firstpage)
      or die $self->tt->error;

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
                            text => $fi,
                           },
                           \$xhtml)
          or die $self->tt->error;

        my $id = $epub->add_xhtml($filename, $xhtml);

        $epub->add_navpoint(label => $self->_clean_html($index->{string}),
                            content => $filename,
                            id => $id,
                            play_order => ++$order);
    }

    # attachments
    foreach my $att ($text->attachments) {
        die "$att doesn't exist!" unless -f $att;
        my $mime;
        if ($att =~ m/\.jpe?g$/) {
            $mime = "image/jpeg";
        }
        elsif ($att =~ m/\.png$/) {
            $mime = "image/png";
        }
        else {
            die "Unrecognized attachment $att!";
        }
        $epub->copy_file($att, $att, $mime);
    }

    # finish
    $epub->pack_zip($epubname);
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




1;
