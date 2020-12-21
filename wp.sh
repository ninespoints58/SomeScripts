#!/bin/bash
function blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
function green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
function red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
function version_lt(){
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; 
}

source /etc/os-release
RELEASE=$ID
VERSION=$VERSION_ID

function install_wordpress(){
    # 安装iptables-services
    green "安装 iptables-services"
    yum install -y iptables-services
    systemctl start iptables
    systemctl enable iptables
    iptables -F
    SSH_PORT=$(awk '$1=="Port" {print $2}' /etc/ssh/sshd_config)
    if [ ! -n "$SSH_PORT" ]; then
        iptables -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT
    else
        iptables -A INPUT -p tcp -m tcp --dport ${SSH_PORT} -j ACCEPT
    fi
    iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
    iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    service iptables save
    green "====================================================================="
    green "安全起见，iptables仅开启ssh,http,https端口，如需开放其他端口请自行放行"
    green "====================================================================="
    sleep 1
    yum -y install wget

    #创建临时目录存方wp
    mkdir /usr/share/wordpresstemp
    cd /usr/share/wordpresstemp/
    wget https://cn.wordpress.org/latest-zh_CN.zip

    # 先从官方下载wp程序
    if [ ! -f "/usr/share/wordpresstemp/latest-zh_CN.zip" ]; then
        red "从cn官网下载wordpress失败，尝试从github下载……"
        wget https://github.com/atrandys/wordpress/raw/master/latest-zh_CN.zip    
    fi
    # 下载不成功则去作者github拉取
    if [ ! -f "/usr/share/wordpresstemp/latest-zh_CN.zip" ]; then
        red "我它喵的从github下载wordpress也失败了，请尝试手动安装……"
        green "从wordpress官网下载包然后命名为latest-zh_CN.zip，新建目录/usr/share/wordpresstemp/，上传到此目录下即可"
        exit 1
    fi
    green "==============="
    green " 1.安装必要软件"
    green "==============="
    sleep 1
    green ""

    # 下载安装源

    # 判断文件是否存在
    if [ ! -f "epel-release-latest-7.noarch.rpm" ]; then
        wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    fi

    if [ ! -f "remi-release-7.rpm" ]; then
        wget https://rpms.remirepo.net/enterprise/remi-release-7.rpm
    fi
    
    if [ -f "epel-release-latest-7.noarch.rpm" -a -f "remi-release-7.rpm" ]; then
        green "下载软件源成功"
    else
        red "下载软件源失败，退出安装"
        exit 1
    fi

    rpm -Uvh remi-release-7.rpm epel-release-latest-7.noarch.rpm --force --nodeps

    #sed -i "0,/enabled=0/s//enabled=1/" /etc/yum.repos.d/epel.repo

    # 安装组件
    green "安装 unzip vim tcl expect curl socat"
    yum -y install  unzip vim tcl expect curl socat
    echo
    echo
    green "============"
    green "2.安装PHP7.4"
    green "============"
    sleep 1

    # 安装php
    yum -y install php74 php74-php-gd php74-php-opcache php74-php-pdo php74-php-mbstring php74-php-cli php74-php-fpm php74-php-mysqlnd php74-php-xml
    service php74-php-fpm start

    #设置开机启动
    chkconfig php74-php-fpm on

    if [ `yum list installed | grep php74 | wc -l` -ne 0 ]; then
        echo
        green "【checked】 PHP7安装成功"
        echo
        echo
        sleep 2
        php_status=1
    fi
    green "==============="
    green "  3.安装MySQL"
    green "==============="
    sleep 1
    #wget http://repo.mysql.com/mysql-community-release-el7-5.noarch.rpm

    # 安装源
    if [ ! -f "mysql80-community-release-el7-3.noarch.rpm" ]; then
        wget https://repo.mysql.com/mysql80-community-release-el7-3.noarch.rpm
    fi
    
    rpm -ivh mysql80-community-release-el7-3.noarch.rpm --force --nodeps

    # 安装mysql
    yum -y install mysql-server
    systemctl enable mysqld.service
    systemctl start  mysqld.service

    if [ `yum list installed | grep mysql-community | wc -l` -ne 0 ]; then
        green "【checked】 MySQL安装成功"
        echo
        echo
        sleep 2
        mysql_status=1
    fi
    echo
    echo
    green "==============="
    green "  4.配置MySQL"
    green "==============="
    sleep 2
    originpasswd=`cat /var/log/mysqld.log | grep password | head -1 | rev  | cut -d ' ' -f 1 | rev`
    mysqlpasswd=`mkpasswd -l 18 -d 2 -c 3 -C 4 -s 5 | sed $'s/[\'\/\;\"\:\.\?\&]//g'`
cat > ~/.my.cnf <<EOT
[mysql]
user=root
password=$originpasswd
EOT
    mysql  --connect-expired-password  -e "alter user 'root'@'localhost' identified by '$mysqlpasswd';"
    systemctl restart mysqld
    sleep 5s
cat > ~/.my.cnf <<EOT
[mysql]
user=root
password=$mysqlpasswd
EOT
    mysql  --connect-expired-password  -e "create database wordpress_db;"
    echo
    green "===================="
    green " 5.配置php和php-fpm"
    green "===================="
    echo
    echo
    sleep 1
    sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 20M/;" /etc/opt/remi/php74/php.ini
    sed -i "s/pm.start_servers = 5/pm.start_servers = 3/;s/pm.min_spare_servers = 5/pm.min_spare_servers = 3/;s/pm.max_spare_servers = 35/pm.max_spare_servers = 8/;" /etc/opt/remi/php74/php-fpm.d/www.conf
    systemctl restart php74-php-fpm.service
    systemctl restart nginx.service
    green "===================="
    green "  6.安装wordpress"
    green "===================="
    echo
    echo
    sleep 1
    cd /usr/share/nginx/html
    mv /usr/share/wordpresstemp/latest-zh_CN.zip ./
    unzip latest-zh_CN.zip >/dev/null 2>&1
    mv wordpress/* ./
    #cp wp-config-sample.php wp-config.php
    wget https://raw.githubusercontent.com/atrandys/trojan/master/wp-config.php
    green "===================="
    green "  7.配置wordpress"
    green "===================="
    echo
    echo
    sleep 1
    sed -i "s/database_name_here/wordpress_db/;s/username_here/root/;s?password_here?$mysqlpasswd?;" /usr/share/nginx/html/wp-config.php
    #echo "define('FS_METHOD', "direct");" >> /usr/share/nginx/html/wp-config.php
    chown -R apache:apache /usr/share/nginx/html/
    #chmod 775 apache:apache /usr/share/nginx/html/ -Rf
    chmod -R 775 /usr/share/nginx/html/wp-content
    green "=========================================================================="
    green " WordPress服务端配置已完成，请打开浏览器访问您的域名进行前台配置"
    green " 数据库密码等信息参考文件：/usr/share/nginx/html/wp-config.php"
    green "=========================================================================="
    echo
    green "=========================================================================="
    green "Trojan已安装完成，请自行下载trojan客户端，使用以下的参数或配置文件"
    green "服务器地址：$your_domain"
    green "端口：443"
    green "trojan密码：$trojan_go_passwd"
    green "=========================================================================="
    cat /usr/local/etc/trojan-go/$your_domain.json
    green "=========================================================================="
}


function install_trojan_go(){

    # 开始进行trojan-go的安装
    green "=========================================="
    green "    开始安装 trojan-go"
    green "=========================================="
    # 安装nginx
    yum install -y nginx

    # 如存在目录则退安装
    if [ ! -d "/etc/nginx/" ]; then
        red "nginx安装有问题，请使用卸载trojan后重新安装"

        read -p "是否强制运行 ?请输入 [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Nn] ]]; then
            green "终止脚本"
            exit 1 
        fi   
    fi

    # 导入nginx配置
    cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    server {
        listen       80;
        server_name  $your_domain;
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
    }
}
EOF
    # 重启nginx
    systemctl restart nginx
    sleep 3

    #rm -rf /usr/share/nginx/html/*
    #cd /usr/share/nginx/html/
    #wget https://github.com/atrandys/trojan/raw/master/fakesite.zip >/dev/null 2>&1
    #unzip fakesite.zip >/dev/null 2>&1
    #sleep 5

    #安装证书执行文件
    curl https://get.acme.sh | sh

    #if [ ! -d "/usr/src" ]; then
    #    mkdir /usr/src
    #fi

    # 创建trojan-go目录，/usr/src/（判断目录没有则创建）
    if [ ! -d "/usr/local/bin/trojan-go" ]; then
        mkdir /usr/local/bin/trojan-go
    fi

    #创建trojan-go证书目录
    if [ ! -d " /usr/local/etc/trojan-go-cert" ]; then
        mkdir /usr/local/etc/trojan-go-cert 
        mkdir /usr/local/etc/trojan-go-cert/$your_domain
        if [ ! -d "/usr/local/etc/trojan-go-cert/$your_domain" ]; then
            red "不存在/usr/local/etc/trojan-go-cert/$your_domain目录"
            exit 1
        fi
        #curl https://get.acme.sh | sh

	#执行证书申请
        ~/.acme.sh/acme.sh  --issue  -d $your_domain  --nginx
        if test -s /root/.acme.sh/$your_domain/fullchain.cer; then
            cert_success="1"
        fi
    elif [ -f "/usr/local/etc/trojan-go-cert/$your_domain/fullchain.cer" ]; then
        cd /usr/local/etc/trojan-go-cert/$your_domain
        create_time=`stat -c %Y fullchain.cer`
        now_time=`date +%s`
        minus=$(($now_time - $create_time ))
        if [  $minus -gt 5184000 ]; then
            #curl https://get.acme.sh | sh
            ~/.acme.sh/acme.sh  --issue  -d $your_domain  --nginx
            if test -s /root/.acme.sh/$your_domain/fullchain.cer; then
                cert_success="1"
            fi
        else 
            green "检测到域名$your_domain证书存在且未超过60天，无需重新申请"
            cert_success="1"
        fi        
    else 
        mkdir /usr/local/etc/trojan-go-cert/$your_domain
        #curl https://get.acme.sh | sh
        ~/.acme.sh/acme.sh  --issue  -d $your_domain  --webroot /usr/share/nginx/html/
        if test -s /root/.acme.sh/$your_domain/fullchain.cer; then
            cert_success="1"
        fi
    fi
    
    #申请通过则添加trojan-go的反向代理
    if [ "$cert_success" == "1" ]; then
        cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    server {
        listen       127.0.0.1:80;
        server_name  $your_domain;
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
        add_header Strict-Transport-Security "max-age=31536000";
        #access_log /var/log/nginx/hostscube.log combined;
        location ~ \.php$ {
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
        location / {
        try_files \$uri \$uri/ /index.php?\$args;
        }
        
    }
    server {
        listen       0.0.0.0:80;
        server_name  $your_domain;
        return 301 https://$your_domain\$request_uri;
    }
    
}
EOF
        systemctl restart nginx
        systemctl enable nginx

	#进入trojan-go目录，并下载trojan-go
        cd /usr/local/bin/trojan-go

        #wget https://api.github.com/repos/trojan-gfw/trojan/releases/latest >/dev/null 2>&1
        #latest_version=`grep tag_name latest| awk -F '[:,"v]' '{print $6}'`
        #rm -f latest
        #green "开始下载最新版trojan amd64"
        #wget https://github.com/trojan-gfw/trojan/releases/download/v${latest_version}/trojan-${latest_version}-linux-amd64.tar.xz
        #tar xf trojan-${latest_version}-linux-amd64.tar.xz >/dev/null 2>&1
        #rm -f trojan-${latest_version}-linux-amd64.tar.xz

	green "检测trojan-go最新版本..."

	latest_version=`wget --no-check-certificate -qO- https://api.github.com/repos/p4gefau1t/trojan-go/tags | grep 'name' | cut -d\" -f4 | head -1`
	green  "检测到trojan-go最新版本：$latest_version"
        #rm -f latest
        #开始下载最新版trojan-go 2020/12/14
	green "开始下载最新版trojan-go"
        wget https://github.com/p4gefau1t/trojan-go/releases/download/${latest_version}/trojan-go-linux-amd64.zip
        unzip trojan-go-linux-amd64.zip -d /usr/local/bin/trojan-go
        rm -f trojan-go-linux-amd64.zip

        #下载trojan客户端
        #green "开始下载并处理trojan windows客户端"
        #wget https://github.com/atrandys/trojan/raw/master/trojan-cli.zip
        #wget -P /usr/src/trojan-temp https://github.com/trojan-gfw/trojan/releases/download/v${latest_version}/trojan-${latest_version}-win.zip
        #unzip trojan-cli.zip >/dev/null 2>&1
        #unzip /usr/src/trojan-temp/trojan-${latest_version}-win.zip -d /usr/src/trojan-temp/ >/dev/null 2>&1
        #mv -f /usr/src/trojan-temp/trojan/trojan.exe /usr/src/trojan-cli/
        
	
	#创建trojan-go配置目录
	if [ ! -d "/usr/local/etc/trojan-go" ]; then
            mkdir /usr/local/etc/trojan-go
        fi

	green "请设置 trojan-go 密码，建议不要出现特殊字符"
        read -p "请输入密码 :" trojan_go_passwd
        #trojan_go_passwd=$(cat /dev/urandom | head -1 | md5sum | head -c 8)
	green "trojan-go 密码：" trojan_go_passwd
        cat > /usr/local/etc/trojan-go/$your_domain.json <<-EOF
{
    "run_type": "client",
    "local_addr": "127.0.0.1",
    "local_port": 1080,
    "remote_addr": "$your_domain",
    "remote_port": 443,
    "password": [
        "$trojan_go_passwd"
    ],
    "log_level": 1,
    "ssl": {
        "verify": true,
        "verify_hostname": true,
        "cert": "",
        "cipher_tls13":"TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "sni": "",
        "alpn": [
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "curves": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": true,
        "fast_open_qlen": 20
    },
    "experimental":{
        "pipeline_num" : 10,
        "pipeline_ack_window" : 200
    }
}
EOF
         rm -rf /usr/local/etc/trojan-go/config.json
         cat > /usr/local/etc/trojan-go/config.json <<-EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$trojan_go_passwd"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/usr/local/etc/trojan-go-cert/$your_domain/fullchain.cer",
        "key": "/usr/local/etc/trojan-go-cert/$your_domain/private.key",
        "key_password": "",
        "cipher_tls13":"TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "prefer_server_cipher": true,
        "alpn": [
            "h2",
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "session_timeout": 600,
        "plain_http_response": "",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": true,
        "fast_open_qlen": 20
    },
    "experimental":{
        "pipeline_num" : 10,
        "pipeline_ack_window" : 200,
        "pipeline_proxy_icmp": true
    }
}
EOF
        #cd /usr/src/trojan-cli/
        #zip -q -r trojan-cli.zip /usr/src/trojan-cli/
        #rm -rf /usr/src/trojan-temp
        #rm -f /usr/src/trojan-cli.zip
        #trojan_path=$(cat /dev/urandom | head -1 | md5sum | head -c 16)
        #mkdir /usr/share/nginx/html/${trojan_path}
        #mv /usr/src/trojan-cli/trojan-cli.zip /usr/share/nginx/html/${trojan_path}/	
        #rm -f /usr/src/trojan-cli.zip
        cat > /etc/systemd/system/trojan-go.service <<-EOF
[Unit]
Description=trojan-go
After=network.target

[Service]
Type=simple
StandardError=journal
ExecStart=/usr/local/bin/trojan-go/trojan-go -config "/usr/local/etc/trojan-go/config.json"
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

        chmod +x /etc/systemd/system/trojan-go.service
        systemctl enable trojan-go.service
        cd /root
        ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
            --key-file   /usr/local/etc/trojan-go-cert/$your_domain/private.key \
            --fullchain-file  /usr/local/etc/trojan-go-cert/$your_domain/fullchain.cer \
            --reloadcmd  "systemctl restart trojan-go"	
    else
        red "==================================="
        red "https证书没有申请成功，本次安装失败"
        red "==================================="
    fi
}

function preinstall_check(){
    
    # 安装 net-tools socat
    green "安装 net-tools socat"
    yum -y install net-tools socat >/dev/null 2>&1
    Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
    Port443=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 443`
    if [ -n "$Port80" ]; then
        process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
        red "==========================================================="
        red "检测到80端口被占用，占用进程为：${process80}，本次安装结束"
        red "==========================================================="
        read -p "是否强制运行 ?请输入 [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Nn] ]]; then
            green "终止脚本"
            exit 1 
        fi    
    fi
    if [ -n "$Port443" ]; then
        process443=`netstat -tlpn | awk -F '[: ]+' '$5=="443"{print $9}'`
        red "============================================================="
        red "检测到443端口被占用，占用进程为：${process443}，本次安装结束"
        red "============================================================="
	read -p "是否强制运行 ?请输入 [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Nn] ]]; then
            green "终止脚本"
            exit 1 
        fi   
    fi
    if [ -f "/etc/selinux/config" ]; then
        CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
        if [ "$CHECK" == "SELINUX=enforcing" ]; then
            green "$(date +"%Y-%m-%d %H:%M:%S") - SELinux状态非disabled,关闭SELinux."
            setenforce 0
            sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
            #loggreen "SELinux is not disabled, add port 80/443 to SELinux rules."
            #loggreen "==== Install semanage"
            #logcmd "yum install -y policycoreutils-python"
            #semanage port -a -t http_port_t -p tcp 80
            #semanage port -a -t http_port_t -p tcp 443
            #semanage port -a -t http_port_t -p tcp 37212
            #semanage port -a -t http_port_t -p tcp 37213
        elif [ "$CHECK" == "SELINUX=permissive" ]; then
            green "$(date +"%Y-%m-%d %H:%M:%S") - SELinux状态非disabled,关闭SELinux."
            setenforce 0
            sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
        fi
    fi
    if [[ "$RELEASE" == "centos" ]] && [[ "$VERSION" == "7" ]]; then
        firewall_status=`systemctl status firewalld | grep "Active: active"`
        if [ -n "$firewall_status" ]; then
            green "检测到firewalld开启状态，添加放行80/443端口规则"
            firewall-cmd --zone=public --add-port=80/tcp --permanent
            firewall-cmd --zone=public --add-port=443/tcp --permanent
            firewall-cmd --reload
        fi
        if [ ! -f "nginx-release-centos-7-0.el7.ngx.noarch.rpm" ]; then
          wget -c http://nginx.org/packages/centos/7/noarch/RPMS/nginx-release-centos-7-0.el7.ngx.noarch.rpm
	fi

        rpm -Uvh nginx-release-centos-7-0.el7.ngx.noarch.rpm --force --nodeps
    else
            red "==============="
            red "当前系统不受支持"
            red "==============="
            exit
    fi

    # 安装 wget\unzip\zip\curl\tar
    green "安装 wget unzip zip curl tar"
    yum -y install  wget unzip zip curl tar >/dev/null 2>&1
    green "======================="
    blue "请输入绑定到本VPS的域名"
    green "======================="
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
        green "=========================================="
        green "    域名解析正常，开始安装trojan go + wp"
        green "=========================================="
        sleep 3s
        #install_trojan
        install_trojan_go
        install_wordpress
    else
        red "===================================="
        red "域名解析地址与本VPS IP地址不一致"
        red "若你确认解析成功你可强制脚本继续运行"
        red "===================================="
        read -p "是否强制运行 ?请输入 [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Yy] ]]; then
            green "强制继续运行脚本"
            sleep 1s
            #install_trojan
	    install_trojan_go
            install_wordpress
        else
            exit 1
        fi
    fi
}


function repair_cert(){
    systemctl stop nginx
    green "============================"
    blue "请输入绑定到本VPS的域名"
    blue "务必与之前失败使用的域名一致"
    green "============================"
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
        ~/.acme.sh/acme.sh  --issue  -d $your_domain  --standalone
        ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
            --key-file   /usr/local/etc/trojan-go-cert/$your_domain/private.key \
            --fullchain-file /usr/local/etc/trojan-go-cert/$your_domain/fullchain.cer \
            --reloadcmd  "systemctl restart trojan-go"
        if test -s /usr/local/etc/trojan-go-cert/$your_domain/fullchain.cer; then
            green "证书申请成功"
            systemctl restart trojan-go
            systemctl start nginx
        else
            red "申请证书失败"
        fi
    else
        red "================================"
        red "域名解析地址与本VPS IP地址不一致"
        red "本次安装失败，请确保域名解析正常"
        red "================================"
    fi
}

function remove_trojan_go(){
    red "=================================================="
    red "你的trojan go + wordpress数据将全部丢失！！你确定要卸载吗？"
    read -s -n1 -p "按回车键开始卸载，按ctrl+c取消"
    systemctl stop trojan-go
    systemctl disable trojan-go
    systemctl stop nginx
    systemctl disable nginx
    rm -f /etc/systemd/system/trojan-go.service
    if [ "$RELEASE" == "centos" ]; then
        yum remove -y nginx
    else
        apt-get -y autoremove nginx
        apt-get -y --purge remove nginx
        apt-get -y autoremove && apt-get -y autoclean
        find / | grep nginx | sudo xargs rm -rf
    fi
    rm -rf /usr/local/bin/trojan-go
    rm -rf /usr/local/etc/trojan-go
    rm -rf /usr/local/etc/trojan-go-cert
    rm -rf ~/.my.cnf
    rm -rf /usr/src/trojan-cli/
    rm -rf /usr/share/nginx/html/*
    rm -rf /etc/nginx/
    rm -rf /root/.acme.sh
    yum remove -y php74 php74-php-gd  php74-php-pdo php74-php-mbstring php74-php-cli php74-php-fpm php74-php-mysqlnd mysql
    rm -rf /var/lib/mysql	
    rm -rf /usr/lib64/mysql
    rm -rf /usr/share/mysql
    rm -rf /var/log/mysqld.log
    green "========================"
    green "trojan go + wordpress删除完毕"
    green "========================"
}

function update_trojan_go(){

    /usr/local/bin/trojan-go/trojan-go -version | grep 'Trojan-Go' | awk -F ":" '{print $1}' | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | sed '/^$/d'>trojan-go.tmp
    curr_version=`cat trojan-go.tmp`
    latest_version=`wget --no-check-certificate -qO- https://api.github.com/repos/p4gefau1t/trojan-go/tags | grep 'name' | cut -d\" -f4 | head -1 | sed 's/[^0-9.]*\([0-9.]*\).*/\1/'`
    green "检测到trojan-go最新版本：$latest_version"    
    #开始下载最新版trojan-go 2020/12/14
    rm -f trojan-go.tmp
    if version_lt "$curr_version" "$latest_version"; then
        green "当前版本$curr_version,最新版本$latest_version,开始升级……"
        mkdir trojan_go_update_temp && cd trojan_go_update_temp
        wget https://github.com/p4gefau1t/trojan-go/releases/download/${latest_version}/trojan-go-linux-amd64.zip
        unzip trojan-go-linux-amd64.zip

        mv .trojan-go/trojan-go /usr/local/bin/trojan-go/
        cd .. && rm -rf trojan_update_temp
        systemctl restart trojan-go
    /usr/local/bin/trojan-go/trojan-go -version | grep 'Trojan-Go' | awk -F ":" '{print $1}' | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | sed '/^$/d'>trojan-go.tmp
    green "服务端trojan升级完成，当前版本：`cat trojan-go.tmp`，客户端请在trojan github下载最新版"
    rm -f trojan-go.tmp
    else
        green "当前版本$curr_version,最新版本$latest_version,无需升级"
    fi   
}

start_menu(){
    clear
    green " ======================================="
    green " 脚本功用: 一键安装trojan go + wordpress      "
    green " 系统支持: centos7"
    green " 脚本作者: atrandys             "
    green "	修改: zzzz		   "
    red " *1. 不要在任何生产环境使用此脚本"
    red " *2. 不要占用80和443端口"
    red " *3. 若第一次使用脚本失败，请先执行卸载trojan go"
    green " ======================================="
    echo
    green " 1. 安装trojan go + wp"
    red " 2. 卸载trojan go + wp"
    green " 3. 升级trojan go"
    green " 4. 修复证书"
    blue " 0. 退出脚本"
    echo
    read -p "请输入数字 :" num
    case "$num" in
    1)
    preinstall_check
    ;;
    2)
    remove_trojan_go
    ;;
    3)
    update_trojan_go 
    ;;
    4)
    repair_cert 
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    red "请输入正确数字"
    sleep 1s
    start_menu
    ;;
    esac
}

start_menu
