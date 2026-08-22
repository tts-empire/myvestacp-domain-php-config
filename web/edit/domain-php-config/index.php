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

$actual = isset($config['ACTUAL']) && is_array($config['ACTUAL']) ? $config['ACTUAL'] : array();
$input_values = array();
$reset_pending = array();
foreach ($fields as $parameter => $label) {
    $input_values[$parameter] = isset($actual[$parameter]['VALUE']) ? $actual[$parameter]['VALUE'] : '';
}

if (!empty($_POST['save'])) {
    if (!isset($_POST['token']) || $_SESSION['token'] != $_POST['token']) {
        header('Location: /login/');
        exit;
    }

    $restart = empty($_POST['v_restart']) ? 'no' : 'yes';
    $operations = array();
    foreach ($fields as $parameter => $label) {
        $actual_value = isset($actual[$parameter]['VALUE']) ? (string)$actual[$parameter]['VALUE'] : '';
        $managed = !empty($actual[$parameter]['MANAGED']);
        $reset_requested = isset($_POST['php_reset'][$parameter]) && $_POST['php_reset'][$parameter] === 'yes';

        if ($reset_requested && $managed) {
            $operations[] = array('action' => 'reset', 'parameter' => $parameter);
            $reset_pending[$parameter] = true;
            $input_values[$parameter] = isset($actual[$parameter]['BASE_VALUE']) ? $actual[$parameter]['BASE_VALUE'] : '';
            continue;
        }

        if (!isset($_POST['php_config'][$parameter])) {
            continue;
        }
        $value = trim($_POST['php_config'][$parameter]);
        $input_values[$parameter] = $value;
        if ($value === '') {
            continue;
        }
        if ($value !== $actual_value) {
            $operations[] = array('action' => 'set', 'parameter' => $parameter, 'value' => $value);
        }
    }

    if (!empty($operations)) {
        $command = VESTA_CMD.'v-update-domain-php-config '.$domain_arg.' '.$restart;
        foreach ($operations as $operation) {
            $command .= ' '.escapeshellarg($operation['action']).' '.escapeshellarg($operation['parameter']);
            if ($operation['action'] === 'set') {
                $command .= ' '.escapeshellarg($operation['value']);
            }
        }
        $command .= ' 2>&1';
        exec($command, $output, $return_var);
        check_return_code($return_var, $output);
        unset($output);
    }

    if (empty($_SESSION['error_msg'])) {
        if (empty($operations)) {
            $_SESSION['ok_msg'] = __('No PHP configuration changes were detected.');
        } else {
            $_SESSION['ok_msg'] = __('PHP domain configuration has been saved.');
            exec($list_command, $config_output, $config_status);
            $updated_config = json_decode(implode('', $config_output), true);
            unset($config_output);
            if ($config_status == 0 && !empty($updated_config['ACTUAL'])) {
                $config = $updated_config;
                $actual = $updated_config['ACTUAL'];
                $reset_pending = array();
                foreach ($fields as $parameter => $label) {
                    $input_values[$parameter] = isset($actual[$parameter]['VALUE']) ? $actual[$parameter]['VALUE'] : '';
                }
            }
        }
    }
}

$source_labels = array(
    'managed' => __('managed override'),
    'pool' => __('domain pool'),
    'php_ini' => sprintf(__('PHP %s php.ini'), $config['PHP_VERSION']),
    'unavailable' => __('unavailable')
);
$field_data = array();
foreach ($fields as $parameter => $label) {
    $info = isset($actual[$parameter]) && is_array($actual[$parameter]) ? $actual[$parameter] : array();
    $source = isset($info['SOURCE']) ? $info['SOURCE'] : 'unavailable';
    $base_source = isset($info['BASE_SOURCE']) ? $info['BASE_SOURCE'] : 'unavailable';
    $has_suggestion = array_key_exists($parameter, $suggested);
    $actual_value = isset($info['VALUE']) ? (string)$info['VALUE'] : '';
    $field_data[$parameter] = array(
        'id' => 'php-config-'.str_replace('.', '-', $parameter),
        'label' => $label,
        'actual_value' => $actual_value,
        'actual_source' => isset($source_labels[$source]) ? $source_labels[$source] : $source_labels['unavailable'],
        'base_value' => isset($info['BASE_VALUE']) ? (string)$info['BASE_VALUE'] : '',
        'base_source' => isset($source_labels[$base_source]) ? $source_labels[$base_source] : $source_labels['unavailable'],
        'managed' => !empty($info['MANAGED']),
        'suggested_value' => $has_suggestion ? (string)$suggested[$parameter] : '',
        'has_suggestion' => $has_suggestion,
        'matches_suggestion' => $has_suggestion && $actual_value === (string)$suggested[$parameter],
        'input_value' => isset($input_values[$parameter]) ? $input_values[$parameter] : $actual_value,
        'reset_pending' => !empty($reset_pending[$parameter])
    );
}

$resource_summary = '';
$audit_notice = __('The auditor analysed this specific server and calculated these suggestions from its RAM, CPU count, configured PHP-FPM pools, PHP-FPM memory budget, and estimated worker memory. These recommendations are specific to this server; they are not standard PHP defaults.');
if (!empty($suggestion['RESOURCES']) && !empty($suggestion['BUDGET'])) {
    $resource_summary = sprintf(
        __('Detected server resources: %s MB RAM, %s CPUs, %s configured PHP-FPM pools. PHP-FPM budget: %s MB; estimated worker memory: %s MB.'),
        $suggestion['RESOURCES']['MEM_TOTAL_MB'],
        $suggestion['RESOURCES']['CPU_COUNT'],
        $suggestion['RESOURCES']['POOL_COUNT'],
        $suggestion['BUDGET']['PHP_FPM_MB'],
        $suggestion['BUDGET']['ESTIMATED_WORKER_MB']
    );
} else {
    $audit_notice = __('No server-specific auditor suggestions are available at this time.');
    foreach ($field_data as $parameter => $data) {
        $field_data[$parameter]['has_suggestion'] = false;
        $field_data[$parameter]['matches_suggestion'] = false;
    }
}

render_page($user, $TAB, 'edit_domain_php_config');
unset($_SESSION['error_msg']);
unset($_SESSION['ok_msg']);
