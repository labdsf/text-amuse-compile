package Text::Amuse::Compile::Templates;

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

=head3 html

=head3 css

The default CSS, with some minor templating.

=head3 bare_html

The HTML fragment with the B<body> of the text (no HTML headers, no
Muse headers).

=head3 minimal_html

Minimal (but valid) XHTML template, with a link to C<stylesheet.css>.
Meant to be used in the EPUB generation.

=head3 title_page_html

Minimal XHTML template for a title page in the EPUB generation.

=head3 bare_latex

Minimal and uncomplete LaTeX chunck, meant to be used when merging
files.

=head3 latex

The LaTeX template.

The template itself uses two hashrefs with tokens: C<options> and
C<safe_options>. The C<options> contains tokens which are interpreted
as L<Text::Amuse> strings from the C<extra> constructor. The
C<safe_options> ones contains validate copies of the C<options> for
places where it make sense, plus some internal things like the
languages and additional strings to get the LaTeX code right.

We use only the C<safe_options> tokens, while the C<options> should be
used only by custom templates which in this way can receive random
stuff.

See L<Text::Amuse::Compile::TemplateOptions>

Anyway, all the values from C<options> and C<safe_options>, because of the
markup interpretation, are (hopefully) safely escaped (so you can pass
even LaTeX commands, and they will be escaped).

=head3 slides

The Beamer template. It shares the same tokens (when it makes sense)
with the LaTeX template.

Theme and color theme selection is done via the
Text::Amuse::Compile::BeamerThemes class, calling C<as_latex> on the
object. The relevant token is C<options.beamer_theme>, picked up from
the C<beamertheme> and C<beamercolortheme> from the C<extra>
constructor.

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
                                            (bare[_.-])?latex     |
                                            css)
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
                $t =~ s/[\.-]/_/g;

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
            die "<$self->{ttdir}> is not a directory!";
        }
    }
    bless $self, $class;
}

sub ttdir {
    return shift->{ttdir};
}

sub names {
    return (qw/html minimal_html bare_html
               css latex bare_latex
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
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="[% doc.language_code %]" lang="[% doc.language_code %]">
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
  [% IF doc.wants_preamble %]
  [% IF doc.header_defined.author %]
  <h2 class="amw-text-author">[% doc.header_as_html.author %]</h2>
  [% END %]
  <h1 class="amw-text-title">[% doc.header_as_html.title %]</h1>
  [% IF doc.header_defined.subtitle %]
  <h2>[% doc.header_as_html.subtitle %]</h2>
  [% END  %]
  [% IF doc.header_defined.date %]
  <h3 class="amw-text-date">[% doc.header_as_html.date %]</h3>
  [% END  %]
  [% END %]
  [% IF doc.toc_as_html %]
  <div class="table-of-contents"[% IF options.notoc %] style="display:none"[% END %]>
  [% doc.toc_as_html %]
  </div>
  [% END %]
 <div id="thework">
[% doc.as_html %]
 </div>
  <hr />
  [% IF doc.wants_postamble %]
  <div id="impressum">
    [% IF doc.header_defined.source %]
    <div class="amw-text-source" id="source">
    [% doc.header_as_html.source %]
    </div>
    [% END %]
    [% IF doc.header_defined.notes %]
    <div class="amw-text-notes" id="notes">
    [% doc.header_as_html.notes %]
    </div>
    [% END %]
  </div>
  [% END %]
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
[% IF epub %]
@page { margin: 5pt; }
[% END %]

[% IF webfonts %]

@font-face {
  font-family: "[% webfonts.family %]";
  font-weight: normal;
  font-style: normal;
  src: url("[% webfonts.regular %]") format("[% webfonts.format %]");
}
@font-face {
  font-family: "[% webfonts.family %]";
  font-weight: normal;
  font-style: italic;
  src: url("[% webfonts.italic %]") format("[% webfonts.format %]");
}
@font-face {
  font-family: "[% webfonts.family %]";
  font-weight: bold;
  font-style: normal;
  src: url("[% webfonts.bold %]") format("[% webfonts.format %]");
}
@font-face {
  font-family: "[% webfonts.family %]";
  font-weight: bold;
  font-style: italic;
  src: url("[% webfonts.bolditalic %]") format("[% webfonts.format %]");
}

[% END %]

html,body {
	margin:0;
	padding:0;
	border: none;
 	background: transparent;
	font-family: [% IF fonts %]"[% fonts.main.name %]",[% END %] serif;
}

div#thework {
    margin-top: 3em;
}

div#thework > p {
   margin: 0;
   text-indent: 1em;
   text-align: justify;
}

