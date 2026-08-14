"""
프로토타입 API 서버 (기획서 3장은 Django+DRF를 명시하지만, 이 프로토타입
단계에서는 빠른 데모를 위해 Flask로 감쌌다 — core/ 모듈은 프레임워크와
무관하게 짜여있어서, 나중에 Django+DRF로 옮길 때 view 레이어만 새로 만들면
된다).

빌드 결과는 세션/DB에 저장하지 않고 요청-응답에 그대로 실어 나른다
(stateless) — 업그레이드 API를 호출할 때 프론트가 "현재 견적"을 그대로
돌려보내면 그걸 기준으로 다시 계산한다.

실행: python api/server.py  (기본 포트 5000)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from flask import Flask, request, jsonify
from flask_cors import CORS

from core.algorithm import (
    Requirements, Options, BuildResult, build_cost_efficient, build_performance,
    select_storage, merge_requirements,
)
from core.upgrade import upgrade_cpu_gpu, upgrade_ram_capacity
from db.db import get_connection

app = Flask(__name__)
CORS(app)


def build_result_to_json(result: BuildResult, storage: dict | None = None) -> dict:
    data = {"status": result.status, "message": result.message}
    if result.status == "ok":
        data["parts"] = result.parts
        data["total_price_krw"] = result.total_price
        data["review_notes"] = result.review_notes
        if storage:
            extra = 0
            if storage.get("ssd"):
                data["parts"]["ssd"] = storage["ssd"]
                extra += storage["ssd"]["price_krw"]
            if storage.get("hdd"):
                data["parts"]["hdd"] = storage["hdd"]
                extra += storage["hdd"]["price_krw"]
            data["total_price_krw"] += extra
    return data


def parse_requirements_and_options(body: dict) -> tuple[Requirements, Options, int, str]:
    """
    다중 게임/PC 용도 통합 (기획서 2.1절): 게임 여러 개, PC 용도 여러 개,
    또는 둘을 함께 선택할 수 있다. game_ids/usage_profile_ids 리스트로
    받아서 전부 병합(항목별 최댓값 채택)한다.

    게임을 하나도 안 고르고 PC 용도만으로 견적을 만드는 것도 가능하다
    (그 반대도 가능) — 최소 하나는 선택해야 한다.
    """
    game_ids = body.get("game_ids", [])
    usage_profile_ids = body.get("usage_profile_ids", [])
    if not game_ids and not usage_profile_ids:
        raise ValueError("게임 또는 PC 용도를 하나 이상 선택해주세요")

    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        rows = []
        if game_ids:
            placeholders = ", ".join(["%s"] * len(game_ids))
            cursor.execute(f"SELECT * FROM game_requirements WHERE id IN ({placeholders})", tuple(game_ids))
            # *** 수정(실제 스키마 연결): game_requirements는 usage_profiles와
            # 컬럼명이 다르다(cpu_tier_rank vs required_cpu_tier 등) — 여기서
            # 공통 이름으로 맞춰서 merge_requirements가 두 출처를 구분 없이
            # 섞어 처리할 수 있게 한다. ***
            for r in cursor.fetchall():
                rows.append({
                    "required_cpu_tier": r["cpu_tier_rank"] or 0,
                    "required_gpu_tier": r["gpu_tier_rank"] or 0,
                    "required_ram_gb": r["ram_gb"] or 8,
                    # *** 수정(실사용자 제공 "PC 용도별 견적 가이드"): 게임의
                    # storage_gb도 이제 다른 필드처럼 merge_requirements에서
                    # max()로 병합한다(이전엔 무시하고 "게임 있으면 무조건
                    # 1TB"라는 대충 정한 규칙을 따로 썼었다). ***
                    "required_ssd_gb": r.get("storage_gb") or 500,
                    "required_hdd_gb": 0,
                })
        if usage_profile_ids:
            placeholders = ", ".join(["%s"] * len(usage_profile_ids))
            cursor.execute(f"SELECT * FROM usage_profiles WHERE id IN ({placeholders})", tuple(usage_profile_ids))
            rows.extend(cursor.fetchall())
        if not rows:
            raise ValueError("선택하신 게임/PC 용도를 찾을 수 없습니다")

        req = merge_requirements(rows)
        opt = Options(
            placement=body.get("placement", "상관없음"),
            rgb=body.get("rgb", "상관없음"),
        )
        budget = int(body["budget_krw"])
        mode = body.get("mode", "cost")  # "cost" | "perf"
        return req, opt, budget, mode
    finally:
        cursor.close()
        conn.close()


@app.route("/api/games", methods=["GET"])
def list_games():
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT id, game_name FROM game_requirements ORDER BY game_name")
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify([{"id": r["id"], "title": r["game_name"]} for r in rows])


@app.route("/api/usage-profiles", methods=["GET"])
def list_usage_profiles():
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT id, code, display_name FROM usage_profiles ORDER BY id")
    rows = cursor.fetchall()
    cursor.close()
    conn.close()
    return jsonify([{"id": r["id"], "code": r["code"], "display_name": r["display_name"]} for r in rows])


@app.route("/api/builds", methods=["POST"])
def create_build():
    body = request.get_json()
    try:
        req, opt, budget, mode = parse_requirements_and_options(body)
    except (ValueError, KeyError) as e:
        return jsonify({"status": "error", "message": str(e)}), 400

    # *** 수정(실사용자 제공 "PC 용도별 견적 가이드"): 이전엔 "게임 선택
    # 여부"로만 대충 500GB/1TB를 나눴는데, 이제 game_requirements.storage_gb와
    # usage_profiles.required_ssd_gb/hdd_gb라는 정확한 근거가 생겨서
    # merge_requirements가 계산한 값(req.ssd_gb_min/hdd_gb_min)을 그대로
    # 쓴다. 프론트엔드가 명시적으로 ssd_gb_min을 보내면 그 값을 우선한다.
    ssd_gb_min = body.get("ssd_gb_min", req.ssd_gb_min)
    hdd_gb_min = body.get("hdd_gb_min", req.hdd_gb_min)
    # *** 수정(실사용자 발견: "게임만 선택했더니 SSD 128GB짜리가 매칭됨") ***
    # 가벼운 게임(롤/발로란트 등)은 game_requirements.storage_gb 자체가
    # 작게 들어있어서, 그 값을 그대로 쓰면 지금 시대에 안 맞는 너무 작은
    # SSD가 골라진다 — 게임을 하나라도 선택했으면 실사용을 감안해 최소
    # 1TB(SSD)+1TB(HDD)는 보장한다(더 큰 요구치가 이미 있으면 그대로 유지 —
    # max()라 3D렌더링처럼 이미 2TB/4TB인 경우는 안 줄어든다).
    if body.get("game_ids"):
        ssd_gb_min = max(ssd_gb_min, 1000)
        hdd_gb_min = max(hdd_gb_min, 1000)
    # *** 수정(실사용자 발견: "성능 견적 최초 금액이 이미 예산을 초과") ***
    # 예전엔 여기서 결과가 나온 "다음에" select_storage()로 저장장치를 따로
    # 붙이면서 예산 재확인을 안 했다 — 이제 build_cost_efficient/build_performance가
    # 저장장치 가격까지 포함해서 예산을 맞추고, 결과에도 이미 포함해서 돌려주므로
    # 여기서 또 붙일 필요가 없다(중복 방지).
    if mode == "perf":
        result = build_performance(req, opt, budget, ssd_gb_min=ssd_gb_min, hdd_gb_min=hdd_gb_min)
    else:
        result = build_cost_efficient(req, opt, budget, ssd_gb_min=ssd_gb_min, hdd_gb_min=hdd_gb_min)

    response = build_result_to_json(result)
    # 업그레이드 API에서 재사용할 수 있도록 요구사양/옵션도 같이 돌려준다(stateless).
    response["_requirements"] = {
        "cpu_tier_min": req.cpu_tier_min, "gpu_tier_min": req.gpu_tier_min,
        "ram_gb_min": req.ram_gb_min,
        "ssd_gb_min": req.ssd_gb_min, "hdd_gb_min": req.hdd_gb_min,
    }
    response["_options"] = {"placement": opt.placement, "rgb": opt.rgb}
    return jsonify(response)


def _rebuild_req_opt(body: dict) -> tuple[Requirements, Options]:
    r, o = body["_requirements"], body["_options"]
    req = Requirements(
        cpu_tier_min=r["cpu_tier_min"], gpu_tier_min=r["gpu_tier_min"], ram_gb_min=r["ram_gb_min"],
        ssd_gb_min=r.get("ssd_gb_min", 500), hdd_gb_min=r.get("hdd_gb_min", 0),
    )
    opt = Options(placement=o["placement"], rgb=o["rgb"])
    return req, opt


def _carry_storage_forward(result: BuildResult, original_parts: dict) -> dict | None:
    """
    업그레이드는 STAGES(cpu/gpu/mboard/ram/cooler/psu/case)만 다시 계산하고
    저장장치는 건드리지 않는다 — search()가 반환하는 BuildResult.parts에는
    애초에 ssd/hdd가 없어서(select_storage()가 별도로 붙이는 항목이라),
    업그레이드 후 응답을 만들 때 원래 있던 저장장치 정보를 다시 실어주지
    않으면 결과에서 저장장치가 사라진다 — 그 버그를 고친 부분이다.
    """
    if result.status != "ok":
        return None
    storage = {}
    if original_parts.get("ssd"):
        storage["ssd"] = original_parts["ssd"]
    if original_parts.get("hdd"):
        storage["hdd"] = original_parts["hdd"]
    return storage or None


@app.route("/api/builds/upgrade-cpu-gpu", methods=["POST"])
def upgrade_cpu_gpu_endpoint():
    body = request.get_json()
    req, opt = _rebuild_req_opt(body)
    base = BuildResult(parts=body["parts"], total_price=body["total_price_krw"], status="ok")
    result = upgrade_cpu_gpu(base, req, opt)
    storage = _carry_storage_forward(result, body["parts"])
    response = build_result_to_json(result, storage)
    response["_requirements"], response["_options"] = body["_requirements"], body["_options"]
    return jsonify(response)


@app.route("/api/builds/upgrade-ram", methods=["POST"])
def upgrade_ram_endpoint():
    body = request.get_json()
    req, opt = _rebuild_req_opt(body)
    base = BuildResult(parts=body["parts"], total_price=body["total_price_krw"], status="ok")
    result = upgrade_ram_capacity(base, req, opt, target_gb=body.get("target_gb"))
    storage = _carry_storage_forward(result, body["parts"])
    response = build_result_to_json(result, storage)
    response["_requirements"], response["_options"] = body["_requirements"], body["_options"]
    return jsonify(response)


if __name__ == "__main__":
    app.run(debug=False, port=5000)
