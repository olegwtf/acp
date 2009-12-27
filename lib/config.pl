our %config;

$config{preg_credit} = '<span class="info_right">(\d+).+?\..+?\(.+?: (\d+)\)';
$config{preg_usage} = '<td>([\d.]+)[^<]{0,10}</td>.?\n\s+<td>([\d.]+)\s*(.)[^<]{0,10}</td>.?\n\s+<td nowrap>\d+-{mon}-{mday}</td>';
$config{version} = 0.280;

1;