p.tableofcontentline {
   margin: 0;
}

blockquote > p, li > p {
   margin-top: 0.5em;
   text-indent: 0em;
   text-align: justify;
}

a {
   color:#000000;
   text-decoration: underline;
}

[% IF html %]
div#page {
   margin:20px;
   padding:20px;
}
[% END %]

pre, code {
    font-family: [% IF fonts %]"[% fonts.mono.name %]",[% END %]Consolas, courier, monospace;
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
    font-size: 80%;
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

.toclevel1 {
	font-weight: bold;
	font-size:110%;
}	

.toclevel2 {
	font-weight: bold;
	font-size: 100%;
    padding-left: 1em;
}

.toclevel3 {
	font-weight: normal;
	font-size: 90%;
    padding-left: 2em;
}

.toclevel4 {
	font-weight: normal;
	font-size: 80%;
    padding-left: 3em;
}

/* definition lists */

dt {
	font-weight: bold;
}
dd {
    margin: 0;
    padding-left: 2em;
}

/* footnotes */

a.footnote, a.footnotebody {
    font-size: 80%;
    line-height: 0;
    vertical-align: super;
}

* + p.fnline {
    margin-top: 3em;
    border-top: 1px solid black;
    padding-top: 2em;
}

p.fnline + p.fnline {
    margin-top: 1em;
    border-top: none;
    padding-top: 0;
}

p.fnline {
    font-size: 80%;
}
/* end footnotes */

EOF
    return \$css;
}

sub bare_html {
    my $self = shift;
    if (my $ref = $self->ttref('bare_html')) {
        return $ref;
    }
    my $html = <<'EOF';
[% IF doc.toc_as_html %]
<div class="table-of-contents"[% IF options.notoc %] style="display:none"[% END %]>
[% doc.toc_as_html %]
</div>
[% END %]
<div id="thework">
[% doc.as_html %]
</div>
EOF
    return \$html;
}

