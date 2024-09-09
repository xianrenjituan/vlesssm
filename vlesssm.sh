#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

dir=/home/vlesssm

[ $(id -u) != "0" ] && echo "错误！你必须要以root身份运行本脚本！" && exit 1
[ "$dir" != "$(dirname $(readlink -f "$0"))" ] && echo "请把本脚本移动到 $dir 中运行，确保本脚本的路径是 $dir/vlesssm.sh" && exit 1
cat /etc/issue | grep -q "Debian" && [ $? -eq 0 ] && is_debian=1
cat /etc/issue | grep -q "Ubuntu" && [ $? -eq 0 ] && is_debian=1
[ -z "$is_debian" ] && echo "错误！您的系统不是Debian，本脚本只适用于Debian！" && exit 1
uname -a | grep -q "x86_64" && [ $? -eq 0 ] && arch="x86_64"
uname -a | grep -q "aarch64" && [ $? -eq 0 ] && arch="aarch64"
[ -z "$arch" ] && echo "错误！您的CPU架构不受支持，本脚本只适用于amd64和arm64！" && exit 1

check_uuid() {
    local uuid=$1
    if [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        return 0
    else
        return 1
    fi
}

check_ipv4() {
    local ip=$1
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local field1=$(echo "$ip"|cut -d. -f1)
        local field2=$(echo "$ip"|cut -d. -f2)
        local field3=$(echo "$ip"|cut -d. -f3)
        local field4=$(echo "$ip"|cut -d. -f4)
        if [ $field1 -le 255 -a $field2 -le 255 -a $field3 -le 255 -a $field4 -le 255 ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

check_ipv6() {
    local ip=$1
    #if [[ "$ip" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$|^([0-9a-fA-F]{1,4}:){1,6}(:[0-9a-fA-F]{1,4})$ ]]; then
    if [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
        return 0
    else
        return 1
    fi
}

check_port_number() {
    local port=$1
    if [[ "$port" =~ ^[1-9][0-9][0-9][0-9][0-9]$ ]] && [ $port -ge 10000 -a $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

check_number() {
    local number=$1
    [[ "$number" =~ ^[0-9]+$ ]] && return 0 || return 1
}

random_60000_port() {
    [ -z "$1" ] && local ne=0 || local ne=$1
    local min=60001
    local max=65534
    local tmp=$(($max-$min+1))
    while :
    do
        local num=$(cat /dev/urandom | head -n 1 | cksum | cut -d ' ' -f 1)
        random_60000_port=$(($num%$tmp+$min))
        if [ $random_60000_port -ne $ne ]; then
            check_port_occupancy "$random_60000_port"
            [ $? -eq 0 ] && return 0
        fi
    done
}

check_port_occupancy() {
    local port=$1
    [ ! -f "/usr/bin/netstat" ] && apt install -y net-tools
    netstat -tunpl | grep -q ":$port"
    [ $? -eq 0 ] && return 1 || return 0
}

random_user_port() {
    load_config
    local count=0
    local flag=0
    while :
    do
        let count++
        [ $count -gt 99 ] && $random_60000_port=0 && return 1
        random_60000_port
        [ $random_60000_port -eq $x_port ] && continue
        cat "$dir/user" | cut -d ' ' -f 1 | grep -q $random_60000_port
        [ $? -eq 0 ] && continue
        random_user_port=$random_60000_port
        return 0
    done
}

random_user_name() {
    while :
    do
        random_user_name=$(cat /dev/urandom | head -n 1 | md5sum | head -c 5)
        check_number "$random_user_name"
        [ $? -eq 1 ] && break
    done
}

first_time_run() {
    rm -f "$dir/config_tmp"
    uuid=$(cat /proc/sys/kernel/random/uuid)
    echo "uuid=$uuid" > "$dir/config_tmp"
    echo "[初次运行配置]"
    echo ""
    echo "写给没用过类似脚本的人: "
    echo "脚本中会出现很多要求用户输入文本或者选择的情况"
    echo "例如出现: 请问要选哪个呢？[1/2]: "
    echo "代表请在数字1或者2中选择，输入选择，然后按下回车键。"
    echo "例如出现: 请问是这样吗？[Y/n]: "
    echo "输入字母Y代表 是/对/好；输入字母n代表 不是/不对/不好"
    echo "大小写不限"
    while :
    do
        read -p "请问您理解吗？[Y/n]: " understand
        if [[ "$understand" == [Yy] ]]; then
            break
        elif [[ "$understand" == [Nn] ]]; then
            echo "那就请仔细再读一次。"
        elif [ -z "$understand" ]; then
            echo "到底要选哪个呢？"
        else
            echo "非常抱歉，本脚本无法为您提供服务。" && exit 1
        fi
    done
    echo ""
    echo "请选择您这台机器的_公网_IPv4地址，例如 123.123.123.123"
    echo "如果是IPv6 only的机器，请选择IPv6地址，例如 2606:4700:4700::1111"
    echo "如果没有列出您的公网IP地址请手动输入"
    hostname_I=$(hostname -I)
    hostname_count=0
    while :
    do
        let hostname_count++
        hostname_single=$(echo -n "$hostname_I" | cut -d ' ' -f $hostname_count)
        if [ ! -z "$hostname_single" ]; then
            echo "$hostname_count) $hostname_single"
        else
            hostname_count=$(( $hostname_count - 1 ))
            break
        fi
    done
    while :
    do
        read -p "请选择或输入您这台机器的公网IP地址: " ip_address
        check_number "$ip_address"
        [ $? -eq 0 ] && [ $ip_address -le $hostname_count ] && ip_address=$(echo -n "$hostname_I" | cut -d ' ' -f $ip_address)
        check_ipv4 "$ip_address"
        [ $? -eq 0 ] && ip_type=ipv4 && break
        check_ipv6 "$ip_address"
        [ $? -eq 0 ] && ip_type=ipv6 && break
        echo "IP地址无效。"
    done
    echo "ip_address=$ip_address" >> "$dir/config_tmp"
    echo "ip_address: $ip_address"
    echo "ip_type: $ip_type"
    echo ""
    echo "使用本脚本，您需要一张_有效的IPv4证书_，该证书的IPv4_不必须_对应您的本机IP。"
    echo "如果您这台是IPv6 only的机器，甚至可以用别的IPv4机器申请的证书呢~"
    echo "您可以通过 zerossl.com 免费申请IPv4证书，申请方法请自行摸索。"
    echo ""
    if [ "$ip_type" = "ipv4" ]; then
        read -p "请问您是使用这台机器的IPv4地址申请的IP证书吗？[Y/n]: " same_ip
    else
        same_ip=n
    fi
    if [[ "$same_ip" == [Nn] ]]; then
        while :
        do
            read -p "请输入您的证书的IPv4地址(例如 123.45.67.89): " certificate_ip
            check_ipv4 "$certificate_ip"
            [ $? -eq 0 ] && break
        done
    else
        certificate_ip=$ip_address
    fi
    echo "certificate_ip=$certificate_ip" >> "$dir/config_tmp"
    echo "certificate_ip: $certificate_ip"
    echo ""
    echo "请选择导入IP证书的方式: "
    echo "1) 目前正使用SSH客户端连接，可以使用右键粘贴文件的方式导入。"
    echo "2) 我是老手/我熟悉SFTP工具的使用，希望使用SFTP工具上传证书文件。"
    while :
    do
        read -p "请选择导入IP证书的方式[1/2]: " upload_cert_method
        [ -z "$upload_cert_method" ] && upload_cert_method=2
        if [ "$upload_cert_method" = 1 ]; then
            import_certificate
            break
        elif [ "$upload_cert_method" = 2 ]; then
            echo "请使用SFTP工具把证书文件上传到 $dir 目录下。"
            echo "(只放证书文件，不要整个 $certificate_ip 目录上传)"
            echo "请确保3个文件的文件名为 certificate.crt ca_bundle.crt private.key"
            read -p "上传完成后按回车键继续" pause
            break
        fi
    done

    random_60000_port
    x_port=$random_60000_port
    echo "x_port=$x_port" >> "$dir/config_tmp"
    if [ "$ip_type" = "ipv4" ]; then
        echo "domain_strategy=4" >> "$dir/config_tmp"
    else
        echo "domain_strategy=6" >> "$dir/config_tmp"
    fi
    echo "user_uuid_mode=3" >> "$dir/config_tmp"

    rm -f "$dir/config"
    mv "$dir/config_tmp" "$dir/config"

    load_config

    if [ ! -f "$dir/user" ]; then
        touch "$dir/user"
        random_user_port
        random_user_name
        echo "$random_user_port user_$random_user_name 0" >> "$dir/user"
    fi

    check_update
    install_xray_core
    service_restart

    choose_an_option=1
    show_user_vless_config
    read -p "按回车键返回。" pause
}

import_certificate() {
    clear
    [ ! -f "/usr/bin/nano" ] && apt install -y nano
    echo ""
    echo "请在本地电脑上解压下载的证书的 $certificate_ip.zip 压缩包"
    echo "然后进入 $certificate_ip 目录"
    read -p "...按回车键继续" pause
    clear
    echo ""
    echo "请使用 记事本 或者 任何文本编辑器(例如VS Code)打开 certificate.crt"
    echo "(在文件上右键 -> 打开方式 -> 使用记事本打开)"
    echo "请复制里面的_所有_内容(Ctrl+A全选 Ctrl+C复制)"
    echo "按回车后会自动使用nano命令打开编辑一个文件的窗口"
    echo "请在那里使用鼠标右键粘贴所复制的内容，并按Ctrl+X, Y, 回车保存"
    read -p "...按回车键继续" pause
    rm -f "$dir/new_certificate.crt"
    nano "$dir/new_certificate.crt"
    if [ -f "$dir/new_certificate.crt" ]; then
        rm -f "$dir/certificate.crt"
        mv "$dir/new_certificate.crt" "$dir/certificate.crt"
    fi
    clear
    echo ""
    echo "请使用 记事本 或者 任何文本编辑器(例如VS Code)打开 ca_bundle.crt"
    echo "(在文件上右键 -> 打开方式 -> 使用记事本打开)"
    echo "请复制里面的_所有_内容(Ctrl+A全选 Ctrl+C复制)"
    echo "按回车后会自动使用nano命令打开编辑一个文件的窗口"
    echo "请在那里使用鼠标右键粘贴所复制的内容，并按Ctrl+X, Y, 回车保存"
    read -p "...按回车键继续" pause
    rm -f "$dir/new_ca_bundle.crt"
    nano "$dir/new_ca_bundle.crt"
    if [ -f "$dir/new_ca_bundle.crt" ]; then
        rm -f "$dir/ca_bundle.crt"
        mv "$dir/new_ca_bundle.crt" "$dir/ca_bundle.crt"
    fi
    clear
    echo ""
    echo "请使用 记事本 或者 任何文本编辑器(例如VS Code)打开 private.key"
    echo "(在文件上右键 -> 打开方式 -> 使用记事本打开)"
    echo "请复制里面的_所有_内容(Ctrl+A全选 Ctrl+C复制)"
    echo "按回车后会自动使用nano命令打开编辑一个文件的窗口"
    echo "请在那里使用鼠标右键粘贴所复制的内容，并按Ctrl+X, Y, 回车保存"
    read -p "...按回车键继续" pause
    rm -f "$dir/new_private.key"
    nano "$dir/new_private.key"
    if [ -f "$dir/new_private.key" ]; then
        rm -f "$dir/private.key"
        mv "$dir/new_private.key" "$dir/private.key"
    fi
}

check_update() {
    if [ ! -f "$dir/xray_core_latest_version" ] || [ $(( $(date +%s) - $(stat -c %Y "$dir/xray_core_latest_version") )) -gt 604800 ]; then
        xray_core_latest_version=$(wget -t2 -T3 -q -O- "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | sed 's/,/\n/g' | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/v//g;s/ //g')
        if [ ! -z "$xray_core_latest_version" ]; then
            echo "$xray_core_latest_version" >  "$dir/xray_core_latest_version"
        fi
    else
        xray_core_latest_version=$(cat "$dir/xray_core_latest_version")
    fi
}

check_installed() {
    unset xray_core_version && [ -f "$dir/xray" ] && xray_core_version=$("$dir/xray" --version | awk '{print $2}' | head -n 1) || xray_core_version="未安装"
    unset xray_running
    xray_pid=$(ps -ef | grep "xray" | grep -v "grep" | awk '{print $2}')
    if [ ! -z "$xray_pid" ] && [ "$(ps -p $xray_pid)" > /dev/null ]; then
        xray_running="运行中"
    else
        xray_running="未运行"
    fi
}

edit_config() {
    config_name=$1
    config_content=$2
    cat "$dir/config" | grep -q "$config_name="
    [ $? -eq 0 ] && sed -i "/$config_name=/d" "$dir/config"
    echo "$config_name=$config_content" >> "$dir/config"
    load_config
}

load_config() {
    ip_address=$(cat "$dir/config" | grep "ip_address=" | awk -F "=" '{print $NF}')

    certificate_ip=$(cat "$dir/config" | grep "certificate_ip=" | awk -F "=" '{print $NF}')
    if [ -f "$dir/certificate.crt" ] && [ -f "$dir/ca_bundle.crt" ] && [ -f "$dir/private.key" ]; then
        certificate_uploaded="证书文件已上传"
    else
        certificate_uploaded="错误: 证书文件未上传"
    fi

    x_port=$(cat "$dir/config" | grep "x_port=" | awk -F "=" '{print $NF}')

    unset ip_type
    check_ipv4 "$ip_address"
    [ $? -eq 0 ] && ip_type=ipv4 && ip_port="$ip_address:$x_port"
    check_ipv6 "$ip_address"
    [ $? -eq 0 ] && ip_type=ipv6 && ip_port="[$ip_address]:$x_port"
    [ -z "$ip_type" ] && echo "错误！在配置文件中的ip_address不是有效的IPv4或IPv6地址！" && exit 1

    domain_strategy=$(cat "$dir/config" | grep "domain_strategy=" | awk -F "=" '{print $NF}')

    uuid=$(cat "$dir/config" | grep "uuid=" | awk -F "=" '{print $NF}')
    user_uuid_mode=$(cat "$dir/config" | grep "user_uuid_mode=" | awk -F "=" '{print $NF}')

    path_before_hash=$(cat "$dir/config" | grep "path_before_hash=" | awk -F "=" '{print $NF}')
    path_after_hash=$(cat "$dir/config" | grep "path_after_hash=" | awk -F "=" '{print $NF}')

    m_traffic_unit=$(cat "$dir/config" | grep "m_traffic_unit" | awk -F "=" '{print $NF}')
    [ "$m_traffic_unit" != "bytes" ] && [ "$m_traffic_unit" != "gb" ] && m_traffic_unit="mb"
}

load_user_from_line() {
    if [ $2 -ge 1 ]; then
        unset user_port
        unset user_name
        unset user_traffic_limit
        user_port=$(echo -n "$1" | cut -d ' ' -f 1)
        user_name=$(echo -n "$1" | cut -d ' ' -f 2)
        user_traffic_limit=$(echo -n "$1" | cut -d ' ' -f 3)
        user_hash=$(echo -n "$user_port$user_name" | md5sum | cut -d ' ' -f 1)

        if [ "$user_uuid_mode" = "1" ]; then
            user_uuid=$uuid
        elif [ "$user_uuid_mode" = "2" ]; then
            user_uuid=$(echo -n "${user_hash:0:8}-${user_hash:8:4}-${user_hash:12:4}-${user_hash:16:4}-${user_hash:20:12}")
        elif [ "$user_uuid_mode" = "3" ]; then
            user_hash_2=$(echo -n "$user_name$user_port" | md5sum | cut -d ' ' -f 1)
            user_uuid=$(echo -n "${user_hash:0:8}-${user_hash_2:8:4}-${user_hash_2:12:4}-${user_hash_2:16:4}-${user_hash_2:20:12}")
        else
            user_uuid="00000000-0000-0000-0000-000000000000"
        fi

        user_path=/$user_hash
        [ ! -z "$path_before_hash" ] && user_path=/$path_before_hash$user_path
        [ ! -z "$path_after_hash" ] && user_path=$user_path/$path_after_hash

        [ "$ip_type" = "ipv4" ] && user_ip_port="$ip_address:$user_port"
        [ "$ip_type" = "ipv6" ] && user_ip_port="[$ip_address]:$user_port"
    fi
    if [ $2 -ge 2 ]; then
        [ ! -d "$dir/user_traffic" ] && mkdir "$dir/user_traffic"
        [ ! -f "$dir/user_traffic/$user_port" ] && echo "0" > "$dir/user_traffic/$user_port"
        unset user_traffic_in_bytes
        unset user_traffic_in_mb
        unset user_traffic_in_gb
        user_traffic_in_bytes=$(cat "$dir/user_traffic/$user_port")
        [ "$user_traffic_in_bytes" = "" ] && user_traffic_in_bytes="0"
        user_traffic_in_mb=$(( $user_traffic_in_bytes / 1048576 ))
        user_traffic_in_gb=$(( $user_traffic_in_bytes / 1073741824 ))
    fi
    if [ $2 -ge 3 ]; then
        unset user_traffic_last_month_in_bytes
        unset user_traffic_last_month_in_mb
        unset user_traffic_last_month_in_gb
        [ -f "$dir/user_traffic/${user_port}_last_month" ] && user_traffic_last_month_in_bytes=$(cat "$dir/user_traffic/${user_port}_last_month") || user_traffic_last_month_in_bytes=0
        [ "$user_traffic_last_month_in_bytes" = "" ] && user_traffic_last_month_in_bytes="0"
        user_traffic_last_month_in_mb=$(( $user_traffic_last_month_in_bytes / 1048576 ))
        user_traffic_last_month_in_gb=$(( $user_traffic_last_month_in_bytes / 1073741824 ))
    fi
}

install_xray_core() {
    if [ -z "$xray_core_latest_version" ]; then
        echo "Xray-core 安装/更新失败。原因: 最新版本号获取失败。"
    elif [ "$xray_core_latest_version" = "$xray_core_version" ]; then
        echo "Xray-core 已安装，无更新，跳过。"
    else
        echo "正在安装 Xray-core..."
        [ "$arch" = "x86_64" ] && file_name="Xray-linux-64.zip"
        [ "$arch" = "aarch64" ] && file_name="Xray-linux-arm64-v8a.zip"
        wget -t2 -T3 -q -O "$dir/$file_name" "https://github.com/XTLS/Xray-core/releases/download/v$xray_core_latest_version/$file_name"
        [ ! -f "$dir/$file_name" ] && echo "Download Error! $dir/$file_name Not Found!" && exit 1
        rm -f "$dir/geoip.dat" "$dir/geosite.dat" "$dir/LICENSE" "$dir/README.md" "$dir/xray"
        [ ! -f "/usr/bin/unzip" ] && apt install -y unzip
        unzip "$dir/$file_name" -d "$dir"
        rm -f "$dir/$file_name"
        [ ! -f "$dir/xray" ] && echo "Download Error! $dir/xray Not Found!" && exit 1
        chmod +x "$dir/xray"
        rm -f "$dir/LICENSE" "$dir/README.md"
        echo "Xray-core 安装/更新成功。"
    fi
}

generate_xray_conf() {
    load_config

    if [ ! -f "$dir/certificate.crt" ] || [ ! -f "$dir/ca_bundle.crt" ] || [ ! -f "$dir/private.key" ]; then
        echo "错误！证书文件不存在！" && exit 1
    fi
    #if [ ! -f "$dir/fullchain.crt" ] || [ $(stat -c %Y "$dir/certificate.crt") -gt $(stat -c %Y "$dir/fullchain.crt") ]; then
        cat "$dir/certificate.crt" "$dir/ca_bundle.crt" > "$dir/fullchain.crt"
    #fi

    cat > "$dir/tmp_vlesssm_xray_config.json" << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": $x_port,
            "protocol": "vless",
            "settings": {
                "clients": [
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": 80
                    }
EOF
    while read line
    do
        load_user_from_line "$line" 2
        if [ "$user_traffic_limit" = "0" ] || [ "$user_traffic_limit" -gt "$user_traffic_in_gb" ]; then
            sed -i '$d' "$dir/tmp_vlesssm_xray_config.json"
            echo "                    }," >> "$dir/tmp_vlesssm_xray_config.json"
            cat >> "$dir/tmp_vlesssm_xray_config.json" << EOF
                    {
                        "path": "$user_path",
                        "dest": $user_port,
                        "xver": 1
                    }
EOF
        fi
    done < "$dir/user"
    cat >> "$dir/tmp_vlesssm_xray_config.json" << EOF
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "tls",
                "tlsSettings": {
                    "alpn": [
                        "http/1.1"
                    ],
                    "certificates": [
                        {
                            "certificateFile": "$dir/fullchain.crt",
                            "keyFile": "$dir/private.key"
                        }
                    ]
                }
            }
        }
EOF
    while read line
    do
        load_user_from_line "$line" 2
        if [ "$user_traffic_limit" = "0" ] || [ "$user_traffic_limit" -gt "$user_traffic_in_gb" ]; then
            sed -i '$d' "$dir/tmp_vlesssm_xray_config.json"
            echo "        }," >> "$dir/tmp_vlesssm_xray_config.json"
            cat >> "$dir/tmp_vlesssm_xray_config.json" << EOF
        {
            "port": $user_port,
            "listen": "127.0.0.1",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$user_uuid",
                        "level": 0
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                    "acceptProxyProtocol": true,
                    "path": "$user_path"
                }
            }
        },
        {
            "port": $user_port,
            "listen": "0.0.0.0",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$user_uuid",
                        "level": 0
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "splithttp",
                "splithttpSettings": {
                    "path": "$user_path",
                    "host": "$certificate_ip"
                },
                "security": "tls",
                "tlsSettings": {
                    "alpn": [
                        "h3"
                    ],
                    "minVersion": "1.3",
                    "certificates": [
                        {
                            "certificateFile": "$dir/fullchain.crt",
                            "keyFile": "$dir/private.key"
                        }
                    ]
                }
            }
        }
EOF
        fi
    done < "$dir/user"
    cat >> "$dir/tmp_vlesssm_xray_config.json" << EOF
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {
EOF
    if [ "$domain_strategy" = "4" ]; then
        echo "                \"domainStrategy\": \"UseIPv4\"" >> "$dir/tmp_vlesssm_xray_config.json"
    elif [ "$domain_strategy" = "6" ]; then
        echo "                \"domainStrategy\": \"UseIPv6\"" >> "$dir/tmp_vlesssm_xray_config.json"
    fi
    cat >> "$dir/tmp_vlesssm_xray_config.json" << EOF
            }
        }
    ]
}
EOF

    file1="$dir/vlesssm_xray_config.json"
    file2="$dir/tmp_vlesssm_xray_config.json"
    if [ -f "$file1" ] && [ -f "$file2" ]; then
        diff "$file1" "$file2" > /dev/null
        if [ $? != 0 ]; then
            rm -f "$file1"
            mv "$file2" "$file1"
            [ "$xray_running" = "运行中" ] && service_restart
        else
            rm -f "$file2"
        fi
    else
        mv "$file2" "$file1"
        [ "$xray_running" = "运行中" ] && service_restart
    fi
}

