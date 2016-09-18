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
use Devel::NYTProf::Util qw/calculate_median_absolute_deviation get_abs_paths_alternation_regex/;
use App::Castamere::Prof::Line;
use App::Castamere::Prof::SubInfo;
use experimental qw/postderef signatures/;

has fileinfo => (
    is => 'ro',
    isa => InstanceOf['Devel::NYTProf::FileInfo'],
    handles => [qw/meta/],
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
has total_statement_calls => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    builder => 1,
);
sub _build_total_statement_calls($self) {
    return sum(map { $_->statement_calls } $self->lines->@*) || 0;
}

has total_statement_time => (
    is => 'ro',
    isa => Num,
    lazy => 1,
    builder => 1,
);
sub _build_total_statement_time($self) {
    return sum(map { $_->statement_time } $self->lines->@*) || 0;
}

has stats => (
    is => 'ro',
    isa => HashRef,
    lazy => 1,
    builder => 1,
);
sub _build_stats($self) {
    my $calls = calculate_median_absolute_deviation([map { $_->statement_calls } grep { $_->statement_calls } $self->lines->@*]);
    my $time = calculate_median_absolute_deviation([map { $_->statement_time } grep { $_->statement_time } $self->lines->@*]);
    my $time_per_call = calculate_median_absolute_deviation([map { $_->statement_average_time_per_call } grep { $_->statement_time } $self->lines->@*]);
    my $subcall_count = calculate_median_absolute_deviation([map { $_->subcall_count } grep { $_->subcall_count } $self->lines->@*]);
    my $subcall_time = calculate_median_absolute_deviation([map { $_->subcall_time } grep { $_->subcall_time } $self->lines->@*]);

    return +{
        calls => {
            median => $calls->[1],
            deviation => $calls->[0],
        },
        time => {
            median => $time->[1],
            deviation => $time->[0],
        },
        time_per_call => {
            median => $time_per_call->[1],
            deviation => $time_per_call->[0],
        },
        subcall_count => {
            median => $subcall_count->[1],
            deviation => $subcall_count->[0],
        },
        subcall_time => {
            median => $subcall_time->[1],
            deviation => $subcall_time->[0],
        },
    };
}
sub stats_for($self, $what) {
    return $self->stats->{ $what };
}
has sub_stats => (
    is => 'ro',
    isa => HashRef,
    lazy => 1,
    builder => 1,
);
sub _build_sub_stats($self) {
    my $subs = $self->subs;

    my $incl_time = calculate_median_absolute_deviation([map { scalar $_->incl_time } grep { scalar $_->incl_time } $subs->@*]);
    my $excl_time = calculate_median_absolute_deviation([map { scalar $_->excl_time } grep { scalar $_->excl_time } $subs->@*]);
    my $calls = calculate_median_absolute_deviation([map { scalar $_->calls } grep { scalar $_->calls } $subs->@*]);
    my $caller_count = calculate_median_absolute_deviation([map { scalar $_->caller_count } grep { scalar $_->caller_count } $subs->@*]);
    my $caller_fids = calculate_median_absolute_deviation([map { scalar $_->caller_fids } grep { scalar $_->caller_fids } $subs->@*]);

    return +{
        incl_time => {
            median => $incl_time->[1],
            deviation => $incl_time->[0],
        },
        excl_time => {
            median => $excl_time->[1],
            deviation => $excl_time->[0],
        },
        calls => {
            median => $calls->[1],
            deviation => $calls->[0],
        },
        caller_count => {
            median => $caller_count->[1],
            deviation => $caller_count->[0],
        },
        caller_fids => {
            median => $caller_fids->[1],
            deviation => $caller_fids->[0],
        },
    };
}
sub sub_stats_for($self, $what) {
    return $self->sub_stats->{ $what };
}

sub clean_filename($self) {
    my $inc_path_regex = get_abs_paths_alternation_regex([$self->profile->inc], qr/^|\[/);
    return $self->fileinfo->filename =~ s{$inc_path_regex}{}r;
}
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

sub total_eval_time($self) {
     return sum(map { $_->sum_of_stmts_time } $self->fileinfo->has_evals(1)) || 0;
}
sub nested_eval_count($self) {
    return scalar grep { $_->eval_fid != $self->fileinfo->fid }  $self->fileinfo->has_evals(1);
}
#sub eval_total_time($self) {
#    return $self->sum_of_stmts_time + $self->nested_eval_time;
#}
sub eval_excl_time($self) {
    return sum(map { $_->excl_time } $self->fileinfo->subs_defined(1)),
}
sub eval_call_count($self) {
    return sum(map { $_->calls } $self->fileinfo->subs_defined(1));
}
sub eval_statement_count($self) {
    return sum(map { $_->sum_of_stmts_count } grep { $_->sum_of_stmts_count } $self->fileinfo->has_evals(1)) || 0;
}
sub eval_sub_count($self) {
    return scalar $self->fileinfo->subs_defined(1);
}

sub total_statement_and_eval_time($self) {
    return $self->total_statement_time + $self->total_eval_time;
}

sub subs($self, %opts) {
    my $order_by = $opts{'order_by'} || undef;
    my $limit = $opts{'limit'} || undef;

    if(!$order_by) {
        return [sort { $a->subname cmp $b->subname } values $self->profile->subs_defined_in_file($self->fileinfo)->%*];
    }
    return [sort { $b->$order_by <=> $a->$order_by || $a->subname cmp $b->subname } values $self->profile->subs_defined_in_file($self->fileinfo)->%*];
}

1;
