package WWW::AOstat;

use strict;
use MIME::Base64;
use LWP::UserAgent;

use constant
{
	URL_STAT     => 'https://stat.academ.org/ugui/api.php?OP=10&KEY=d3d9446802a44259755d38e6d163e820',
	URL_TURN_ON  => 'https://stat.academ.org/ugui/api.php?OP=2&USERID=4397&STATUS=ON&KEY=86c170e1c56dab3194474dbb4e34a775',
	URL_TURN_OFF => 'https://stat.academ.org/ugui/api.php?OP=2&USERID=4397&STATUS=OFF&KEY=499f46e2e46da8608bc04b95694dfbfd',
	URL_USAGE    => 'https://stat.academ.org/ugui/index.php?pid=504',
	URL_CREDIT   => 'https://stat.academ.org/ugui/index.php?pid=500',
};

our $VERSION = 0.1;

sub new
{
	my ($class, %lwp_opts) = @_;
	
	my $self = {ua=>LWP::UserAgent->new(agent=>'', timeout=>10, default_headers=>HTTP::Headers->new(Pragma=>'no-cache', Accept=>'image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, */*'), %lwp_opts)};
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
		my $page = $self->geturl(URL_STAT);
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
	
	my $page = $self->geturl(URL_STAT);
	my ($traff) = $page =~ /REMAINS_MB=(\d+)/;
	my ($money) = $page =~ /REMAINS_RUR=(\d+(?:.\d{1,2})?)/;
	my $status  = index($page, ';OFF') == -1
			? 
				index($page, ';ON') == -1 ? 
					-1 : 
					 1
			:
			0;
	
	return ($traff, $money, $status);
}

sub turn
{
	my ($self, $act) = @_;
	
	my $page;
	
	if($act)
	{ # turn on
		$page = $self->geturl(URL_TURN_ON);
		
	}
	else
	{ # turn off
		$page = $self->geturl(URL_TURN_OFF);
	}
	
	$page =~ /ERR=(\d+)/;
	return !$1;
}

sub usage
{
	my ($self, $regexp) = @_;
	
	my $page = $self->geturl(URL_USAGE);
	my($mday, $mon) = (localtime)[3, 4];
	($mday, $mon) = (sprintf('%02d', $mday), sprintf('%02d', $mon+1));
	
	if($regexp)
	{
		$regexp =~ s/\{mon\}/$mon/;
		$regexp =~ s/\{mday\}/$mday/;
	}
	else
	{
		$regexp = qr!<td>([\d.]+)[^<]{0,10}</td>.?\n\s+<td>([\d.]+)[^<]{0,10}</td>.?\n\s+<td nowrap>\d+-$mon-$mday</td>!;
	}

	my ($money, $traff) = $page =~ $regexp;
	
	return ($traff || $money) ? ($traff, $money) : ();
}

sub credit
{
	my($self, $regexp) = @_;
	
	my $page = $self->geturl(URL_CREDIT);
	$regexp = '<span class="info_right">(\d+).+?\..+?\(.+?: (\d+)\)' unless $regexp;
	my ($cred_sum, $cred_time) = $page =~ $regexp;
	
	return ($cred_sum || $cred_time) ? ($cred_sum, $cred_time) : ();
}

sub geturl
{
	my ($self, $url) = @_;
	
	return $self->{ua}->get($url, Authorization=>"Basic ".encode_base64("$self->{login}:$self->{password}"))->content;
}

1;
