<?php
include_once "db.php";

$link = mysql_connect( $db_host, $db_user, $db_pwd);

if (!$link) {
	echo "FAIL";
}
else {
 if (! mysql_select_db($db_name)) {
 	echo "FAIL";
 }
 else {
 	echo "PASS";
 } 
}
?>
