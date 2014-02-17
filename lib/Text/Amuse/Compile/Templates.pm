package Text::Amuse::Compile::Templates;

use 5.010001;
use strict;
use warnings FATAL => 'all';
use utf8;

use File::Spec::Functions qw/catfile/;

=head1 NAME

Text::Amuse::Compile::Templates - Built-in templates for Text::Amuse::Compile

=head1 METHODS

=head2 new(ttdir => 'mytemplates')

Costructor. Options:

=over 4

=item ttdir

The directory where to search for templates.

B<Disclaimer>: some things are needed for a correct
layout/compilation. It's strongly reccomended to use the existing one
(known to work as expected) as starting point for a custom template.

=back

=head2 TEMPLATES

The following methods return a B<reference> to a scalar with the
templates. It should be self-evident which kind of template they
return.

=over 4

=item html

=item css

(not actually a template, it's the default CSS).

=item bare_html

The HTML fragment with the B<body> of the text (no HTML headers, no
Muse headers).

=item minimal_html

Minimal (but valid) XHTML template, with a link to C<stylesheet.css>.
Meant to be used in the EPUB generation.

=item latex

The LaTeX template, with dimension conditional.

=back

=head2 INTERNALS

=head3 ttref($name)

Return the scalar ref associated to the given template file, if any.

=head3 names

Return the list of methods for template generation

=cut


sub new {
    my ($class, @args) = @_;
    die "Wrong usage" if @args % 2;
    my %params = @args;
    my $self = {};

    # argument parsing
    foreach my $k (qw/ttdir/) {
        if (exists $params{$k}) {
            $self->{$k} = delete $params{$k};
        }
    }
    die "Unrecognized options: " . join(" ", keys %params) if %params;

    $self->{tt_subrefs} = {};
    if (exists $self->{ttdir} and defined $self->{ttdir}) {

        if (-d $self->{ttdir}) {
            my $dir = $self->{ttdir};
            opendir (my $dh, $dir) or die "Couldn't open $dir $!";
            my @templates = grep { -f catfile($dir, $_) 
                                    and
                                       /^(((bare|minimal)[_.-])?html|
                                            latex|css)
                                        (\.tt2?)?/x
                               } readdir($dh);
            closedir $dh;

            foreach my $t (@templates) {
                my $target = catfile($dir, $t); 
                open (my $fh, '<:encoding(utf-8)', $target)
                  or die "Can't open $target $!";
                local $/ = undef;
                my $content = <$fh>;
                close $fh;

                # manipulate the subref name
                $t =~ s/\.(tt|tt2)//;
                $t =~ s/\./_/g;

                # populate the object with closures.
                $self->{tt_subrefs}->{$t} = sub {
                    # copy the content, otherwise we return
                    # a ref that can be modified
                    my $string = $content;
                    return \$string;
                };
            }
        }
        else {
            die "$self->{ttdir} is not a directory!\n";
        }
    }
    bless $self, $class;
}

sub ttdir {
    return shift->{ttdir};
}

sub names {
    return (qw/html minimal_html bare_html
               css latex
              /);
}

sub ttref {
    my ($self, $name) = @_;
    return unless $name;
    if (exists $self->{tt_subrefs}->{$name}) {
        return $self->{tt_subrefs}->{$name}->();
    }
    return;
}

sub html {
    my $self = shift;
    if (my $ref = $self->ttref('html')) {
        return $ref;
    }
    my $html = <<'EOF';
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
  <meta http-equiv="Content-type" content="application/xhtml+xml; charset=UTF-8" />
  <title>[% doc.header_as_html.title %]</title>
  <style type="text/css">
 <!--/*--><![CDATA[/*><!--*/
[% css %]
  /*]]>*/-->
    </style>
</head>
<body>
 <div id="page">
  [% IF doc.header_as_html.author.length %]
  <h2>[% doc.header_as_html.author %]</h2>
  [% END %]
  <h1>[% doc.header_as_html.title %]</h1>

  [% IF doc.header_as_html.subtitle.length %]
  <h2>[% doc.header_as_html.subtitle %]</h2>
  [% END  %]

  [% IF doc.toc_as_html %]
  <div class="header">
  [% doc.toc_as_html %]
  </div>
  [% END %]

 <div id="thework">

[% doc.as_html %]

 </div>

  <hr />
  <div id="impressum">
    <div id="source">
    [% IF doc.header_as_html.source.length %]
    [% doc.header_as_html.source %]
    [% END %]
    </div>

    <div id="notes">
    [% IF doc.header_as_html.notes.length %]
    [% doc.header_as_html.notes %]
    [% END %]
    </div>
  </div>


</div>
</body>
</html>

EOF
    return \$html;
}

sub css {
    my $self = shift;
    if (my $ref = $self->ttref('css')) {
        return $ref;
    }
        my $css = <<'EOF';
/* This is not a template, just a static file! */
html,body {
	margin:0;
	padding:0;
	border: none;
 	background: transparent;
	font-family: serif;
	font-size: 10pt;
}
div#page {
   margin:20px;
   padding:20px;
}
pre, code {
    font-family: Consolas, courier, monospace;
}
/* invisibles */
span.hiddenindex, span.commentmarker, .comment, span.tocprefix, #hitme {
    display: none
}

