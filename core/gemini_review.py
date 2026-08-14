"""
Gemini 단계별 누적 검수 (기획서 1.4/2.6/5.3절).

*** 수정(실사용자 재요청 — 설계 전면 변경) ***
이전엔 "완성된 견적 하나에 대해 딱 한 번"만 검수했는데, 사용자가 명확히
정정했다: "검수를 남발하지 말라"는 건 매 **후보 시도**마다(백트래킹 중
버려지는 조합까지) 검수하지 말라는 뜻이지, 스테이지 자체를 건너뛰라는
뜻이 아니었다. 올바른 흐름은:

  CPU+GPU 확정 -> 검수 -> 메인보드 확정(CPU에 맞춰) -> 검수 ->
  RAM 확정(메인보드에 맞춰) -> 검수 -> 쿨러 확정(CPU에 맞춰) -> 검수 ->
  PSU 확정(GPU에 맞춰) -> 검수 -> 케이스 확정(전부에 맞춰) -> 검수

즉 "지금까지 확정된 부품들끼리" 한 단계 늘어날 때마다 서로 잘 맞는지
누적 검수한다. 특히 쿨러 단계에서 CPU 발열/스로틀링을, PSU 단계에서
80PLUS 인증과 ATX 3.0/12VHPWR 케이블 호환성을, 케이스 단계에서 통풍을
집중적으로 봐야 한다는 요구가 있었다(반복적으로 발열/스로틀링/파워
규격 문제가 새어나갔기 때문).

정상 흐름(모든 스테이지가 첫 후보에서 바로 통과)이면 빌드 하나당 검수
호출은 6번(CPU+GPU, 메인보드, RAM, 쿨러, PSU, 케이스) 정도로 고정되고,
백트래킹 중 버려지는 조합에 대해서는 호출하지 않는다 — CPU 단독은
비교할 대상이 없어 검수하지 않는다(GPU와 묶어서 첫 검수 지점으로 삼음).

*** 중요: 이 모듈은 실제 Gemini API(generativelanguage.googleapis.com)를
호출한다 — 이 API는 이 개발 환경(샌드박스)의 네트워크 허용 목록에 없어서
여기서는 직접 테스트하지 못했다. 실제 API 키가 있는 실행 환경에서 확인이
필요하다. ***
"""
import json
import os

import requests

from core.psu_rules import has_atx3_support, extract_80plus_tier

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.6-flash")
GEMINI_URL = (
    f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"
)

_LABELS = {
    "cpu": "CPU", "gpu": "GPU", "mboard": "메인보드", "ram": "RAM",
    "cooler": "쿨러", "psu": "PSU", "case": "케이스",
}

# 스테이지별로 특히 중점적으로 봐야 할 관점(사용자가 반복 지적한 항목들)
_STAGE_FOCUS = {
    "gpu": "CPU와 GPU의 성능 체급이 심하게 어긋나지 않는지(병목).",
    "mboard": "CPU 소켓/칩셋과 메인보드가 실제로 호환되는지, GPU 체급에 맞는 전원부(VRM) 등급인지.",
    "ram": "메인보드가 지원하는 RAM 규격(DDR4/DDR5)과 슬롯 수에 맞는지.",
    "cooler": "CPU의 발열(TDP)을 이 쿨러가 실제로 감당할 수 있는지 — 특히 i7-K/i9(또는 Ultra7/9) 급인데 "
              "공랭이 선택됐다면 서멀 스로틀링 위험이 매우 높으니 반드시 지적할 것.",
    "psu": "PSU 안전성 검수 — 아래는 이미 상품명 키워드로 1차 확인된 항목이니 "
           "여기 적힌 값을 신뢰하고, 그 외 상품명만으로는 알 수 없는 항목만 판단하세요:\n"
           "  (1) '정격출력 여유율': 이 PSU 출력이 CPU+GPU 실사용 전력 대비 30~50% 이상 "
           "여유가 있는지 다시 한 번 확인하세요.\n"
           "  (2) '보호회로'(SCP/OPP/OVP/UVP/OCP/OTP, 특히 SCP·OTP)와 '+12V 싱글레일 "
           "가동률 95% 이상'은 상품명만으로는 알 수 없으니, 주어진 스펙 정보에서 확인되면 "
           "판단하고 스펙이 아예 없으면 '정보 부족'이라고만 표시하고 issue를 true로 만들지 "
           "마세요.\n"
           "  주의: 'ATX 파워'라는 표기는 단순 물리 규격(폼팩터)일 뿐 최신 전력 규격과 "
           "무관합니다 — ATX3.0/3.1 지원 여부는 이미 별도로 확인됐으니 이 프롬프트에서는 "
           "판단하지 마세요.",
    "case": "케이스의 통풍(전면 패널 구조)과 내부 공간이 지금까지 고른 부품(특히 발열이 큰 쿨러/GPU)을 "
            "수용하기에 충분한지.",
}

_REVIEW_PROMPT_TEMPLATE = """당신은 PC 견적 검수 전문가입니다. 지금까지 확정된 부품 조합을 검토해서
JSON으로만 답변하세요(다른 설명 없이 JSON만).

[지금까지 확정된 부품]
{parts_summary}

[이번에 검수할 항목]
방금 "{latest_label}" 단계가 확정됐습니다. 지금까지의 다른 부품들과 물리적/전기적/
발열 측면에서 문제가 없는지 확인하세요. 특히 다음 관점을 중점적으로 보세요:
{focus}

가격이 싸다는 것 자체는 문제가 아닙니다 — 실제 호환/발열/안전 문제가 있는
경우만 issue를 true로 답하세요. 문제가 있다면, 같은 역할(같은 부품 카테고리)
안에서 실제로 존재할 법한 구체적인 대체 모델명을 suggested_model에
적으세요(모르면 빈 문자열).

반드시 이 형식의 JSON만 출력하세요:
{{"issue": true 또는 false, "reason": "이유(문제 없으면 빈 문자열)", "suggested_model": ""}}
"""


