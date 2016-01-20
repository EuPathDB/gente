#!/usr/bin/env perl
use Mojolicious::Lite;
use Net::LDAP;
use Net::LDAP::Extension::SetPassword;

my $config = plugin 'JSONConfig' => { file => 'gente.json' };

app->secrets($config->{secret});

# if someone is using mod_rewrite to hide the script file name
# generate urls that reflect that
hook before_dispatch => sub {
  my $self = shift;
  my $base = $self->req->env->{SCRIPT_URI};
  if ($base) {
    $self->req->url->base( Mojo::URL->new($base) );
  }
};

get '/' => sub {
  my $self = shift;
  $self->stash( title => $config->{title} );
  $self->render('form');
};

post '/' => sub {
  my $self = shift;

  my $server = $config->{server};
  my $dn     = $config->{dn};
  my $cafile = $config->{cafile};
  $self->stash( title => $config->{title} );

  my $username = $self->param('username');
  my $old      = $self->param('old');
  my $new      = $self->param('new');

  my $error;
  my $result;
  my $status = 200;

  # these nested ifs are ridiculously hard to follow
  # should return early instead
  my $ldap = Net::LDAP->new($server);
  if ( not $ldap ) {
    $error = "Unable to connect to $server";
    $self->app->log->error($error);
    $status = 500;
    $result = 'An internal error occured';
  }
  else {
    $self->app->log->debug('LDAP Connected');
    my $mesg = $ldap->start_tls( verify => 'require', cafile => $cafile );
    if ( $mesg->code ) {
      $error = "Unable to start TLS to $server using $cafile";
      $self->app->log->error($error);
      $status = 500;
      $result = 'An internal error occured';
    }
    else {
      $self->app->log->debug('TLS Enabled');
      $mesg = $ldap->bind( "uid=$username,$dn", password => $old );
      if ( $mesg->code ) {
        $error = "Unable to bind as $username. Server says " . $mesg->error;
        $self->app->log->info($error);
        $result = 'Unable to change your password. Try again or get help.';
      }
      else {
        $self->app->log->debug('User Bound');
        $mesg = $ldap->set_password( oldpasswd => $old, newpasswd => $new );
        if ( $mesg->code ) {
          $error = "Unable to change password as $username. Server says "
            . $mesg->error;
          $self->app->log->info($error);
          $result = 'Unable to change your password. Try again or get help.';
        }
        else {
          $self->app->log->debug('Password Changed');
          $result = 'Your password was successfully changed';
        }
      }
    }
    $ldap->unbind();
  }
  $self->render( 'feedback', status => $status, result => $result );

};

app->start;
__DATA__

@@ form.html.ep
% layout 'default';
<%= form_for '/' => (method => 'post') => begin %>
Username:
<%= input_tag 'username' %>
<br>
Old Password:
<%= input_tag 'old', type => 'password' %>
<br>
New Password:
<%= input_tag 'new', type => 'password' %>
<br>
<%= submit_button %>
<% end %>

@@ feedback.html.ep
% layout 'default';
<p> <%= $result %> </p>
<p> <%= link_to 'Back to the form' => '/' %> </p>

@@ layouts/default.html.ep
<!doctype html><html>
  <head><title><%= title %></title></head>
  <body>
    <h1> <%= title %> </h1>
    <%= content %>
  </body>
</html>