h1 {
    font-size: 200%;
    margin: .67em 0
}
h2 {
    font-size: 180%;
    margin: .75em 0
}
h3 {
    font-size: 150%;
    margin: .83em 0
}
h4 {
    font-size: 130%;
    margin: 1.12em 0
}
h5 {
    font-size: 115%;
    margin: 1.5em 0
}
h6 {
    font-size: 100%;
    margin: 0;
}

sup, sub {
    font-size: 8pt;
    line-height: 0;
}

/* invisibles */
span.hiddenindex, span.commentmarker, .comment, span.tocprefix, #hitme {
    display: none
}

.comment {
    background: rgb(255,255,158);
}

.verse {
    margin: 24px 48px;
    overflow: auto;
}

table, th, td {
    border: solid 1px black;
    border-collapse: collapse;
}
td, th {
    padding: 2px 5px;
}

hr {
    margin: 24px 0;
    color: #000;
    height: 1px;
    background-color: #000;
}

table {
    margin: 24px auto;
}

td, th { vertical-align: top; }
th {font-weight: bold;}

caption {
    caption-side:bottom;
}

img.embedimg {
    max-width:90%;
}
div.image, div.float_image_f {
    margin: 1em;
    text-align: center;
    padding: 3px;
    background-color: white;
}

div.float_image_r {
    float: right;
}

div.float_image_l {
    float: left;
}

div.float_image_f {
    clear: both;
    margin-left: auto;
    margin-right: auto;

}

.biblio p, .play p {
  margin-left: 1em;
  text-indent: -1em;
}

div.biblio, div.play {
  padding: 24px 0;
}

div.caption {
    padding-bottom: 1em;
}

div.center {
    text-align: center;
}

div.right {
    text-align: right;
}

div#tableofcontents{
    padding:20px;
}

#tableofcontents p {
    margin: 3px 1em;
    text-indent: -1em;
}

.toclevel1 {
	font-weight: bold;
	font-size:11pt
}	

.toclevel2 {
	font-weight: bold;
	font-size: 10pt;
}

.toclevel3 {
	font-weight: normal;
	font-size: 9pt;
}

.toclevel4 {
	font-weight: normal;
	font-size: 8pt;
}
EOF
    return \$css;
}

sub bare_html {
    my $self = shift;
    if (my $ref = $self->ttref('bare_html')) {
        return $ref;
    }
    my $html = <<'EOF';

[%- IF doc.toc_as_html -%]
<div class="table-of-contents">
[% doc.toc_as_html %]
</div>
[%- END -%]

<div id="thework">
[% doc.as_html %]
</div>
EOF
    return \$html;
}

sub minimal_html {
    my $self = shift;
    if (my $ref = $self->ttref('minimal_html')) {
        return $ref;
    }
    my $html = <<'EOF';
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <title>[% title %]</title>
    <link href="stylesheet.css" type="text/css" rel="stylesheet" />
  </head>
  <body>
    <div id="page">
      [% text %]
    </div>
  </body>
</html>
EOF
    return \$html;
}


