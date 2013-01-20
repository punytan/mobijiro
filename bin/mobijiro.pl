use strict;
use warnings;

use AE;
use App::Mobijiro;
use Getopt::Long;

my %opts;

GetOptions(\%opts, qw< server=s port=i channel=s nick=s user=s real=s >)
    or die "Invalid arguments";

for my $key (qw/ server port channel nick /) {
    $opts{$key} or die "$key is required";
}

my $cv = AE::cv;

my $app = App::Mobijiro->new(
    cv      => $cv,
    server  => $opts{server},
    port    => $opts{port},
    channel => $opts{channel},
    info    => {
        nick => $opts{nick},
        user => $opts{user} || $opts{nick},
        real => $opts{real} || $opts{nick},
    }
);

my $watcher = $app->run;

$cv->recv;

__END__

