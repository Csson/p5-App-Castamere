use 5.20.0;
use warnings;

package App::Castamere::Prof::File;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use Moo;
use Types::Standard -all;
use List::Util qw/max sum/;
use PerlX::Maybe;
use Syntax::Keyword::Gather;
use Devel::NYTProf::Util qw/calculate_median_absolute_deviation/;
use App::Castamere::Prof::Line;
use App::Castamere::Prof::SubInfo;
use experimental qw/postderef signatures/;

has fileinfo => (
    is => 'ro',
    isa => InstanceOf['Devel::NYTProf::FileInfo'],
    required => 1,
);
has level => (
    is => 'ro',
    isa => Str,
    default => 'line',
);

has profile => (
    is => 'ro',
    isa => InstanceOf['Devel::NYTProf::Data'],
    required => 1,
);
# -- end constructor arguments
has meta => (
    is => 'rw',
    isa => HashRef,
    lazy => 1,
    default => sub($self) { $self->fileinfo->meta },
);
has subcalls_at_line => (
    is => 'rw',
    isa => HashRef,
    lazy => 1,
    default => sub($self) { $self->fileinfo->sub_call_lines },
);
has subcalls_max_line => (
    is => 'rw',
    isa => Int,
    lazy => 1,
    default => sub($self) { max(keys $self->subcalls_at_line->%*) || 0 },
);
has subdefs_at_line => (
    is => 'rw',
    isa => HashRef,
    lazy => 1,
    default => sub($self) {
        my $subdefs = $self->profile->subs_defined_in_file_by_line($self->fileinfo->filename);
        delete $subdefs->{'0'}; # prof: xsubs handled separately
        return $subdefs;
    },
);
has subdefs_max_line => (
    is => 'rw',
    isa => Int,
    lazy => 1,
    default => sub($self) { max(keys $self->subdefs_at_line->%*) || 0 },
);
has xsubs => (
    is => 'ro',
    isa => ArrayRef,
    lazy => 1,
    builder => 1,
);
sub _build_xsubs($self) {
    my $subs_defined_in_file = $self->profile->subs_defined_in_file($self->fileinfo->filename);
    return [
        gather {
            for my $subname (sort keys $subs_defined_in_file->%*) {
                my $subinfo = $subs_defined_in_file->{ $subname };
                next if $subinfo->kind eq 'perl';
                next if !$subinfo->calls;
                take(App::Castamere::Prof::SubInfo->new(subinfo => $subinfo));
            }
        }
    ];
}



has evals_at_line => (
    is => 'rw',
    isa => HashRef,
    lazy => 1,
    default => sub($self) { $self->fileinfo->evals_by_line },
);
has evals_max_line => (
    is => 'rw',
    isa => Int,
    lazy => 1,
    default => sub($self) { max(keys $self->evals_at_line->%*) || 0 },
);
has fileinfo_lines_array => (
    is => 'rw',
    isa => ArrayRef,
    lazy => 1,
    default => sub($self) { $self->fileinfo->line_time_data([$self->level]) || [] },
);
has source_max_line => (
    is => 'rw',
    isa => Int,
    lazy => 1,
    default => sub($self) { scalar $self->fileinfo_lines_array->@* },
);
has lines => (
    is => 'ro',
    isa => ArrayRef[InstanceOf['App::Castamere::Prof::Line']],
    lazy => 1,
    builder => 1,
);
sub _build_lines($self) {
    my $max_linenum = max($self->subcalls_max_line, $self->subdefs_max_line, $self->evals_max_line, $self->source_max_line);

    return [
        gather {
            for my $linenum (0..$max_linenum) {
                take(App::Castamere::Prof::Line->new(
                          level => $self->level,
                          profile => $self->profile,
                    maybe subcalls => $self->subcalls_at_line->{ $linenum },
                    maybe subdefs => $self->subdefs_at_line->{ $linenum },
                    maybe evalcalls => $self->evals_at_line->{ $linenum },
                    maybe statements => $self->fileinfo_lines_array->[$linenum],
                          num => scalar(gathered->@*),
                ));
            }
        }
    ];
}
has total_subcall_count => (
    is => 'ro',
    isa => Int,
    lazy => 1,
    default => sub($self) {
        sum(map { $_->subcall_count } $self->filtered_lines('subcall_count')->@*);
    },
);
has total_subcall_time => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    default => sub($self) {
        sum(map { $_->subcall_time } $self->filtered_lines('subcall_time')->@*);
    }
);
has total_time => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    default => sub($self) {
        sum(map { $_->time } $self->filtered_lines('time')->@*);
    }
);
has total_calls => (
    is => 'ro',
    isa => Int,
    lazy => 1,
    default => sub($self) {
        sum(map { $_->calls } $self->filtered_lines('calls')->@*);
    }
);
has average_time_per_call => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    default => sub($self) {
        (sum(map { $_->time } $self->filtered_lines('time')->@*)) / (sum(map { $_->calls } $self->filtered_lines('calls')->@*));
    }
);

sub filtered_lines($self, $method) {
    [grep { defined $_->$method } $self->lines->@*];
}

sub merged_evals($self) {
    my $merged = $self->fileinfo->meta->{'merged_fids'};
    return $merged ? $merged : [];
}
sub has_merged_evals($self) {
    return !!scalar $self->merged_evals->@*;
}

sub nested_eval_time($self) {
     return sum map { $_->sum_of_stmts_time } $self->fileinfo->has_evals(1);
}

sub eval_total_time($self) {
    return $self->sum_of_stmts_time + $self->nested_eval_time;
}
sub eval_excl_time($self) {
    return sum(map { $_->excl_time } $self->fileinfo->subs_defined(1)),
}
sub eval_call_count($self) {
    return sum(map { $_->calls } $self->fileinfo->subs_defined(1));
}
sub eval_sub_count($self) {
    return scalar $self->fileinfo->subs_defined(1);
}

sub stats($self) {
    my $i = [map { $_->statement_calls } grep { $_->statement_calls } $self->lines->@*];
    use Data::Printer;
    p $i;
    my $calls = calculate_median_absolute_deviation($i);
    p $calls;
    return +{
        calls => {
            median => $calls->[1],
            deviation => $calls->[0],
        },
    };
}

1;
