use 5.20.0;
use warnings;

package App::Castamere::HtmlGenerator;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use Moo;
use Path::Tiny;
use Types::Standard -all;
use Types::Path::Tiny qw/Dir Path/;
use Dir::Self;
use List::Util qw/sum/;
use Devel::NYTProf::Util qw/
                fmt_float
                fmt_time
                fmt_incl_excl_time
                calculate_median_absolute_deviation
/;
use Data::Printer;
use experimental qw/postderef signatures/;

has reporter => (
    is => 'ro',
    isa => InstanceOf['App::Castamere::Reporter'],
    required => 1,
    handles => [qw/profile/],
);
has output_dir => (
    is => 'ro',
    isa => Path,
    coerce => 1,
    default => sub { path('castamere') },
);
has template_dir => (
    is => 'ro',
    isa => Dir,
    coerce => 1,
    default => sub { path(__DIR__ .'/../../../share/templates') },
);

sub BUILD($self, @) {

    my $total_calls = 0;
    my $total_time = 0;
    my @files = grep { $_->fileinfo->filename =~ m{Sub/Quote\.pm} } $self->reporter->files->@*;
    my $file = $files[0];
#
#    my $eval = $file->lines->[3]->evalcall_info;
#            say join "\n", keys $eval->%*;
#    my $count = 0;
#    for my $key (sort { $eval->{ $b }->total_time <=> $eval->{ $a }->total_time } keys $eval->%*) {
#        ++$count;
#        my $e = $eval->{ $key };
#        #say ">$key: $count   " . $e->total_time . '  ' . $e->total_calls . '  ' . (scalar keys $e->subcalls_at_line->%*);
#        say sprintf ' # includes %s spent executing %d calls to %d subs defined therein',
#                       $e->eval_excl_time,
#                       $e->eval_call_count,
#                       $e->eval_sub_count;
#
#        say ref $e;
#        say $e->total_time;
#    }
#
#    say '-' x 100;
    my $linenum = 0;
    SOURCELINE:
    for my $source_line ($file->fileinfo->srclines_array->@*) {
        ++$linenum;
        next if $linenum < 25;
        last if $linenum > 32;
        chomp $source_line;
        my $line = $file->lines->[$linenum];

say $linenum . ' -------------------------------------------------------';

        say "statements: " . $line->statements->@*;
        for my $subinfo ($line->subdefs->@*) {
#            say ref $subinfo;
            my $callers = [sort { $b->{'total_calls'} <=> $a->{'total_calls'} || $b->{'incl_time'} <=> $a->{'incl_time'} } $subinfo->callers->@*];
            next if !scalar $callers->@*;
            say sprintf '   # spent %s within %s which was called %s',
                                fmt_incl_excl_time($subinfo->incl_time, $subinfo->excl_time),
                                $subinfo->subname,
                                $line->calls <= 1
                                ? ''
                                : sprintf(" %d times, avg %s/call",
                                        $line->calls, fmt_time($line->time / $line->calls));

            say scalar $callers->@*;
            for my $caller ($callers->@*) {
                my $timers = sprintf " (%s+%s)", fmt_time($caller->{'excl_time'}),  fmt_time($caller->{'incl_time'} - $caller->{'excl_time'});
                my $avg_time = "";
                $avg_time = sprintf "avg %s/call", fmt_time($caller->{'incl_time'} / $caller->{'total_calls'}) if $caller->{'total_calls'} > 1;

                say sprintf q{# %*s times%s by %s at line %s of %s, %s},
                        length($subinfo->maximum_calls_by_caller),
                        $caller->{'total_calls'},
                        $timers,
                        $subinfo->subname,
                        $caller->{'line'}, $self->reporter->filename_of_fid($caller->{'fid'}), $avg_time;
            }

            say '  ' . $line->calls || '';
            my $subname = $subinfo->subname;
          #  p $sub_info; die;
            say $subname;
            say "    $source_line";
            next SOURCELINE;
        }
        say $line->calls || '';

    }
}

1;

__END__
 my $caller_fi = $profile->fileinfo_of($fid);
my $filename = $caller_fi->filename($fid);

my $filename = $self->profile->fileinfo_of($caller->{'fid'})->filename($caller->{'fid'})

__END__

     for my $caller (@callers) {
                my ($fid, $line, $count, $incl_time, $excl_time, undef, undef,
                    undef, undef, $calling_subs) = @$caller;

                my @subnames = sort keys %{$calling_subs || {}};
                my $subname = (@subnames) ? " by " . join(" or ", @subnames) : "";

                my $caller_fi = $profile->fileinfo_of($fid);
                if (!$caller_fi) { # should never happen
                    warn sprintf "Caller of %s, from fid %d line %d has no fileinfo (%s)",
                        $sub_info, $fid, $line, $subname;
                        die 2;
                    next;
                }

                my $avg_time = "";
                $avg_time = sprintf ", avg %s/call", fmt_time($caller->{'incl_time'} / $caller->{'total_calls'})
                    if $count > 1;
                my $times = sprintf " (%s+%s)", fmt_time($caller->{'excl_time'}),
                    fmt_time($caller->{'incl_time'} - $caller->{'excl_time'});

                my $filename = $caller_fi->filename($fid);
                my $line_desc = "line $line of $filename";
                $line_desc =~ s/ of \Q$filename\E$//g if $filename eq $fi->filename;
                # remove @INC prefix from paths
                $line_desc =~ s/$inc_path_regex//g;

                my $href = $reporter->href_for_file($caller_fi, $line);
                push @prologue,
                    sprintf q{# %*s times%s%s at <a %s>%s</a>%s},
                                length($max_calls), $count, $times, $subname, $href,
                    $line_desc, $avg_time;
                $prologue[-1] =~ s/^(# +)1 times/$1   once/;  # better English
            }










        my $subdef_info = $stats_for_line->{subdef_info} || [];
        for my $sub_info (@$subdef_info) {
            my $callers = $sub_info->caller_fid_line_places;
            next unless $callers && %$callers;
            my $subname = $sub_info->subname;

            my @callers;
            while (my ($fid, $fid_line_info) = each %$callers) {
                for my $line (keys %$fid_line_info) {
                    my $sc = $fid_line_info->{$line};
                    warn "$linesrc $subname caller info missing" if !@$sc;
                    next if !@$sc;
                    push @callers, [ $fid, $line, @$sc ];
                }
            }
            my $total_calls = sum(my @caller_calls = map { $_->[2] } @callers);

            push @prologue, sprintf "# spent %s within %s which was called%s:",
                fmt_incl_excl_time($sub_info->incl_time, $sub_info->excl_time),
                $subname,
                ($total_calls <= 1) ? ""
                    : sprintf(" %d times, avg %s/call",
                        $total_calls, fmt_time($sub_info->incl_time / $total_calls));
            push @prologue, sprintf "# (data for this subroutine includes %d others that were merged with it)",
                    scalar @{$sub_info->meta->{merged_sub_names}}
                if $sub_info->meta->{merged_sub_names};
            my $max_calls = max(@caller_calls);

            # order by most frequent caller first, then by time
            @callers = sort { $b->[2] <=> $a->[2] || $b->[3] <=> $a->[3] } @callers;

            for my $caller (@callers) {
                my ($fid, $line, $count, $incl_time, $excl_time, undef, undef,
                    undef, undef, $calling_subs) = @$caller;

                my @subnames = sort keys %{$calling_subs || {}};
                my $subname = (@subnames) ? " by " . join(" or ", @subnames) : "";

                my $caller_fi = $profile->fileinfo_of($fid);
                if (!$caller_fi) { # should never happen
                    warn sprintf "Caller of %s, from fid %d line %d has no fileinfo (%s)",
                        $sub_info, $fid, $line, $subname;
                        die 2;
                    next;
                }

                my $avg_time = "";
                $avg_time = sprintf ", avg %s/call", fmt_time($incl_time / $count)
                    if $count > 1;
                my $times = sprintf " (%s+%s)", fmt_time($excl_time),
                    fmt_time($incl_time - $excl_time);

                my $filename = $caller_fi->filename($fid);
                my $line_desc = "line $line of $filename";
                $line_desc =~ s/ of \Q$filename\E$//g if $filename eq $fi->filename;
                # remove @INC prefix from paths
                $line_desc =~ s/$inc_path_regex//g;

                my $href = $reporter->href_for_file($caller_fi, $line);
                push @prologue,
                    sprintf q{# %*s times%s%s at <a %s>%s</a>%s},
                    length($max_calls), $count, $times, $subname, $href,
                    $line_desc, $avg_time;
                $prologue[-1] =~ s/^(# +)1 times/$1   once/;  # better English
            }
        }
=cut
    #    say sprintf '%5d %6s  %s'
    #    say $linenum . ' ' .$line;
    }

=pod
            if (my @subs_defined = $eval_fi->subs_defined(1)) {
                my $sub_count  = @subs_defined;
                my $call_count = sum map { $_->calls } @subs_defined;
                my $excl_time  = sum map { $_->excl_time } @subs_defined;
                $extra .= sprintf "<br />%s# includes %s spent executing %d call%s to %d sub%s defined therein.",
                        $ws, fmt_time($excl_time, 2),
                        $call_count, ($call_count != 1) ? 's' : '',
                        $sub_count,  ($sub_count  != 1) ? 's' : ''
                    if $call_count;
            }


=cut






    #say $eval->{'227'}->fileinfo->srclines_array->@*;
    #for my $line ($files[0]->lines->@*) {
    #    p $line->evalcall_info;
    #}

  #  for my $file2 ($files[1]->lines->@*) {
  #      my $file = $file2->evalcall_info->{ $file2 };
  #      say join '  ' => ($file->fileinfo->is_eval,
  #                        scalar $file->lines->@*,
  #                        $file->total_time,
  #                        $file->total_calls,
  #                        $file->subcalls_at_line,
  #                        $file->fileinfo->filename,
  #                       );
  #      $total_calls += $file->total_calls;
  #      $total_time += $file->total_time;
  #  }
    say '----';
    say $total_calls;
    say $total_time;
    say '-----';

    #say join keys $_->evalcall_info->%* for $files[0]->lines->@*;
    for my $line ($files[0]->lines->@*) {
        next if !keys $line->evalcall_info->%*;
        #p $line->evalcall_info;
        my $t = (keys $line->evalcall_info->%*)[0];
    #    p $line->evalcall_info->{ $t };
     ##   say ref $line->evalcall_info->{ $t };
      #  die;
    }
    #my $evals_called = $stats_for_line->{evalcall_info};

}

1;
