<?php
error_reporting(NULL);
$TAB = 'WEB';

include($_SERVER['DOCUMENT_ROOT'].'/inc/main.php');

$domain = isset($_GET['domain']) ? $_GET['domain'] : '';
if (!preg_match('/^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$/', $domain)) {
    header('Location: /list/web/');
    exit;
}

$domain_arg = escapeshellarg($domain);
exec(VESTA_CMD.'v-search-domain-owner '.$domain_arg, $owner_output, $owner_status);
$owner = trim(implode('', $owner_output));
unset($owner_output);
if ($owner_status != 0 || empty($owner)) {
    header('Location: /list/web/');
    exit;
}
if ($_SESSION['user'] != 'admin' && $_SESSION['user'] != $owner) {
    header('Location: /list/web/');
    exit;
}

$list_command = VESTA_CMD.'v-list-domain-php-config '.$domain_arg.' json';
exec($list_command, $config_output, $config_status);
$config = json_decode(implode('', $config_output), true);
unset($config_output);

if ($config_status != 0 || empty($config['PHP_VERSION'])) {
    $_SESSION['error_msg'] = __('PHP-FPM configuration is not available for this domain.');
    header('Location: /edit/web/?domain='.rawurlencode($domain));
    exit;
}

$values = isset($config['CONFIG']) && is_array($config['CONFIG']) ? $config['CONFIG'] : array();
$suggest_command = VESTA_CMD.'v-suggest-domain-php-config '.$domain_arg.' json';
exec($suggest_command, $suggest_output, $suggest_status);
$suggestion = json_decode(implode('', $suggest_output), true);
unset($suggest_output);
$suggested = ($suggest_status == 0 && !empty($suggestion['SUGGESTED'])) ? $suggestion['SUGGESTED'] : array();

$fields = array(
    'memory_limit' => __('Memory Limit'),
    'max_execution_time' => __('Max Execution Time'),
    'max_input_time' => __('Max Input Time'),
    'post_max_size' => __('Post Max Size'),
    'upload_max_filesize' => __('Upload Max Filesize'),
    'max_input_vars' => __('Max Input Vars'),
    'max_file_uploads' => __('Max File Uploads'),
    'pm.max_children' => __('PHP-FPM Max Children'),
    'pm.max_requests' => __('PHP-FPM Max Requests')
);

if (!empty($_POST['save'])) {
    if (!isset($_POST['token']) || $_SESSION['token'] != $_POST['token']) {
        header('Location: /login/');
        exit;
    }

    $restart = empty($_POST['v_restart']) ? 'no' : 'yes';
    foreach ($fields as $parameter => $label) {
        if (!isset($_POST['php_config'][$parameter])) {
            continue;
        }
        $value = trim($_POST['php_config'][$parameter]);
        if ($value === '') {
            continue;
        }
        $command = VESTA_CMD.'v-change-domain-php-config '.$domain_arg.' '.escapeshellarg($parameter).' '.escapeshellarg($value).' '.$restart;
        exec($command, $output, $return_var);
        check_return_code($return_var, $output);
        unset($output);
        if (!empty($_SESSION['error_msg'])) {
            break;
        }
        $values[$parameter] = $value;
    }

    if (empty($_SESSION['error_msg'])) {
        $_SESSION['ok_msg'] = __('PHP domain configuration has been saved.');
    }
}

foreach ($fields as $parameter => $label) {
    if (!isset($values[$parameter]) && isset($suggested[$parameter])) {
        $values[$parameter] = $suggested[$parameter];
    }
}

$resource_summary = '';
if (!empty($suggestion['RESOURCES']) && !empty($suggestion['BUDGET'])) {
    $resource_summary = sprintf(
        __('Detected resources: %s MB RAM, %s CPU, %s active FPM pools. PHP-FPM budget: %s MB.'),
        htmlentities($suggestion['RESOURCES']['MEM_TOTAL_MB']),
        htmlentities($suggestion['RESOURCES']['CPU_COUNT']),
        htmlentities($suggestion['RESOURCES']['POOL_COUNT']),
        htmlentities($suggestion['BUDGET']['PHP_FPM_MB'])
    );
}

render_page($user, $TAB, 'edit_domain_php_config');
unset($_SESSION['error_msg']);
unset($_SESSION['ok_msg']);
