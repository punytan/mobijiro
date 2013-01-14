package App::Mobijiro;
use strict;
use warnings;
use feature 'say';
our $VERSION = '0.02';

use AE;
use Encode;
use Socket;
use AnyEvent::IRC::Client;
use Tatsumaki::HTTPClient;
use URI;
use Web::Scraper;
use Data::Validate::URI;

sub new {
    my ($class, %args) = @_;

    my $cv = $args{cv};

    my $useragent = Tatsumaki::HTTPClient->new(agent => 'Mozilla/5.0 (X11; Linux i686) AppleWebKit/534.30 (KHTML, like Gecko)');
    my $client    = AnyEvent::IRC::Client->new;
    my $loopback  = inet_ntoa( inet_aton('localhost') );

    my $server  = $args{server};
    my $channel = $args{channel};
    my $port    = $args{port};
    my $info    = $args{info} || {};
    my ($nick, $user, $real) = @$info{qw/ nick user real /};

    return bless {
        cv        => $cv,
        useragent => $useragent,
        client    => $client,
        loopback  => $loopback,
        server    => $server,
        channel   => $channel,
        port => $port,
        info => {
            nick => $nick,
            user => $user,
            real => $real,
        },
    }, $class;
}

sub channel { shift->{channel} }

sub run {
    my $self = shift;
    my $con_watcher; $con_watcher = AE::timer 5, 30, sub {
        say "called con_watcher";
        unless ($self->{client}->registered) {
            $self->connect;
            $self->{client}->send_srv("JOIN", $self->channel);
            $self->{client}->send_chan($self->channel, "NOTICE", $self->channel, "Hi, I'm a bot!");
        }
    };
    return $con_watcher;
}

sub connect {
    my $self = shift;

    $self->{client}->reg_cb(
        connect => sub {
            my ($cl, $err) = @_;
            say defined $err ? "Connect error: $err" : "Connected"
        },
        registered => sub {
            say "Registered";
            $self->{client}->enable_ping(10);
        },
        irc_privmsg => sub {
            my $msg = Encode::decode_utf8($_[1]->{params}[1]);
            my @url = $msg =~ m{(https?://[\S]+)}g;
            $self->resolve($_) for @url;
        },
        disconnect => sub {
            $self->{cv}->broadcast;
            say "Disconnected: $_[1]";
        },
    );

    $self->{client}->connect(@$self{ qw/ server port info /})
}

sub resolve {
    my ($self, $url) = @_;

    return unless Data::Validate::URI::is_uri($url);

    $self->{useragent}->head($url, sub {
        my $res = shift;
        my $h = $res->headers;
        say "HEAD: $url";

        # NOTE: $host must be predecleared for $remote->{addr}
        my $host = URI->new( $h->header('url') )->host;

        my $remote = {
            host   => $host,
            addr   => inet_ntoa( inet_aton($host) ),
            length => $h->content_length ? $h->content_length : 0,
            url    => $h->header('url')  ? $h->header('url')  : $url,
            type   => $h->content_type   ? scalar $h->content_type : 'text/plain',
                # NOTE: content_type should be called in scalar context
        };

        if ($remote->{addr} eq $self->{loopback}) {
            $self->send(sprintf "Loopback: %s", $url);
            return;
        }

        if ($remote->{length} > 1024 * 1024) {
            $self->send(sprintf "Large: %s [%s]", $url, $res->content_type);
            return;
        }

        if ($remote->{type} ne 'text/html') {
            $self->send(sprintf "%s [%s]", $url, $remote->{type});
            return;
        }

        if ($self->is_twitter($remote->{url})) {
            $remote->{url} =~ s{\.com/#!/}{.com/};
            say "Twitter: $remote->{url}";
            $self->{useragent}->get($remote->{url}, sub {
                my $res = shift;

                unless ($res->is_success) {
                    $self->send(sprintf "Error: %d %s", $res->code, $res->status_line);
                    return;
                }

                my $ts = scraper { process '.tweet-text', 'tweet' => 'TEXT'; };

                my $s = $ts->scrape($res->decoded_content);
                my ($screen_name) = $remote->{url} =~ m|https://twitter.com/([^/]+)|;

                $self->send(sprintf "<%s> %s / via %s", $screen_name, $s->{tweet}, $remote->{host});
            });
            return;
        }

        $self->{useragent}->get($url, sub {
            my $res = shift;
            my $h = $res->headers;
            say "GET: $url";

            my $info = {};
            my ($title, $content_type);
            if ($res->is_success) {
                $title = scraper { process '/html/head/title', 'title' => 'TEXT' }->scrape($res->decoded_content)->{title};
                $content_type = $h->content_type;
            } else {
                $title = $res->status_line;
                $content_type = '';
            }

            $self->send(sprintf "%s [%s] %s", $title, $content_type, URI->new($h->header('url'))->host);
        });
    });
}

sub send {
    my ($self, $message) = @_;
    $self->{client}->send_chan($self->channel, "NOTICE", $self->channel, Encode::encode_utf8($message));
}

sub is_twitter {
    my ($self, $url) = @_;
    say "called is_twitter: $url";
    $url =~ m{^https?://twitter.com/(?:#!/)?[^/]+/status(?:es)?/\d+} ? 1 : 0;
}


1;
__END__

