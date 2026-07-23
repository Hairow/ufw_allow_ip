# UFW Allow IP — UFW 白名单批量管理工具

基于 UFW（Uncomplicated Firewall）的 IP 白名单批量管理脚本，支持从文件读取 IP/CIDR 列表，一键添加/删除/查看指定端口的 TCP 放行规则。

## 功能特性

- **批量管理**：从 `ip.txt` 读取 IP/CIDR 列表，批量操作 UFW 规则
- **交互式操作**：彩色终端界面，中文交互提示
- **三种模式**：添加规则、删除规则、查看规则
- **灵活端口输入**：支持单端口、多端口（空格分隔）、端口范围（如 `8000-8100`）、混合输入
- **智能检测**：自动跳过已存在的规则（添加时）或不存在的规则（删除时）
- **操作日志**：所有操作记录到 `/var/log/ufw_whitelist.log`
- **格式校验**：自动验证 IP/CIDR/端口的有效性，过滤无效条目
- **支持 IPv4 CIDR**：自动处理网段规则

## 快速开始

### 前置条件

- Linux 系统
- 已安装 UFW：`sudo apt install ufw`
- UFW 已启用：`sudo ufw enable`

### 基本用法

```bash
# 1. 准备 ip.txt（选择需要的白名单列表）
cp china_ipv4&6.txt ip.txt      # 使用中国 IP 列表
# 或
cp cloudflare_ipv4&6.txt ip.txt  # 使用 Cloudflare IP 列表

# 2. 运行脚本
sudo bash ufw_allow_whitelist.sh
```

### 操作流程

1. 脚本启动后自动检查 UFW 状态
2. 显示主菜单，选择操作模式：
   - `1` — 添加规则：将 `ip.txt` 中的 IP 加入指定端口的白名单
   - `2` — 删除规则：从指定端口移除 `ip.txt` 中的 IP 规则
   - `3` — 查看规则：显示当前所有 TCP 白名单规则
3. 输入要操作的端口（支持多种格式）
4. 确认后执行批量操作
5. 显示执行统计

## 文件说明

| 文件 | 说明 |
|------|------|
| `ufw_allow_whitelist.sh` | 主脚本 |
| `ip.txt` | 当前使用的白名单 IP 列表（运行前需手动指定） |
| `china_ipv4&6.txt` | 中国 IP 地址段列表 |
| `cloudflare_ipv4&6.txt` | Cloudflare IP 地址段列表（含 IPv6） |

> **注意**：`ip.txt` 中的 IPv6 地址当前不会被处理（脚本仅校验 IPv4 格式）。

## 端口输入示例

```
单个端口: 22
多个端口: 22 80 443
端口范围: 8000-8100
混合输入: 22 80 443 8000-8100
```

## 使用示例

```bash
# 示例：只允许中国 IP 访问 SSH 和 HTTP/HTTPS
cp china_ipv4&6.txt ip.txt
sudo bash ufw_allow_whitelist.sh
# 选择 1（添加规则），输入: 22 80 443

# 示例：允许 Cloudflare IP 访问 443 端口
cp cloudflare_ipv4&6.txt ip.txt
sudo bash ufw_allow_whitelist.sh
# 选择 1（添加规则），输入: 443
```

## 日志

操作日志位于 `/var/log/ufw_whitelist.log`，记录每次操作的时间、模式、处理条目数和结果统计。

## License

MIT
