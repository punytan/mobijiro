package App::Mobijiro;
use practical;
our $VERSION = '0.02';
use constant DEBUG => $ENV{MOBIJIRO_DEBUG};
use parent 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw/
    loopback channel connection
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
    my $con_watcher; $con_watcher = AE::timer 5, 90, sub {
        say "con_watcher" if DEBUG;

        $self->connect unless $self->connection;
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
                $self->connection(0);
            } else {
                say "Connected" if DEBUG;
                $self->connection(1);
            }
        },
        registered => sub {
            say "Registered" if DEBUG;
            $self->{client}->enable_ping(60);
            $self->{client}->send_srv("JOIN", $self->channel);
            $self->{client}->send_chan($self->channel, "NOTICE", $self->channel, "Hi, I'm a bot!");
        },
        irc_privmsg => sub {
            my $msg = Encode::decode_utf8($_[1]->{params}[1]);
            my @url = $msg =~ m{(https?://[\S]+)}g;
            $self->resolve($_) for @url;
        },
        disconnect => sub {
            $self->connection(0);
            say "Disconnected: $_[1]" if DEBUG;
        },
    );

    $self->{client}->reg_cb(%opts);
    $self->{client}->connect($self->{server}, $self->{port}, $self->{info})
}

sub resolve {
    my ($self, $url) = @_;

    return unless Data::Validate::URI::is_uri($url);

    $self->{ua}->head($url, sub {
        my $res = shift;
        my $h = $res->headers;
        say "HEAD: $url" if DEBUG;

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

        if ($remote->{addr} eq $self->loopback) {
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
            say "Twitter: $remote->{url}" if DEBUG;
            $self->{ua}->get($remote->{url}, sub {
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

                $self->send(sprintf "<%s> %s / via %s", $s->{name}, $s->{tweet}, $remote->{url});
            });
            return;
        }

        $self->{ua}->get($url, sub {
            my $res = shift;
            my $h = $res->headers;
            say "GET: $url" if DEBUG;

            my $info = {};
            if ($res->is_success) {
                my $scraper = scraper {
                    process '/html/head/title', 'title' => 'TEXT';
                };
                my $data = $scraper->scrape($res->decoded_content);
                $info->{title} = $data->{title};
                $info->{type} = $h->content_type;
            } else {
                $info->{title} = $res->status_line;
                $info->{type} = '';
            }

            $self->send(sprintf "%s [%s] %s", $info->{title}, $info->{type}, $h->header('url'));
        });
    });
}

sub send {
    my $self = shift;
    $self->{client}->send_chan(
        $self->channel, "NOTICE", $self->channel, Encode::encode_utf8(shift)
    );
}

sub is_twitter {
    my $self = shift;
    say "Is Twitter: $_[0]" if DEBUG;
    return ($_[0] =~ m{^https?://twitter.com/(?:#!/)?[^/]+/status(?:es)?/\d+}) ? 1 : undef;
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