service_restart() {
    if [ ! -f "/etc/systemd/system/vlesssm_xray.service" ]; then
        cat > "/etc/systemd/system/vlesssm_xray.service" << EOF
[Unit]
Description=VLESS Server Manager
After=network.target

[Service]
ExecStart=$dir/xray run -c $dir/vlesssm_xray_config.json

Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi
    [ ! -f "/etc/systemd/system/multi-user.target.wants/vlesssm_xray.service" ] && systemctl enable vlesssm_xray

    generate_xray_conf

    systemctl restart vlesssm_xray

    [ ! -f "/usr/sbin/iptables" ] && apt install -y iptables
    while read line
    do
        user_port=$(echo -n "$line" | cut -d ' ' -f 1)
        add_traffic "$user_port"
    done < "$dir/user"

    crontab -l | grep -q "bash $dir/vlesssm.sh cron"
    [ $? -eq 1 ] && (crontab -l ; echo "*/5 * * * * bash $dir/vlesssm.sh cron") | crontab -
    crontab -l | grep -q "bash $dir/vlesssm.sh monthly_cron"
    [ $? -eq 1 ] && (crontab -l ; echo "1 0 1 * * bash $dir/vlesssm.sh monthly_cron") | crontab -
}

service_stop() {
    systemctl stop vlesssm_xray

    while read line
    do
        user_port=$(echo -n "$line" | cut -d ' ' -f 1)
        add_traffic "$user_port"
        delete_port_from_iptables "$user_port"
    done < "$dir/user"
}

