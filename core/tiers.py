"""
부품 성능 등급 고정 순서표 (기획서 6장).
벤치마크 점수 없이, 제조사를 Intel/NVIDIA 하나로 한정한 덕분에 세대·라인업·
접미사를 조합한 고정 순서만으로 "한 단계 위/아래"를 판단할 수 있다.

각 리스트는 오름차순(약한 것 -> 강한 것)이며, 인덱스가 등급(tier) 번호다.
카탈로그의 실제 상품명은 이 표의 키워드가 상품명에 포함되는지로 매칭한다
(예: "인텔 코어i5-14세대 14600K" -> "14600K" 포함 -> i5 계열 3번째 등급).
"""

# GPU: 6.1절 "NVIDIA GPU 정렬 표준 계층"
GPU_TIER_ORDER = [
    "4060", "5060", "4060 Ti", "5060 Ti",                          # 0~3 엔트리/메인스트림
    "4070", "4070 SUPER", "5070", "4070 Ti", "5070 Ti",             # 4~8 하이엔드
    "4080", "5080", "4090", "5090",                                  # 9~12 플래그십
]

# CPU: 6.2절 "Intel CPU 정렬 표준 계층"
CPU_TIER_ORDER = [
    "13100", "14100",                                                          # 0~1 i3
    "13400", "14400", "13500", "14500", "245K", "13600K", "14600K",            # 2~6 i5 (Ultra 5 245K 포함)
    "13700", "265K", "14700", "13700K", "14700K",                              # 7~11 i7 (Ultra 7 265K 포함)
    "13900", "285K", "14900", "13900K", "14900K", "14900KS",                   # 12~17 i9 (Ultra 9 285K 포함)
]


def _find_tier(name: str, order: list[str]) -> int | None:
    """상품명에 순서표의 키워드가 포함되는지 찾아 등급(인덱스)을 반환한다.
    긴 키워드가 짧은 키워드의 부분 문자열인 경우(예: "14600K" 안에 "4600"은
    없지만 유사 사례 방지를 위해)가 있을 수 있어, 긴 키워드부터 먼저 검사한다."""
    name_upper = name.upper().replace(" ", "")
    candidates = sorted(enumerate(order), key=lambda x: -len(x[1]))
    for idx, keyword in candidates:
        if keyword.upper().replace(" ", "") in name_upper:
            return order.index(keyword)
    return None


def gpu_tier(name: str) -> int | None:
    return _find_tier(name, GPU_TIER_ORDER)


def cpu_tier(name: str) -> int | None:
    return _find_tier(name, CPU_TIER_ORDER)


def next_gpu_keyword(current_tier: int) -> str | None:
    """한 단계 위 등급의 키워드를 반환한다(카탈로그 검색용). 이미 최고 등급이면 None."""
    if current_tier is None or current_tier + 1 >= len(GPU_TIER_ORDER):
        return None
    return GPU_TIER_ORDER[current_tier + 1]


def next_cpu_keyword(current_tier: int) -> str | None:
    if current_tier is None or current_tier + 1 >= len(CPU_TIER_ORDER):
        return None
    return CPU_TIER_ORDER[current_tier + 1]
