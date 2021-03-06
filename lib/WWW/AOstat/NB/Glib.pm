package WWW::AOstat::NB::Glib;

use strict;
use MIME::Base64;
use Digest::MD5;
use URI;
use Net::DNS;
use Net::HTTP::NB;
use Net::HTTPS::NB;
use Glib;

use constant DEBUG => $ENV{ACP_DEBUG};

our $VERSION = 0.01;

use constant {
	URL_STAT     => 'https://stat.academ.org/ugui/api.php?OP=10&KEY=d3d9446802a44259755d38e6d163e820',
	URL_TURN     => 'https://stat.academ.org/ugui/api.php?OP=2&USERID=%d&STATUS=%s&KEY=%s',
	API_HOST     => 'stat.academ.org',
};

sub new
{
	my ($class, $timeout) = @_;
	
	my $self = {
			login     => '',
			password  => '',
			uid       => '',
			page      => '',
			update    => 0,
			timeout   => $timeout || 30,
			resolver  => Net::DNS::Resolver->new(),
			dns_cache => {}, # XXX: should we periodically clean the cache?
	};
	
	bless $self, $class;
}

sub login
{
	my ($self, $login, $password, $cb) = @_;
	
	$self->{tmp_login} = $self->{login};
	$self->{tmp_password} = $self->{password};
	$self->{login} = $login;
	$self->{password} = $password;
	
	$self->geturl(
		URL_STAT,
		sub {
			if (my ($uid) = $_[0] =~ /USERID=(\d+)/) {
				$self->{uid} = $uid;
				$self->{page} = $_[0];
				$self->{update} = time();
				$cb->($uid);
			}
			else {
				if($self->{tmp_login} && $self->{tmp_password}) {
					# reset to old values after unsuccessfull login
					# only if we have old values
					$self->{login} = $self->{tmp_login};
					$self->{password} = $self->{tmp_password};
				}
				$cb->();
			}
		}
	);
}

sub stat
{
	my ($self, $cb) = @_;
	
	my $cached = exists($self->{page}) && time() - $self->{update} == 0;
	
	my $sub = sub {
		return $cb->() if index($_[0], 'ERR=0') == -1;
		
		($self->{uid}) = $_[0] =~ /USERID=(\d+)/ unless $self->{uid};
		my ($traff) = $_[0] =~ /REMAINS_MB=(-?\d+)/;
		my ($money) = $_[0] =~ /REMAINS_RUR=(-?\d+(?:.\d{1,2})?)/;
		my ($cred_sum, $cred_time) = $_[0] =~ /CREDIT=(\d+);(\d+)/;
		my $status  = index($_[0], ';OFF') == -1
				? 
					index($_[0], ';ON') == -1 ? 
						-1 : 
						 1
				:
				0;
		if (!$cached) {
			$self->{page} = $_[0];
			$self->{update} = time();
		}
		
		$cb->($traff, $money, $status, $cred_sum, $cred_time);
	};
	
	if ($cached) {
		$sub->($self->{page});
	}
	else {
		$self->geturl(
			URL_STAT,
			$sub
		);
	}
}

sub turn
{
	my ($self, $act, $cb) = @_;
	
	my $key = Digest::MD5::md5_hex('2' . $self->{uid} .($act ? 'ON' : 'OFF'));
	my $url = sprintf(URL_TURN, $self->{uid}, $act ? 'ON' : 'OFF', $key);
	
	$self->geturl(
		$url,
		sub {
			$cb->( index($_[0], 'ERR=0') != -1 );
		}
	);
}

sub geturl
{
	my ($self, $url, $cb) = @_;
	DEBUG && warn "${\(time)} geturl($self, $url, $cb)";
	
	my $timer;
	eval {
		my $uri = URI->new($url);
		my $watcher;
		
		$timer = Glib::Timeout->add(
			$self->{timeout}*1000, \&_geturl_timeout,
			[ $cb, \$watcher ]
		);
		
		if (exists $self->{dns_cache}{$uri->host}) {
			DEBUG && warn "${\(time)} already resolved: $self->{dns_cache}{$uri->host}";
			_geturl_resolve(undef, undef, [$self, undef, $cb, $timer, \$watcher, $uri]);
		}
		else {
			my $dns_sock = $self->{resolver}->bgsend($uri->host)
				or die $self->{resolver}->errorstring;
			$watcher = Glib::IO->add_watch(
				fileno($dns_sock), 'in', \&_geturl_resolve,
				[
					$self, $dns_sock, $cb, $timer, \$watcher,
					$uri
				]
			);
		}
		
		1;
	} or do {
		DEBUG && warn "${\(time)} Error: $@";
		Glib::Source->remove($timer) if $timer;
		$cb->();
	};
	
	1;
}

sub _geturl_timeout
{
	my ($cb, $watcher) = @{$_[0]};
	DEBUG && warn "${\(time)} _geturl_timeout($cb, $watcher)";
	
	Glib::Source->remove($$watcher);
	$cb->();
	
	0;
}

