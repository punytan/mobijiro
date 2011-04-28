package App::Mobijiro;
use practical;
our $VERSION = '0.01';
use constant DEBUG => $ENV{MOBIJIRO_DEBUG};
use parent 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw/
    ua cv scraper loopback channel client
/);

use AE;
use Encode;
use Socket;
use AnyEvent::IRC::Client;
use Tatsumaki::HTTPClient;
use URI;
use Web::Scraper;
use Data::Validate::URI;

our $CONNECTION = 0;

sub new {
    my $class = shift;
    my %args  = @_;

    return bless {
        %args,
        ua       => Tatsumaki::HTTPClient->new,
        client   => AnyEvent::IRC::Client->new,
        loopback => inet_ntoa( inet_aton('localhost') ),
    }, $class;
}

sub run {
    my $self = shift;
    my $con_watcher; $con_watcher = AE::timer 5, 30, sub {
        say "con_watcher" if DEBUG;
        $self->connect unless $CONNECTION;
        undef $con_watcher;
    };
    return $con_watcher;
}

sub connect {
    my $self = shift;

    my %opts = (
        connect => sub {
            my ($cl, $err) = @_;

            if (defined $err) {
                say "Connect error: $err" if DEBUG;
                $CONNECTION = 0;
                $self->cv->boroadcast;
            } else {
                say "Connected" if DEBUG;
                $CONNECTION = 1;
            }
        },
        registered => sub {
            say "Registered" if DEBUG;
            $self->client->enable_ping(60);
            $self->client->send_srv("JOIN", $self->channel);
            $self->client->send_chan($self->channel, "NOTICE", $self->channel, "Hi, I'm a bot!");
        },
        irc_privmsg => sub {
            my $msg = Encode::decode_utf8($_[1]->{params}[1]);
            my @url = $msg =~ m{(https?://[\S]+)}g;
            $self->resolve($_) for @url;
        },
        disconnect => sub {
            $CONNECTION = 0;
            say "Disconnected: $_[1]" if DEBUG;
        },
    );

    $self->client->reg_cb(%opts);
    $self->client->connect($self->{server}, $self->{port}, $self->{info})
}

sub resolve {
    my ($self, $url) = @_;

    return unless Data::Validate::URI::is_uri($url);

    if ($self->is_twitter($url)) {
        $url =~ s{\.com/#!/}{.com/};
        say "Twitter: $url" if DEBUG;
        $self->ua->get($url, sub {
            my $res = shift;

            unless ($res->is_success) {
                $self->send(sprintf "Error: %s", $res->status_line);
                return;
            }

            my $ts = scraper {
                process '.entry-content', 'tweet' => 'TEXT';
                process '.screen-name', 'name' => 'TEXT';
            };

            my $s = $ts->scrape($res->decoded_content);

            $self->send(sprintf "<%s> %s / via %s", $s->{name}, $s->{tweet}, $url);
        });
        return;
    }

    $self->ua->head($url, sub {
        my $res = shift;
        say "HEAD: $url" if DEBUG;

        my $host = URI->new( $res->header('url') )->host;
        my $remote = {
            host => $host,
            addr => inet_ntoa( inet_aton($host) ),
            length => $res->headers->content_length ? $res->headers->content_length : 0,
        };

        if ($remote->{addr} eq $self->loopback) {
            $self->send(sprintf "Loopback: %s", $url);
            return;
        }

        if ($remote->{length} > 1024 * 1024) {
            $self->send(sprintf "Large: %s [%s]", $url, $res->content_type);
            return;
        }

        if ($res->headers->content_type ne 'text/html') {
            $self->send(sprintf "%s [%s]", $url, $res->headers->content_type);
            return;
        }

        $self->ua->get($url, sub {
            my $res = shift;
            say "GET: $url" if DEBUG;

            my $info = {};
            if ($res->is_success) {
                my $scraper = scraper { process '/html/head/title', 'title' => 'TEXT'; };
                my $data = $scraper->scrape($res->decoded_content);
                $info->{title} = $data->{title};
                $info->{content_type} = $res->headers->content_type;
            } else {
                $info->{title} = $res->status_line;
                $info->{content_type} = '';
            }

            $self->send(sprintf "%s [%s] %s", $info->{title}, $info->{content_type}, $res->header('url'));
        });
    });
}

sub send {
    my $self = shift;
    $self->client->send_chan(
        $self->channel, "NOTICE", $self->channel, Encode::encode_utf8(shift)
    );
}

sub is_twitter {
    my $self = shift;
    say "Is Twitter: $_[0]" if DEBUG;
    return ($_[0] =~ m{^https?://twitter.com/(?:#!/)?[^/]+/status/\d+}) ? 1 : undef;
}


1;
__END__

=head1 NAME

App::Mobijiro -

=head1 SYNOPSIS

  use App::Mobijiro;

=head1 DESCRIPTION

App::Mobijiro is

=head1 AUTHOR

punytan E<lt>punytan@gmail.comE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
