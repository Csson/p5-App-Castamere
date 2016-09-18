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


    $r->get('/file/*filename')->to(cb => sub($c) {
        my($file) = grep { $_->fileinfo->filename eq $c->param('filename') } $self->reporter->files->@*;
        $c->render(template => 'views/one_source_file', file => $file);
    })->name('one_file');

    $r->get('/sub/*subname')->to(cb => sub($c) {
        my @file_line_range = $self->reporter->profile->file_line_range_of_sub($c->param('subname'));
        my $filename = $file_line_range[0];
        my $first_line = $file_line_range[2] || -1;
        my $last_line = $file_line_range[3] || -1;

        if(defined $filename) {
            my($file) = grep { $_->fileinfo->filename eq $file_line_range[0] } $self->reporter->files->@*;
            $c->stash(start_at => $first_line);
            $c->stash(end_at => $last_line);
            $c->render(layout => undef, template => 'views/one_source_file', file => $file);
        }
        else {
            $c->render(text => 'No source to show.');
        }
    })->name('sub');

    $r->get('/svg')->to(cb => sub ($c) {
        $c->render(template => 'views/svg', reporter => $self->reporter);
    })->name('svg');
    $r->get('/')->to(cb => sub ($c) {
        $c->render(template => 'views/overview', reporter => $self->reporter);
    });
}

1;

__END__
