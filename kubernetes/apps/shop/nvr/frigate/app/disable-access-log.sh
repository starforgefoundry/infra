#!/command/with-contenv bash
set -o errexit -o nounset -o pipefail

sed -i 's|access_log /dev/stdout main;|access_log off;|' /usr/local/nginx/conf/nginx.conf
