#!perl

use strict;
use warnings;
use utf8;

use Test::More;
use File::Spec;
use Text::Amuse;
use Text::Amuse::Compile;
use Text::Amuse::Compile::Utils qw/read_file/;

my $builder = Test::More->builder;
binmode $builder->output,         ":utf8";
binmode $builder->failure_output, ":utf8";
binmode $builder->todo_output,    ":utf8";
binmode STDOUT, ':encoding(utf-8)';
binmode STDERR, ':encoding(utf-8)';

if ($ENV{TEST_WITH_LATEX}) {
    plan tests => 157;
}
else {
    plan tests => 140;
}


# this is the test file for the LaTeX output, which is the most
# complicated.

my $file_no_toc = File::Spec->catfile(qw/t tex testing-no-toc.muse/);
my $file_with_toc = File::Spec->catfile(qw/t tex testing.muse/);
my $file_with_full_header = File::Spec->catfile(qw/t tex headers.muse/);


test_file($file_no_toc, {
                         division => 9,
                         fontsize => 11,
                         papersize => 'half-lt',
                         nocoverpage => 0,
                        },
          qr/scrbook/,
          qr/DIV=9/,
          qr/fontsize=11pt/,
          qr/mainlanguage\{croatian\}/,
          qr/\\setmainfont\{CMU Serif\}/,
          qr/paper=5.5in:8.5in/,
          qr/\\end\{titlepage\}\s*\\cleardoublepage/s,
          qr/document\}\s*\\hyphenation\{\s*a-no-ther\ste-st\s*}/s,
         );

test_file($file_no_toc, {
                         division => 9,
                         fontsize => 10,
                         papersize => 'a6',
                         nocoverpage => 1,
                         bcor => '15mm',
                        },
          qr/\{scrartcl\}/,
          qr/DIV=9/,
          qr/fontsize=10pt/,
          qr/paper=a6/,
          qr/BCOR=15mm/,
          qr/\\end\{center\}\s*\\vskip 3em\s*\\par\s*\w/s,
         );

test_file($file_no_toc, {
                         nocoverpage => 1,
                         mainfont => 'Iwona',
                         twoside => 1,
                        },
          qr/\\end\{center\}\s*\\vskip 3em\s*\\par\s*\w/s,
          qr/\\setmainfont\{Iwona\}/,
          qr/^\s+twoside,%$/m,
          qr/BCOR=0mm/,
         );

test_file($file_with_toc, {
                           cover => 'prova.png',
                           oneside => 1,
                           bcor => '2.5cm',
                           coverwidth => '0.1',
                          },
          qr/\\end\{titlepage\}\s*\\cleardoublepage\s*\\tableofcontents/s,
          qr/\\includegraphics\[width=0.1\\textwidth\]\{prova.png\}/,
          qr/^\s+oneside,%$/m,
          qr/BCOR=2.5cm/,
         );


test_file($file_with_toc, {
                           papersize => 'generic',
                           oneside => 1,
                           twoside => 1,
                          },
          qr/scrbook/,
          qr/^\s+oneside,%$/m,
          qr/^\\setmainlanguage\{russian\}/m,
          qr/\\renewcaptionname\{russian\}\{\\contentsname\}\{Содржина\}/,
          qr/\\russianfont\[Script=Cyrillic\]\{CMU\sSerif\}/,
          qr/paper=210mm:11in/,
          qr/\\end\{titlepage\}\s*\\cleardoublepage/s,
         );


test_file($file_with_toc, {
                           papersize => 'generic',
                           oneside => 1,
                           twoside => 1,
                           cover => 'prova.png',
                          },
          qr/\\includegraphics\[width=1\\textwidth\]\{prova\.png\}/,
          qr/\\pagestyle\{plain\}/,
         );

