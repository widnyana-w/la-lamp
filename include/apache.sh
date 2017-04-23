# Copyright (C) 2014 - 2017, Teddysun <i@teddysun.com>
# 
# This file is part of the LAMP script.
#
# LAMP is a powerful bash script for the installation of 
# Apache + PHP + MySQL/MariaDB/Percona and so on.
# You can install Apache + PHP + MySQL/MariaDB/Percona in an very easy way.
# Just need to input numbers to choose what you want to install before installation.
# And all things will be done in a few minutes.
#
# Website:  https://lamp.sh
# Github:   https://github.com/teddysun/lamp

#Pre-installation apache
apache_preinstall_settings(){

    display_menu apache 2

    if [[ "$apache" != "do_not_install" ]];then
        if [ "$apache" == "${apache2_2_filename}" ];then
            apache_configure_args="--prefix=${apache_location} \
            --with-included-apr \
            --with-mpm=prefork \
            --with-ssl \
            --enable-so \
            --enable-suexec \
            --enable-deflate=shared \
            --enable-expires=shared \
            --enable-ssl=shared \
            --enable-headers=shared \
            --enable-rewrite=shared \
            --enable-static-support \
            --enable-modules=all \
            --enable-mods-shared=all"
        elif [ "$apache" == "${apache2_4_filename}" ];then
            apache_configure_args="--prefix=${apache_location} \
            --with-pcre=${depends_prefix}/pcre \
            --with-mpm=prefork \
            --with-included-apr \
            --with-ssl=${openssl_location} \
            --with-nghttp2 \
            --enable-http2 \
            --enable-so \
            --enable-dav \
            --enable-suexec \
            --enable-deflate=shared \
            --enable-ssl=shared \
            --enable-expires=shared \
            --enable-headers=shared \
            --enable-rewrite=shared \
            --enable-static-support \
            --enable-modules=all \
            --enable-mods-shared=all"
        fi
    fi
}

#Install apache
install_apache(){

    if check_sys packageManager apt;then
        apt-get -y remove apache2 apache2-doc apache2-utils apache2.2-common apache2.2-bin apache2-mpm-prefork apache2-doc apache2-mpm-worker
        apt-get -y install libssl-dev lynx
    elif check_sys packageManager yum;then
        yum -y remove httpd*
        yum -y install zlib-devel openssl openssl-devel lynx
    fi

if [ "$apache" == "${apache2_2_filename}" ];then
    cd ${cur_dir}/software/
    download_file "${apache2_2_filename}.tar.gz"
    tar zxf ${apache2_2_filename}.tar.gz
    cd ${apache2_2_filename}

    if grep -qi "Ubuntu 12.04" /etc/issue;then
        sed -i '/SSL_PROTOCOL_SSLV2/d' modules/ssl/ssl_engine_io.c
    fi

    LDFLAGS=-ldl
    error_detect "./configure ${apache_configure_args}"
    error_detect "parallel_make"
    error_detect "make install"
    unset LDFLAGS
    config_apache 2.2

elif [ "$apache" == "${apache2_4_filename}" ];then

    check_installed "install_pcre" "${depends_prefix}/pcre"
    check_installed "install_openssl" "${openssl_location}"
    install_nghttp2

    echo "/usr/local/lib" > /etc/ld.so.conf.d/locallib.conf
    ldconfig

    cd ${cur_dir}/software/
    download_file "${apr_filename}.tar.gz"
    tar zxf ${apr_filename}.tar.gz
    download_file "${apr_util_filename}.tar.gz"
    tar zxf ${apr_util_filename}.tar.gz
    download_file "${apache2_4_filename}.tar.gz"
    tar zxf ${apache2_4_filename}.tar.gz
    cd ${apache2_4_filename}
    mv ${cur_dir}/software/${apr_filename} srclib/apr
    mv ${cur_dir}/software/${apr_util_filename} srclib/apr-util

    LDFLAGS=-ldl
    LD_LIBRARY_PATH=${openssl_location}/lib:${LD_LIBRARY_PATH}
    error_detect "./configure ${apache_configure_args}"
    error_detect "parallel_make"
    error_detect "make install"
    unset LDFLAGS
    unset LD_LIBRARY_PATH
    config_apache 2.4
fi
}


