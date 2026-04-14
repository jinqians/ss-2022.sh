#!/usr/bin/env python3
"""
从MaxMind GeoIP2 mmdb文件提取中国IP CIDR段
需要安装: pip install maxminddb
"""

import sys
from ipaddress import IPv4Address, IPv4Network, ip_network


def _configure_stdio_utf8():
    """在低版本或非UTF-8 locale环境下，尽量确保输出不因中文崩溃。"""
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream is None:
            continue
        if hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass

def check_dependencies():
    """检查是否已安装maxminddb库"""
    try:
        import maxminddb
        return True
    except ImportError:
        print("[错误] 未安装maxminddb库", file=sys.stderr)
        print("[信息] 请运行: pip install maxminddb", file=sys.stderr)
        return False


def _metadata_value(metadata, key, default="N/A"):
    """兼容 maxminddb Metadata 对象与 dict 两种读取方式。"""
    if hasattr(metadata, key):
        return getattr(metadata, key)
    if isinstance(metadata, dict):
        return metadata.get(key, default)
    return default


def _country_code(record):
    """从 GeoIP2 记录中提取国家代码。"""
    if not isinstance(record, dict):
        return None

    for key in ("country", "registered_country", "represented_country"):
        section = record.get(key)
        if isinstance(section, dict):
            code = section.get("iso_code")
            if code:
                return code

    return None


def _iter_ipv4_networks_by_prefix(reader):
    """使用 get_with_prefix_len 逐段扫描 IPv4 空间，兼容老版本 Reader。"""
    if not hasattr(reader, "get_with_prefix_len"):
        raise RuntimeError("当前 maxminddb 版本不支持 get_with_prefix_len，无法遍历网段")

    current = 0
    ipv4_end = 1 << 32

    while current < ipv4_end:
        ip_text = str(IPv4Address(current))
        record, prefix_len = reader.get_with_prefix_len(ip_text)

        # 异常值保护，保证循环前进
        if prefix_len is None or not isinstance(prefix_len, int) or prefix_len < 0 or prefix_len > 32:
            prefix_len = 32

        netmask_bits = 32 - prefix_len
        mask = ((1 << 32) - 1) ^ ((1 << netmask_bits) - 1) if netmask_bits > 0 else (1 << 32) - 1
        network_start = current & mask
        network = IPv4Network((network_start, prefix_len), strict=False)

        yield str(network), record

        next_ip = int(network.broadcast_address) + 1
        current = next_ip if next_ip > current else current + 1

def extract_china_ip_from_mmdb(mmdb_file, output_file):
    """
    从mmdb文件提取中国IP CIDR
    使用maxminddb库的网络查询功能
    """
    import maxminddb
    
    print(f"[信息] 打开数据库文件: {mmdb_file}")
    
    try:
        reader = maxminddb.open_database(mmdb_file)
    except FileNotFoundError:
        print(f"[错误] 文件不存在: {mmdb_file}")
        return False
    except Exception as e:
        print(f"[错误] 打开数据库失败: {e}")
        return False
    
    print("[信息] 开始提取中国IP段...")
    
    # 获取数据库元数据（Metadata 对象）
    metadata = reader.metadata()
    db_type = _metadata_value(metadata, "database_type")
    description = _metadata_value(metadata, "description", {})
    if isinstance(description, dict):
        db_desc = description.get("zh-CN") or description.get("en") or next(iter(description.values()), "N/A")
    else:
        db_desc = str(description)

    print(f"[信息] 数据库类型: {db_type}")
    print(f"[信息] 数据库描述: {db_desc}")
    
    china_networks = []
    subnet_count = 0
    
    # 遍历所有IPv4网段，使用前缀长度跳跃扫描
    try:
        for prefix, result in _iter_ipv4_networks_by_prefix(reader):
            subnet_count += 1

            # 检查地理数据
            country_code = _country_code(result)
            if country_code == 'CN':
                china_networks.append(prefix)
                
                if len(china_networks) % 500 == 0:
                    print(f"[信息] 已处理 {subnet_count} 个网段，找到 {len(china_networks)} 个中国IP段...")
            
            # 进度显示
            if subnet_count % 5000 == 0:
                print(f"[信息] 已处理 {subnet_count} 个网段...")
    
    except Exception as e:
        print(f"[错误] 读取数据库时出错: {e}")
        reader.close()
        return False
    
    reader.close()
    
    if not china_networks:
        print("[错误] 未找到中国IP段")
        return False
    
    # 去重并排序IP段
    print("[信息] 正在去重和排序IP段...")
    china_networks = sorted(
        set(china_networks),
        key=lambda x: (int(ip_network(x).network_address), ip_network(x).prefixlen),
    )
    
    # 写入文件
    print(f"[信息] 写入输出文件: {output_file}")
    try:
        with open(output_file, 'w') as f:
            for network in china_networks:
                f.write(f"{network}\n")
    except IOError as e:
        print(f"[错误] 写入文件失败: {e}")
        return False
    
    print(f"[成功] 提取完成！共找到 {len(china_networks)} 个中国IP CIDR段")
    return True

def main():
    _configure_stdio_utf8()

    if len(sys.argv) < 2:
        print("用法: python3 extract-cn-ip-from-mmdb.py <mmdb文件> [输出文件]")
        print("")
        print("例如:")
        print("  python3 extract-cn-ip-from-mmdb.py Country.mmdb mainland_cn.txt")
        sys.exit(1)
    
    mmdb_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else "mainland_cn.txt"
    
    # 检查依赖
    if not check_dependencies():
        print("\n[提示] 安装依赖后重试:")
        print("  pip install maxminddb")
        sys.exit(1)
    
    # 提取IP
    success = extract_china_ip_from_mmdb(mmdb_file, output_file)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
