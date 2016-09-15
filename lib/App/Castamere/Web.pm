use 5.20.0;
use warnings;

package App::Castamere::Web;

# ABSTRACT: ...
our $AUTHORITY = 'cpan:CSSON'; # AUTHORITY
our $VERSION = '0.0100';

use Mojo::Base 'Mojolicious';
use Mojo::Home;
use File::ShareDir 'dist_dir';
use Path::Tiny;
use App::Castamere::Reporter;
use experimental qw/postderef signatures/;

has reporter => sub { App::Castamere::Reporter->new(infile => Mojo::Home->new->rel_file('share/nytprof.out')) };

sub startup($self) {
    $self->plugin('BootstrapHelpers');
    $self->plugin('EPRenderer', template => { prepend => 'use experimental qw/postderef/;' });

    my $dirroot = 1 ? path(Mojo::Home->new->rel_dir('share'))
                    : path(dist_dir('App-Castamere'))
                    ;
    my $template_dir = $dirroot->child('templates');
    push $self->renderer->paths->@* => $template_dir->realpath;
    push $self->static->paths->@* => $dirroot->child('public')->stringify;
    $self->defaults(layout => 'default');

    $self->renderer->cache->max_keys(0);
    my $r = $self->routes;
 #   $r->cache->max_keys(0);
    $r->get('/')->to(cb => sub($c) {
        my($file) = grep { $_->fileinfo->filename =~ m{Sub/Quote\.pm} } $self->reporter->files->@*;
        $c->render(template => 'views/one_source_file', file => $file);
    });

}

1;

__END__