test_file($file_with_full_header, {
                                   cover => 'prova.png',
                                   headings => 1,
                                  },
          qr/usekomafont{author}{AuthorT/,
          qr/usekomafont{title}{\\huge TitleT/,
          qr/usekomafont{date}{DateT/,
          qr/usekomafont{subtitle}{SubtitleT/,
          qr/\\pagestyle\{headings\}/,
         );

test_file($file_with_toc, {
                           papersize => 'generic',
                           oneside => 1,
                           twoside => 1,
                           cover => 'prova.png',
                           coverwidth => 'blablabla',
                          },
          qr/\\includegraphics\[width=1\\textwidth\]\{prova\.png\}/,);


test_file($file_with_toc, {
                           papersize => 'half-a4',
                          },
          qr/paper=a5/,
          qr/\\end\{titlepage\}\s*\\cleardoublepage/s,
         );

test_file({
           path => File::Spec->catfile(qw/t tex/),
           files => [ qw/testing testing-no-toc testing/],
           name => 'merged-1',
           title => 'Merged',
          },
          {
          },
          qr/croatian/,
          qr/russian/,
          qr/Pallino.*Pinco.*Second.*author/s,
          qr/mainlanguage\{russian}.*selectlanguage\{croatian}.*selectlanguage\{russian}/s,
          qr/\\end\{titlepage\}\s*\\cleardoublepage/s,
          qr/\\setmainlanguage\{russian\}\s*
             \\newfontfamily\s*
             \\russianfont\[Script=Cyrillic\]\{CMU\sSerif\}\s*
             \\setotherlanguages\{croatian\}\s*
             \\renewcaptionname\{russian\}\{\\contentsname\}\{Содржина\}/sx,
         );

test_file({
           path => File::Spec->catfile(qw/t tex/),
           files => [ qw/testing-no-toc testing testing-no-toc/],
           name => 'merged-2',
           title => 'Merged',
          },
          {
          },
          qr/\\end\{titlepage\}\s*\\cleardoublepage/s,
          qr/mainlanguage\{croatian}.*selectlanguage\{russian}.*selectlanguage\{croatian}/s,
          qr/Second.*author.*Pallino.*Pinco/s,
          qr/croatian/,
          qr/russian/,
          qr/\\setmainlanguage\{croatian\}\s*
             \\setotherlanguages\{russian\}\s*
             \\newfontfamily\s*
             \\russianfont\[Script=Cyrillic\]\{CMU\sSerif\}/sx
         );

test_file({
           path => File::Spec->catfile(qw/t tex/),
           files => [ qw/testing testing-no-toc testing headers/ ],
           name => 'merged-3',
           title => 'Merged 3',
          },
          {
          },
          qr/mainlanguage\{russian}.*
             selectlanguage\{croatian}.*
             selectlanguage\{russian}.*
             selectlanguage\{italian}/sx,
          qr/\\begin\{document\}\s*
             \\hyphenation\{\s*pal-li-no\s*pin-co\s*\}.*
             \\hyphenation\{\s*pal-li-no\s*pin-co\s*\}.*
             \\selectlanguage\{croatian\}\s*
             \\hyphenation\{\s*a-no-ther\s*te-st\s*\}.*
             \\selectlanguage\{russian\}\s*
             \\hyphenation\{\s*pal-li-no\s*pin-co\s*\}.*
             \\selectlanguage\{italian\}\s*
             \\hyphenation\{\s*ju-st\s*th-is\s*\}
            /sx,
          qr/\\setotherlanguages\{croatian,italian\}/,
          qr/usekomafont\{title\}\{\\huge\ TitleT.*
             usekomafont\{subtitle\}\{SubtitleT.*
             usekomafont\{author\}\{AuthorT.*
             usekomafont\{date\}\{DateT.*
             SourceT.*
             NotesT/sx,
          );


my $outbody = test_file($file_with_toc, {
                                         notoc => 0,
                                         opening => 'right',
                                        },
                        qr/open=right/,
                       );
like $outbody, qr/tableofcontents/;
$outbody = test_file($file_with_toc, { notoc => 1,
                                       opening => 'any',
                                     },
                     qr/open=any/,
                    );
unlike $outbody, qr/tableofcontents/;
$outbody = test_file($file_no_toc, { notoc => 1,
                                     nocoverpage => 1,
                                     opening => 'any',
                                   },
                     qr/\{scrartcl\}/,
                    );
unlike $outbody, qr/tableofcontents/;
unlike $outbody, qr/open=any/, "No opening found, it has no toc";
$outbody = test_file($file_no_toc, { notoc => 0 });
unlike $outbody, qr/tableofcontents/;

my $siteslogan =<<'EXPECTED';
\#x\$x\%x\^{}x\&x\_x\{x\}x\textasciitilde{}x\textbackslash{}
EXPECTED
chomp $siteslogan;

my $sitename =<< 'EXPECTED';
\emph{hello} t\textbar{}h\&r\textasciitilde{}\_\textbackslash{}
EXPECTED
chomp $sitename;

$outbody = test_file($file_no_toc, {
                                    siteslogan => '#x$x%x^x&x_x{x}x~x\\',
                                    sitename => '*hello* t|h&r~_\\',
                                   },
                     qr/\Q$siteslogan\E/,
                     qr/\Q$sitename\E/,
                    );
sub test_file {
    my ($file, $extra, @regexps) = @_;
    my $c = Text::Amuse::Compile->new(tex => 1, extra => $extra,
                                      pdf => !!$ENV{TEST_WITH_LATEX});
    $c->compile($file);
    my $out;
    if (ref($file)) {
        $out = File::Spec->catfile($file->{path}, $file->{name} . '.tex');
    }
    else {
        $out = $file;
        $out =~ s/\.muse$/.tex/;
    }
    ok (-f $out, "$out produced");
    if ($ENV{TEST_WITH_LATEX}) {
        my $pdf = $out;
        $pdf =~ s/\.tex$/.pdf/;
        ok (-f $pdf, "$pdf produced");
    }
    my $body = read_file($out);
    # print $body;
    my $error = 0;
    unlike $body, qr/\[%/, "No opening template tokens found";
    unlike $body, qr/%\]/, "No closing template tokens found";
    foreach my $regexp (@regexps) {
        like($body, $regexp, "$regexp matches the body") or $error++;
    }
    if (ref($file)) {
        my $index = 0;
        foreach my $f (@{$file->{files}}) {
            my $fullpath = File::Spec->catfile($file->{path},
                                               $f . '.muse');
            my $muse = Text::Amuse->new(file => $fullpath);
            my $current = index($body, $muse->as_latex, $index);
            ok($current > $index, "$current is greater than $index") or $error++;;
            $index = $current;
        }
    }
    else {
        my $muse = Text::Amuse->new(file => $file);
        my $latex = $muse->as_latex;
        ok ((index($body, $latex) > 0), "Found the body") or $error++;
    }
    unless ($ENV{NO_CLEANUP}) {
        unlink $out unless $error;
        $out =~ s/tex$/status/;
        unlink $out unless $error;
        $out =~ s/status$/pdf/;
        if (-f $out) {
            unlink $out unless $error;
        }
        $out =~ s/pdf$/log/;
        if (-f $out) {
            unlink $out unless $error;
        }
    }
    return $body;
}