config_apache(){
    id -u apache >/dev/null 2>&1
    [ $? -ne 0 ] && groupadd apache && useradd -M -s /sbin/nologin -g apache apache

    [ ! -d ${web_root_dir} ] && mkdir -p ${web_root_dir} && chmod -R 755 ${web_root_dir}
    local version=$1

    if [ -f ${apache_location}/conf/httpd.conf ];then
        cp -f ${apache_location}/conf/httpd.conf ${apache_location}/conf/httpd.conf.bak
    fi

    grep -E -q "^\s*#\s*Include conf/extra/httpd-vhosts.conf" ${apache_location}/conf/httpd.conf && \
    sed -i 's#^\s*\#\s*Include conf/extra/httpd-vhosts.conf#Include conf/extra/httpd-vhosts.conf#' ${apache_location}/conf/httpd.conf || \
    sed -i '$aInclude conf/extra/httpd-vhosts.conf' ${apache_location}/conf/httpd.conf

    mv ${apache_location}/conf/extra/httpd-vhosts.conf ${apache_location}/conf/extra/httpd-vhosts.conf.bak
    mkdir -p ${apache_location}/conf/vhost/
    touch ${apache_location}/conf/vhost/none.conf

    cat > /etc/logrotate.d/httpd <<EOF
${apache_location}/logs/access_log ${apache_location}/logs/error_log {
    daily
    rotate 14
    missingok
    notifempty
    compress
    sharedscripts
    postrotate
        [ ! -f ${apache_location}/logs/httpd.pid ] || kill -USR1 \`cat ${apache_location}/logs/httpd.pid\`
    endscript
}
EOF

    cat > ${apache_location}/conf/extra/httpd-vhosts.conf <<EOF
<VirtualHost *:80>
ServerName localhost
ServerAlias localhost
DocumentRoot ${web_root_dir}
DirectoryIndex index.php index.html index.htm
<Directory ${web_root_dir}>
Options +Includes -Indexes
AllowOverride All
Order Deny,Allow
Allow from All
</Directory>
</VirtualHost>
Include ${apache_location}/conf/vhost/*.conf
EOF

    sed -i 's/^User.*/User apache/i' ${apache_location}/conf/httpd.conf
    sed -i 's/^Group.*/Group apache/i' ${apache_location}/conf/httpd.conf
    sed -i 's/^#ServerName www.example.com:80/ServerName 0.0.0.0:80/' ${apache_location}/conf/httpd.conf
    sed -i 's/^ServerAdmin you@example.com/ServerAdmin admin@localhost/' ${apache_location}/conf/httpd.conf
    sed -i 's@^#Include conf/extra/httpd-info.conf@Include conf/extra/httpd-info.conf@' ${apache_location}/conf/httpd.conf
    sed -i 's@DirectoryIndex index.html@DirectoryIndex index.html index.php@' ${apache_location}/conf/httpd.conf
    sed -i "s@^DocumentRoot.*@DocumentRoot \"${web_root_dir}\"@" ${apache_location}/conf/httpd.conf
    sed -i "s@^<Directory \"${apache_location}/htdocs\">@<Directory \"${web_root_dir}\">@" ${apache_location}/conf/httpd.conf
    echo "ServerTokens ProductOnly" >> ${apache_location}/conf/httpd.conf

    if [ ${version} == "2.4" ];then
        sed -i -r 's/^#(.*mod_cache.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_cache_socache.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_socache_shmcb.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_socache_dbm.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_socache_memcache.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_proxy.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_proxy_connect.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_proxy_ftp.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_proxy_http.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_suexec.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_vhost_alias.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_rewrite.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_deflate.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_expires.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_ssl.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i -r 's/^#(.*mod_http2.so)/\1/' ${apache_location}/conf/httpd.conf
        sed -i "s@^export LD_LIBRARY_PATH.*@export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:${openssl_location}/lib@" ${apache_location}/bin/envvars
        echo "ProtocolsHonorOrder On" >> ${apache_location}/conf/httpd.conf
        echo "Protocols h2 http/1.1" >> ${apache_location}/conf/httpd.conf
        
        sed -i 's/Allow from All/Require all granted/' ${apache_location}/conf/extra/httpd-vhosts.conf
        sed -i 's/Require host .example.com/Require host localhost/g' ${apache_location}/conf/extra/httpd-info.conf
    elif [ ${version} == "2.2" ];then
        sed -i -r 's/^(.*mod_unique_id.so)/\#&/' ${apache_location}/conf/httpd.conf
        sed -i 's/Allow from .example.com/Allow from localhost/g' ${apache_location}/conf/extra/httpd-info.conf
    fi

    rm -f /etc/init.d/httpd
    if centosversion 6; then
        cp -f ${cur_dir}/conf/httpd-init-centos6 /etc/init.d/httpd
    else
        cp -f ${cur_dir}/conf/httpd-init /etc/init.d/httpd
    fi
    sed -i "s#^apache_location=.*#apache_location=$apache_location#" /etc/init.d/httpd
    chmod +x /etc/init.d/httpd

    rm -fr /var/log/httpd /usr/sbin/httpd
    ln -s ${apache_location}/bin/httpd /usr/sbin/httpd
    ln -s ${apache_location}/logs /var/log/httpd

    cp -f ${cur_dir}/conf/index.html ${web_root_dir}
    cp -f ${cur_dir}/conf/index_cn.html ${web_root_dir}
    cp -f ${cur_dir}/conf/lamp.gif ${web_root_dir}
    cp -f ${cur_dir}/conf/jquery.js ${web_root_dir}
    cp -f ${cur_dir}/conf/p.php ${web_root_dir}
    cp -f ${cur_dir}/conf/p_cn.php ${web_root_dir}
    cp -f ${cur_dir}/conf/phpinfo.php ${web_root_dir}
    cp -f ${cur_dir}/conf/favicon.ico ${web_root_dir}

    chown -R apache.apache ${web_root_dir}

    boot_start httpd

}