add_port_to_iptables() {
    iptables -A INPUT -p tcp --dport $1 > /dev/null 2>&1
    iptables -A OUTPUT -p tcp --sport $1 > /dev/null 2>&1
    iptables -A INPUT -p udp --dport $1 > /dev/null 2>&1
    iptables -A OUTPUT -p udp --sport $1 > /dev/null 2>&1
}

delete_port_from_iptables() {
    iptables -D INPUT -p tcp --dport $1 > /dev/null 2>&1
    iptables -D OUTPUT -p tcp --sport $1 > /dev/null 2>&1
    iptables -D INPUT -p udp --dport $1 > /dev/null 2>&1
    iptables -D OUTPUT -p udp --sport $1 > /dev/null 2>&1
    # 执行2次以排除潜在BUG
    iptables -D INPUT -p tcp --dport $1 > /dev/null 2>&1
    iptables -D OUTPUT -p tcp --sport $1 > /dev/null 2>&1
    iptables -D INPUT -p udp --dport $1 > /dev/null 2>&1
    iptables -D OUTPUT -p udp --sport $1 > /dev/null 2>&1
}

add_traffic() {
    [ ! -d "$dir/user_traffic" ] && mkdir "$dir/user_traffic"
    if [ -f "$dir/user_traffic/$1" ]; then
        previous_traffic=$(cat "$dir/user_traffic/$1")
        [ "$previous_traffic" = "" ] && previous_traffic="0"
    else
        previous_traffic="0"
    fi

    new_tcp_input_traffic=$(iptables -nvx -L INPUT | grep "tcp dpt:$1" | awk '{print $2}')
    new_tcp_output_traffic=$(iptables -nvx -L OUTPUT | grep "tcp spt:$1" | awk '{print $2}')
    new_udp_input_traffic=$(iptables -nvx -L INPUT | grep "udp dpt:$1" | awk '{print $2}')
    new_udp_output_traffic=$(iptables -nvx -L OUTPUT | grep "udp spt:$1" | awk '{print $2}')
    delete_port_from_iptables "$1"
    add_port_to_iptables "$1"
    check_number "$new_tcp_input_traffic"
    [ $? -ne 0 ] && new_tcp_input_traffic=0
    check_number "$new_tcp_output_traffic"
    [ $? -ne 0 ] && new_tcp_output_traffic=0
    check_number "$new_udp_input_traffic"
    [ $? -ne 0 ] && new_udp_input_traffic=0
    check_number "$new_udp_output_traffic"
    [ $? -ne 0 ] && new_udp_output_traffic=0

    total_traffic=$(( $previous_traffic + $new_tcp_input_traffic + $new_tcp_output_traffic + $new_udp_input_traffic + $new_udp_output_traffic ))

    echo "$total_traffic" > "$dir/user_traffic/$1"
}

