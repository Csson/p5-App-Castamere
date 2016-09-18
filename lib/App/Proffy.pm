use 5.20.0;
use strict;
use warnings;

package App::Proffy;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use base 'App::Spec::Run';
use Moo;
use Dir::Self;
use List::Util qw/any/;
use App::Proffy::Reporter;

sub doit {
    my $reporter = App::Proffy::Reporter->new;
}

1;

__END__

=pod

=head1 SYNOPSIS

    use App::Proffy;

=head1 DESCRIPTION

App::Proffy is ...

=head1 SEE ALSO

=cut
