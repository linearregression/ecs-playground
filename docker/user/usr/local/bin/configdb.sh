#!/usr/bin/env bash

cat > /usr/share/nginx/html/db.php <<EOF
<?php
\$db_host  =  "${DB_HOST}";
\$db_user  = "${DB_USER}";
\$db_pwd  = "${DB_PWD}";
\$db_name  = "${DB_NAME}";
?>
EOF