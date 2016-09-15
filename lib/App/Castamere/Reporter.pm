use 5.20.0;
use warnings;

package App::Castamere::Reporter;

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

use Devel::NYTProf::Data;
use Devel::NYTProf::Util qw/
        fmt_float
        fmt_time
        calculate_median_absolute_deviation
        get_abs_paths_alternation_regex
/;
use App::Castamere::Prof::File;
use experimental qw/postderef signatures/;

use constant SEVERITY_SEVERE => 2.0;
use constant SEVERITY_BAD => 1.0;
use constant SEVERITY_GOOD => 0.5;

our $FLOAT_FORMAT = $Config{'nvfformat'} =~ s{"}{}rg;

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
# -- end constructor arguments
has sawampersand => (
    is => 'rw',
    isa => Bool,
    init_arg => undef,
    default => 0,
);
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
    isa => ArrayRef[InstanceOf['App::Castamere::Prof::File']],
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
                    take(App::Castamere::Prof::File->new(profile => $self->profile, fileinfo => $fileinfo, level => $level));
                }
            }
        }
    ];
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

1;
