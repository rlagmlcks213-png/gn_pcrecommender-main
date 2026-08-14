"""
부품 업그레이드 기능 (기획서 2.5절).

- CPU/GPU 성능 개선(2.5.1): DB의 tier_rank 기준 한 단계 위로 올리고 전체를
  다시 순차 결정한다. 이 과정에서 다른 부품이 원래 견적보다 다운그레이드되면
  이 업그레이드 자체를 무효로 처리한다.
- RAM 용량 개선(2.5.2): *** 현재 지원 중단 상태 ***. 실제 ram_products
  테이블에 용량(GB) 컬럼이 아직 없어서(추가 컬럼 작업 예정), "용량을 2배로"
  같은 개념 자체를 검증할 방법이 없다. 추가 컬럼 작업이 끝나기 전까지는
  호출하면 명확한 안내 메시지를 반환한다.
"""
from dataclasses import replace

from core.algorithm import (
    BuildResult, Requirements, Options, search,
)


def upgrade_cpu_gpu(base: BuildResult, req: Requirements, opt: Options) -> BuildResult:
    """2.5.1절: CPU/GPU 한 단계 상위로 고정 후 전체 재탐색. 다른 부품이
    원래 견적보다 다운그레이드(가격 하락)되면 업그레이드를 무효로 처리한다.

    *** 수정(실제 스키마 연결): 이름 매칭(core/tiers.py) 대신 DB의 tier_rank
    컬럼을 직접 쓴다. "한 단계 위"는 현재 tier_rank보다 큰 값 중 최솟값이
    아니라, 그냥 "현재값+1"을 최소 요구치로 넘긴다 — search()가 그 이상을
    만족하는 후보 중 가장 저렴한 걸 고르므로, 실제 카탈로그에 tier_rank가
    연속되지 않아도(예: 5 다음이 8) 자연스럽게 다음으로 존재하는 등급이
    선택된다. ***
    """
    if base.status != "ok":
        return BuildResult(status="no_matching_product", message="업그레이드할 기존 견적이 없습니다")

    cur_cpu_tier = base.parts["cpu"].get("tier_rank")
    cur_gpu_tier = base.parts["gpu"].get("tier_rank")
    if cur_cpu_tier is None or cur_gpu_tier is None:
        return BuildResult(
            status="no_matching_product",
            message="현재 CPU/GPU의 성능 등급(tier_rank)이 없어 업그레이드할 수 없습니다 — performance_tier.sql 적용 여부를 확인해주세요",
        )

    upgraded_req = replace(req, cpu_tier_min=cur_cpu_tier + 1, gpu_tier_min=cur_gpu_tier + 1)
    new_build = search(upgraded_req, opt, mode="cost", start_stage="cpu")
    if new_build.status != "ok":
        return BuildResult(status="no_matching_product", message="이미 카탈로그 최고 등급이거나, 한 단계 위를 만족하는 조합을 찾지 못했습니다")

    # 다른 부품이 원래 견적보다 다운그레이드(더 저렴한 것으로)됐는지 확인 — 2.5.1절 무효화 조건.
    for stage in ("mboard", "ram", "cooler", "psu", "case"):
        if new_build.parts[stage]["price_krw"] < base.parts[stage]["price_krw"]:
            return BuildResult(
                status="no_matching_product",
                message=f"업그레이드 시 {stage} 부품이 기존보다 낮은 등급으로 바뀌어 이 업그레이드를 적용할 수 없습니다",
            )
    return new_build


def upgrade_ram_capacity(base: BuildResult, req: Requirements, opt: Options,
                          target_gb: int | None = None) -> BuildResult:
    """2.5.2절: RAM 용량 개선.

    *** 현재 지원 중단 — 실제 ram_products 테이블에 용량(GB) 컬럼이 아직
    없어서(추가 컬럼 작업 예정) "용량을 늘린다"는 검증 자체가 불가능하다.
    컬럼이 채워지면 이 함수를 원래 로직(RAM 단계부터만 재탐색)으로 복원하면
    된다 — search()의 start_stage="ram" 기능은 이미 준비돼 있다. ***
    """
    return BuildResult(
        status="no_matching_product",
        message="RAM 용량 개선은 현재 지원되지 않습니다 — 실제 데이터에 RAM 용량 정보가 아직 없습니다(추가 컬럼 작업 예정)",
    )
