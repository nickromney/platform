<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Request Info - SD-WAN Demo</title>
    <style>
        body { font-family: monospace; background: #1a1a2e; color: #eee; padding: 20px; }
        h1 { color: #00d9ff; }
        h2 { color: #ff6b6b; border-bottom: 1px solid #333; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { text-align: left; padding: 12px; border: 1px solid #333; }
        th { background: #16213e; color: #00d9ff; }
        tr:nth-child(even) { background: #16213e; }
        .highlight { color: #00ff88; font-weight: bold; }
        .cloud-sys1 { border-left: 4px solid #ff6b6b; }
        .cloud-sys2 { border-left: 4px solid #4ecdc4; }
        .cloud-sys3 { border-left: 4px solid #ffe66d; }
    </style>
</head>
<body>
    <h1>SD-WAN Request Inspector</h1>
    
    <h2>Request Headers</h2>
    <table>
        <tr><th>Header</th><th>Value</th></tr>
        <?php
        $headers = array(
            'HTTP_HOST' => 'Host',
            'HTTP_X_REAL_IP' => 'X-Real-IP',
            'HTTP_X_FORWARDED_FOR' => 'X-Forwarded-For', 
            'HTTP_X_FORWARDED_PROTO' => 'X-Forwarded-Proto',
            'HTTP_X_FORWARDED_HOST' => 'X-Forwarded-Host',
            'HTTP_X_REAL_PORT' => 'X-Real-Port',
            'HTTP_USER_AGENT' => 'User-Agent',
            'REMOTE_ADDR' => 'Remote Addr',
            'SERVER_PROTOCOL' => 'Server Protocol',
            'REQUEST_METHOD' => 'Request Method',
            'REQUEST_URI' => 'Request URI'
        );
        
        foreach ($headers as $serverKey => $displayName) {
            $value = isset($_SERVER[$serverKey]) ? htmlspecialchars($_SERVER[$serverKey]) : '<span style="color:#666">(not set)</span>';
            echo "<tr><td>{$displayName}</td><td class='highlight'>{$value}</td></tr>\n";
        }
        ?>
    </table>
    
    <h2>Server Variables</h2>
    <table>
        <tr><th>Variable</th><th>Value</th></tr>
        <?php
        $serverVars = array(
            'SERVER_ADDR' => 'Server Address',
            'SERVER_NAME' => 'Server Name',
            'SERVER_PORT' => 'Server Port',
            'DOCUMENT_ROOT' => 'Document Root',
            'SCRIPT_FILENAME' => 'Script Filename'
        );
        
        foreach ($serverVars as $key => $displayName) {
            $value = isset($_SERVER[$key]) ? htmlspecialchars($_SERVER[$key]) : '<span style="color:#666">(not set)</span>';
            echo "<tr><td>{$displayName}</td><td>{$value}</td></tr>\n";
        }
        ?>
    </table>
    
    <h2>Network Context</h2>
    <table>
        <tr><th>Property</th><th>Value</th></tr>
        <tr><td>Client IP</td><td class="highlight"><?php echo htmlspecialchars($_SERVER['REMOTE_ADDR']); ?></td></tr>
        <tr><td>Original Client (X-Forwarded-For)</td><td class="highlight"><?php echo htmlspecialchars($_SERVER['HTTP_X_FORWARDED_FOR'] ?? 'N/A'); ?></td></tr>
        <tr><td>Protocol</td><td><?php echo isset($_SERVER['HTTP_X_FORWARDED_PROTO']) ? htmlspecialchars($_SERVER['HTTP_X_FORWARDED_PROTO']) : 'direct'; ?></td></tr>
    </table>
    
    <hr>
    <p style="color:#666; font-size: 12px;">
        Generated at: <?php echo date('Y-m-d H:i:s'); ?><br>
        This page shows all request headers to help understand SD-WAN routing.
    </p>
</body>
</html>
