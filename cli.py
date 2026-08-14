"""
프로토타입 CLI — 견적 생성 알고리즘을 실제로 돌려본다.
사용: python cli.py
"""
from core.algorithm import Requirements, Options, build_cost_efficient, build_performance, select_storage
from core.upgrade import upgrade_cpu_gpu, upgrade_ram_capacity
from db.db import get_connection


def load_game(title: str) -> Requirements:
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM game_requirements WHERE title = %s", (title,))
    row = cursor.fetchone()
    cursor.close()
    conn.close()
    if row is None:
        raise ValueError(f"게임을 찾을 수 없습니다: {title}")
    return Requirements(
        cpu_tier_min=row["required_cpu_tier"],
        gpu_tier_min=row["required_gpu_tier"],
        ram_gb_min=row["required_ram_gb"],
        ram_type_required=row["required_ram_type"],
    )


def print_build(label: str, result):
    print(f"\n{'='*50}\n{label}\n{'='*50}")
    if result.status != "ok":
        print(f"상태: {result.status}")
        print(f"메시지: {result.message}")
        return
    for stage, part in result.parts.items():
        print(f"  {stage:8s}: {part['name']:45s} {part['price_krw']:>10,}원")
    print(f"  {'총액':8s}: {'':45s} {result.total_price:>10,}원")


if __name__ == "__main__":
    req = load_game("엘든 링")
    opt = Options(placement="상관없음", rgb="상관없음")

    print_build("가성비 모드 — 엘든 링, 예산 200만원", build_cost_efficient(req, opt, 2_000_000))
    print_build("가성비 모드 — 엘든 링, 예산 30만원(부족 케이스)", build_cost_efficient(req, opt, 300_000))
    print_build("성능 모드 — 엘든 링, 예산 200만원", build_performance(req, opt, 2_000_000))
    print_build("성능 모드 — 엘든 링, 예산 800만원(최대 견적이 예산 내)", build_performance(req, opt, 8_000_000))

    req2 = load_game("배틀그라운드")
    opt2 = Options(placement="상관없음", rgb="상관없음")
    print_build("가성비 모드 — 배틀그라운드, 예산 250만원", build_cost_efficient(req2, opt2, 2_500_000))
    print_build("성능 모드 — 배틀그라운드, 예산 250만원", build_performance(req2, opt2, 2_500_000))

    # ---------------- 부품 업그레이드 기능(2.5절) ----------------
    base = build_cost_efficient(req, opt, 2_000_000)
    print_build("업그레이드 전 — 엘든 링, 가성비 모드, 200만원", base)

    upgraded_cpu_gpu = upgrade_cpu_gpu(base, req, opt)
    print_build("CPU/GPU 1단계 업그레이드 결과", upgraded_cpu_gpu)

    upgraded_ram = upgrade_ram_capacity(base, req, opt)
    print_build("RAM 용량 업그레이드 결과(용량 2배 목표)", upgraded_ram)

    # ---------------- 저장장치(SSD/HDD) 선택 ----------------
    storage = select_storage(ssd_gb_min=1000, hdd_gb_min=2000)
    print(f"\n{'='*50}\n저장장치 선택(SSD 1TB 이상 + HDD 2TB 이상)\n{'='*50}")
    if storage["ssd"]:
        print(f"  SSD : {storage['ssd']['name']:45s} {storage['ssd']['price_krw']:>10,}원")
    if storage["hdd"]:
        print(f"  HDD : {storage['hdd']['name']:45s} {storage['hdd']['price_krw']:>10,}원")
