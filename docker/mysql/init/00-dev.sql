CREATE DATABASE IF NOT EXISTS revive_605;

ALTER USER IF EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '';

CREATE USER IF NOT EXISTS 'revive'@'%' IDENTIFIED WITH mysql_native_password BY '';
ALTER USER 'revive'@'%' IDENTIFIED WITH mysql_native_password BY '';
GRANT ALL PRIVILEGES ON revive_605.* TO 'revive'@'%';

FLUSH PRIVILEGES;
