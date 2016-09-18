use 5.20.0;
use warnings;

package App::Proffy::Core::SubCall;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use Moo;
use Types::Standard -all;
use List::Util qw/max/;
use Syntax::Keyword::Gather;
use Devel::NYTProf::Util qw/
                fmt_float
                fmt_time
                fmt_incl_excl_time
/;
use App::Proffy::Util qw/fix_time/;
use Data::Printer;
use experimental qw/postderef signatures/;

has subcall => (
    is => 'ro',
    isa => ArrayRef,
    required => 1,
);
has to => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has calls => (
    is => 'ro',
    isa => Int,
    required => 1,
);
has incl_time => (
    is => 'ro',
    isa => Num,
    required => 1,
);
has recur_time => (
    is => 'ro',
    isa => Num,
    required => 1,
);
has recur_depth => (
    is => 'ro',
    isa => Int,
    required => 1,
);
has origins => (
    is => 'ro',
    isa => ArrayRef,
    required => 1,
);

around BUILDARGS => sub ($orig, $class, %args) {
    return $class->$orig(%args) if !exists $args{'subcall'};

    my $subcall = $args{'subcall'};
    $args{'calls'} = $subcall->[0];
    $args{'incl_time'} = $subcall->[1];
    $args{'recur_time'} = $subcall->[5];
    $args{'recur_depth'} = $subcall->[6];
    $args{'origins'} = [keys $subcall->[7]->%*];

    $class->$orig(%args);
};

sub incl_and_recur_time($self) {
    return $self->incl_time + $self->recur_time;
}

1;

__END__

