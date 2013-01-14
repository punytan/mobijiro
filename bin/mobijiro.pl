use strict;
use warnings;

use AE;
use App::Mobijiro;
use Getopt::Long;

my %opts;

GetOptions(\%opts, qw< server=s port=i channel=s nick=s user=s real=s >);

my $server  = $opts{server}  or die "`server` option is required";
my $port    = $opts{port}    or die "`port` option is required";
my $channel = $opts{channel} or die "`channel` option is required";
my $nick    = $opts{nick}    or die "`server` option is required";
my $user    = $opts{user} || $nick;
my $real    = $opts{real} || $nick;

my $cv = AE::cv;

my $app = App::Mobijiro->new(
    cv      => $cv,
    server  => $server,
    port    => $port,
    channel => $channel,
    info    => {
        nick => $nick,
        user => $user,
        real => $real,
    }
);

my $watcher = $app->run;

$cv->recv;

__END__

