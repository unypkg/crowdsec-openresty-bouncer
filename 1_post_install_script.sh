#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154,SC1003,SC2005,SC2016

current_dir="$(pwd)"
unypkg_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
unypkg_root_dir="$(cd -- "$unypkg_script_dir"/.. &>/dev/null && pwd)"

cd "$unypkg_root_dir" || exit

#############################################################################################
### Start of script

OPENRESTY_PATH=(/uny/pkg/openresty/*/)
NGINX_CONF="crowdsec_openresty.conf"
NGINX_CONF_DIR="/etc/uny/openresty/conf.d/"
LIB_PATH="${OPENRESTY_PATH[0]}"lualib/
CONFIG_DIR="/etc/uny/crowdsec/bouncers"
DATA_PATH="/var/lib/crowdsec/lua"
SSL_CERTS_PATH="/etc/ssl/certs/ca-certificates.crt"
LAPI_DEFAULT_PORT="8080"
CSCLI_BIN=(/uny/pkg/crowdsec/*/bin/cscli)

[[ -d ${CONFIG_DIR} ]] || mkdir -pv ${CONFIG_DIR}

mkdir -pv "${DATA_PATH}/templates"
mkdir -pv "${NGINX_CONF_DIR}"
mkdir -pv "${LIB_PATH}"

if [[ -s /bin/perl && ! -L /bin/perl ]]; then
    mv -v /bin/perl /bin/perl_unybak
    unyp si perl
fi

if ! "${OPENRESTY_PATH[0]}"bin/opm list | grep "pintsized/lua-resty-http" >/dev/null; then
    "${OPENRESTY_PATH[0]}"bin/opm get "${dep}" >/dev/null
    echo "pintsized/lua-resty-http successfully installed in openresty"
fi

#Don't overwrite the existing file
if [ ! -s "${CONFIG_DIR}/crowdsec-openresty-bouncer.conf" ]; then
    #check if cscli is available, this can be installed on systems without crowdsec installed
    if command -v "${CSCLI_BIN[0]}" >/dev/null; then
        SUFFIX=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
        API_KEY=$("${CSCLI_BIN[0]}" bouncers add "crowdsec-openresty-bouncer-${SUFFIX}" -o raw)
        PORT=$("${CSCLI_BIN[0]}" config show --key "Config.API.Server.ListenURI" | cut -d ":" -f2)
        if [ ! -z "$PORT" ]; then
            LAPI_DEFAULT_PORT=${PORT}
        fi
        CROWDSEC_LAPI_URL="http://127.0.0.1:${LAPI_DEFAULT_PORT}"
    fi
    API_KEY=${API_KEY} CROWDSEC_LAPI_URL="${CROWDSEC_LAPI_URL}" envsubst '$API_KEY $CROWDSEC_LAPI_URL' <config/config_example.conf >"${CONFIG_DIR}/crowdsec-openresty-bouncer.conf"
    [ -n "${API_KEY}" ] && echo "New API key generated to be used in '${CONFIG_DIR}/crowdsec-openresty-bouncer.conf'"
else
    #Patch the existing file with new parameters if the need to be added
    echo "Patch crowdsec-openresty-bouncer.conf .."
    sed "s/=.*//g" "${CONFIG_DIR}/crowdsec-openresty-bouncer.conf" >/tmp/crowdsec.conf.raw
    sed "s/=.*//g" config/config_example.conf >/tmp/config_example.conf.raw
    if grep -vf /tmp/crowdsec.conf.raw /tmp/config_example.conf.raw; then
        grep -vf /tmp/crowdsec.conf.raw /tmp/config_example.conf.raw >/tmp/config_example.newvals
        cp "${CONFIG_DIR}/crowdsec-openresty-bouncer.conf" "${CONFIG_DIR}/crowdsec-openresty-bouncer.conf.bak"
        #Make sure we start on a new line.
        echo "" >>"${CONFIG_DIR}/crowdsec-openresty-bouncer.conf"
        grep -f /tmp/config_example.newvals /tmp/crowdsec/config/config_example.conf >>"${CONFIG_DIR}/crowdsec-openresty-bouncer.conf"
    fi
fi
sed -i 's|/var/lib/crowdsec/lua|'"${DATA_PATH}"'|' "${CONFIG_DIR}/crowdsec-openresty-bouncer.conf"

cp -r lua/lib/* "${LIB_PATH}"
cp templates/* "${DATA_PATH}/templates/"
#Patch the nginx config file
SSL_CERTS_PATH=${SSL_CERTS_PATH} envsubst '$SSL_CERTS_PATH' <openresty/${NGINX_CONF} >"${NGINX_CONF_DIR}/${NGINX_CONF}"
sed "s|/etc/crowdsec/bouncers|${CONFIG_PATH}|" -i "${NGINX_CONF_DIR}/${NGINX_CONF}"

#############################################################################################
### End of script

cd "$current_dir" || exit
