use 5.20.0;
use warnings;

package App::Castamere::Prof::Line;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use Moo;
use MooX::Aliases;
use namespace::autoclean;
use Types::Standard -all;
use Syntax::Keyword::Gather;
use List::Util qw/sum any/;
use Devel::NYTProf::Util qw/
                fmt_float
                fmt_time
                fmt_incl_excl_time
/;
use experimental qw/postderef signatures/;
use App::Castamere::Prof::File;
use App::Castamere::Prof::SubInfo;
use App::Castamere::Prof::SubCall;
use App::Castamere::Util qw/fix_time/;

has num => (
    is => 'ro',
    isa => Int,
    required => 1,
);

has subcalls => (
    is => 'ro',
    isa => ArrayRef[InstanceOf['App::Castamere::Prof::SubCall']],
    alias => 'subcall_info',
    default => sub { [] },
);
has subdefs => (
    is => 'ro',
    isa => ArrayRef[InstanceOf['App::Castamere::Prof::SubInfo']],
    alias => 'subdef_info',
    default => sub { [] },
);
has evalcalls => (
    is => 'ro',
    isa => HashRef,
    alias => 'evalcall_info',
    default => sub { +{} },
);
has statements => (
    is => 'ro',
    isa => ArrayRef,
    default => sub { [] },
);
has level => (
    is => 'ro',
    isa => Str,
    required => 1,
);
has profile => (
    is => 'ro',
    isa => InstanceOf['Devel::NYTProf::Data'],
    required => 1,
);

#-- end constructor arguments
has subcall_count => (
    is => 'ro',
    isa => Int,
    lazy => 1,
    default => sub($self) { sum(map { $_->calls } $self->subcalls->@*) || 0 },
);
has subcall_time => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    default => sub($self) { sum(map { $_->incl_time } $self->subcalls->@*) || 0 },
);
has evalcall_count => (
    is => 'ro',
    isa => Int,
    lazy => 1,
    default => sub($self) { scalar values $self->evalcalls->%* },
);
has eval_files => (
    is => 'ro',
    isa => ArrayRef[InstanceOf['App::Castamere::Prof::File']],
    lazy => 1,
    builder => 1,
);
sub _build_eval_files($self) {
    return [map { App::Castamere::Prof::File->new(profile => $self->profile, fileinfo => $_, level => $self->level) } $self->eval_fis->@*];
}
# This is an array ref of all nested evals
has eval_fis => (
    is => 'ro',
    isa => ArrayRef,
    lazy => 1,
    default => sub($self) { [map { ($_->fileinfo, $_->fileinfo->has_evals(1)) } values $self->evalcalls->%*] },
);
has evalcall_count_nested => (
    is => 'ro',
    isa => Int,
    lazy => 1,
    default => sub($self) { scalar $self->eval_fis->@* },
);
has evalcall_stmts_time_nested => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    default => sub($self) { sum(map { $_->sum_of_stmts_time } $self->eval_fis->@*) },
);
has time => (
    is => 'ro',
    isa => Maybe[Num],
    lazy => 1,
    default => sub($self) {
        sum(map { $_->{'incl_time'} + 0 } map { $_->callers->@* } $self->subdefs->@*) || 0;
    },
);
has calls => (
    is => 'ro',
    isa => Maybe[Int],
    lazy => 1,
    default => sub($self) {
        sum(map { $_->{'total_calls'} + 0 } map { $_->callers->@* } $self->subdefs->@*) || 0;
    },
);
has statement_calls => (
    is => 'ro',
    isa => Int,
    lazy => 1,
    default => 0,
);
has statement_time => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    default => 0,
);
has statement_average_time_per_call => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    default => sub($self) {
        return 0 if !$self->statement_calls || !$self->statement_time;
        return $self->statement_time / $self->statement_calls;
    },
);




around BUILDARGS => sub ($orig, $class, %args) {

    if(exists $args{'subcalls'}) {
        $args{'subcalls'} = [
            gather {
                for my $to (keys $args{'subcalls'}->%*) {
                    take(App::Castamere::Prof::SubCall->new(to => $to, subcall => $args{'subcalls'}{ $to }));
                }
            }
        ];
    }
    if(exists $args{'subdefs'}) {
        $args{'subdefs'} = [
            gather {
                for my $subdef ($args{'subdefs'}->@*) {
                    take(App::Castamere::Prof::SubInfo->new(subinfo => $subdef));
                }
            }
        ];
    }
    if(exists $args{'evalcalls'}) {
        my $new_evalcalls = {};
        for my $key ($args{'evalcalls'}->%*) {
            next if !ref $args{'evalcalls'}{ $key };
            $new_evalcalls->{ $key } = App::Castamere::Prof::File->new(
                profile => $args{'profile'},
                level => $args{'level'},
                fileinfo => $args{'evalcalls'}{ $key },
            );
        }
        $args{'evalcalls'} = $new_evalcalls;
    }
    if($args{'statements'} && $args{'statements'}->@* == 2) {
        $args{'statement_time'} = $args{'statements'}->[0] || 0;
        $args{'statement_calls'} = $args{'statements'}->[1] || 1;
    }
    return $class->$orig(%args);
};

sub formatted_avg_time_per_call($self) {
    return fix_time fmt_time($self->time / $self->calls);
}

sub sorted_subcalls($self) {
    return [sort { $b->incl_time <=> $a->incl_time || $b->calls <=> $a->calls } $self->subcalls->@*];
}
sub sorted_eval_files($self) {
    return [sort { $b->fileinfo->sum_of_stmts_time(1) <=> $a->fileinfo->sum_of_stmts_time(1) || $a->fileinfo->filename cmp $b->fileinfo->filename } $self->eval_files->@*];
}

sub has_callers($self) {
    return any { scalar $_->callers->@* } $self->subdefs->@*;
}

1;
