<?php
	$result = exec('./listMethods.pl', $output, $return_var);
	print_r($output);
	print "return_var: $return_var\n";
?>
