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

sub set_panel ($self, $panel_id, $rgb) {
  my $bytes = join q{},
    (pack "n", 1),              # will affect one panel
    (pack "n", $panel_id),      # panel id
    (map {; chr } (@$rgb, 0)),  # RGBW, W is always 0
    (pack "n", 10),             # transition time (for later)
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
    unless ($res->is_success) {
      die "Got failure from API: " . $res->as_string;
    }

    $self->_clear_state;
    return Future->done if $res->is_success;
  });
}

sub get_current_effect ($self) {
  $self->get_state->then(sub ($config) {
    return Future->done($config->{effects}{select});
  });
}

sub get_state ($self) {
  $self->{_nib_state} //= do {
    $self->_do_http_request({
      method  => 'GET',
      path    => "/",
    })->then(sub ($res) {
      unless ($res->is_success) {
        die "Got failure from API: " . $res->as_string;
      }

      return Future->done(
        decode_json($res->decoded_content(charset => undef))
      );
    });
  }
}

sub get_panel_position_data ($self) {
  $self->get_state->then(sub ($state) {
    my @panels = $state->{panelLayout}{layout}{positionData}->@*;

    return Future->done(@panels);
  });
}

sub blackout ($self) {
  $self->set_all_panels([0,0,0]);
}

sub set_all_panels ($self, $rgb) {
  $self->get_panel_position_data->then(sub (@panels) {
    my @panel_ids =
      map  {; $_->{panelId} }
      grep {; $_->{shapeType} != 12 } # Skip the control panel!
      @panels;

    $self->set_panel($_, $rgb) for @panel_ids;

    Future->done;
  });
}

sub _clear_state ($self) {
  delete $self->{_nib_state};
}
