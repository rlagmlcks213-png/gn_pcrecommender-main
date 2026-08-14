"""
견적 생성 알고리즘 (기획서 2.2~2.4절).

순서: CPU/GPU 확정 -> 메인보드 -> RAM -> 쿨러 -> PSU -> 케이스
탐색 방식은 아래 명시적 스택으로 구현한다 — 각 스테이지에서 후보를 하나씩
시도하다가(예: 1.2.8 -> 1.2.9 -> 1.2.10) 후보가 전부 소진되면 바로 이전
스테이지로 돌아가 그 선택을 한 칸 위 후보로 바꾸고(1.2.10 -> 1.3.1) 다시
내려온다(기획서 2.2.1절 백트래킹 규칙). 가장 앞 스테이지(CPU)까지 후보가
소진되면 최종 실패.
"""
import re
from dataclasses import dataclass, field

from db.db import get_connection
from core import gemini_review

STAGES = ["cpu", "gpu", "ram", "mboard", "cooler", "psu", "case"]

# *** 수정(실사용자 요청: "메인보드가 RAM보다 먼저 정해지면, DDR4 전용 보급형
# 보드가 가성비 모드에서 먼저 골라졌을 때 RAM이 억지로 DDR4로 폴백된다") ***
# RAM 매칭 가이드가 "DDR5가 현재 주력 규격, DDR4는 구형·비추천"이라고 명시하니,
# RAM을 먼저(DDR5 우선으로) 고르고 메인보드가 그 규격을 지원하는 것 중에서
# 골라지도록 순서를 뒤집었다 — 메인보드가 RAM 규격을 강요하는 게 아니라
# RAM이 메인보드 규격 선택을 이끈다.
STAGE_DEPENDENCIES: dict[str, list[str]] = {
    "cpu": [],
    "gpu": ["cpu"],       # *** 수정(밸런스 가이드): GPU는 이제 CPU 체급도 본다 ***
    "ram": [],            # 이제 메인보드와 무관하게 요구 용량만 보고 고른다(DDR5 우선)
    "mboard": ["cpu", "gpu", "ram"],  # *** 수정: 이제 RAM 규격/슬롯 요구사항도 만족해야 한다 ***
    "cooler": ["cpu", "ram"],  # *** 수정(RAM 매칭 가이드 5절): 대장급 공랭이 RAM 히트싱크와 간섭하는지 확인 ***
    "psu": ["gpu", "cpu"],  # *** 수정: CPU 체급별 최소 와트수 하한선도 참조하므로 cpu도 의존 ***
    "case": ["mboard", "cooler", "gpu", "psu"],
}

# *** 신설(실사용자 제공 Gemini 밸런스 가이드 1절 반영) ***
# CPU/GPU 체급을 4단계(Flagship/High-End/Mainstream/Entry)로 나누고,
# CPU-GPU는 1단계 초과 차이 나면 병목으로 본다. cpu_performance_tier/
# gpu_performance_tier의 tier_rank 값 구간을 가이드의 실제 모델 예시
# (i9/Ultra9=Flagship, i7/Ultra7=High-End, i5-K/Ultra5상위=Mainstream,
# i5비K/Ultra5하위=Entry / RTX 5080~5090=Flagship, RTX 4070~5070Ti=High-End,
# RTX 4060Ti~5060Ti=Mainstream, RTX 4060/5050=Entry)에 맞춰 눈금을 매겼다.
CPU_TIER_BUCKETS = [(8, "entry"), (11, "mainstream"), (18, "high"), (25, "flagship")]
GPU_TIER_BUCKETS = [(2, "entry"), (5, "mainstream"), (10, "high"), (14, "flagship")]
BUCKET_ORDER = ["entry", "mainstream", "high", "flagship"]


def _tier_bucket(tier_rank: int | None, boundaries: list[tuple[int, str]]) -> str | None:
    if tier_rank is None:
        return None
    for upper, name in boundaries:
        if tier_rank <= upper:
            return name
    return boundaries[-1][1]


def cpu_tier_bucket(tier_rank: int | None) -> str | None:
    return _tier_bucket(tier_rank, CPU_TIER_BUCKETS)


def gpu_tier_bucket(tier_rank: int | None) -> str | None:
    return _tier_bucket(tier_rank, GPU_TIER_BUCKETS)


# 메인보드 라인업 등급(상품명 기반 — 3사 라인업명은 컬럼이 아니라 상품명에만
# 있어서 정규식으로 판별한다). 가이드 표의 "보급형(H/A)/중급형(B)/상급·최상위(Z)"를
# 그대로 GPU 버킷과 대응시킨다: 보급형->entry/mainstream, 중급형->mainstream/high,
# 상급->high/flagship.
_MBOARD_CHIPSET_RE = re.compile(r"\b([ZXBHA])\d{3}[A-Z]?\b")
_MBOARD_CHIPSET_BUCKET = {"Z": "high", "X": "high", "B": "mainstream", "H": "entry", "A": "entry"}
_MBOARD_LINEUP_PATTERNS = [
    (re.compile(r"MEG|MPG|MAXIMUS|STRIX|AORUS MASTER|TACHYON", re.IGNORECASE), "high"),
    (re.compile(r"MAG|박격포|토마호크|TUF|AORUS ELITE", re.IGNORECASE), "mainstream"),
    (re.compile(r"PRO |PRIME|UD|EAGLE", re.IGNORECASE), "entry"),
]


def mboard_lineup_bucket(name: str) -> str:
    """상품명에서 메인보드 등급을 판별한다.

    *** 수정(실사용자 발견: "i9-14900KS+RTX4090에 B760 보드가 매칭됨") ***
    브랜드 서브라인 이름(STRIX/TUF/PRIME 등)만 보고 판별했더니, "ASUS ROG
    STRIX B760-G"처럼 ASUS가 B(중급) 칩셋 보드에도 STRIX 이름을 붙이는
    경우를 "상급"으로 오판했다 — STRIX는 원래 상급 라인업(Z790 STRIX 등)에
    주로 쓰이지만 B시리즈에도 마케팅상 확장돼있다. 칩셋 코드(Z/X=상급,
    B=중급, H/A=보급형)가 상품명에 명시적으로 있으면 그걸 최우선으로
    쓰고, 칩셋 코드를 못 찾을 때만 브랜드 서브라인 이름으로 폴백한다."""
    chip_m = _MBOARD_CHIPSET_RE.search((name or "").upper())
    if chip_m:
        return _MBOARD_CHIPSET_BUCKET.get(chip_m.group(1), "entry")
    for pattern, bucket in _MBOARD_LINEUP_PATTERNS:
        if pattern.search(name or ""):
            return bucket
    return "entry"


