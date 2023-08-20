package Nib::Dev;

use v5.38.0;

use parent 'IO::Async::Notifier';

use Carp ();
use JSON::MaybeXS;
use Net::Async::HTTP;

sub configure ($self, %params) {
  Carp::confess("no Nib config given") unless $params{config};

  $self->{_nib_config} = $params{config};

  return;
}

sub config ($self) {
  return $self->{_nib_config};
}

sub http ($self) {
  return $self->{_nib_http} //= do {
    my $http = Net::Async::HTTP->new;
    $self->loop->add($http);

    $http;
  };
}

sub _streaming_socket ($self) {
  return $self->{_nib_stream_sock} //= do {
    $self->loop->connect(
      host    => $self->config->{host},
      service => 60222, # Boo, hardcoded in ... protocol!?
      family  => 'inet',
      socktype => 'dgram',
    )->get;
  };
}

sub set_panel ($self, $panel_id, $r, $g, $b, $w) {
  my $bytes = join q{},
    (pack "n", 1),                    # will affect one panel
    (pack "n", $panel_id),            # panel id
    (map {; chr } ($r, $g, $b, $w)),  # R G B W
    (pack "n", 10),                   # transition time (for later)
    ;

  $self->_streaming_socket->send($bytes);

  say "Set panel $panel_id";
}

sub _do_http_request ($self, $req_param) {
  my $host = $self->config->host;
  my $auth = $self->config->auth;
  my $port = 16021; # should be configurable, but won't matter

  my %req  = %$req_param;
  my $path = (delete $req{path} // q{}) =~ s{\A/}{}r;

  $self->http->do_request(
    uri => "http://$host:$port/api/v1/$auth/$path",
    %req,
  );
}

sub set_streaming ($self) {
  state $payload = encode_json({
    write => {
      command   => "display",
      animType  => "extControl",
      extControlVersion => "v2",
    },
  });

  $self->_do_http_request({
    method  => 'PUT',
    path    => "/effects",
    content_type => 'application/json',
    content => $payload,
  })->then(sub ($res) {
    return 1 if $res->is_success;
    die "Got failure from API: " . $res->as_string;
  });
}

sub get_current_effect ($self) {
  $self->get_state->then(sub ($config) {
    return Future->done($config->{effects}{select});
  });
}

sub get_state ($self) {
  $self->_do_http_request({
    method  => 'GET',
    path    => "/",
  })->then(sub ($res) {
    unless ($res->is_success) {
      die "Got failure from API: " . $res->as_string;
    }

    return decode_json($res->decoded_content(charset => undef));
  });
}
