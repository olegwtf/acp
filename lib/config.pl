our %config;

$config{login_failed} = '<div style="color:red">';
$config{stat_url} = 'https://stat.academ.org/ugui/index.php';
$config{preg_cred} = '<span class="info_right">(\d+).+?\..+?\(.+?: (\d+)\)';
$config{preg_bal} = 'font-size:24px;">(.+?)<\/span';
$config{preg_pid} = '\?(pid=[0-9]+&id=[0-9]+)"';
$config{version} = 0.2501;
1;