def _spec_lines(conn, category: str, product_id: int, keys: list[str]) -> list[str]:
    cursor = conn.cursor(dictionary=True)
    placeholders = ", ".join(["%s"] * len(keys))
    cursor.execute(
        f"""
        SELECT spec_key, spec_value FROM danawa_spec_summary
        WHERE category = %s AND product_id = %s
          AND (spec_key IN ({placeholders}) OR spec_value REGEXP %s)
        LIMIT 10
        """,
        (category, product_id, *keys, "|".join(keys)),
    )
    rows = cursor.fetchall()
    cursor.close()
    return [f"{r['spec_key'] or '(항목)'}: {r['spec_value']}" for r in rows]


_SPEC_CATEGORY = {
    "cpu": "cpu", "gpu": "vga", "mboard": "mboard", "ram": "ram",
    "cooler": "cooler", "psu": "power", "case": "case",
}
_SPEC_KEYWORDS = {
    "cooler": ["TDP", "소켓"],
    "psu": ["80PLUS", "인증", "핀", "케이블"],
    "case": ["측면", "전면", "통풍", "메쉬"],
    "gpu": ["전원", "TDP", "TGP"],
}


def _build_parts_summary(conn, parts: dict) -> str:
    lines = []
    for key, label in _LABELS.items():
        if key not in parts:
            continue
        p = parts[key]
        lines.append(f"- {label}: {p['name']} ({p['price_krw']:,}원)")
        if key == "psu":
            # *** 신설(실사용자 제공 PSU 매칭 가이드) *** ATX3.0/3.1 지원 여부와
            # 80PLUS 등급은 이미 상품명 키워드로 결정론적으로 판정했으니, 그
            # 결과를 그대로 알려줘서 Gemini가 다시 판단하다 혼동하지 않게 한다
            # ("ATX 파워" 표기만 보고 최신 규격으로 오판하는 걸 방지).
            atx3 = has_atx3_support(p["name"])
            tier = extract_80plus_tier(p["name"])
            lines.append(
                f"  (사전 확인됨: ATX3.0/3.1 또는 12VHPWR 지원={'예' if atx3 else '아니오(구형 ATX로 간주)'}, "
                f"80PLUS 등급={tier or '표기 없음(무인증으로 간주)'})"
            )
        keywords = _SPEC_KEYWORDS.get(key)
        if keywords:
            specs = _spec_lines(conn, _SPEC_CATEGORY[key], p["product_id"], keywords)
            if specs:
                lines.append(f"  (관련 스펙: {'; '.join(specs)})")
    return "\n".join(lines)


def review_partial(conn, parts: dict, latest_stage: str) -> dict | None:
    """지금까지 확정된 부품(parts)에 방금 latest_stage 부품이 새로 추가된
    상태를 검수한다. conn은 이미 열려있는 DB 커넥션을 재사용한다.
    반환: {"issue": bool, "reason": str, "suggested_model": str} 또는
    (API 키 없음/호출 실패 시) None — 이 경우 호출부는 검수를 통과한 것으로
    간주하고 진행한다(검수는 안전망이지 필수 관문이 아님)."""
    if not GEMINI_API_KEY:
        print(f"[gemini_review] ({latest_stage}) GEMINI_API_KEY가 없어 검수를 건너뜁니다.")
        return None

    focus = _STAGE_FOCUS.get(latest_stage, "전체적인 호환성.")
    prompt = _REVIEW_PROMPT_TEMPLATE.format(
        parts_summary=_build_parts_summary(conn, parts),
        latest_label=_LABELS.get(latest_stage, latest_stage),
        focus=focus,
    )
    try:
        resp = requests.post(
            GEMINI_URL,
            headers={"x-goog-api-key": GEMINI_API_KEY, "Content-Type": "application/json"},
            json={
                "contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {"temperature": 0.2, "responseMimeType": "application/json"},
            },
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        parsed = json.loads(text)
        result = {
            "issue": bool(parsed.get("issue", False)),
            "reason": str(parsed.get("reason", "")),
            "suggested_model": str(parsed.get("suggested_model", "")),
        }
        print(f"[gemini_review] ({latest_stage}) 검수 완료 — issue={result['issue']}, reason='{result['reason']}'")
        return result
    except Exception as e:
        print(f"[gemini_review] ({latest_stage}) 검수 호출 실패, 건너뜀: {e}")
        return None


def find_best_match(candidates: list[dict], suggested_model: str, exclude_id: int) -> dict | None:
    """Gemini가 제안한 모델명(suggested_model)과 가장 가깝게 일치하는 상품을
    후보 목록에서 찾는다. 토큰(공백 기준) 일치 개수로 점수를 매기고, 정확히
    일치하는 게 없으면 현재 상품을 제외한 다음(가장 저렴한) 후보로 폴백한다."""
    others = [c for c in candidates if c["product_id"] != exclude_id]
    if not others:
        return None
    if suggested_model:
        tokens = [t for t in suggested_model.replace("-", " ").split() if len(t) >= 2]
        if tokens:
            scored = [(sum(1 for t in tokens if t in c["name"]), c) for c in others]
            scored.sort(key=lambda x: (-x[0], x[1]["price_krw"]))
            if scored[0][0] > 0:
                return scored[0][1]
    return others[0]
