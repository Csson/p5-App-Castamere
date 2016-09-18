use 5.20.0;
use warnings;

package App::Proffy::Reporter;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use Moo;
use Carp;
use Config;

use List::Util qw/any/;
use Data::Dumper;
use Types::Standard -all;
use Path::Tiny;
use Types::Path::Tiny -all;
use Syntax::Keyword::Gather;
use Data::Printer;
use Config qw/%Config/;
use File::Spec;

use Devel::NYTProf::Data;
use Devel::NYTProf::Util qw/
        fmt_float
        fmt_time
        calculate_median_absolute_deviation
        get_abs_paths_alternation_regex
/;
use App::Proffy::Core::File;
use Graph::Flames;
use Graph::Flames::CallStack;
use experimental qw/postderef signatures/;

=pod

html related attributes:
 * header
 * datastart
 * mk_report_source_line
 * mk_report_separator_line
 * dataend

 (possibly more)

=cut

has infile => (
    is => 'ro',
    isa => File,
    coerce => 1,
    default => sub { path('nytprof.out') },
);
has quiet => (
    is => 'ro',
    isa => Bool,
    default => 0,
);
has profile_attrs => (
    is => 'ro',
    isa => HashRef,
    default => sub($self) {
        return {
            filename => $self->infile->stringify,
            skip_collapse_evals => 0,
        };
    },
);
has nytprofcalls => (
    is => 'ro',
    default => sub {
        File::Spec->catfile($Config{'bin'}, 'nytprofcalls');
    },
);
# -- end constructor arguments
has profile => (
    is => 'ro',
    isa => InstanceOf['Devel::NYTProf::Data'],
    lazy => 1,
    default => sub($self) {
        Devel::NYTProf::Data->new($self->profile_attrs);
    },
);
has files => (
    is => 'ro',
    isa => ArrayRef[InstanceOf['App::Proffy::Core::File']],
    lazy => 1,
    init_arg => undef,
    builder => 1,
);
sub _build_files($self) {
    return [
        gather {
            for my $level ($self->levels) {
                my @fileinfos = $self->get_all_fileinfos($level);

                for my $fileinfo (@fileinfos) {
                    take(App::Proffy::Core::File->new(profile => $self->profile, fileinfo => $fileinfo, level => $level));
                }
            }
        }
    ];
}
has _subs => (
    is => 'ro',
    isa => ArrayRef,
    lazy => 1,
    default => sub($self) { [values $self->profile->subname_subinfo_map->%*] },
);
has sub_stats => (
    is => 'ro',
    isa => HashRef,
    lazy => 1,
    builder => 1,
);
sub _build_sub_stats($self) {
    my $subs = $self->_subs;

    my $incl_time = calculate_median_absolute_deviation([map { scalar $_->incl_time } grep { $_->incl_time } $subs->@*], 1);
    my $excl_time = calculate_median_absolute_deviation([map { scalar $_->excl_time } grep { $_->excl_time } $subs->@*], 1);
    my $calls = calculate_median_absolute_deviation([map { scalar $_->calls } grep { scalar $_->calls } $subs->@*], 1);
    my $caller_count = calculate_median_absolute_deviation([map { scalar $_->caller_count } grep { scalar $_->caller_count } $subs->@*], 1);
    my $caller_fids = calculate_median_absolute_deviation([map { scalar $_->caller_fids } grep { scalar $_->caller_fids } $subs->@*], 1);

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
has file_stats => (
    is => 'ro',
    isa => HashRef,
    lazy => 1,
    builder => 1,
);
sub _build_file_stats($self) {
    my $excl_time = calculate_median_absolute_deviation([map { scalar $_->total_statement_and_eval_time } grep { $_->total_statement_and_eval_time } $self->noneval_files->@*], 1);
    my $stmts = calculate_median_absolute_deviation([map { scalar $_->total_statement_calls + $_->eval_statement_count } grep { $_->total_statement_calls && $_->eval_statement_count } $self->noneval_files->@*], 1);

    return +{
        excl_time => {
            median => $excl_time->[1],
            deviation => $excl_time->[0],
        },
        stmts => {
            median => $stmts->[1],
            deviation => $stmts->[0],
        },
    };
}

has callstacks => (
    is => 'ro',
    isa => ArrayRef[InstanceOf['Graph::Flames::CallStack']],
    lazy => 1,
    builder => 1,
);
sub _build_callstacks($self) {
    my $nytprofcalls = $self->nytprofcalls;
    my $infile = $self->infile;
    my @data = split /\n/ => qx/$nytprofcalls $infile/;

    return [
        gather {
            for my $stack (@data) {
                $stack =~ m{^(?<stack>.*) (?<ticks>[^ ]+)$};
                my @calls = split /;/ => $+{'stack'};

                take(Graph::Flames::CallStack->new(calls => \@calls, ticks => $+{'ticks'}));
            }
        }
    ];
}
has flamegraph => (
    is => 'ro',
    isa => InstanceOf['Graph::Flames'],
    lazy => 1,
    default => sub($self) {
        Graph::Flames->new(callstacks => $self->callstacks, ticks_per_second => $self->ticks_per_second, total_time => $self->profiler_active);
    }
);



# shortcuts for profile stuff
sub total_stmts_duration($self) {
    return $self->profile->{'attribute'}{'total_stmts_duration'};
}
sub total_stmts_measured($self) {
    return $self->profile->{'attribute'}{'total_stmts_measured'};
}
sub total_stmts_discounted($self) {
    return $self->profile->{'attribute'}{'total_stmts_discounted'};
}
sub total_stmts($self) {
    return $self->total_stmts_measured - $self->total_stmts_discounted;
}
sub application($self) {
    return $self->profile->{'attribute'}{'application'};
}
sub profiler_active($self) {
    return $self->profile->{'attribute'}{'profiler_active'};
}
sub profiler_duration($self) {
    return $self->profile->{'attribute'}{'profiler_duration'};
}
sub total_sub_calls($self) {
    return $self->profile->{'attribute'}{'total_sub_calls'};
}
sub ticks_per_second($self) {
    return $self->profile->{'attribute'}{'ticks_per_sec'};
}

sub subs($self, %opts) {
    my $order_by = $opts{'order_by'} || undef;
    my $limit = $opts{'limit'} || undef;

    my @subs;
    if($order_by) {
        @subs = sort { $b->$order_by <=> $a->$order_by } $self->_subs->@*;
    }
    else {
        @subs = $self->_subs->@*;
    }
    return \@subs if !$limit;
    return [splice @subs, 0, $limit];
}

sub levels($self) {
    my $levels = $self->profile->get_profile_levels;
    return grep { my $test = $_; any { $test eq $_ } (values $levels->%*) } (qw/sub block line/);
}
sub get_all_fileinfos($self, $level) {
    my @all_fileinfos = $self->profile->all_fileinfos or carp "Profile report data contains no files";

    if($level ne 'line') {
        @all_fileinfos = grep { not $_->is_eval } @all_fileinfos;
    }
    return @all_fileinfos;
}
sub filename_of_fid($self, $fid) {
    my $inc_path_regex = get_abs_paths_alternation_regex([$self->profile->inc], qr/^|\[/);
    my $filename = $self->profile->fileinfo_of($fid)->filename($fid);
    $filename =~ s{$inc_path_regex}{};
    return $filename;
}
sub noneval_files($self) {
    return [grep { !$_->fileinfo->eval_line } $self->files->@*];
}

1;
