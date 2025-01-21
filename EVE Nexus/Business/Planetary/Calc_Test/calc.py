import math
from datetime import datetime, timezone
import json


class ExtractorCalculator:
    def __init__(self, quantity_per_cycle, cycle_time):
        self.quantity_per_cycle = quantity_per_cycle
        self.cycle_time = cycle_time
        # 转换周期时间为15分钟单位数
        self.w_count = cycle_time / 900  # 900秒 = 15分钟
        self.phase_shift = math.pow(quantity_per_cycle, 0.7)
        self.decay_factor = 0.012  # ecuDecayFactor 的 defaultValue
        self.noise_factor = 0.8  # ecuNoiseFactor 的 defaultValue
        self.f1 = 1.0 / 12.0
        self.f2 = 1.0 / 5.0
        self.f3 = 1.0 / 2.0

    def calculate_yield(self, cycle_index):
        """计算指定周期的产量"""
        # 使用15分钟为基本单位计算时间
        t = (cycle_index + 0.5) * self.w_count

        # 计算衰减
        decay = self.quantity_per_cycle / (1.0 + t * self.decay_factor)

        # 计算余弦波动
        sina = math.cos(self.phase_shift + t * self.f1)
        sinb = math.cos(self.phase_shift / 2 + t * self.f2)
        sinc = math.cos(t * self.f3)

        # 计算波动值
        sins = max((sina + sinb + sinc) / 3.0, 0.0)

        # 计算产量
        hourly_yield = decay * (1.0 + self.noise_factor * sins)

        # 返回总产量
        return int(self.w_count * hourly_yield)

    def calculate_range(self, start_cycle, end_cycle):
        """计算一个范围内的所有周期产量"""
        results = []
        for cycle in range(start_cycle, end_cycle + 1):
            yield_value = self.calculate_yield(cycle)
            results.append({
                'cycle': cycle + 1,  # 显示从1开始的周期编号
                'yield': yield_value
            })
        return results


def calculate_total_cycles(install_time, expiry_time, cycle_time):
    """计算总周期数"""
    # 将时间字符串转换为datetime对象
    install_dt = datetime.strptime(install_time, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    expiry_dt = datetime.strptime(expiry_time, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)

    # 计算总秒数
    total_seconds = (expiry_dt - install_dt).total_seconds()

    # 计算总周期数
    total_cycles = int(total_seconds / cycle_time)

    return total_cycles - 1  # 减1是因为周期从0开始


def get_current_cycle(install_time, cycle_time):
    """获取当前周期"""
    # 将安装时间转换为datetime对象
    install_dt = datetime.strptime(install_time, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)

    # 获取当前UTC时间
    current_dt = datetime.now(timezone.utc)

    # 计算从安装到现在经过的秒数
    elapsed_seconds = (current_dt - install_dt).total_seconds()

    # 计算当前周期
    current_cycle = int(elapsed_seconds / cycle_time)

    return current_cycle


def load_extractor_data(json_file):
    """从JSON文件加载提取器数据"""
    with open(json_file, 'r') as f:
        data = json.load(f)
    extra_range = [2848, 3060, 3061, 3062, 3063, 3064, 3067, 3068]
    # 查找类型为提取器的设施（type_id: 2848）
    extractors = [pin for pin in data['pins'] if pin.get('type_id') in extra_range and pin.get('extractor_details')]

    if not extractors:
        raise ValueError("No extractors found in JSON data")

    results = []
    for extractor in extractors:
        details = extractor['extractor_details']
        results.append({
            'quantity_per_cycle': details['qty_per_cycle'],
            'cycle_time': details['cycle_time'],
            'install_time': extractor['install_time'],
            'expiry_time': extractor['expiry_time'],
            'product_type_id': details['product_type_id'],
            'pin_id': extractor['pin_id']
        })

    return results


def main():
    # 从JSON文件加载数据
    json_file = 'response_1737264298263.json'
    extractors = load_extractor_data(json_file)

    for extractor in extractors:
        print(f"\n提取器 ID: {extractor['pin_id']}")
        print(f"产品类型 ID: {extractor['product_type_id']}")

        # 计算总周期数
        total_cycles = calculate_total_cycles(
            extractor['install_time'],
            extractor['expiry_time'],
            extractor['cycle_time']
        )

        # 获取当前周期
        current_cycle = get_current_cycle(
            extractor['install_time'],
            extractor['cycle_time']
        )

        # 创建计算器实例
        calculator = ExtractorCalculator(
            extractor['quantity_per_cycle'],
            extractor['cycle_time']
        )

        # 计算所有周期的产量
        results = calculator.calculate_range(0, total_cycles)

        # 打印结果
        print(f"基础产量: {extractor['quantity_per_cycle']}")
        print(f"周期时间: {extractor['cycle_time']}秒 ({extractor['cycle_time'] / 3600}小时)")
        print(f"15分钟单位数: {extractor['cycle_time'] / 900}")
        print(f"总周期数: {total_cycles + 1}")  # +1是为了显示实际周期数
        print(f"当前周期: {current_cycle + 1}")  # +1是为了显示从1开始的周期编号
        print("\n周期\t产量")
        print("-" * 20)

        total_yield = 0
        for result in results:
            cycle_marker = " <--" if result['cycle'] == current_cycle + 1 else ""
            total_yield += result['yield']
            print(f"{result['cycle']}\t{result['yield']}{cycle_marker}")

        print(f"\n总产量: {total_yield}")


if __name__ == "__main__":
    main()