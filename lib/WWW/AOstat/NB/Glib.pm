package WWW::AOstat;

use strict;
use MIME::Base64;
use Digest::MD5;
use LWP::UserAgent;
use Carp;

our $VERSION = 0.4;

my $URL_STAT = 'https://stat.academ.org/ugui/api.php?OP=10&KEY=d3d9446802a44259755d38e6d163e820';
my $URL_TURN_ON = 'https://stat.academ.org/ugui/api.php?OP=2&USERID={UID}&STATUS=ON&KEY={KEY}';
my $URL_TURN_OFF = 'https://stat.academ.org/ugui/api.php?OP=2&USERID={UID}&STATUS=OFF&KEY={KEY}';

sub new
{
	my ($class, $login, $password, %lwp_opts) = @_;
	
	croak 'usage: new(login, password, [%lwp_opts])' unless defined($login) && defined($password);
	
	my $self = {
			login => $login,
			password => $password,
			uid => undef,
			ua => LWP::UserAgent->new(agent=>'', timeout=>10, default_headers=>HTTP::Headers->new(Pragma=>'no-cache', Accept=>'image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, */*'), %lwp_opts),
		};
		
	bless $self, $class;
}

# get/set properties
foreach my $key qw(login password uid)
{
      no strict 'refs';
      *$key = sub
      {
            my $self = shift;
      
            return $self->{$key} = $_[0] if defined $_[0];
            return $self->{$key};
      }
}

sub try_login
{
	my ($self, $login, $password) = @_;
	
	my $page = $self->geturl($URL_STAT, $login, $password);
	my ($uid) = $page =~ /USERID=(\d+)/;
	return $uid;
}


sub stat
{
	my ($self) = @_;
	
	my $page = $self->geturl($URL_STAT);
	return () if index($page, 'ERR=0') == -1;
	
	my ($traff) = $page =~ /REMAINS_MB=(-?\d+)/;
	my ($money) = $page =~ /REMAINS_RUR=(-?\d+(?:.\d{1,2})?)/;
	my ($cred_sum, $cred_time) = $page =~ /CREDIT=(\d+);(\d+)/;
	my $status  = index($page, ';OFF') == -1
			? 
				index($page, ';ON') == -1 ? 
					-1 : 
					 1
			:
			0;
	
	return ($traff, $money, $status, $cred_sum, $cred_time);
}

sub turn
{
	my ($self, $act) = @_;
	
	my $page;
	
	unless( $self->{uid} )
	{
		$self->{uid} = $self->try_login();
	}
	
	if($act)
	{ # turn on
		my $key = Digest::MD5::md5_hex('2' . $self->{uid} . 'ON');
		my $url_turn_on = $URL_TURN_ON;
		
		$url_turn_on =~ s/\{UID\}/$self->{uid}/;
		$url_turn_on =~ s/\{KEY\}/$key/;
		
		$page = $self->geturl($url_turn_on);
	}
	else
	{ # turn off
		my $key = Digest::MD5::md5_hex('2' . $self->{uid} . 'OFF');
		my $url_turn_off = $URL_TURN_OFF;
		
		$url_turn_off =~ s/\{UID\}/$self->{uid}/;
		$url_turn_off =~ s/\{KEY\}/$key/;
		
		$page = $self->geturl($url_turn_off);
	}
	
	return index($page, 'ERR=0') != -1;
}

sub geturl
{
	my ($self, $url, $login, $password) = @_;
	
	return $self->{ua}->get( $url, Authorization=>"Basic ".encode_base64( ($login||$self->{login}) . ':' . ($password||$self->{password}) ) )->content;
}

1;

__END__

=head1 NAME

WWW::AOstat - Implementation of the stat.academ.org API

=head1 SYNOPSIS

 use WWW::AOstat;
 
 my $stat = WWW::AOstat->new('login', 'password', timeout=>10);
 
 $stat->turn(1);
 my ($traff, $money, $status, $cred_sum, $cred_time) = $stat->stat();

=head1 DESCRIPTION

The C<WWW::AOstat> is a class implementing stat.academ.org API (only useful parts of the API).
With this module you can login to stat.academ.org, turn on/off internet, get actual balance and online status.
Also you can get amount of the credit (if you use it) and number of days remains.

=head1 METHODS

=over

=item WWW::AOstat->new($login, $password, %lwp_opts)

Constructs new C<WWW::AOstat> object. $login and $password are login and password from stat.academ.org. Also you
can pass options pairs as argument. This options would pass to LWP::UserAgent constructor.

Example:

	$stat = WWW::AOstat->new('user_login', 'user_password', timeout=>10, agent=>'Mozilla 5.0');

=item $stat->try_login($login, $password)

Trying to login to stat.academ.org with given login and password or with login from constructor if $login is undef
and password from constructor if $password is undef. On success return user id and false on failure.

Example:

	my $uid = $stat->try_login('qwerty', '1234') or die('Login failed');

=item $stat->stat()

Trying to get user statistic. Return list of the traffic (mb) remained, money (rub) remained, online
status, credit amount (rub) and days remains ( If credit not used this will be (0,0) ) on success.
On failure return empty list, which means false in the list context.

Example:

	if(my ($traff, $money, $status, $cred_sum, $cred_time) = $stat->stat)
	{
		print "Statistic: traffic - $traff, money - $money, status - "
		      .($status == 1 ? "online" : $status == 0 ? "offline" : "inaccessible").
		      .($cred_sum ? "credit - $cred_sum rub, $cred_time days" : "credit not used");
	}
	else
	{
		die("Failed to get stat");
	}

=item $stat->turn($act)

Trying to turn on the internet if argument is true and turn off if argument is false.
Return true on success and false on failure.

=item $stat->geturl($url, $login, $password)

For private usage. But you can use it to get some external page which is not
implemented by this module. It use GET method with Basic authorization which
use your current login and password or $login and $password if given.

Example:

	my $page = $stat->geturl('http://google.ru', 'anonym', 'anonym');

=item $stat->login

=item $stat->login($login)

Get or set current user login

=item $stat->password

=item $stat->password($password)

Get or set current user password

=item $stat->uid

=item $stat->uid($uid)

Get or set current user id

=back

=head1 SEE ALSO

L<LWP::UserAgent>

=head1 COPYRIGHT

Copyright 2009 Oleg G <verdrehung@gmail.com>.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
