use common::sense;
use Encode;
use Socket;

use AnyEvent;
use AnyEvent::IRC::Client;
use Tatsumaki::HTTPClient;

use URI;
use Web::Scraper;
use Data::Validate::URI ();

our $CONFIG;

if (-f 'settings.pl') {
    $CONFIG = do 'settings.pl' or die $!;
} else {
    $CONFIG = {
        ch => '#',
        server => 'irc.freenode.net',
        port => 6667,
        info => {
            nick => '',
            user => '',
            real => 'the bot',
        },
    };
}

$CONFIG->{loopback} = inet_ntoa( inet_aton('localhost') );

#-----

our $CONNECTION = 0;
our $LT = scalar localtime;

my @conf = ( $CONFIG->{server}, $CONFIG->{port}, $CONFIG->{info} );

my $cv = AnyEvent->condvar;

my $ua = Tatsumaki::HTTPClient->new;

my $cl;

my $ltw; $ltw = AnyEvent->timer(
    after    => 1,
    interval => 1,
    cb       => sub { $LT = scalar localtime; },
);

my $t; $t = AnyEvent->timer (after => 5, interval=> 30, cb => sub {
    say "[ $LT ] connection status : $CONNECTION";
    connect_to_server() unless $CONNECTION;
});

my $scraper = scraper {
    process '/html/head/title', 'title' => 'TEXT';
};

$cv->recv;

sub connect_to_server {
    say "[ $LT ] start connection";

    $cl = AnyEvent::IRC::Client->new;

    $cl->reg_cb(
        'connect' => sub {
            my ( $cl, $err ) = @_;
            if ( defined $err ) {
                print "[ $LT ] Connect ERROR! => $err\n";
                $CONNECTION = 0;
                $cv->broadcast;
            }
            else {
                print "[ $LT ] Connected! Yay!\n";
                $CONNECTION = 1;
            }
        },

        registered => sub {
            my ($self) = @_;
            print "[ $LT ] registered!\n";
            $cl->enable_ping (60);

            $cl->send_srv("JOIN", $CONFIG->{ch});
            $cl->send_chan($CONFIG->{ch}, "NOTICE", $CONFIG->{ch}, "hi, i'm a bot!");
        },

        irc_001 => sub {
            say "[ $LT ] irc_001";
        },

        irc_privmsg => sub {
            my ($self, $msg) = @_;
            my $message = decode_utf8 $msg->{params}[1];

            my @url_list = $message =~ m{(http://[\S]+)}g;

            for my $url (@url_list) {
                process_url($url);
            }
        },

        disconnect => sub {
            $CONNECTION = 0;
            print "[ $LT ] Oh, got a disconnect: $_[1], exiting...\n";
        }
    );

    $cl->connect(@conf);
}

sub process_url {
    my $url = shift;

    say "[ $LT ] $url";

    return unless Data::Validate::URI::is_uri($url);

    if (is_twitter($url)) {
        send_twitter_status($url);
        return;
    }

    $ua->head($url, timeout => 3, sub {
        my $res = shift;

        my $remote = URI->new( $res->header('url') )->host;
        my $remote_addr = inet_ntoa( inet_aton($remote) );
        my $content_length = $res->headers->content_length ? $res->headers->content_length : 0;

        if ($remote_addr eq $CONFIG->{loopback}) {
            my $msg = sprintf "%s is loopback!", $url;
            $cl->send_chan($CONFIG->{ch}, "NOTICE", $CONFIG->{ch}, encode_utf8($msg));

        } elsif ($content_length > 0 && $content_length > 1024 * 1024) {
            my $msg = sprintf "Too large to fetch: %s [ %s ]", $url, $res->content_type;
            $cl->send_chan($CONFIG->{ch}, "NOTICE", $CONFIG->{ch}, encode_utf8($msg));

        } elsif ($res->headers->content_type ne 'text/html') {
            my $msg = sprintf "%s is not HTML [%s]", $url, $res->headers->content_type;
            $cl->send_chan($CONFIG->{ch}, "NOTICE", $CONFIG->{ch}, encode_utf8($msg));

        } else {
            $ua->get($url, timeout => 3, sub {
                my $res = shift;

                my $info = {};
                if ($res->is_success) {
                    my $data = $scraper->scrape($res->decoded_content);
                    $info->{title} = $data->{title};
                    $info->{content_type} = $res->headers->content_type;

                } else {
                    $info->{title} = $res->status_line;
                }

                my $msg = sprintf "%s [%s] %s", $info->{title}, $info->{content_type}, $url;
                $cl->send_chan($CONFIG->{ch}, "NOTICE", $CONFIG->{ch}, encode_utf8($msg));
            });

        }

    });
}

sub is_twitter {
    return ($_[0] =~ m{^http://twitter.com/(?:#!/)?[^/]+/status/\d+}) ? 1 : undef;
}

sub send_twitter_status {
    my $url = shift;

    $url =~ s{\.com/#!/}{.com/};

    $ua->get($url, timeout => 3, sub {
        my $res = shift;

        return unless ($res->is_success); 

        my $ts = scraper {
            process '.entry-content', 'tweet' => 'TEXT';
            process '.screen-name', 'screen_name' => 'TEXT';
        };

        my $status = $ts->scrape($res->decoded_content);

        my $msg = sprintf "<%s> %s / via %s", $status->{screen_name}, $status->{tweet}, $url;
        $cl->send_chan($CONFIG->{ch}, "NOTICE", $CONFIG->{ch}, encode_utf8($msg));
    });
}

__END__

