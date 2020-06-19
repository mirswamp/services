<?php

// Make an object to represent our server.
$client = new /xmlrpc_client('path', 'localhost', 8084);

// Send a message to the server.
$message = new xmlrpcmsg('listMethods');
$result = $client->send($message);

// Process the response.
if (! $result) {
} elseif ($result->faultCode()) {
    print "<p>XML-RPC Fault #" . $result->faultCode() . ": " .  $result->faultString();
} else {
}
?>