add_user() {
    echo "$add_user_port $add_user_name $add_user_traffic_limit" >> "$dir/user"
    add_port_to_iptables "$add_user_port"
}

delete_user() {
    line=$( cat "$dir/user" | sed -n ${choose_an_option}p )
    [ -z "$line" ] && return
    user_port=$(echo -n "$line" | cut -d ' ' -f 1)
    sed -i "${choose_an_option}d" "$dir/user"
    delete_port_from_iptables "$user_port"
    rm -f "$dir/user_traffic/$user_port"
    rm -f "$dir/user_traffic/${user_port}_last_month"
}

edit_user() {
    line=$( cat "$dir/user" | sed -n ${choose_an_option}p )
    [ -z "$line" ] && return
    load_user_from_line "$line" 1
    echo "正在编辑用户端口: $user_port (端口无法修改)"
    echo "警告: 修改用户名会影响用户VLESS配置，修改后需重新获取配置。"
    read -p "用户名(英数字)，留空则不更改: " edit_user_name
    [ -z "$edit_user_name" ] && edit_user_name=$user_name
    edit_user_name=$(echo -n "$edit_user_name" | sed s/\ //g)
    while :
    do
        read -p "用户月流量限制(GB为单位整数)，留空则不更改: " edit_user_traffic_limit
        [ -z "$edit_user_traffic_limit" ] && edit_user_traffic_limit=$user_traffic_limit
        check_number "$edit_user_traffic_limit"
        [ $? -eq 0 ] && break
    done
    sed -i "${choose_an_option}a $user_port $edit_user_name $edit_user_traffic_limit" "$dir/user"
    sed -i "${choose_an_option}d" "$dir/user"
}

show_user_vless_config() {
    load_config
    line=$( cat "$dir/user" | sed -n ${choose_an_option}p )
    [ -z "$line" ] && return
    load_user_from_line "$line" 1
    vless_link_generator
    vless_h3_link_generator

    output="服务器
    地址(address) $ip_address
    端口(port) $x_port
    用户ID(id) $user_uuid
    加密方式(encrypiton) none
    底层传输方式(transport)
    传输协议(network) ws
    伪装类型(type) none
    伪装域名(host) $certificate_ip
    路径(path) $user_path%3Fed%3D2560
    传输层安全(TLS) tls
    SNI $certificate_ip
    Alpn http/1.1
    跳过证书验证(allowInsecure) false
"
    [ ! -f "/usr/bin/column" ] && apt install -y bsdmainutils
    echo "$output" | column -t
    echo ""
    echo "$vless_link#vlesssm-$user_port"
    echo ""
    echo "$vless_h3_link#vlesssm-$user_port%20%28SplitHTTP%20%2B%20HTTP%2F3%29"
    echo ""
    echo "以上是用户 $user_port:$user_name 的配置信息"
    echo "您可以通过使用网页浏览器访问以下地址来检测该用户是否可以正常连接: "
    echo "https://$ip_port$user_path"
    echo "如果出现纯文本\"Bad Request\"即正常，出现其他情况就不正常。"
    if [ "$ip_address" != "$certificate_ip" ]; then
        echo "注: 由于您的证书IP地址非本机IP地址，提示不安全/证书无效是正常的。点继续前往即可。"
    fi
}

vless_link_generator() {
    vless_link="vless://$user_uuid@$ip_port?encryption=none&type=ws&host=$certificate_ip&path=$user_path%3Fed%3D2560&security=tls&sni=$certificate_ip&alpn=http%2F1.1"
}

vless_h3_link_generator() {
    vless_h3_link="vless://$user_uuid@$user_ip_port?encryption=none&type=splithttp&host=$certificate_ip&path=$user_path&security=tls&sni=$certificate_ip&alpn=h3"
}

main_do_option() {
    case "$1" in
        1)
            service_restart
            read -p "按回车键返回。" pause
            ;;
        2)
            service_stop
            ;;
        3)
            systemctl status vlesssm_xray
            ;;
        4)
            download_client_ui
            ;;
        5)
            user_manager_ui
            ;;
        6)
            install_xray_core
            read -p "按回车键返回。" pause
            ;;
        7)
            import_certificate
            ;;
        8)
            edit_config_ui
            ;;
        9)
            [ -f "/etc/systemd/system/multi-user.target.wants/vlesssm_xray.service" ] && systemctl disable vlesssm_xray
            if [ -f "/etc/systemd/system/vlesssm_xray.service" ]; then
                systemctl stop vlesssm_xray
                rm -f "/etc/systemd/system/vlesssm_xray.service"
            fi

            crontab -l > "$dir/crontab_tmp"
            sed -i "/\/vlesssm.sh cron/d" "$dir/crontab_tmp"
            sed -i "/\/vlesssm.sh monthly_cron/d" "$dir/crontab_tmp"
            crontab "$dir/crontab_tmp"
            rm -f "$dir/crontab_tmp"

            echo "清理完毕，现在您可以执行 rm -rf \"$dir\" 完全删除本脚本文件夹啦！"
            exit 0
    esac
}

