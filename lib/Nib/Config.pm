package Nib::Config;

use v5.38.0;

use TOML::Parser;

sub read_file ($class, $filename) {
  my $parser = TOML::Parser->new;
  my $data   = $parser->parse_file($filename);

  bless $data, $class;
}

sub auth ($self) { $self->{auth} }
sub host ($self) { $self->{host} }

1;