sub latex {
    my $self = shift;
    if (my $ref = $self->ttref('latex')) {
        return $ref;
    }
    my $latex = <<'EOF';
[% # this is the preamble of the preamble... -%]
[% # set the dimension                       -%]
[% IF size == 'half-a4'                      -%]
[% SET paper = 'a5'                          -%]
[% ELSIF size == 'half-lt'                   -%]
[% SET paper = '5.5in:8.5in'                 -%]
[% ELSE                                      -%]
[% # fits letter and a4                      -%]
[% SET paper = '210mm:11in'                  -%]
[% END                                       -%]
[% # set the class                           -%]
[% IF doc.wants_toc                          -%]
[% SET class = 'scrbook'                     -%]
[% ELSE                                      -%]
[% SET class = 'scrartcl'                    -%]
[% END                                       -%]
[% # set the div, if any                     -%]
[% UNLESS division                           -%]
[% SET division = '12'                       -%]
[% END                                       -%]
[% UNLESS fontsize                           -%]
[% SET fontsize = '10'                       -%]
[% END                                       -%]
\documentclass[DIV=[% division -%],%
               fontsize=[% fontsize %]pt,%
               oneside,%
               paper=[% paper %]]{[% class %]}
\usepackage{fontspec}
\usepackage{polyglossia}
\setmainfont[Mapping=tex-text]{Linux Libertine O}
\setsansfont[Mapping=tex-text,Scale=MatchLowercase]{DejaVu Sans}
\setmonofont[Mapping=tex-text,Scale=MatchLowercase]{DejaVu Sans Mono}
[% IF doc.language == 'serbian' %]
\setmainlanguage{croatian}
[% ELSIF doc.language == 'macedonian' %]
\setmainlanguage{russian}
[% ELSE %]
\setmainlanguage{[% doc.language %]}
[% END %]
\usepackage{microtype} % you need an *updated* texlive 2012, but harmless
\usepackage{graphicx}
\usepackage{alltt}
\usepackage{verbatim}
% http://tex.stackexchange.com/questions/3033/forcing-linebreaks-in-url
\PassOptionsToPackage{hyphens}{url}\usepackage[hyperfootnotes=false,hidelinks,breaklinks=true]{hyperref}
\usepackage{bookmark}
\usepackage[stable]{footmisc}
\usepackage{enumerate}
\usepackage{tabularx}
\usepackage[normalem]{ulem}
\usepackage{wrapfig}
\usepackage{indentfirst}
% remove the numbering
\setcounter{secnumdepth}{-2}

% remove labels from the captions
\renewcommand*{\captionformat}{}
\renewcommand*{\figureformat}{}
\renewcommand*{\tableformat}{}
\KOMAoption{captions}{belowfigure,nooneline}
\addtokomafont{caption}{\centering}

% avoid breakage on multiple <br><br> and avoid the next [] to be eaten
\newcommand*{\forcelinebreak}{\strut\\{}}

\newcommand*{\hairline}{%
  \bigskip%
  \noindent \hrulefill%
  \bigskip%
}

% reverse indentation for biblio and play

\newenvironment*{amusebiblio}{
  \leftskip=\parindent
  \parindent=-\parindent
  \smallskip
  \indent
}{\smallskip}

\newenvironment*{amuseplay}{
  \leftskip=\parindent
  \parindent=-\parindent
  \smallskip
  \indent
}{\smallskip}

\newcommand*{\Slash}{\slash\hspace{0pt}}

% global style
\pagestyle{plain}
\addtokomafont{disposition}{\rmfamily}
% forbid widows/orphans
\clubpenalty=10000
\widowpenalty=10000
\frenchspacing
\sloppy

\title{[% doc.header_as_latex.title %]}
\date{[% doc.header_as_latex.date %]}
\author{[% doc.header_as_latex.author %]}
\subtitle{[% doc.header_as_latex.subtitle %]}
\begin{document}
\maketitle

[% IF doc.wants_toc %]

\tableofcontents
\cleardoublepage

[% END %]

[% doc.as_latex %]

\cleardoublepage

\thispagestyle{empty}
\strut
%
% Here a logo maybe?
%
\vfill

\begin{center}

[% doc.header_as_latex.author     %]

[% doc.header_as_latex.title      %]

[% doc.header_as_latex.subtitle   %]

[% doc.header_as_latex.date       %]

\bigskip

[% doc.header_as_latex.source     %]

[% doc.header_as_latex.notes      %]

% Here an URL maybe?

\end{center}

\end{document}

EOF
    return \$latex;
}


=head1 EXPORT

None.

=cut

1;