user_manager_do_option() {
    case "$1" in
        a)
            echo "+----------+" &&
            echo "| 新增用户 |" &&
            echo "+----------+"

            unset add_user_port
            unset add_user_name
            unset add_user_traffic_limit

            random_user_port
            echo "请输入一个_未被使用_的5位数高位端口用于该用户的流量监控"
            while :
            do
                read -p "用户端口[10000-65535]，直接回车随机$random_user_port: " add_user_port
                [ -z "$add_user_port" ] && add_user_port=$random_user_port
                [ "$add_user_port" = "0" ] && return
                check_port_number "$add_user_port"
                [ $? -eq 1 ] && echo "请输入10000-65535范围内的端口" && continue
                if [ $add_user_port -eq $x_port ]; then
                    echo "端口不可与x_port相同" && continue
                fi
                cat "$dir/user" | cut -d ' ' -f 1 | grep -q $add_user_port
                [ $? -eq 0 ] && echo "端口不可与其他用户端口相同" && continue
                check_port_occupancy "$add_user_port"
                [ $? -eq 1 ] && echo "该端口已被占用" && continue
                break
            done
            random_user_name
            echo "请输入用户名，仅限英数字"
            read -p "用户名(英数字)，直接回车默认user_$random_user_name: " add_user_name
            [ -z "$add_user_name" ] && add_user_name=user_$random_user_name
            add_user_name=$(echo -n "$add_user_name" | sed s/\ //g)
            echo "请输入该用户月流量限制，每月1号重置，GB为单位，整数，输入0或者留空为不限制"
            while :
            do
                read -p "用户月流量限制(GB为单位整数): " add_user_traffic_limit
                [ -z "$add_user_traffic_limit" ] && add_user_traffic_limit=0
                check_number "$add_user_traffic_limit"
                [ $? -eq 0 ] && break
            done
            add_user
            ;;
        d)
            while :
            do
                echo "+----------+" &&
                echo "| 删除用户 |" &&
                echo "+----------+"

                list_user
                echo "0) 返回上一级"
                unset choose_an_option
                while :
                do
                    read -p "选择删除一个用户(数字): " choose_an_option
                    [ -z "$choose_an_option" ] && continue
                    check_number "$choose_an_option"
                    [ $? -eq 0 -a "$choose_an_option" -le "$count" ] && break
                done
                [ "$choose_an_option" = "0" ] && break
                delete_user
            done
            ;;
        e)
            while :
            do
                echo "+----------+" &&
                echo "| 编辑用户 |" &&
                echo "+----------+"

                echo "警告: 修改用户名会影响用户VLESS配置，修改后需重新获取配置。"
                list_user
                echo "0) 返回上一级"
                unset choose_an_option
                while :
                do
                    read -p "选择编辑一个用户(数字): " choose_an_option
                    [ -z "$choose_an_option" ] && continue
                    check_number "$choose_an_option"
                    [ $? -eq 0 -a "$choose_an_option" -le "$count" ] && break
                done
                [ "$choose_an_option" = "0" ] && break
                edit_user
            done
            ;;
        z)
            edit_config "m_traffic_unit" "bytes"
            ;;
        x)
            edit_config "m_traffic_unit" "mb"
            ;;
        c)
            edit_config "m_traffic_unit" "gb"
            ;;
        *)
            clear
            echo "+-----------+" &&
            echo "| VLESS配置 |" &&
            echo "+-----------+"
            show_user_vless_config
            read -p "按回车键返回。" pause
            ;;
    esac
}