sub _geturl_resolve
{
	my ($fd, $cond) = splice @_, 0, 2;
	my ($self, $dns_sock, $cb, $timer, $watcher, $uri) = @{$_[0]};
	DEBUG && warn "${\(time)} _geturl_resolve($self, $dns_sock, $cb, $timer, $watcher, $uri)";
	
	eval {
		my $ip;
		if (defined $fd) {
			my $packet = $self->{resolver}->bgread($dns_sock)
				or die $self->{resolver}->errorstring;
			
			foreach my $record ($packet->answer) {
				if ($record->type eq 'A') {
					$ip = $record->address;
					last;
				}
			}
			
			$dns_sock->close();
			if ($ip) {
				$self->{dns_cache}{$uri->host} = $ip;
			}
		}
		else {
			$ip = $self->{dns_cache}{$uri->host};
		}
		DEBUG && warn "${\(time)} ip: $ip";
		
		my $class = $uri->scheme eq 'http' ? 'Net::HTTP::NB' : 'Net::HTTPS::NB';
		my $sock = $class->new(Host => $uri->host, PeerHost => $ip, PeerPort => $uri->port, Blocking => 0)
			or die $@;
		
		$$watcher = Glib::IO->add_watch(
			fileno($sock), 'out', \&_geturl_write_request,
			[
				$sock, $cb, $timer, $watcher,
				GET => $uri->path_query||'/',
				$uri->host eq API_HOST ?
					(Authorization => "Basic " . encode_base64($self->{login} . ':' . $self->{password}))
					:
					()
			]
		);
	} or do {
		DEBUG && warn "${\(time)} Error: $@";
		Glib::Source->remove($timer);
		Glib::Source->remove($$watcher);
		$cb->();
	};
	
	return;
}

sub _geturl_write_request
{
	my ($fd, $cond) = splice @_, 0, 2;
	my ($sock, $cb, $timer, $watcher) = splice @{$_[0]}, 0, 4;
	DEBUG && warn "${\(time)} _geturl_write_request($sock, $cb, $timer, $watcher)";
	
	if ($sock->isa('Net::HTTPS::NB') && !$sock->connected) {
		unshift @{$_[0]}, $sock, $cb, $timer, $watcher;
		
		if ($HTTPS_ERROR == HTTPS_WANT_READ) {
			$$watcher = Glib::IO->add_watch(
				$fd, 'in', \&_geturl_write_request,
				$_[0]
			)
		}
		elsif ($HTTPS_ERROR == HTTPS_WANT_WRITE) {
			$$watcher = Glib::IO->add_watch(
				$fd, 'out', \&_geturl_write_request,
				$_[0]
			)
		}
		else {
			Glib::Source->remove($timer);
			$_[0][1]->();
		}
	}
	else {
		DEBUG && warn "${\(time)} connected";
		if ($sock->write_request(@{$_[0]})) {
			$$watcher = Glib::IO->add_watch(
				$fd, 'in', \&_geturl_read_response_headers,
				[$sock, $cb, $timer, $watcher]
			);
		}
		else {
			Glib::Source->remove($timer);
			$cb->();
		}
	}
	
	return; # remove watcher
}

sub _geturl_read_response_headers
{
	my ($fd, $cond) = splice @_, 0, 2;
	my ($sock, $cb, $timer, $watcher) = @{$_[0]};
	DEBUG && warn "${\(time)} _geturl_read_response_headers($sock, $cb, $timer, $watcher)";
	
	my $rv = eval {
		$sock->read_response_headers()
			or return 1; # no headers yet
			             # continue watching
		
		my $page;
		$$watcher = Glib::IO->add_watch(
			$fd, 'in', \&_geturl_read_response_body,
			[$sock, $cb, $timer, \$page]
		);
		
		0; # remove watcher
	};
	if ($@) {
		DEBUG && warn "${\(time)} Error: $@";
		Glib::Source->remove($timer);
		$cb->();
	}
	
	return $rv;
}

sub _geturl_read_response_body
{
	my ($fd, $cond) = splice @_, 0, 2;
	my ($sock, $cb, $timer, $page) = @{$_[0]};
	DEBUG && warn "${\(time)} _geturl_read_response_body($sock, $cb, $timer, $page)";
	
	eval {
		my $n = $sock->read_entity_body(my $buf, 1024)
			or die 'Not error';
	
		substr($$page, length $$page) = $buf
			unless $n == -1;
	};
	if ($@) {
		DEBUG && warn "${\(time)} Error: $@";
		Glib::Source->remove($timer);
		$cb->($$page);
		return; # remove watcher
	}
	
	1;
}

1;

__END__

=head1 NAME

WWW::AOstat::NB::Glib - Non-blocking Implementation of the stat.academ.org API based on Glib

=head1 SYNOPSIS

	$ao->login('root', '******',
		sub { 
			if ($_[0]) {
				say 'Login ok';
				$ao->stat(
					sub {
						require Data::Dumper;
						say Data::Dumper::Dumper(@_)
					}
				)
			}
			else {
				say 'Login failed';
			}
		}
	);

=head1 DESCRIPTION

The C<WWW::AOstat::NB::Glib> is a class implementing stat.academ.org API (only useful parts of the API).
With this module you can login to stat.academ.org, turn on/off internet, get actual balance and online status.
Also you can get amount of the credit (if you use it) and number of days remains.

=head1 METHODS

=over

=item WWW::AOstat->new($timeout||30)

Constructs new C<WWW::AOstat::NB::Glib> object.

=item $stat->login($login, $password, $cb)

Trying to login to stat.academ.org with given login and password

=item $stat->stat($cb)

Trying to get user statistic.

=item $stat->turn($act, $cb)

Trying to turn on the internet if argument is true and turn off if argument is false.

=item $stat->geturl($url, $cb)

For private usage. But you can use it to get some external page.

=back

=head1 COPYRIGHT

Copyright 2011 Oleg G <verdrehung@gmail.com>.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
