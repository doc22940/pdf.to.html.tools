package PDF::FromHTML;
$PDF::FromHTML::VERSION = '0.21';

use 5.006;
use strict;
use warnings;

BEGIN {
    foreach my $method ( qw( pdf twig tidy args ) ) {
        no strict 'refs';
        *$method = sub { $#_ ? ($_[0]{$method} = $_[1]) : $_[0]{$method} };
    }
}

use Cwd;
use File::Temp;
use File::Basename;

use PDF::Writer;
use PDF::FromHTML::Twig;
use PDF::FromHTML::Template;

use constant HAS_UNICODE_SUPPORT => ($] >= 5.008);

use constant PDF_WRITER_BACKEND => do {
    local $@;

    # For Perl 5.6.x, we have to use pdflib
    PDF::Writer->import('pdflib')
        unless HAS_UNICODE_SUPPORT();

    eval { ref(PDF::Writer->new) }
        or die( "Please install PDF::API2 (preferred) or pdflib_pl first" );
};
use constant HAS_HTML_TIDY => do {
    local $@;
    eval { require HTML::Tidy; 1 } or do {
        unless ( eval { require XML::Clean; 1 } ) {
            die( "Please install HTML::Tidy (preferred) or XML::Clean first" );
        }
        0; # Has XML::Clean but no HTML::Tidy
    };
};

=head1 NAME

PDF::FromHTML - Convert HTML documents to PDF

=head1 SYNOPSIS

    my $pdf = PDF::FromHTML->new( encoding => 'utf-8' );
    $pdf->load_file('source.html');
    $pdf->convert(
        # With PDF::API2, font names such as 'traditional' also works
        Font        => 'font.ttf',
        LineHeight  => 10,
        Landscape   => 1,
    );
    $pdf->write_file('target.pdf');

=head1 DESCRIPTION

This module transforms HTML into PDF, using an assortment of XML
transformations implemented in L<PDF::FromHTML::Twig>.

There is also a command-line utility, L<html2pdf.pl>, that comes
with this distribution.

=head1 PUBLIC METHODS

=cut

sub new {
    my $class = shift;
    bless({
        twig => PDF::FromHTML::Twig->new,
        args => { @_ },
    }, $class);
}

sub load_file {
    my ($self, $file) = @_;
    $self->{file} = $file;
}

sub parse_file {
    my $self = shift;
    my $file = $self->{file};
    my $content = '';

    my $dir = Cwd::getcwd();

    if (!ref $file) {
        open my $fh, $file or die $!;
        chdir File::Basename::dirname($file);
        $content = do { local $/; <$fh> };
    }
    else {
        $content = $$file;
    }

    my $encoding = ($self->args->{encoding} || 'utf8');
    if (HAS_UNICODE_SUPPORT() and $self->args) {
        require Encode;
        $content = Encode::decode($encoding, $content, Encode::FB_XMLCREF());
    }

    $content =~ s{&nbsp;}{}g;
    $content =~ s{<!--.*?-->}{}gs;

    if (HAS_HTML_TIDY()) {
        if (HAS_UNICODE_SUPPORT()) {
            $content = Encode::encode( ascii => $content, Encode::FB_XMLCREF());
        }
        $content = HTML::Tidy->new->clean(
            '<?xml version="1.0" encoding="UTF-8"?>',
            '<html xmlns="http://www.w3.org/1999/xhtml">',
            $content,
        );
    }
    else {
        $content =~ s{&#(\d+);}{chr $1}eg;
        $content =~ s{&#x([\da-fA-F]+);}{chr hex $1}eg;
        $content = XML::Clean::clean($content, '1.0', { encoding => 'UTF-8' });
        $content =~ s{<(/?\w+)}{<\L$1}g;
    }

    $self->twig->parse( $content );

    chdir $dir;
}

=head2 convert(%params)

Convert the loaded file to PDF.  Valid parameters are:

    PageWidth         640
    PageResolution    540
    FontBold          'HelveticaBold'
    FontOblique       'HelveticaOblique'
    FontBoldOblique   'HelveticaBoldOblique'
    LineHeight        12
    FontUnicode       'Helvetica'
    Font              (same as FontUnicode)
    PageSize          'A4'
    Landscape         0

=cut

sub convert {
    my ($self, %args) = @_;

    {
        # import arguments into Twig parameters
        no strict 'refs';
        ${"PDF::FromHTML::Twig::$_"} = $args{$_} foreach keys %args;
    }

    $self->parse_file;

    my ($fh, $filename) = File::Temp::tempfile(
        SUFFIX => '.xml',
        UNLINK => 1,
    );

    binmode($fh);
    if (HAS_UNICODE_SUPPORT()) {
        binmode($fh, ':utf8');
    }

    # use File::Copy;
    # copy($filename => '/tmp/foo.xml');

    # XXX HACK! XXX
    my $text = $self->twig->sprint;
    $text =~ s{\$(__[A-Z_]+__)}{<var name='$1' />}g;
    print $fh $text;
    close $fh;

    # print STDERR "==> Temp file written to $filename\n";

    local $^W;
    $self->pdf(eval { PDF::FromHTML::Template->new( filename => $filename ) })
      or die "$filename: $@";
    $self->pdf->param(@_);
}

sub write_file {
    my $self = shift;
    local $^W;
    $self->pdf->write_file(@_);
}

1;

=head1 HINTS & TIPS

=head2 E<lt>imgE<gt> tags

Add the height and width attributes if you are creating the source HTML,
it keeps PDF::FromHTML from having to open and read the source image file
to get the real size.  Less file I/O means faster processing.

=head1 SEE ALSO

L<PDF::FromHTML::Twig>, L<PDF::Template>, L<XML::Twig>.

=head1 AUTHORS

Audrey Tang E<lt>cpan@audreyt.orgE<gt>

=head1 CONTRIBUTORS

Charleston Software Associates E<lt>info@charletonsw.comE<gt>

=head1 COPYRIGHT

Copyright 2004, 2005 by Audrey Tang E<lt>cpan@audreyt.orgE<gt>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