main_ui() {
    check_update
    while :
    do
        load_config
        check_installed

        echo "+----------+" &&
        echo "|  主菜单  |" &&
        echo "+----------+"

        if [ "$ip_address" = "$certificate_ip" ]; then
            echo "IP $ip_address $certificate_uploaded"
        else
            echo "本机IP $ip_address 证书IP $certificate_ip $certificate_uploaded"
        fi

        output="Xray Core|$xray_core_version|$xray_running"
        if [ "$xray_core_version" = "$xray_core_latest_version" ]; then
            output="$output|已是最新版本"
        else
            output="$output|检测到更新: $xray_core_latest"
        fi

        [ ! -f "/usr/bin/column" ] && apt install -y bsdmainutils
        echo "$output" | column -t -s "|"

        echo "请问您今天要来点兔子吗？"
        if [ "$xray_core_version" != "未安装" ]; then
            if [ "$xray_running" = "未运行" ]; then
                echo "1) 启动 Xray"
            elif [ "$xray_running" = "运行中" ]; then
                echo "1) 重新生成 Xray 配置并重启 Xray"
                echo "2) 停止 Xray"
            fi
            if [ -f "/etc/systemd/system/vlesssm_xray.service" ]; then
                echo "3) 查看 Xray 日志 (按q返回)"
                echo "4) 下载适配的客户端"
                echo "5) 用户管理 (添加/删除用户/获取VLESS配置链接)"
            fi
        fi
        if [ "$xray_core_version" = "未安装" ]; then
            echo "6) 安装 Xray Core"
        elif [ "$xray_core_version" != "$xray_core_latest_version" ]; then
            echo "6) 更新 Xray Core"
        fi
        echo "7) 导入新的IP证书"
        echo "8) 查看/编辑脚本配置"
        echo "9) 完全停止 并且打算移除本脚本"
        echo "0) 退出脚本。"

        unset choose_an_option
        while :
        do
            read -p "选择一个选项: " choose_an_option
            [ -z "$choose_an_option" ] && continue
            check_number "$choose_an_option"
            [ $? -eq 1 ] && continue
            if [ "$xray_core_version" = "未安装" ]; then
                [ "$choose_an_option" -ge 1 -a "$choose_an_option" -le 5 ] && continue
            fi
            [ "$choose_an_option" -le 9 ] && break
        done
        [ "$choose_an_option" = "0" ] && break
        main_do_option "$choose_an_option"
    done
}

list_user() {
    count=0
    output=" /用户端口/用户名/流量限制(GB)/已使用流量/上个月使用流量"
    while read line
    do
        let count++
        load_user_from_line "$line" 3
        if [ $m_traffic_unit = "bytes" ]; then
            output="$output
$count)/$user_port/$user_name/$user_traffic_limit/$user_traffic_in_bytes bytes/$user_traffic_last_month_in_bytes bytes"
        elif [ $m_traffic_unit = "gb" ]; then
            output="$output
$count)/$user_port/$user_name/$user_traffic_limit/$user_traffic_in_gb GB/$user_traffic_last_month_in_gb GB"
        else
            output="$output
$count)/$user_port/$user_name/$user_traffic_limit/$user_traffic_in_mb MB/$user_traffic_last_month_in_mb MB"
        fi
    done < "$dir/user"
    [ ! -f "/usr/bin/column" ] && apt install -y bsdmainutils
    echo "$output" | column -t -s "/"
}

user_manager_ui() {
    while :
    do
        echo "+----------+" &&
        echo "| 用户管理 |" &&
        echo "+----------+"

        echo "提示: 选择一个用户查看该用户的VLESS配置。"
        echo "提示: 新增/删除用户后请返回主菜单选择_1_重启服务使其立即生效。"
        list_user
        echo "a) 新增用户"
        echo "d) 删除用户"
        echo "e) 编辑用户"
        echo "z) 切换以bytes显示流量"
        echo "x) 切换以MB显示流量"
        echo "c) 切换以GB显示流量"
        echo "0) 返回上一级"
        unset choose_an_option
        while :
        do
            read -p "选择一个选项: " choose_an_option
            [ -z "$choose_an_option" ] && continue
            [ "$choose_an_option" = "a" ] || [ "$choose_an_option" = "d" ] || [ "$choose_an_option" = "e" ] && break
            [ "$choose_an_option" = "z" ] || [ "$choose_an_option" = "x" ] || [ "$choose_an_option" = "c" ] && break
            check_number "$choose_an_option"
            [ $? -eq 0 -a "$choose_an_option" -le "$count" ] && break
        done
        [ "$choose_an_option" = "0" ] && break
        user_manager_do_option "$choose_an_option"
    done
}

