package WWW::AOstat;

use strict;
use MIME::Base64;
use LWP::UserAgent;

my $URL_STAT     = 'https://stat.academ.org/ugui/api.php?OP=10&KEY=d3d9446802a44259755d38e6d163e820';
my $URL_TURN_ON  = 'https://stat.academ.org/ugui/api.php?OP=2&USERID={UID}&STATUS=ON&KEY=86c170e1c56dab3194474dbb4e34a775';
my $URL_TURN_OFF = 'https://stat.academ.org/ugui/api.php?OP=2&USERID={UID}&STATUS=OFF&KEY=499f46e2e46da8608bc04b95694dfbfd';


our $VERSION = 0.3;

sub new
{
	my ($class, %lwp_opts) = @_;
	
	my $self = {uid => undef, ua => LWP::UserAgent->new(agent=>'', timeout=>10, default_headers=>HTTP::Headers->new(Pragma=>'no-cache', Accept=>'image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, */*'), %lwp_opts)};
	bless $self, $class;
}

sub login
{
	my ($self, $login, $password, $nocheck) = @_;
	
	my $old_login    = $self->{login};
	my $old_password = $self->{password};
	
	$self->{login}    = $login;
	$self->{password} = $password;
	
	unless($nocheck)
	{
		my $page = $self->geturl($URL_STAT);
		$page =~ /ERR=(\d+)/ or return 0;
		unless($1 == 0)
		{
			$self->{login}    = $old_login;
			$self->{password} = $old_password;
			return 0;
		}
	}
	
	return 1;
}

sub stat
{
	my ($self) = @_;
	
	my $page = $self->geturl($URL_STAT);
	return () unless $page =~ /ERR=(\d+)/;
	return () if $1 != 0;
	
	unless(defined $self->{uid})
	{
		($self->{uid}) = $page =~ /USERID=(\d+)/;
		$URL_TURN_ON  =~ s/\{UID\}/$self->{uid}/;
		$URL_TURN_OFF =~ s/\{UID\}/$self->{uid}/;
	}
	
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
	
	if($act)
	{ # turn on
		$page = $self->geturl($URL_TURN_ON);
		
	}
	else
	{ # turn off
		$page = $self->geturl($URL_TURN_OFF);
	}
	
	return 0 unless $page =~ /ERR=(\d+)/;
	return !$1;
}

sub geturl
{
	my ($self, $url, $anonym) = @_;
	
	return $self->{ua}->get($url, $anonym ? undef : Authorization=>"Basic ".encode_base64("$self->{login}:$self->{password}"))->content;
}

1;

__END__

=head1 NAME

WWW::AOstat - Implementation of the stat.academ.org API

=head1 SYNOPSIS

 use WWW::AOstat;
 
 my $stat = WWW::AOstat->new(timeout=>10);
 if($stat->login('login', 'password'))
 {
	$stat->turn(1);
	my ($money, $traffic, $status) = $stat->stat();
 }
 else
 {
	die('Login failed');
 }

=head1 DESCRIPTION

The C<WWW::AOstat> is a class implementing stat.academ.org API (only useful parts of the API).
With this module you can login to stat.academ.org, turn on/off internet, get actual balance and online status.
Also you can get amount of the credit (if you use it) and number of days remains.

=head1 METHODS

=over

=item WWW::AOstat->new(%lwp_opts)

Constructs new C<WWW::AOstat> object. You can pass options pairs as argument. This options
would pass to LWP::UserAgent constructor.

Example:

	$stat = WWW::AOstat->new(timeout=>10, agent=>'Mozilla 5.0');

=item $stat->login($login, $password , $nocheck_for_success)

Trying to login to stat.academ.org . If optional parameter $nocheck_for_success set to true
login method will not try to real login and will return true even if login or password is 
incorrect. Otherwise return true on success and false on failure.

Example:

	$stat->login('qwerty', '1234') or die('Login failed');

=item $stat->stat()
Trying to get user statistic. Return list of the traffic (mb) remained, money (rub) remained, online
status, credit amount (rub) and days remains ( If credit not used this will be (0,0) ) on success. On failure return empty list, which means false in the list context.

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

=item $stat->geturl($url , $anonym)

For private usage. But you can use it to get some external page which is not
implemented by this module. It use GET method with Basic authorization which
use your current login and password. If optional second parameter set to true
it will not use Basic authorization.

Example:

	my $page = $stat->geturl('http://google.ru', 1);

=back

=head1 SEE ALSO

L<LWP::UserAgent>

=head1 COPYRIGHT

Copyright 2009 Oleg G <verdrehung@gmail.com>.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