@dataclass
class Requirements:
    # *** 수정(실제 스키마 연결): cpu_tier_min/gpu_tier_min은 이제 코드 안에서
    # 이름을 추측하는 게 아니라, DB의 cpu_performance_tier/gpu_performance_tier
    # 테이블이 매긴 tier_rank 값을 그대로 쓴다(정확도가 훨씬 높음 — 팀원이
    # 기획서 6장을 SQL로 옮기면서 K/비K, 세대, Ultra 시리즈까지 정확히 반영함).
    cpu_tier_min: int = 0
    gpu_tier_min: int = 0
    ram_gb_min: int = 8
    # *** 수정(실사용자 제공 "PC 용도별 견적 가이드"): 이전엔 "게임을 하나라도
    # 선택하면 무조건 1TB, 아니면 500GB"라는 대충 정한 규칙이었는데, 이제
    # game_requirements.storage_gb / usage_profiles.required_ssd_gb·hdd_gb라는
    # 정확한 근거가 생겨서 다른 필드들과 똑같이 merge_requirements에서
    # max()로 병합한다. ***
    ssd_gb_min: int = 500
    hdd_gb_min: int = 0


def merge_requirements(rows: list[dict]) -> Requirements:
    """
    다중 게임/PC 용도 통합 (기획서 2.1절 핵심 규칙): 게임을 2개 이상 선택했거나,
    게임과 용도를 함께 선택한 경우, 항목별로 더 높은 쪽을 채택한다.

    rows: game_requirements/usage_profiles에서 뽑은 행을, api/server.py가
    미리 공통 키(required_cpu_tier/required_gpu_tier/required_ram_gb/
    required_ssd_gb/required_hdd_gb)로 정규화해서 넘긴다 — 두 테이블의
    실제 컬럼명이 서로 다르기 때문이다(game_requirements는 cpu_tier_rank
    /storage_gb, usage_profiles는 required_cpu_tier/required_ssd_gb).
    """
    if not rows:
        return Requirements()

    cpu_tier_min = max(r["required_cpu_tier"] for r in rows)
    gpu_tier_min = max(r["required_gpu_tier"] for r in rows)
    ram_gb_min = max(r["required_ram_gb"] for r in rows)
    ssd_gb_min = max(r.get("required_ssd_gb") or 500 for r in rows)
    hdd_gb_min = max(r.get("required_hdd_gb") or 0 for r in rows)

    return Requirements(
        cpu_tier_min=cpu_tier_min, gpu_tier_min=gpu_tier_min, ram_gb_min=ram_gb_min,
        ssd_gb_min=ssd_gb_min, hdd_gb_min=hdd_gb_min,
    )


@dataclass
class Options:
    placement: str = "상관없음"   # 책상 위/책상 아래/미니 PC/상관없음
    rgb: str = "상관없음"          # 화려/없음/상관없음


@dataclass
class BuildResult:
    parts: dict = field(default_factory=dict)   # {stage: row(dict)}
    total_price: int = 0
    status: str = "ok"           # ok / no_matching_product / budget_insufficient
    message: str = ""
    review_notes: list = field(default_factory=list)  # Gemini 검수 코멘트(있으면)


def _fetch_all(conn, table, where="", params=(), media_category=None):
    """MySQL 커서로 조회한다. table 인자엔 _v 뷰 이름(가격 포함)을 넘긴다.
    ? 대신 %s 플레이스홀더를 쓴다(mysql.connector 규칙).

    media_category를 주면 product_media(사진/다나와 링크)를 LEFT JOIN해서
    image_url/product_url을 같이 붙여준다 — 아직 그 카테고리 사진 데이터가
    없으면 NULL로 채워지며(LEFT JOIN이라 에러 없음), 실제 덤프가 들어오면
    자동으로 채워진다."""
    sql = f"SELECT p.*"
    if media_category:
        sql += ", m.image_url, m.product_url"
    sql += f" FROM {table} p"
    if media_category:
        sql += f" LEFT JOIN product_media m ON m.category = '{media_category}' AND m.product_id = p.product_id"
    if where:
        sql += f" WHERE {where}"
    cursor = conn.cursor(dictionary=True)
    cursor.execute(sql, params)
    rows = cursor.fetchall()
    cursor.close()
    return rows


_RAM_OPTION_RE = re.compile(r"^\s*(\d+)\s*GB(?:\((\d+)\s*G[xX]\s*(\d+)\))?")


def _parse_ram_option(option_name: str) -> tuple[int, int] | None:
    """다나와 RAM 옵션명("64GB(32Gx2)", "8GB" 등)에서 (총용량GB, 패키지 개수)를
    뽑아낸다. 괄호 표기가 없으면 단일 스틱(패키지 개수 1)으로 본다.
    형식이 하나도 안 맞으면 None(용량 파싱 실패한 옵션은 후보에서 제외)."""
    m = _RAM_OPTION_RE.match(option_name or "")
    if not m:
        return None
    total_gb = int(m.group(1))
    stick_count = int(m.group(3)) if m.group(3) else 1
    return total_gb, stick_count


_RAM_SPEED_RE = re.compile(r"DDR[45]-(\d+)")
MIN_DDR5_SPEED_MHZ = 5600  # 실사용자 제공 RAM 가이드 3절: "DDR5-4800은 초기형 속도로 성능이 떨어지므로 5600MHz 권장"