download_client_ui() {
    echo "+----------+" &&
    echo "|下载客户端|" &&
    echo "+----------+"

    echo "Windows: v2rayN https://github.com/2dust/v2rayN"
    echo "macOS: V2rayU https://github.com/yanue/V2rayU"
    echo "Android: v2rayNG https://github.com/2dust/v2rayNG"
    echo "iOS: Shadowrocket https://apps.apple.com/app/shadowrocket/id932747118"
    read -p "按回车键返回。" pause
}

edit_config_ui() {
    while :
    do
        echo "+----------+" &&
        echo "| 编辑配置 |" &&
        echo "+----------+"

        if [ "$domain_strategy" = "4" ]; then
            domain_strategy_text="IPv4优先"
        elif [ "$domain_strategy" = "6" ]; then
            domain_strategy_text="IPv6优先"
        else
            domain_strategy_text="不指定"
        fi

        if [ "$user_uuid_mode" = "1" ]; then
            user_uuid_mode_text="统一"
        elif [ "$user_uuid_mode" = "2" ]; then
            user_uuid_mode_text="简单"
        elif [ "$user_uuid_mode" = "3" ]; then
            user_uuid_mode_text="复杂"
        else
            user_uuid_mode_text="全0"
        fi

        output="1) 本机IP地址: $ip_address
        2) 证书IP地址: $certificate_ip
        3) VLESS端口: $x_port
        4) 流量出口IPv4/v6优先: $domain_strategy_text
        5) 用户UUID模式: $user_uuid_mode_text
        6) 统一UUID(只在模式为统一时有用): $uuid
        7) hash前额外路径: $path_before_hash
        8) hash后额外路径: $path_after_hash"
        [ ! -f "/usr/bin/column" ] && apt install -y bsdmainutils
        echo "$output" | column -t
        echo "9) 手动编辑脚本配置文件"
        echo "0) 返回上一级"

        unset choose_an_option
        while :
        do
            read -p "选择一个选项: " choose_an_option
            [ -z "$choose_an_option" ] && continue
            check_number "$choose_an_option"
            [ $? -eq 0 -a "$choose_an_option" -le 9 ] && break
        done
        [ "$choose_an_option" = "0" ] && break
        edit_config_do_option "$choose_an_option"
    done
}

