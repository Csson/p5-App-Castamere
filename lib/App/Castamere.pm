use 5.20.0;
use strict;
use warnings;

package App::Castamere;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use base 'App::Spec::Run';
use Moo;
use Dir::Self;
use List::Util qw/any/;
use App::Castamere::Reporter;
use App::Castamere::HtmlGenerator;

sub doit {
    my $reporter = App::Castamere::Reporter->new;
    my $generator = App::Castamere::HtmlGenerator->new(reporter => $reporter);

}

1;

__END__

=pod

=head1 SYNOPSIS

    use App::Castamere;

=head1 DESCRIPTION

App::Castamere is ...

=head1 SEE ALSO

=cut
