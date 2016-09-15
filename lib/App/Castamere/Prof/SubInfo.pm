use 5.20.0;
use warnings;

package App::Castamere::Prof::SubInfo;

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
use App::Castamere::Util qw/fix_time/;
use Data::Printer;
use experimental qw/postderef signatures/;

has subinfo => (
    is => 'ro',
    isa => InstanceOf['Devel::NYTProf::SubInfo'],
    handles => [qw/caller_fid_line_places subname incl_time excl_time calls/],
    required => 1,
);
#----
has callers => (
    is => 'ro',
    isa => ArrayRef,
    lazy => 1,
    default => sub($self) {
        my $callers = $self->subinfo->caller_fid_line_places;
        return [] unless $callers && $callers->%*;
        return [
            gather {
                for my $fid (keys $callers->%*) {
                    my $line_info = $callers->{ $fid };

                    for my $line (keys $line_info->%*) {
                        my $caller = $line_info->{ $line };

                        take +{
                            fid => $fid,
                            line => $line,
                            total_calls => $caller->[0],
                            incl_time => $caller->[1],
                            excl_time => $caller->[2],
                            calling_subs => [keys $caller->[7]->%*],
                        };
                    }
                }
            }
        ];
    },
);

sub maximum_calls_by_caller($self) {
    return max(map { $_->{'total_calls'} } $self->callers->@*);
}
sub how_much_shorter_than_maximum_calls($self, $comparer) {
    return length($self->maximum_calls_by_caller) - length($comparer);
}
sub formatted_time_incl_excl($self) {
    return fix_time fmt_incl_excl_time($self->incl_time, $self->excl_time);
}
sub formatted_avg_time_per_call($self) {
    return fix_time fmt_time $self->incl_time / $self->calls;
}
sub format_time($self, @args) {
    return fix_time fmt_time @args;
}

1;

__END__

