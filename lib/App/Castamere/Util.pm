use 5.20.0;
use warnings;

package App::Castamere::Util;

# ABSTRACT: Short intro
# AUTHORITY
our $VERSION = '0.0100';

use base qw/Exporter/;
use Devel::NYTProf::Util qw/fmt_time/;
use experimental qw/postderef signatures/;

our @EXPORT_OK = qw/
   fix_time
   format_time
/;

sub fix_time($time) {
    utf8::decode $time;
    return $time;
}
sub format_time($time, @args) {
    return fix_time fmt_time $time, @args;
}

1;