edit_config_do_option() {
    case "$1" in
        1)
            echo "正在修改 本机IP地址"
            while :
            do
                read -p "请输入您这台机器的公网IP地址: " edit_ip_address
                [ -z "$edit_ip_address" ] && break
                check_ipv4 "$edit_ip_address"
                [ $? -eq 0 ] && break
                check_ipv6 "$edit_ip_address"
                [ $? -eq 0 ] && break
                echo "IP地址无效。"
            done
            if [ ! -z "$edit_ip_address" ]; then
                edit_config "ip_address" "$edit_ip_address"
                echo "ip_address=$ip_address"
                echo "已修改 本机IP地址: $ip_address"
                echo "返回主菜单选_1_重启服务后生效。"
                echo "注意！您需要重新获取用户配置才能连接。"
                read -p "按回车键返回。" pause
            fi
            ;;
        2)
            echo "正在修改 证书IP地址"
            while :
            do
                read -p "请输入证书IP地址: " edit_certificate_ip
                [ -z "$edit_certificate_ip" ] && break
                check_ipv4 "$edit_certificate_ip"
                [ $? -eq 0 ] && break
                echo "IP地址无效。"
            done
            if [ ! -z "$edit_certificate_ip" ]; then
                edit_config "certificate_ip" "$edit_certificate_ip"
                echo "certificate_ip=$certificate_ip"
                echo "已修改 证书IP地址: $certificate_ip"
                echo "返回主菜单选_1_重启服务后生效。"
                echo "注意！您需要重新获取用户配置才能连接。"
                read -p "按回车键返回。" pause
            fi
            ;;
        3)
            echo "正在修改 VLESS端口"
            while :
            do
                read -p "请输入一个_未被使用_的5位数高位端口[10000-65535]: " edit_x_port
                [ -z "$edit_x_port" ] && break
                check_port_number "$edit_x_port"
                [ $? -eq 1 ] && continue
                cat "$dir/user" | cut -d ' ' -f 1 | grep -q $edit_x_port
                [ $? -eq 0 ] && echo "端口不可与其他用户端口相同" && continue
                check_port_occupancy "$edit_x_port"
                [ $? -eq 1 ] && echo "该端口已被占用" && continue
                break
            done
            if [ ! -z "$edit_x_port" ]; then
                edit_config "x_port" "$edit_x_port"
                echo "x_port=$x_port"
                echo "已修改 VLESS端口: $x_port"
                echo "返回主菜单选_1_重启服务后生效。"
                echo "注意！您需要重新获取用户配置才能连接。"
                read -p "按回车键返回。" pause
            fi
            ;;
        4)
            echo "正在修改 流量出口IPv4/v6优先"
            echo "1) IPv4优先"
            echo "2) IPv6优先"
            echo "0) 不指定 (依照系统配置)"
            while :
            do
                read -p "IPv4/v6优先: " edit_domain_strategy
                [ -z "$edit_domain_strategy" ] && edit_domain_strategy="0"
                if [ "$edit_domain_strategy" = "0" ]; then
                    edit_config "domain_strategy" "0"
                    echo "domain_strategy=$domain_strategy"
                    echo "已切换 不指定IPv4/6优先"
                    break
                elif [ "$edit_domain_strategy" = "1" ]; then
                    edit_config "domain_strategy" "4"
                    echo "domain_strategy=$domain_strategy"
                    echo "已切换 IPv4优先"
                    break
                elif [ "$edit_domain_strategy" = "2" ]; then
                    edit_config "domain_strategy" "6"
                    echo "domain_strategy=$domain_strategy"
                    echo "已切换 IPv6优先"
                    break
                fi
            done
            echo "返回主菜单选_1_重启服务后生效。"
            read -p "按回车键返回。" pause
            ;;
        5)
            echo "正在修改 用户UUID模式"
            echo "1) 统一: 所有用户使用相同的UUID"
            echo "2) 简单: 用户UUID与其用户hash一致"
            echo "3) 复杂: 用户UUID只有前8位与其用户hash一致"
            echo "0) 全0 (不推荐)"
            while :
            do
                read -p "用户UUID模式: " edit_user_uuid_mode
                [ -z "$edit_user_uuid_mode" ] && break
                if [ "$edit_user_uuid_mode" = "0" ]; then
                    edit_config "user_uuid_mode" "0"
                    echo "user_uuid_mode=$user_uuid_mode"
                    echo "已切换 用户UUID模式: 全0"
                    break
                elif [ "$edit_user_uuid_mode" = "1" ]; then
                    edit_config "user_uuid_mode" "1"
                    echo "user_uuid_mode=$user_uuid_mode"
                    echo "已切换 用户UUID模式: 统一"
                    break
                elif [ "$edit_user_uuid_mode" = "2" ]; then
                    edit_config "user_uuid_mode" "2"
                    echo "user_uuid_mode=$user_uuid_mode"
                    echo "已切换 用户UUID模式: 简单"
                    break
                elif [ "$edit_user_uuid_mode" = "3" ]; then
                    edit_config "user_uuid_mode" "3"
                    echo "user_uuid_mode=$user_uuid_mode"
                    echo "已切换 用户UUID模式: 复杂"
                    break
                else
                    continue
                fi
                echo "返回主菜单选_1_重启服务后生效。"
                echo "注意！您需要重新获取用户配置才能连接。"
                read -p "按回车键返回。" pause
            done
            ;;
        6)
            if [ "$user_uuid_mode" != "1" ]; then
                echo "错误: 此设置项只在用户UUID模式为统一时有效。"
                read -p "按回车键返回。" pause
            else
                echo "正在修改 统一UUID"
                while :
                do
                    read -p "统一UUID: " edit_uuid
                    edit_uuid=${edit_uuid,,}
                    [ -z "$edit_uuid" ] && break
                    check_uuid "$edit_uuid"
                    [ $? -eq 0 ] && break
                    echo "UUID地址无效。"
                done
                if [ ! -z "$edit_uuid" ]; then
                    edit_config "uuid" "$edit_uuid"
                    echo "uuid=$uuid"
                    echo "已修改 统一UUID: $uuid"
                    echo "返回主菜单选_1_重启服务后生效。"
                    echo "注意！您需要重新获取用户配置才能连接。"
                    read -p "按回车键返回。" pause
                fi
            fi
            ;;
        7)
            if [ -z "$path_before_hash" ]; then
                echo "开启后path将会变成 /hash前额外路径/用户hash"
                read -p "请输入hash前额外路径: " edit_path_before_hash
                edit_path_before_hash=$(echo -n "$edit_path_before_hash" | sed s/\ //g)
                edit_path_before_hash=$(echo -n "$edit_path_before_hash" | sed s/\\///g)
                if [ ! -z "$edit_path_before_hash" ]; then
                    if [ -z "$path_after_hash" ]; then
                        path_length=$(( 1 + ${#edit_path_before_hash} ))
                    else
                        path_length=$(( 1 + ${#edit_path_before_hash} + 1 + ${#path_after_hash} ))
                    fi
                    if [ $path_length -gt 26 ]; then
                        if [ -z "$path_after_hash" ]; then
                            echo "错误: hash前额外路径 的长度不能大于25。保存失败。"
                        else
                            echo "错误: hash前额外路径 + hash后额外路径 的长度不能大于24。保存失败。"
                        fi
                    else
                        edit_config "path_before_hash" "$edit_path_before_hash"
                        echo "path_before_hash=$path_before_hash"
                        echo "已开启 hash前额外路径: $path_before_hash"
                        echo "返回主菜单选_1_重启服务后生效。"
                    fi
                    read -p "按回车键返回。" pause
                fi
            else
                edit_config "path_before_hash" ""
                echo "path_before_hash=$path_before_hash"
                echo "已关闭 hash前额外路径"
            fi
            ;;
        8)
            if [ -z "$path_after_hash" ]; then
                echo "开启后path将会变成 /用户hash/hash后额外路径"
                read -p "请输入hash后额外路径: " edit_path_after_hash
                edit_path_after_hash=$(echo -n "$edit_path_after_hash" | sed s/\ //g)
                edit_path_after_hash=$(echo -n "$edit_path_after_hash" | sed s/\\///g)
                if [ ! -z "$edit_path_after_hash" ]; then
                    if [ -z "$path_before_hash" ]; then
                        path_length=$(( 1 + ${#edit_path_after_hash} ))
                    else
                        path_length=$(( 1 + ${#path_before_hash} + 1 + ${#edit_path_after_hash} ))
                    fi
                    if [ $path_length -gt 26 ]; then
                        if [ -z "$path_before_hash" ]; then
                            echo "错误: hash后额外路径 的长度不能大于25。保存失败。"
                        else
                            echo "错误: hash前额外路径 + hash后额外路径 的长度不能大于24。保存失败。"
                        fi
                    else
                        edit_config "path_after_hash" "$edit_path_after_hash"
                        echo "path_after_hash=$path_after_hash"
                        echo "已开启 hash后额外路径: $path_after_hash"
                        echo "返回主菜单选_1_重启服务后生效。"
                    fi
                    read -p "按回车键返回。" pause
                fi
            else
                edit_config "path_after_hash" ""
                echo "path_after_hash=$path_after_hash"
                echo "已关闭 hash后额外路径"
            fi
            ;;
        9)
            nano "$dir/config"
            load_config
            ;;
    esac
}

case "$1" in
    cron)
        [ ! -f "$dir/config" ] && exit 1
        load_config
        check_installed
        if [ "$xray_running" = "运行中" ]; then
            while read line
            do
                user_port=$(echo -n "$line" | cut -d ' ' -f 1)
                add_traffic "$user_port"
            done < "$dir/user"
            generate_xray_conf
        fi
    ;;
    monthly_cron)
        while read line
        do
            user_port=$(echo -n "$line" | cut -d ' ' -f 1)
            add_traffic "$user_port"
            rm -f "$dir/user_traffic/${user_port}_last_month"
            mv "$dir/user_traffic/$user_port" "$dir/user_traffic/${user_port}_last_month"
        done < "$dir/user"
    ;;
    *)
        echo "+----------------------------------+" &&
        echo "|  github.com/yeyingorg/vlesssm.sh |" &&
        echo "|     vless+wss 多用户管理脚本     |" &&
        echo "|        2023-10-10 v1.0.0         |" &&
        echo "|     追加 vless+splithttp+h3      |" &&
        echo "|        2024-09-09 v2.0.0         |" &&
        echo "+----------------------------------+"
        [ ! -f "$dir/config" ] && first_time_run
        [ -f "$dir/config" ] && main_ui
    ;;
esac
exit 0