def _fetch_ram_options(conn, ram_gb_min: int) -> list[dict]:
    """RAM을 상품(product_id) 단위가 아니라 "옵션"(용량 구성) 단위로 조회한다.
    *** 수정(실사용자 제공 RAM 매칭 가이드 + 매칭 순서 변경) ***
    이제 메인보드보다 먼저 RAM을 고른다 — 메인보드 규격에 RAM이 끌려가면서
    DDR4 전용 보급형 보드가 먼저 골라졌을 때 RAM이 억지로 DDR4로 폴백되는
    문제를 막기 위해서다. 여기서는 메인보드 정보 없이:
      1) DDR5-5600MHz 이상만 우선 조회한다(가이드 3절 — 4800은 구형 취급).
      2) 그걸로 요구 용량을 못 채우면 DDR5 전체(4800 포함)로 넓힌다.
      3) 그래도 없으면 DDR4로 폴백한다(가이드 1절 — "구형, 비추천"이지만
         카탈로그에 DDR5가 전혀 없는 경우의 최후 수단).
    항상 듀얼 채널(단일 스틱 2개, quantity=2)로 고정한다(가이드 2절 — 단일/
    4개 금지, 정확히 2개가 정석). 슬롯 수 검증은 이 시점엔 메인보드가 아직
    안 정해졌으니 할 수 없고, 뒤이어 오는 메인보드 스테이지가 "이 RAM의
    quantity를 수용할 슬롯이 있는지"를 확인한다."""
    quantity = 2  # 가이드 2절: 무조건 듀얼 채널(동일 용량 2개)이 정석

    def _query(ram_type: str) -> list[dict]:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT p.product_id, p.name, pp.option_name, pp.price AS price_krw,
                   m.image_url, m.product_url,
                   (SELECT CAST(REGEXP_REPLACE(spec_value, '[^0-9]', '') AS UNSIGNED)
                    FROM danawa_spec_summary
                    WHERE category = 'ram' AND product_id = p.product_id AND spec_key = '높이'
                    LIMIT 1) AS heatsink_height_mm
            FROM ram_products p
            JOIN ram_prices pp ON pp.product_id = p.product_id
            LEFT JOIN product_media m ON m.category = 'ram' AND m.product_id = p.product_id
            WHERE p.ram_type = %s
              AND pp.crawl_date = (SELECT MAX(crawl_date) FROM ram_prices)
            """,
            (ram_type,),
        )
        rows = cursor.fetchall()
        cursor.close()
        return rows

    def _to_options(rows: list[dict], ram_type: str, min_speed: int) -> list[dict]:
        options = []
        for row in rows:
            speed_m = _RAM_SPEED_RE.search(row["name"] or "")
            speed = int(speed_m.group(1)) if speed_m else 0
            if speed < min_speed:
                continue
            parsed = _parse_ram_option(row["option_name"])
            if parsed is None:
                continue
            stick_capacity_gb, stick_count = parsed
            if stick_count != 1:
                continue  # 이미 묶인 킷 옵션은 제외 — 단일 스틱만 후보로 삼는다
            total_capacity_gb = stick_capacity_gb * quantity
            if total_capacity_gb < ram_gb_min:
                continue
            unit_price = row["price_krw"]
            option_label = row["option_name"].split("_")[0]
            options.append({
                "product_id": row["product_id"],
                "name": f"{row['name']} {option_label} x{quantity}",
                "price_krw": unit_price * quantity,
                "unit_price_krw": unit_price,
                "quantity": quantity,
                "capacity_gb": total_capacity_gb,
                "ram_type": ram_type,
                "speed_mhz": speed,
                "heatsink_height_mm": row.get("heatsink_height_mm"),
                "image_url": row["image_url"],
                "product_url": row["product_url"],
            })
        return options

    ddr5_fast = _to_options(_query("DDR5"), "DDR5", MIN_DDR5_SPEED_MHZ)
    if ddr5_fast:
        return ddr5_fast
    ddr5_all = _to_options(_query("DDR5"), "DDR5", 0)
    if ddr5_all:
        return ddr5_all
    return _to_options(_query("DDR4"), "DDR4", 0)  # 최후 수단(가이드상 비추천이지만 DDR5 자체가 없을 때만)



def _psu_form_factor_matches(psu_form_factor: str, case_supported: str) -> bool:
    """케이스의 support_psu_form_factors는 다나와 원문 그대로("표준-ATX",
    "M-ATX(SFX)")라 PSU 쪽 단순 표기(ATX/SFX/TFX)와 형식이 다르다.
    괄호가 있으면 괄호 안 값이 실제 지원 PSU 폼팩터고("M-ATX(SFX)" -> SFX),
    없으면 하이픈 뒤 값을 쓴다("표준-ATX" -> ATX)."""
    m = re.search(r"\(([A-Za-z]+)\)", case_supported)
    tail = m.group(1) if m else case_supported.split("-")[-1].strip()
    return psu_form_factor == tail


from core.psu_rules import has_atx3_support, extract_80plus_tier, HIGH_POWER_GPU_TIER_THRESHOLD


def get_candidates(conn, stage: str, context: dict, req: Requirements, opt: Options, mode: str) -> list[dict]:
    """해당 스테이지에서 이전 단계 선택(context)과 호환되는 후보를 정렬해서 반환한다.
    mode='cost' -> 가격 오름차순(가성비 모드, 2.3절)
    mode='perf' -> 등급/가격 내림차순(성능 모드 최대 견적 산출, 2.4절)
    """
    if stage == "cpu":
        rows = _fetch_all(conn, "cpu_products_v", "usage_type = 'consumer'", media_category="cpu")
        rows = [r for r in rows if (r["tier_rank"] or 0) >= req.cpu_tier_min]
    elif stage == "gpu":
        # *** 수정(실사용자 제공 밸런스 가이드 1-①): CPU-GPU 체급이 1단계를
        # 초과해서 벌어지면 안 됨. 4단계(entry/mainstream/high/flagship)로
        # 나눠서, CPU 버킷 기준 상하 1단계 이내의 GPU만 후보로 남긴다 —
        # "필요조건(req.gpu_tier_min)"과 "밸런스 상한"을 동시에 만족해야 한다.
        # context에 cpu가 없으면(예: 예산 사전 체크용 단독 조회) 밸런스
        # 필터는 건너뛰고 요구조건만 적용한다.
        rows = _fetch_all(conn, "vga_products_v", media_category="vga")
        rows = [r for r in rows if (r["tier_rank"] or 0) >= req.gpu_tier_min]
        cpu = context.get("cpu")
        if cpu:
            cpu_bucket = cpu_tier_bucket(cpu.get("tier_rank"))
            if cpu_bucket:
                cpu_idx = BUCKET_ORDER.index(cpu_bucket)
                allowed = set(BUCKET_ORDER[max(0, cpu_idx - 1): cpu_idx + 2])
                balanced = [r for r in rows if gpu_tier_bucket(r["tier_rank"]) in allowed]
                if balanced:
                    rows = balanced
    elif stage == "ram":
        # *** 수정(실사용자 요청: 매칭 순서 변경 — RAM을 메인보드보다 먼저) ***
        # 메인보드가 RAM보다 먼저 정해지면, 가성비 모드에서 DDR4 전용 보급형
        # 보드가 먼저 골라졌을 때 RAM이 억지로 DDR4로 폴백되는 문제가 있었다.
        # 이제 메인보드와 무관하게 요구 용량만 보고 RAM을 먼저 고른다(DDR5
        # 우선, 5600MHz 미만은 배제 — _fetch_ram_options 안에서 처리).
        rows = _fetch_ram_options(conn, req.ram_gb_min)
    elif stage == "mboard":
        cpu = context["cpu"]
        ram = context["ram"]
        rows = _fetch_all(conn, "mboard_products_v", "socket = %s AND usage_type = 'consumer'", (cpu["socket"],), media_category="mboard")
        if opt.placement == "미니 PC":
            rows = [r for r in rows if r["form_factor"] == "ITX"]
        # *** 수정(실사용자 요청: 매칭 순서 변경) *** 이제 RAM이 먼저 정해져
        # 있으니, 그 RAM의 규격(DDR4/DDR5)을 지원하고 슬롯 수가 RAM 개수
        # (항상 2, 듀얼채널)를 수용할 수 있는 메인보드만 남긴다 — 예전엔
        # 메인보드가 RAM 규격을 강제했는데, 이제 반대로 RAM 규격이 메인보드
        # 선택을 이끈다.
        rows = [r for r in rows if r["ram_type"] == ram["ram_type"]]
        rows = [r for r in rows if (r["ram_slot_count"] or 0) >= ram["quantity"]]
        # *** 수정(실사용자 발견: "i9-14900KS에 B760 보급형 보드가 붙음") ***
        # 예전엔 GPU 체급만 보고 메인보드 라인업을 골랐는데, 메인보드
        # 전원부(VRM) 품질은 실제로 CPU 전력 소모가 더 크게 좌우한다 —
        # CPU와 GPU 버킷 중 "더 상위"인 쪽을 기준으로 삼는다(가이드 1-②
        # 원문도 "권장 매칭(CPU & GPU)"라고 둘 다 명시하고 있었는데 GPU만
        # 반영했던 게 누락이었다).
        cpu_bucket = cpu_tier_bucket(cpu.get("tier_rank"))
        gpu = context.get("gpu")
        gpu_bucket = gpu_tier_bucket(gpu.get("tier_rank")) if gpu else None
        buckets = [b for b in (cpu_bucket, gpu_bucket) if b]
        if buckets:
            idx = max(BUCKET_ORDER.index(b) for b in buckets)
            allowed = set(BUCKET_ORDER[max(0, idx - 1): idx + 2])
            matched = [r for r in rows if mboard_lineup_bucket(r["name"]) in allowed]
            if matched:
                rows = matched
    elif stage == "cooler":
        # *** 수정(실사용자 제공 CPU-쿨러 발열 매칭 가이드) ***
        # CPU 라인업(등급)에 따라 필요한 쿨러 체급을 강제한다 — 공랭이 이론상
        # 그 TDP를 버틸 수 있어 보여도, i7/i9(및 Ultra7/9) 라인업은 순간 피크
        # 발열·서멀 스로틀링 위험 때문에 무조건 3열(360mm급 이상, 실측
        # 라디에이터 길이 약 390mm 이상) 수랭만 허용한다 — 이미 만든
        # CPU_TIER_BUCKETS(entry/mainstream/high/flagship)가 가이드의 4단계
        # 경계와 정확히 일치해서 그대로 재사용한다.
        #   - entry(1~8, i3·i5비K 등 65~120W): 제한 없음
        #   - mainstream(9~11, i5-K 등 150~180W): 듀얼타워급 공랭(TDP 등급
        #     150W 이상으로 표기된 것) 또는 수랭 전체 허용
        #   - high(12~18, i7·Ultra7 220~280W): 3열 수랭(라디에이터 390mm+) 필수
        #   - flagship(19~25, i9·Ultra9 250~320W+): 3열 수랭(라디에이터 390mm+) 필수
        cpu = context["cpu"]
        rows = _fetch_all(conn, "cooler_products_v", media_category="cooler")
        rows = [r for r in rows if cpu["socket"] in [s.strip() for s in (r["support_sockets"] or "").split(",")]]

        bucket = cpu_tier_bucket(cpu.get("tier_rank"))
        if bucket in ("high", "flagship"):
            rows = [
                r for r in rows
                if r["cooler_type"] == "수랭" and (r["radiator_length_mm"] or 0) >= 390
            ]
        elif bucket == "mainstream":
            rows = [
                r for r in rows
                if r["cooler_type"] == "수랭" or (r["tdp_rating_w"] or 0) >= 150
            ]
        # entry는 별도 제한 없음(소켓 호환만 확인)

        # *** 신설(실사용자 제공 RAM 매칭 가이드 5절: "대장급 공랭 쿨러 사용 시
        # 방열판 높은 튜닝 RAM과 물리적 간섭") ***
        # cooler_products엔 "RAM 클리어런스"(첫 슬롯까지의 여유 공간) 컬럼이
        # 없어서 정확한 물리 치수 비교는 못 한다 — 대신 실무에서 흔히 쓰이는
        # 경험적 기준(공랭 쿨러 자체 높이 155mm 이상 = "대장급"으로 분류되는
        # 제품군, RAM 히트싱크 40mm 초과 = 간섭 위험이 실제로 자주 보고되는
        # 두께)으로 근사한다. 정확한 클리어런스 값이 나중에 추가되면 이
        # 근사 규칙을 교체하면 된다.
        ram = context.get("ram")
        ram_height = ram.get("heatsink_height_mm") if ram else None
        if ram_height and ram_height > 40:
            rows = [
                r for r in rows
                if r["cooler_type"] != "공랭" or (r["height_mm"] or 0) < 155
            ]
    elif stage == "psu":
        # *** 수정(실사용자 발견: "CPU+GPU 300~350W인데 PSU가 800W로 나옴") ***
        # gpu["recommended_psu_w"]는 다나와 스펙 원문("550W 이상")에서 그대로
        # 뽑은 값인데, 이건 GPU 제조사가 이미 "시스템 전체" 기준으로 안전
        # 마진까지 포함해서 제시하는 권장치다(GPU 자체 소비전력이 아님).
        # 여기에 다시 1.3배를 곱하면 마진이 이중으로 걸려서, 실사용
        # 300~350W 조합에 800W급이 붙는 과잉 스펙이 나왔다 — 카탈로그에
        # 600W/650W가 이미 있는데도 그쪽에 못 미쳤던 건 순전히 이 계산식
        # 문제였다(부품 부재 아님). 안전마진 10%만 추가로 얹는다.
        # recommended_psu_w 자체가 이미 제조사의 안전마진 포함 권장치라 추가
        # 마진 없이 그대로 최소 기준으로 쓴다(위 1.1배도 여전히 5W 차이로
        # 600W 정품을 걸러내는 경우가 있어 완전히 제거).
        #
        # *** 신설(실사용자 발견: "i9-14900KS+RTX4090에 550W PSU가 붙음") ***
        # GPU 데이터 하나에만 의존하면, 그 GPU의 recommended_psu_w 자체가
        # 부실하거나 잘못된 경우(예: 알려진 가격 이상치 상품처럼 스펙도
        # 같이 부실할 수 있음) PSU가 위험할 정도로 작게 나올 수 있다.
        # CPU 체급별 최소 하한선을 안전장치로 추가한다 — GPU 값이 부실해도
        # 이 하한선 밑으로는 절대 안 내려간다.
        cpu = context["cpu"]
        cpu_bucket = cpu_tier_bucket(cpu.get("tier_rank"))
        min_by_cpu = {"entry": 400, "mainstream": 500, "high": 650, "flagship": 750}.get(cpu_bucket, 400)
        gpu = context["gpu"]
        required_w = max(gpu["recommended_psu_w"] or 0, min_by_cpu)
        form = "SFX" if opt.placement == "미니 PC" else None
        rows = _fetch_all(conn, "power_products_v", "rated_w >= %s", (required_w,), media_category="power")
        # *** 신설(실사용자 제공 PSU 안전 가이드): 고성능 GPU(RTX 4070Ti/5070Ti/
        # 4080/5080/4090/5090급, tier_rank>=9)는 12VHPWR 케이블을 쓰는데,
        # PSU가 ATX 3.0/3.1 네이티브 지원이 아니면(구형 ATX + 변환젠더) 접촉
        # 불량/전류 쏠림으로 케이블 멜팅·화재 위험이 있다 — 상품명에
        # ATX3.0/3.1 또는 12VHPWR/12V-2x6 표기가 명시된 것만 후보로 남긴다
        # (그냥 "ATX 파워"라고만 된 건 구형으로 간주, 가이드 원문 판정 규칙).
        if (gpu.get("tier_rank") or 0) >= HIGH_POWER_GPU_TIER_THRESHOLD:
            rows = [r for r in rows if has_atx3_support(r["name"])]
        if form:
            rows = [r for r in rows if r["form_factor"] == form]
    elif stage == "case":
        mboard, cooler, gpu, psu = context["mboard"], context["cooler"], context["gpu"], context["psu"]
        rows = _fetch_all(conn, "case_products_v", media_category="case")
        rows = [r for r in rows if mboard["form_factor"] in [s.strip() for s in (r["support_form_factors"] or "").split(",")]]
        rows = [r for r in rows if (gpu["length_mm"] or 0) + 20 <= (r["max_vga_length_mm"] or 0)]
        rows = [r for r in rows if psu["form_factor"] and r["support_psu_form_factors"] and _psu_form_factor_matches(psu["form_factor"], r["support_psu_form_factors"])]
        if cooler["cooler_type"] == "공랭":
            rows = [r for r in rows if (cooler["height_mm"] or 0) <= (r["max_cooler_height_mm"] or 0)]
        # *** 수정(실제 스키마 연결): case_products에 수랭 라디에이터 지원 크기
        # 컬럼(support_radiator_mm)이 아직 없어서(나중에 추가 컬럼 작업 때 처리),
        # 수랭 쿨러를 고른 경우엔 케이스가 실제로 그 라디에이터를 넣을 수 있는지
        # 확인하지 않는다 — 실제 운영 전에는 반드시 채워야 하는 항목이다. ***
        if opt.placement == "미니 PC":
            rows = [r for r in rows if r["support_form_factors"] == "ITX"]
        elif opt.placement == "책상 위":
            # 책상 위에 놓기 좋은 미니타워/미들타워를 우선한다(상품명 기반 — 미니 PC처럼
            # 완전히 강제하지는 않는다, 조건을 만족하는 상품이 없으면 전체로 폴백).
            preferred = [r for r in rows if ("미니타워" in r["name"] or "미들타워" in r["name"])]
            if preferred:
                rows = preferred
        elif opt.placement == "책상 아래":
            preferred = [r for r in rows if ("미들타워" in r["name"] or "빅타워" in r["name"])]
            if preferred:
                rows = preferred

        if opt.rgb == "화려":
            preferred = [r for r in rows if ("RGB" in r["name"].upper())]
            if preferred:
                rows = preferred
        elif opt.rgb == "없음":
            preferred = [r for r in rows if ("RGB" not in r["name"].upper())]
            if preferred:
                rows = preferred
    else:
        rows = []

    if mode == "cost":
        rows.sort(key=lambda r: r["price_krw"])
    else:  # perf: 등급 높은 것 우선(CPU/GPU), 나머지는 비싼 것(더 좋은 것으로 간주) 우선
        if stage == "cpu" or stage == "gpu":
            rows.sort(key=lambda r: (-(r["tier_rank"] or 0), -r["price_krw"]))
        else:
            rows.sort(key=lambda r: -r["price_krw"])
    return rows


REVIEWABLE_STAGES = {"gpu", "mboard", "ram", "cooler", "psu", "case"}
MAX_REVIEW_RETRIES_PER_STAGE = 5  # 같은 스테이지에서 검수 거부가 반복될 때 API 호출 상한


def search(req: Requirements, opt: Options, mode: str,
           start_stage: str = "cpu", fixed_parts: dict | None = None,
           with_review: bool = False) -> BuildResult:
    """스택 기반 순차 결정 + 백트래킹 (기획서 2.2.1절).

    start_stage/fixed_parts: 부품 업그레이드 기능(2.5절)에서, CPU/GPU/메인보드처럼
    이미 확정된 앞단은 그대로 두고 특정 스테이지부터만 다시 탐색할 때 쓴다
    (예: RAM 용량 개선은 start_stage="ram", fixed_parts={"cpu":..., "gpu":..., "mboard":...}).

    *** 수정(실사용자 발견: "물리 스펙 없을 때 견적 생성이 몇 분씩 걸림") ***
    메인보드는 CPU만 보고 정해지는데, 백트래킹은 무조건 "바로 이전 스테이지"부터
    다시 시도한다 — 메인보드 실패가 GPU와 무관해도, GPU 후보 수만큼 메인보드를
    반복 조회하게 되어 CPU×GPU 조합 수만큼(수만 번) DB 쿼리가 발생했다.
    STAGE_DEPENDENCIES로 각 스테이지가 실제로 어떤 이전 스테이지에 의존하는지
    정의해두고, 그 의존 대상의 product_id만으로 캐시 키를 만들어 같은 조합을
    다시 조회하지 않도록 한다 — 탐색 순서 자체는 그대로 두고 중복 조회만 없앤다.

    *** 수정(실사용자 재요청: 단계별 누적 Gemini 검수) *** with_review=True면,
    각 스테이지에서 후보를 하나 고를 때마다(CPU는 비교 대상이 없어 제외,
    GPU부터 시작) "지금까지 확정된 부품 + 이번 후보"를 Gemini에 보내 검수한다.
    문제가 있다고 답하면 이 후보는 버리고 같은 스테이지의 다음 후보를 시도한다
    (기존 백트래킹 루프에 자연스럽게 편입 — 후보 소진과 동일하게 처리하되,
    "검수 탈락"과 "완전 소진"을 구분해서 review_notes에 남긴다). 같은 스테이지에서
    검수 탈락이 MAX_REVIEW_RETRIES_PER_STAGE번을 넘으면 더 이상 검수하지 않고
    그냥 다음 후보로 진행한다(API 호출 폭주 방지 — 예: 카탈로그 데이터 자체가
    부실해서 Gemini가 계속 다른 이유로 거부하는 경우를 대비).
    """
    fixed_parts = fixed_parts or {}
    start_idx = STAGES.index(start_stage)
    conn = get_connection()
    candidate_cache: dict[tuple, list[dict]] = {}
    review_notes: list[str] = []
    review_retry_count: dict[int, int] = {}  # stage_idx -> 이 스테이지에서 검수 거부 누적 횟수
    try:
        stack: list[tuple[int, dict]] = [(0, fixed_parts[s]) for s in STAGES[:start_idx]]
        stage_idx = start_idx
        candidate_idx = 0

        while True:
            if stage_idx == len(STAGES):
                parts = {STAGES[i]: stack[i][1] for i in range(len(STAGES))}
                total = sum(p["price_krw"] for p in parts.values())
                return BuildResult(parts=parts, total_price=total, status="ok", review_notes=review_notes)

            stage = STAGES[stage_idx]
            context = {STAGES[i]: stack[i][1] for i in range(stage_idx)}
            cache_key = (
                stage,
                tuple(context[dep]["product_id"] for dep in STAGE_DEPENDENCIES[stage] if dep in context),
            )
            if cache_key not in candidate_cache:
                candidate_cache[cache_key] = get_candidates(conn, stage, context, req, opt, mode)
            candidates = candidate_cache[cache_key]

            if candidate_idx >= len(candidates):
                # 이 스테이지 후보 소진 -> 백트래킹(2.2.1절)
                if stage_idx == start_idx:
                    return BuildResult(status="no_matching_product", message="해당하는 상품을 찾을 수 없습니다", review_notes=review_notes)
                stage_idx -= 1
                prev_idx, _ = stack.pop()
                candidate_idx = prev_idx + 1
                review_retry_count.pop(stage_idx, None)
                continue

            chosen = candidates[candidate_idx]

            if with_review and stage in REVIEWABLE_STAGES:
                retries = review_retry_count.get(stage_idx, 0)
                if retries < MAX_REVIEW_RETRIES_PER_STAGE:
                    trial_parts = dict(context)
                    trial_parts[stage] = chosen
                    review = gemini_review.review_partial(conn, trial_parts, stage)
                    if review and review["issue"]:
                        review_retry_count[stage_idx] = retries + 1
                        review_notes.append(
                            f"Gemini 검수: {chosen['name']} 거부됨({review['reason']}) — 다음 후보로 대체"
                        )
                        candidate_idx += 1
                        continue
                    elif review and retries == 0:
                        # 첫 시도에 바로 통과한 경우에만 "정상 통과" 로그를 남긴다(과도한 기록 방지)
                        pass

            stack.append((candidate_idx, chosen))
            stage_idx += 1
            candidate_idx = 0
    finally:
        conn.close()


def check_data_readiness(conn) -> str | None:
    """
    *** 신설(실사용자 발견: "물리 스펙 없을 때 견적 생성이 몇 분씩 걸리다 무한
    로딩") *** STAGE_DEPENDENCIES 캐싱은 "같은 조합을 두 번 조회 안 하는" 것만
    막아줄 뿐, 케이스처럼 메인보드+쿨러+GPU+PSU 4개에 동시에 의존하는 스테이지가
    스펙 데이터 자체가 하나도 없어서 무조건 실패하는 경우엔 여전히 그 4개
    조합 수만큼(수백만 번) 반복하게 된다 — 탐색을 시작하기 전에 각 스테이지의
    호환성 컬럼에 데이터가 조금이라도 있는지 미리 확인해서, 없으면 즉시
    실패 메시지를 준다(탐색 자체를 시도하지 않음).

    반환값: 문제없으면 None, 문제 있으면 사람이 읽을 안내 메시지.
    """
    checks = [
        ("cpu_products", "socket", "CPU 소켓"),
        ("mboard_products", "socket", "메인보드 소켓"),
        ("mboard_products", "form_factor", "메인보드 폼팩터"),
        ("mboard_products", "ram_type", "메인보드 RAM 규격"),
        ("mboard_products", "ram_slot_count", "메인보드 RAM 슬롯 수"),
        ("ram_products", "ram_type", "RAM 규격"),
        ("cooler_products", "support_sockets", "쿨러 지원 소켓"),
        ("cooler_products", "cooler_type", "쿨러 타입(공랭/수랭)"),
        ("vga_products", "recommended_psu_w", "GPU 권장 전력"),
        ("power_products", "rated_w", "PSU 정격 출력"),
        ("power_products", "form_factor", "PSU 폼팩터"),
        ("case_products", "support_form_factors", "케이스 지원 폼팩터"),
        ("case_products", "max_vga_length_mm", "케이스 최대 GPU 길이"),
        ("case_products", "support_psu_form_factors", "케이스 지원 PSU 폼팩터"),
    ]
    cursor = conn.cursor()
    missing = []
    for table, column, label in checks:
        cursor.execute(f"SELECT COUNT({column}) FROM {table}")
        (count,) = cursor.fetchone()
        if count == 0:
            missing.append(label)
    cursor.close()
    if missing:
        return (
            "물리 스펙 데이터가 아직 준비되지 않았습니다(" + ", ".join(missing) + " 없음) — "
            "spec_scraper.py 실행 또는 팀원 덤프 반영이 필요합니다."
        )
    return None

def build_cost_efficient(
    req: Requirements, opt: Options, budget: int,
    ssd_gb_min: int = 500, hdd_gb_min: int = 0,
) -> BuildResult:
    """가성비 모드(2.3절): CPU+GPU 최소 조합가가 예산보다 크면 즉시 종료(최적화).

    *** 수정(실사용자 발견: "성능 모드 최초 견적이 이미 예산을 초과") ***
    저장장치(SSD/HDD)는 STAGES에 없어서 search()가 아예 모르는 항목인데,
    예전엔 이 함수가 반환한 뒤 API 레이어에서 저장장치를 나중에 붙이면서
    예산 재확인을 전혀 안 했다 — 그래서 부품 7개로는 예산 안에 들어왔어도
    저장장치를 더하면 초과하는 사고가 났다. 이제 저장장치 가격을 먼저 계산해서
    "부품에 쓸 수 있는 예산"에서 미리 빼두고, 최종 결과에 저장장치를 포함해서
    반환한다 — 이러면 반환되는 total_price가 항상 실제 예산 이내임을 보장한다.
    """
    storage = select_storage(ssd_gb_min, hdd_gb_min)
    storage_price = sum(p["price_krw"] for p in storage.values() if p)
    parts_budget = budget - storage_price
    if parts_budget < 0:
        return BuildResult(
            status="budget_insufficient",
            message=f"저장장치 최저가({storage_price:,}원)만으로도 예산을 초과합니다",
        )

    conn = get_connection()
    readiness_issue = check_data_readiness(conn)
    if readiness_issue:
        conn.close()
        return BuildResult(status="no_matching_product", message=readiness_issue)
    cpus = get_candidates(conn, "cpu", {}, req, opt, "cost")
    gpus = get_candidates(conn, "gpu", {}, req, opt, "cost")
    conn.close()
    if not cpus or not gpus:
        return BuildResult(status="no_matching_product", message="요구 성능을 만족하는 CPU 또는 GPU가 없습니다")
    min_cpu_gpu = cpus[0]["price_krw"] + gpus[0]["price_krw"]
    if min_cpu_gpu > parts_budget:
        return BuildResult(
            status="budget_insufficient",
            message=f"최소한 {min_cpu_gpu + storage_price:,}원 이상의 예산이 필요합니다(CPU+GPU+저장장치 최저가 기준)",
        )
    result = search(req, opt, mode="cost", with_review=True)
    if result.status == "ok" and result.total_price > parts_budget:
        return BuildResult(
            status="budget_insufficient",
            message=f"최소 견적조차 예산을 초과합니다 — 최소한 {result.total_price + storage_price:,}원의 예산이 필요합니다",
        )
    return _attach_storage(result, storage)


def _attach_storage(result: BuildResult, storage: dict) -> BuildResult:
    """검색 결과(BuildResult)에 저장장치를 합쳐서 새 BuildResult를 만든다.
    build_cost_efficient/build_performance가 반환하는 결과에는 항상 저장장치가
    포함돼 있어야, 그 total_price가 실제로 지불해야 할 총액과 정확히 일치한다."""
    if result.status != "ok":
        return result
    parts = dict(result.parts)
    total = result.total_price
    for key in ("ssd", "hdd"):
        if storage.get(key):
            parts[key] = storage[key]
            total += storage[key]["price_krw"]
    return BuildResult(parts=parts, total_price=total, status="ok")


_STORAGE_OPTION_RE = re.compile(r"^\s*(?:(\d+)\s*[xX]\s*)?(\d+(?:\.\d+)?)\s*(GB|TB)", re.IGNORECASE)


def _parse_storage_option(option_name: str) -> tuple[int, int] | None:
    """다나와 SSD/HDD 옵션명에서 (단품 용량GB, 묶음 개수)를 뽑아낸다.
    SSD는 "512GB_1,549원/1GB", "1TB_980원/1GB" 형태(묶음 없음)이고,
    HDD는 그 외에 "2x12TB_77원/1GB"(12TB 2개 묶음, 서버·벌크용 판매 단위)
    형태도 있다 — 묶음 개수가 있으면 호출부에서 "일반 조립 PC엔 안 맞는
    벌크 상품"으로 보고 제외한다(케이스 안에 여러 개 넣을 자리를 확인하는
    로직이 없어서, 안전하게 단품만 후보로 삼는다)."""
    m = _STORAGE_OPTION_RE.match(option_name or "")
    if not m:
        return None
    pack_count = int(m.group(1)) if m.group(1) else 1
    size = float(m.group(2))
    unit = m.group(3).upper()
    capacity_gb = int(size * 1000) if unit == "TB" else int(size)
    return capacity_gb, pack_count


def _fetch_storage_options(conn, prefix: str, media_category: str, gb_min: int) -> list[dict]:
    """SSD/HDD를 상품 단위가 아니라 "옵션"(용량) 단위로 조회한다 — RAM과 동일한
    방식으로, capacity_gb 컬럼 없이 다나와 option_name에서 용량을 파싱한다.
    2개/4개 묶음(벌크) 표기가 있는 옵션은 일반 조립 PC 용도가 아니라고 보고
    제외하고, 단품(묶음 개수 1)만 후보로 남긴다.
    prefix: "ssd" 또는 "hdd" — {prefix}_products/{prefix}_prices 테이블을 조회한다."""
    cursor = conn.cursor(dictionary=True)
    cursor.execute(
        f"""
        SELECT p.product_id, p.name, pp.option_name, pp.price AS price_krw,
               m.image_url, m.product_url
        FROM {prefix}_products p
        JOIN {prefix}_prices pp ON pp.product_id = p.product_id
        LEFT JOIN product_media m ON m.category = '{media_category}' AND m.product_id = p.product_id
        WHERE pp.crawl_date = (SELECT MAX(crawl_date) FROM {prefix}_prices)
        """
    )
    rows = cursor.fetchall()
    cursor.close()

    options = []
    for row in rows:
        parsed = _parse_storage_option(row["option_name"])
        if parsed is None:
            continue
        capacity_gb, pack_count = parsed
        if pack_count != 1:
            continue  # 벌크(서버용) 묶음 상품 제외
        if capacity_gb < gb_min:
            continue
        options.append({
            "product_id": row["product_id"],
            "name": f"{row['name']} {row['option_name'].split('_')[0]}",
            "price_krw": row["price_krw"],
            "capacity_gb": capacity_gb,
            "image_url": row["image_url"],
            "product_url": row["product_url"],
        })
    return options


def select_storage(ssd_gb_min: int = 500, hdd_gb_min: int = 0) -> dict:
    """저장장치 선택 (기획서 10장 확인 필요 항목: 순차 결정 순서에 저장장치 단계가
    명시적으로 없어서, 어느 시점에 처리할지 미정 — 이 프로토타입에서는 잠정적으로
    다른 부품과 호환성 제약이 없는 독립 항목으로 보고, 메인 순차 결정과 별개로
    붙이는 후처리 단계로 둔다.

    *** 수정(RAM과 동일한 발견 적용): ssd_products/hdd_products에 용량(GB)
    컬럼은 없지만, 다나와 option_name에 용량이 이미 있어서 컬럼 추가 없이도
    실제 용량 요구사항을 검증할 수 있다. ***"""
    conn = get_connection()
    try:
        ssds = _fetch_storage_options(conn, "ssd", "ssd", ssd_gb_min)
        ssds.sort(key=lambda r: r["price_krw"])
        ssd = ssds[0] if ssds else None

        hdd = None
        if hdd_gb_min > 0:
            hdds = _fetch_storage_options(conn, "hdd", "hdd", hdd_gb_min)
            hdds.sort(key=lambda r: r["price_krw"])
            hdd = hdds[0] if hdds else None

        return {"ssd": ssd, "hdd": hdd}
    finally:
        conn.close()


def check_bottleneck(cpu_row: dict, gpu_row: dict) -> bool:
    """CPU-GPU 체급 불균형(병목) 여부 — 실제로는 Gemini가 PC 용도까지 감안해
    최종 검수한다(기획서 1.4/2.4절). 프로토타입에서는 등급 격차가 too 크면
    병목으로 보는 간단한 임시 규칙으로 대체한다.

    *** 수정(실제 스키마 연결): 이름 매칭(core/tiers.py) 대신 DB의
    tier_rank 컬럼을 직접 쓴다 — cpu_performance_tier_fix.sql 기준 CPU는
    1~25, gpu_performance_tier 기준 GPU는 1~14 스케일이라 정규화 분모를
    거기에 맞췄다. ***"""
    ct, gt = cpu_row.get("tier_rank"), gpu_row.get("tier_rank")
    if ct is None or gt is None:
        return False
    ct_norm, gt_norm = ct / 25, gt / 14
    return abs(ct_norm - gt_norm) > 0.55


# 성능 모드 다운그레이드 순서(2.4절): 가성비 모드의 정반대
DOWNGRADE_ORDER = ["case", "psu", "cooler", "ram", "mboard", "gpu", "cpu"]


def build_performance(
    req: Requirements, opt: Options, budget: int,
    ssd_gb_min: int = 500, hdd_gb_min: int = 0,
) -> BuildResult:
    """성능 모드(2.4절): 최대 견적을 만든 뒤 예산 초과 시 역순으로 다운그레이드.

    가성비 모드와 동일한 이유로, 저장장치 가격을 먼저 빼둔 "부품용 예산"
    기준으로 다운그레이드를 진행하고, 최종 결과에 저장장치를 포함해서
    반환한다 — 반환되는 total_price가 항상 budget 이내임을 보장한다.
    """
    storage = select_storage(ssd_gb_min, hdd_gb_min)
    storage_price = sum(p["price_krw"] for p in storage.values() if p)
    parts_budget = budget - storage_price
    if parts_budget < 0:
        return BuildResult(
            status="budget_insufficient",
            message=f"저장장치 최저가({storage_price:,}원)만으로도 예산을 초과합니다",
        )

    conn = get_connection()
    readiness_issue = check_data_readiness(conn)
    conn.close()
    if readiness_issue:
        return BuildResult(status="no_matching_product", message=readiness_issue)

    max_build = search(req, opt, mode="perf", with_review=True)
    if max_build.status != "ok":
        return max_build
    if max_build.total_price <= parts_budget:
        return _attach_storage(max_build, storage)

    # 다운그레이드 진행 상태: 각 스테이지별로 "현재 몇 단계 내렸는지" 인덱스를 추적
    conn = get_connection()
    review_notes: list[str] = []
    try:
        current = dict(max_build.parts)
        # 각 스테이지의 전체 후보를 비싼 순(perf 정렬)으로 캐싱해두고, 다운그레이드는
        # 그 리스트에서 한 칸씩 뒤로(더 저렴한 쪽으로) 이동하는 식으로 구현한다.
        candidate_cache: dict[str, list[dict]] = {}

        def candidates_for(stage):
            if stage not in candidate_cache:
                context = {s: current[s] for s in STAGES if s != stage}
                candidate_cache[stage] = get_candidates(conn, stage, context, req, opt, "perf")
            return candidate_cache[stage]

        cpu_gpu_floor_reached = False
        best_within_budget = None

        for stage in DOWNGRADE_ORDER:
            candidates = candidates_for(stage)
            try:
                cur_pos = next(i for i, c in enumerate(candidates) if c["product_id"] == current[stage]["product_id"])
            except StopIteration:
                cur_pos = 0

            review_retries = 0
            for next_pos in range(cur_pos + 1, len(candidates)):
                trial = dict(current)
                trial[stage] = candidates[next_pos]
                total = sum(p["price_krw"] for p in trial.values())

                bottleneck = check_bottleneck(trial["cpu"], trial["gpu"])
                if bottleneck:
                    continue  # ③ 병목 발생 -> 이 후보는 건너뛰고 다음 후보 시도

                if total <= parts_budget:
                    # *** 수정(실사용자 발견: "성능 모드에서 PSU 전력량 부족,
                    # 메인보드 등급 부족 — 다운그레이드가 검수를 안 받는다") ***
                    # 예산 안에 들어온 후보에 대해서만 검수한다(모든 시도마다
                    # 검수하면 호출이 폭발적으로 늘어난다 — 예산 안에 들어온
                    # 시점이 "이 스테이지에서 실제로 채택될 후보"이므로 검수
                    # 타이밍으로 적절하다). 검수 거부되면 이 후보를 버리고
                    # 계속 다음(더 싼) 후보를 시도한다 — 같은 스테이지에서
                    # 재시도가 MAX_REVIEW_RETRIES_PER_STAGE번을 넘으면 더 이상
                    # 검수하지 않고 그냥 채택한다(API 호출 상한).
                    if with_review := (review_retries < MAX_REVIEW_RETRIES_PER_STAGE):
                        review = gemini_review.review_partial(conn, trial, stage)
                        if review and review["issue"]:
                            review_retries += 1
                            review_notes.append(
                                f"Gemini 검수(다운그레이드): {trial[stage]['name']} 거부됨({review['reason']}) — 다음 후보로 대체"
                            )
                            continue

                    current = trial
                    candidate_cache.pop("mboard", None)
                    candidate_cache.pop("ram", None)
                    candidate_cache.pop("cooler", None)
                    candidate_cache.pop("psu", None)
                    candidate_cache.pop("case", None)

                    if best_within_budget is None or total > best_within_budget[0]:
                        best_within_budget = (total, dict(current))
                    break  # 이 스테이지에서는 예산 안에 들어왔으니 다음 스테이지로
                # ① 계속 예산 부족 -> 이 스테이지에서 더 낮출 후보가 있으면 계속 시도
            else:
                # ② 더 이상 대안 없음 -> 다음 순서의 부품 다운그레이드로 넘어감(그대로 유지)
                pass

            if stage in ("cpu", "gpu") and best_within_budget is None:
                cpu_gpu_floor_reached = True

        if best_within_budget is not None:
            total, parts = best_within_budget
            return _attach_storage(BuildResult(parts=parts, total_price=total, status="ok", review_notes=review_notes), storage)

        if cpu_gpu_floor_reached:
            return BuildResult(
                status="budget_insufficient",
                message="CPU/GPU까지 최소 옵션으로 내렸는데도 예산을 맞추지 못했습니다",
            )
        return BuildResult(status="budget_insufficient", message="예산 내 견적을 찾지 못했습니다")
    finally:
        conn.close()
