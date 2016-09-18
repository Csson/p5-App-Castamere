use 5.20.0;
use warnings;

package App::Proffy::Util;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use base qw/Exporter/;
use Devel::NYTProf::Util qw/fmt_time get_abs_paths_alternation_regex/;
use Syntax::Keyword::Try 'try';
use experimental qw/postderef signatures/;

our @EXPORT_OK = qw/
   fix_time
   format_time
   sub_url_info
/;

sub fix_time($time) {
    utf8::decode $time;
    return $time;
}
sub format_time($time, @args) {
    return fix_time fmt_time $time, @args;
}

sub sub_url_info($profile, $sub, $file = undef) {
    my $subname;
    {
        my $to_return_if_fail = +{
            filename => '',
            clean_filename => '',
            first_line => '',
            last_line => '',
            fileinfo => '',
            package => '',
            subname => '',
            anchor => '',
            extras => '',
        };
        try {
            # peekaboo (suppress cluck callstack)
            if(!ref $sub && !exists $profile->{'sub_subinfo'}{ $sub }) {
                return $to_return_if_fail;
            }

            $sub = !ref $sub ? $profile->subinfo_of($sub) : $sub;
            $subname = $sub->subname;
        }
        catch {
            return $to_return_if_fail;
        }
    }

    my $extras = [];
    if(my $merged_sub_names = $sub->meta->{'merged_sub_names'}) {
        push $extras->@*, sprintf 'merge of %d subs', 1 + scalar $merged_sub_names->@*;
    }
    my($package, $clean) = $subname =~ m{^(.*::)(.*?)$} ? ($1, $2) : ('', $subname);

    if($file) {
        my $in_filename = $file->fileinfo->filename;
        $clean =~ s{\Q$in_filename\E:(\d+)}{:$1}g;
    }
    my $inc_path_regex = get_abs_paths_alternation_regex([$profile->inc], qr/^|\[/);
    $clean =~ s{$inc_path_regex}{};


    if($sub->is_xsub) {
        my $is_opcode = $package eq 'CORE' || $clean =~ m{^CORE:};
        unshift $extras->@*, $is_opcode ? 'opcode' : 'xsub';
    }
    if(my $recur_depth = $sub->recur_max_depth) {
        unshift $extras->@*, sprintf 'recurses: max depth %s, inclusive time %s', $recur_depth, format_time($sub->recur_incl_time);
    }

    my @subrange = $profile->file_line_range_of_sub($sub->subname);

    return +{
        filename => $subrange[0],
        clean_filename => $subrange[0] =~ s{$inc_path_regex}{}rg,
        first_line => $subrange[2],
        last_line => $subrange[3],
        fileinfo => $subrange[4],
        package => $package,
        subname => $clean,
        anchor => 'line-' . ($subrange[2] ? $subrange[2] : lc $sub->subname =~ s{\W+}{-}rg),
        extras => $extras,
    };
}

1;
