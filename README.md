# vless server multi-user manager script

vless服务器的多用户管理脚本
(vless) (s)erver (m)anager script  

修改自 [使用v2ray-plugin的Shadowsocks服务器的多用户管理脚本(sssm.sh)](https://github.com/yeyingorg/sssm.sh)

### 脚本要求

- 系统: **Debian**/Ubuntu
- CPU架构: x86_64 (amd64) 或 aarch64 (arm64)
- 以**root**用户执行
- IPv4证书 (可在 [**ZeroSSL**](https://zerossl.com/) 免费申请)
> IP证书并不需要是本机的IP，假如您有多台机器，甚至是IPv6 only的机器，您只需要使用其中一台有IPv4地址的申请一张IP证书，即可使用该证书为所有机器配置本脚本。

### 脚本功能

- 简洁易懂快捷方便的多用户管理(添加删除用户)
- 针对单个用户的流量统计与限制(达量自动断网)
- 自动生成xray配置文件
- 自动生成用户配置vless链接

### 脚本缺点

- 初次执行劝退99.99%潜在用户(因为需要IP证书)
- 不支持巨量用户的情况(1000+)

### 脚本使用的服务端

- [**Xray-core**](https://github.com/XTLS/Xray-core)

## 脚本使用方法

首先准备好一个IP证书，没有的可以去[**ZeroSSL**](https://zerossl.com/)免费申请  
然后创建 **/home/vlesssm**目录，把**vlesssm.sh**放进去，然后使用**root**用户/或者`sudo`运行。

```bash
mkdir /home/vlesssm && wget --no-check-certificate -q -O /home/vlesssm/vlesssm.sh "https://github.com/yeyingorg/vlesssm.sh/raw/main/vlesssm.sh" && chmod +x /home/vlesssm/vlesssm.sh && bash /home/vlesssm/vlesssm.sh
```

更新可用代码
```bash
mkdir /home/vlesssm && wget --no-check-certificate -q -O /home/vlesssm/vlesssm.sh "https://github.com/xianrenjituan/vlesssm/raw/main/vlesssm.sh" && chmod +x /home/vlesssm/vlesssm.sh && bash /home/vlesssm/vlesssm.sh
```
