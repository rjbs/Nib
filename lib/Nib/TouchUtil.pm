package Nib::TouchUtil;

use v5.38.0;
use utf8;

use Term::ANSIColor qw(colored);

my $PARITY;
my @COLORS = ('ansi105', 'ansi219');

my %type_name = (
  0 => 'hover',
  1 => 'down',
  2 => 'hold',
  3 => 'up',
  4 => 'swipe',
);

my sub parse_1b ($b)       { oct "0b$b"     }
my sub parse_2b ($b1, $b2) { oct "0b$b1$b2" }

my sub hdr ($counter, $len) {
  say colored([ 'ansi172', ], "┏━━━━━━━ ") . "event $counter; len: $len";
}

my sub line ($line) {
  say colored([ 'ansi172', ], "┃ ") . $line;
}

my sub ftr {
  say colored([ 'ansi172', ], "┗━━━━━━━ ");
}

my sub bytes ($desc, $bytes, $arg = {}) {
  my $color = $COLORS[ $PARITY++ % 2 ];

  for my $i (0 .. $#$bytes) {
    my $chr = @$bytes == 1    ? '─'
            : $i == 0         ? '┬'
            : $i == $#$bytes  ? '┘'
            :                   '│';

    line(
      join q{ },
        colored([ $color ], $bytes->[$i]),
        colored([ 'ansi11' ], $chr),
        ($i == 0 ? $desc : ())
    );
  }
}

sub dump_dgram ($self, $dgram, $n) {
  $PARITY = 0;

  my $len = length $dgram;

  hdr($n, $len);

  my @bytes = map {; sprintf '%08b', ord } split //, $dgram;

  my @count_bytes = splice @bytes, 0, 2;
  my ($panel_ct) = parse_2b(@count_bytes[0,1]);

  bytes("panel ct $panel_ct", [ @count_bytes[0, 1] ]);
  line("");

  for my $i (1 .. $panel_ct) {
    my @panel_bytes = splice @bytes, 0, 5;

    my ($panel_id) = parse_2b(@panel_bytes[0,1]);
    bytes("panel id $panel_id", [ @panel_bytes[0,1] ]);

    my $panel_event = parse_1b($panel_bytes[2]);
    my $touch_type  = ($panel_event      & 0b0111_0000) >> 4;
    my $touch_str   = ($panel_event      & 0b0000_1111);
    my $type_name   = $type_name{$touch_type} // $touch_type;
    bytes("type: $type_name; strength: $touch_str", [ $panel_bytes[2] ]);

    my ($swipe_value) = parse_2b(@panel_bytes[3,4]);
    my $swipe_source = $swipe_value == (2**16-1)
                     ? "not a swipe"
                     : "panel $swipe_value";

    bytes("swipe: $swipe_source", [ @panel_bytes[3,4] ]);

    line(q{}) if $i < $panel_ct;
  }

  for my $excess (@bytes) {
    my $value = parse_1b($excess);
    bytes(sprintf("%3i (???)", $value), [$excess]);
  }

  ftr();
}

