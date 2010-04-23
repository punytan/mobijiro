use strict;
use warnings;
use feature qw/say/;
use Data::Dumper;
use Encode;
use Data::Validate::URI qw/is_uri/;
use AnyEvent;
use AnyEvent::HTTP;
use AnyEvent::IRC;
use AnyEvent::IRC::Connection;
use AnyEvent::IRC::Client;
use Tatsumaki::HTTPClient;
use Web::Scraper;

our $CONFIG = {
    ch => '#',
    server => 'irc.freenode.net',
    port => 6667,
    info => {
        nick => '',
        user => '',
        real => 'the bot',
    },
};

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
            process_msg($message);
        },
        disconnect => sub {
            $CONNECTION = 0;
            print "[ $LT ] Oh, got a disconnect: $_[1], exiting...\n";
        }
    );

    $cl->connect(@conf);
}

sub process_msg {
    my $msg = shift;

    my @url_list = $msg =~ m{(http://[\S]+)}g;

    for my $url (@url_list) {
        say "[ $LT ] $url";

        if (is_uri($url)) {
            $ua->get($url, timeout => 3, sub {
                    my $res = shift;

                    my $info = {};
                    my $decoded_content = $res->decoded_content;

                    $info->{content_type} = $res->headers->content_type;

                    if ($res->is_success) {
                        my $data = $scraper->scrape($res->decoded_content);
                        $info->{title} = $data->{title};
                    } else {
                        $info->{title} = 'NO TITLE';
                    }

                    my $msg = encode_utf8(" $info->{title} [ Content-Type: $info->{content_type} ] ");

                    $cl->send_chan($CONFIG->{ch}, "NOTICE", $CONFIG->{ch}, "$msg");
                }
            );
        } 
        else {
            $cl->send_chan($CONFIG->{ch}, "NOTICE", $CONFIG->{ch}, "$url is not valid URL");
        }
    }
}

__END__