sub title_page_html {
    my $self = shift;
    if (my $ref = $self->ttref('title_page_html')) {
        return $ref;
    }
    my $html = <<'EOF';
[% IF doc.wants_preamble %]
<div id="first-page-title-page">
  [% IF doc.header_defined.author %]
  <h2 class="amw-text-author">[% doc.header_as_html.author %]</h2>
  [% END %]
  <h1 class="amw-text-title">[% doc.header_as_html.title %]</h1>
  [% IF doc.header_defined.subtitle %]
  <h2 class="amw-text-subtitle">[% doc.header_as_html.subtitle %]</h2>
  [% END  %]
  [% IF doc.header_defined.date %]
  <h3 class="amw-text-date">[% doc.header_as_html.date %]</h3>
  [% END  %]
</div>
[% END %]
<div style="padding-top: 3em; padding-bottom: 3em; text-align:center">
 <strong>* * * * *</strong>
</div>
[% IF doc.wants_postamble %]
<div id="impressum-title-page">
  [% IF doc.header_defined.source %]
  <div class="amw-text-source" id="source">
  [% doc.header_as_html.source %]
  </div>
  [% END %]
  [% IF doc.header_defined.notes %]
  <div class="amw-text-notes" id="notes">
  [% doc.header_as_html.notes %]
  </div>
  [% END %]
</div>
[% END %]
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
\documentclass[DIV=[% safe_options.division %],%
               BCOR=[% safe_options.bcor %],%
               headinclude=[% IF safe_options.headings %]true[% ELSE %]false[% END %],%
               footinclude=false,[% IF safe_options.opening %]open=[% safe_options.opening %],[% END %]%
               fontsize=[% safe_options.fontsize %]pt,%
               [% safe_options.paging %],%
               paper=[% safe_options.papersize %]]%
               {[% safe_options.class %]}
\usepackage{fontspec}
\usepackage{polyglossia}
\setmainfont{[% safe_options.mainfont %]}
% these are not used but prevents XeTeX to barf
\setsansfont[Scale=MatchLowercase]{[% safe_options.sansfont %]}
\setmonofont[Scale=MatchLowercase]{[% safe_options.monofont %]}
\setmainlanguage{[% safe_options.lang %]}
[% safe_options.mainlanguage_script %]

[% IF safe_options.other_languages %]
\setotherlanguages{[% safe_options.other_languages %]}
[% END %]
[% IF safe_options.other_languages_additional %]
[% safe_options.other_languages_additional %]
[% END %]

[% IF safe_options.mainlanguage_toc_name %]
\renewcaptionname{[% safe_options.lang %]}{\contentsname}{[% safe_options.mainlanguage_toc_name %]}
[% END %]

[% IF safe_options.nocoverpage %]
\let\chapter\section
[% END %]
% global style
[% IF safe_options.headings %]
\setlength{\headsep}{\baselineskip}
\usepackage{scrlayer-scrpage}
\pagestyle{scrheadings}
  [% IF safe_options.twoside %]
    [% IF safe_options.headings.title_subtitle %]
    \lehead{\pagemark}
    \rohead{\pagemark}
    \rehead{[% doc.header_as_latex.title %]}
    \lohead{[% IF doc.header_defined.subtitle %][% doc.header_as_latex.subtitle %][% ELSE %][% doc.header_as_latex.title %][% END %]}
    [% END %]
    [% IF safe_options.headings.author_title %]
    \lehead{\pagemark}
    \rohead{\pagemark}
    \rehead{[% IF doc.header_defined.author %][% doc.header_as_latex.author %][% ELSE %][% doc.header_as_latex.title %][% END %]}
    \lohead{[% doc.header_as_latex.title %]}
    [% END %]
    [% IF safe_options.headings.section_subsection %]
    \automark[subsection]{section}
    \ohead[]{\pagemark}
    \ihead[]{\headmark}
    [% END %]
    [% IF safe_options.headings.chapter_section %]
    \automark[section]{chapter}
    \ohead[]{\pagemark}
    \ihead[]{\headmark}
    [% END %]
    [% IF safe_options.headings.title_chapter %]
    \automark[chapter]{chapter}
    \lehead{\pagemark}
    \rohead{\pagemark}
    \rehead{[% doc.header_as_latex.title %]}
    \lohead{\headmark}
    [% END %]
    [% IF safe_options.headings.title_section %]
    \automark[section]{section}
    \lehead{\pagemark}
    \rohead{\pagemark}
    \rehead{[% doc.header_as_latex.title %]}
    \lohead{\headmark}
    [% END %]
    \chead[]{}
    \ifoot[]{}
    \cfoot[]{}
    \ofoot[]{}
  [% ELSE %]
    [% IF safe_options.headings.title_subtitle %]
    \chead{[% doc.header_as_latex.title %]}
    [% END %]
    [% IF safe_options.headings.author_title %]
    \chead{[% doc.header_as_latex.title %]}
    [% END %]
    [% IF safe_options.headings.section_subsection %]
    \automark[section]{section}
    \chead[]{\headmark}
    [% END %]
    [% IF safe_options.headings.chapter_section %]
    \automark[chapter]{chapter}
    \chead[]{\headmark}
    [% END %]
    [% IF safe_options.headings.title_chapter %]
    \automark[chapter]{chapter}
    \chead[]{\headmark}
    [% END %]
    [% IF safe_options.headings.title_section %]
    \automark[section]{section}
    \chead[]{\headmark}
    [% END %]
    \ihead[]{}
    \ohead[]{}
    \ifoot[]{}
    \cfoot[\pagemark]{\pagemark}
    \ofoot[]{}
  [% END %]
[% ELSE %]
\pagestyle{plain}
[% END %]



\usepackage{microtype} % you need an *updated* texlive 2012, but harmless
\usepackage{graphicx}
\usepackage{alltt}
\usepackage{verbatim}
% http://tex.stackexchange.com/questions/3033/forcing-linebreaks-in-url
\PassOptionsToPackage{hyphens}{url}\usepackage[hyperfootnotes=false,hidelinks,breaklinks=true]{hyperref}
\usepackage{bookmark}
\usepackage[stable]{footmisc}
\usepackage[shortlabels]{enumitem}
\usepackage{tabularx}
\usepackage[normalem]{ulem}
\def\hsout{\bgroup \ULdepth=-.55ex \ULset}
% https://tex.stackexchange.com/questions/22410/strikethrough-in-section-title
% Unclear if \protect \hsout is needed. Doesn't looks so
\DeclareRobustCommand{\sout}[1]{\texorpdfstring{\hsout{#1}}{#1}}
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
\newcommand*{\forcelinebreak}{\strut\\*{}}

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

\addtokomafont{disposition}{\rmfamily}
\addtokomafont{descriptionlabel}{\rmfamily}
% forbid widows/orphans
\frenchspacing
\sloppy
\clubpenalty=10000
\widowpenalty=10000
% http://tex.stackexchange.com/questions/304802/how-not-to-hyphenate-the-last-word-of-a-paragraph
\finalhyphendemerits=10000

% given that we said footinclude=false, this should be safe
\setlength{\footskip}{2\baselineskip}

\title{[% doc.header_as_latex.title %]}
\date{[% doc.header_as_latex.date %]}
\author{[% doc.header_as_latex.author %]}
\subtitle{[% doc.header_as_latex.subtitle %]}

[% IF tex_metadata %]
% https://groups.google.com/d/topic/comp.text.tex/6fYmcVMbSbQ/discussion
\hypersetup{%
pdfencoding=auto,
pdftitle={[% tex_metadata.title %]},%
pdfauthor={[% tex_metadata.author %]},%
pdfsubject={[% tex_metadata.subject %]},%
pdfkeywords={[% tex_metadata.keywords %]}%
}
[% END %]

\begin{document}
[% IF doc.hyphenation %]
\hyphenation{ [% doc.hyphenation %] }
[% END %]

[% IF safe_options.nocoverpage %]
\thispagestyle{empty}
[% ELSE %]
  \begin{titlepage}
[% END %]
  \strut\vskip 2em
  \begin{center}
[% IF doc.wants_preamble %]
  {\usekomafont{title}{\huge [% doc.header_as_latex.title %]\par}}%
  \vskip 1em
  [% IF doc.header_defined.subtitle %]
  {\usekomafont{subtitle}{[% doc.header_as_latex.subtitle %]\par}}%
  [% END %]
  \vskip 2em
  [% IF doc.header_defined.author %]
  {\usekomafont{author}{[% doc.header_as_latex.author %]\par}}%
  [% END %]
  \vskip 1.5em
[% ELSE %]
\strut
[% END %]
[% UNLESS safe_options.nocoverpage %]
   [% IF safe_options.cover %]
      \vskip 3em
      \includegraphics[keepaspectratio=true,height=0.5\textheight,width=[% safe_options.coverwidth %]\textwidth]{[% safe_options.cover %]}
   [% END %]
   \vfill
[% END %]
[% IF doc.wants_preamble %]
  [% IF doc.header_defined.date %]
  {\usekomafont{date}{[% doc.header_as_latex.date %]\par}}%
  [% ELSE %]
    \strut\par
  [% END %]
[% ELSE %]
\strut
[% END %]
  \end{center}
[% IF safe_options.nocoverpage %]
  \vskip 3em
  \par
[% ELSE %]
  \end{titlepage}
\cleardoublepage
[% END %]

[% IF safe_options.wants_toc %]
\tableofcontents
% start a new right-handed page
[% IF safe_options.nocoverpage %]
  \vskip 3em
[% ELSE %]
\cleardoublepage
[% END %]
[% END %]

[% doc.as_latex %]

[% UNLESS safe_options.nofinalpage %]
% begin final page

\clearpage

[% IF safe_options.twoside %]
% if we are on an odd page, add another one, otherwise when imposing
% the page would be odd on an even one.
\ifthispageodd{\strut\thispagestyle{empty}\clearpage}{}
[% END %]

% new page for the colophon

\thispagestyle{empty}

\begin{center}
[% IF safe_options.sitename %]
[% safe_options.sitename %]
[% END %]

[% IF safe_options.siteslogan %]
\smallskip
[% safe_options.siteslogan %]
[% END %]

[% IF safe_options.logo %]
\bigskip
\includegraphics[width=0.25\textwidth]{[% safe_options.logo %]}
\bigskip
[% ELSE %]
\strut
[% END %]
\end{center}

\strut

\vfill

\begin{center}

[% IF doc.wants_preamble %]
[% doc.header_as_latex.author     %]

[% doc.header_as_latex.title      %]

[% doc.header_as_latex.subtitle   %]

[% doc.header_as_latex.date       %]
[% ELSE %]
\strut
[% END %]

\bigskip

[% IF doc.wants_postamble %]
[% doc.header_as_latex.source     %]

[% doc.header_as_latex.notes      %]
[% ELSE %]
\strut
[% END %]

[% IF safe_options.site %]
\bigskip
\textbf{[% safe_options.site %]}
[% END %]

\end{center}

% end final page with colophon
[% END %]

\end{document}

EOF
    return \$latex;
}

sub slides {
    my $self = shift;
    if (my $ref = $self->ttref('slides')) {
        return $ref;
    }
    my $slides =<<'LATEX';
\documentclass[ignorenonframetext]{beamer}
\usepackage{fontspec}
\usepackage{polyglossia}
\setmainfont{[% safe_options.mainfont %]}
\setsansfont{[% safe_options.sansfont %]}
\setmonofont[Scale=MatchLowercase]{[% safe_options.monofont %]}
\usetheme{[% safe_options.beamertheme %]}
\usecolortheme{[% safe_options.beamercolortheme %]}
\setmainlanguage{[% safe_options.lang %]}
[% safe_options.mainlanguage_script %]
[% IF safe_options.mainlanguage_toc_name %]
\renewcaptionname{[% safe_options.lang %]}{\contentsname}{[% safe_options.mainlanguage_toc_name %]}
[% END %]
\usepackage{graphicx}
\usepackage{alltt}
\usepackage{verbatim}
\usepackage[stable]{footmisc}
\usepackage[shortlabels]{enumitem}
\usepackage{tabularx}
\usepackage[normalem]{ulem}
\def\hsout{\bgroup \ULdepth=-.55ex \ULset}
% https://tex.stackexchange.com/questions/22410/strikethrough-in-section-title
% Unclear if \protect  \hsout is needed. Doesn't looks so
\DeclareRobustCommand{\sout}[1]{\texorpdfstring{\hsout{#1}}{#1}}
\usepackage{wrapfig}
% remove the numbering
\setcounter{secnumdepth}{-2}

% avoid breakage on multiple <br><br> and avoid the next [] to be eaten
\newcommand*{\forcelinebreak}{\strut\\*{}}

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

\title{[% doc.header_as_latex.title %]}
\date{[% doc.header_as_latex.date %]}
\author{[% doc.header_as_latex.author %]}
\subtitle{[% doc.header_as_latex.subtitle %]}
\begin{document}
[% IF doc.hyphenation %]
\hyphenation{ [% doc.hyphenation %] }
[% END %]

\begin{document}
\begin{frame}
\titlepage
\end{frame}

[% doc.as_beamer %]

\end{document}

LATEX
    return \$slides;
}


sub bare_latex {
    my $self = shift;
    if (my $ref = $self->ttref('bare_latex')) {
        return $ref;
    }
    my $latex =<<'LATEX';
[% IF doc.hyphenation %]
\hyphenation{ [% doc.hyphenation %] }
[% END %]

\cleardoublepage

[% IF doc.wants_preamble %]
% start titlepage

[% IF doc.wants_toc %]
\strut
\thispagestyle{empty}
\vspace{0.1\textheight}
[% END %]

\phantomsection
\addcontentsline{toc}{part}{[% doc.header_as_latex.title %]}

\begin{center}
  \strut\vskip 2em
  {\usekomafont{title}{\huge [% doc.header_as_latex.title %]\par}}%
  \vskip 1em
  [% IF doc.header_defined.subtitle %]
  {\usekomafont{subtitle}{[% doc.header_as_latex.subtitle %]\par}}%
  [% END %]
  \vskip 2em
  [% IF doc.header_defined.author %]
  {\usekomafont{author}{[% doc.header_as_latex.author %]\par}}%
  [% END %]
  \vskip 1.5em
  [% IF doc.header_defined.date %]
  {\usekomafont{date}{[% doc.header_as_latex.date %]\par}}%
  [% END %]
\end{center}

% end titlepage

[% IF doc.wants_toc %]
\cleardoublepage
[% ELSE %]
\strut\vskip 2em
[% END %]

[% END %]

[% doc.as_latex %]

[% IF doc.wants_postamble %]
\strut
\vfill

[% IF doc.header_defined.source %]
\begin{center}
[% doc.header_as_latex.source     %]
\end{center}
[% END %]

[% IF doc.header_defined.notes %]
\begin{center}
[% doc.header_as_latex.notes      %]
\end{center}
[% END %]

[% END %]

LATEX
    return \$latex;
}

=head1 EXPORT

None.

=cut

1;
