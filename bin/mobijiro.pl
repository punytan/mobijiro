use practical;
use AE;
use FindBin;
use lib "$FindBin::Bin/../lib";
use App::Mobijiro;

my $CONFIG;

if (-f "$FindBin::Bin/../settings.pl") {
    $CONFIG = do "$FindBin::Bin/../settings.pl" or die $!;
} else {
    warn "Using inline config";
    $CONFIG = {
        server  => 'irc.freenode.net',
        channel => '#',
        port => 6667,
        info => {
            nick => '',
            user => '',
            real => 'the bot',
        },
    };
}

my $cv = AE::cv;
my $w = App::Mobijiro->new(
    %$CONFIG,
)->run;
$cv->recv;

__END__

