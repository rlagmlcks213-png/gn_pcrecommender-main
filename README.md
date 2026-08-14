# 개인 PC 사양 추천 시스템 — 프로토타입

기획서·요구사항명세서(별도 문서)와 [neungjichai/Danawa-DB](https://github.com/neungjichai/Danawa-DB)의
SQL 스키마를 기반으로 만든 1단계 프로토타입입니다. **기존 Django 프로젝트(pc_recommender)는
전혀 재사용하지 않았습니다** — 완전히 새로 작성했습니다.

## 무엇이 들어있는가

| 파일 | 내용 |
|---|---|
| `db/schema.sql` | Danawa-DB 저장소의 `danawa_only_load.sql`(최종 테이블) + `add_compat_columns.sql`을 MySQL로 그대로 이식한 스키마 |
| `db/seed_data.sql` | 제조사 제한(기획서 1.3절)을 반영한 목업 데이터(프로토타입 단계는 고정 데이터로 동작 — 기획서 ECR-005) |
| `db/db.py` | DB 초기화/연결 헬퍼(MySQL) |
| `core/tiers.py` | CPU/GPU 성능 등급 고정 순서표(기획서 6장) — 벤치마크 점수 없이 이름 매칭만으로 등급 비교 |
| `core/algorithm.py` | 순차 결정 + 백트래킹 알고리즘(기획서 2.2절), 가성비 모드(2.3절), 성능 모드(2.4절), 저장장치 선택 |
| `core/upgrade.py` | 부품 업그레이드 기능(기획서 2.5절) — CPU/GPU 1단계 업그레이드, RAM 용량 개선 |
| `api/server.py` | Flask API 서버 — core/ 모듈을 HTTP로 노출(기획서는 Django+DRF지만 프로토타입 단계라 가볍게 구성) |
| `frontend/` | React + Vite + TypeScript 프론트엔드 — 예전 프로젝트와 같은 시각 스타일(다크 네이비 + 핑크 액센트) |
| `cli.py` | 실행 테스트 스크립트 |
| `inspect_db.py` | DB 데이터 확인용 스크립트 |

## DB — Danawa-DB 저장소 스키마를 그대로 사용 (MySQL)

`db/schema.sql`은 [Danawa-DB](https://github.com/neungjichai/Danawa-DB)의
`New_crawler/danawa_only_load.sql`(최종 products/prices 테이블 구조) +
`add_compat_columns.sql`(호환성 컬럼)을 그대로 이식했습니다.

**원본과 다른 점**:
- CSV 적재 중간 테이블(staging/unpivot/date_map)은 뺐습니다 — 원본은 실제 크롤링 결과 CSV를
  `LOAD DATA INFILE`로 읽는데, 그 CSV가 이 프로젝트엔 없어서 최종 테이블에 목업 데이터를 바로
  INSERT합니다.
- 저장소에 없는 컬럼을 일부 추가했습니다(`schema.sql`에 `★ 저장소에 없어서 추가` 주석으로 표시) —
  원본은 쿨러 냉각 용량(TDP 감당치)·라디에이터 크기·RAM/SSD/HDD 용량 컬럼이 없어서 수랭 매칭과
  용량 기반 검색이 불가능했습니다.
- 가격은 원본처럼 날짜별 이력 테이블(`cpu_prices` 등)로 관리하되, "최신 최저가"를 뽑는
  `*_products_v` 뷰를 추가해서 애플리케이션 코드가 매번 날짜 계산을 안 해도 되게 했습니다.

## MySQL 준비

```bash
pip install -r requirements.txt
```

환경변수(비워두면 기본값 `localhost:3306`, `root`, 빈 비밀번호, DB명 `DW_db`):
```bash
export DANAWA_DB_HOST=localhost
export DANAWA_DB_PORT=3306
export DANAWA_DB_USER=root
export DANAWA_DB_PASSWORD=원하는비밀번호
export DANAWA_DB_NAME=DW_db
```

## 실행 방법

**백엔드(터미널 1):**
```bash
python3 db/db.py       # 최초 1회 또는 스키마/데이터 변경 후 — DW_db 새로 생성
python3 api/server.py   # http://127.0.0.1:5000
```

**프론트엔드(터미널 2):**
```bash
cd frontend
npm install
npm run dev              # http://localhost:5173
```

브라우저에서 `http://localhost:5173` 접속 → 게임/용도 선택 → 예산·옵션 입력 →
견적 생성 → 결과 화면에서 CPU/GPU·RAM 업그레이드, 이전 단계 되돌리기, 확정까지
확인 가능합니다.

## 구현된 것

- **순차 결정 + 백트래킹**: CPU → GPU → 메인보드 → RAM → 쿨러 → PSU → 케이스 순서로 확정하며,
  한 카테고리 후보를 전부 소진하면 이전 카테고리로 돌아가 한 단계 업그레이드 후 재시도합니다
  (기획서 2.2.1절의 `1.2.8→1.2.9→1.2.10→1.3.1` 예시와 동일한 방식, 스택 기반으로 구현).
- **가성비 모드**: 오름차순 탐색으로 최저가 조합 하나를 도출. CPU+GPU 최저가 합이 예산을 넘으면
  즉시 예산 부족 안내.
- **성능 모드**: 예산 무시하고 최대 스펙 견적을 먼저 만든 뒤, 케이스→PSU→쿨러→RAM→메인보드→GPU→CPU
  순서로 한 단계씩 다운그레이드하며 예산에 맞춥니다.
- **부품 제조사 제한**: CPU=Intel, GPU=NVIDIA, 메인보드=MSI/ASUS, 쿨러=DEEPCOOL, RAM=삼성전자/TeamGroup,
  SSD=삼성전자, HDD=Western Digital, PSU=마이크로닉스, 케이스=darkFlash/앱코 (Danawa-DB 저장소의
  `danawa_only_load.sql`이 이미 이 제한을 WHERE절에 반영해두고 있어 그대로 이식했습니다).
- **입력 옵션 필터링**: 미니 PC 선택 시 ITX 메인보드/SFX 파워/ITX 케이스로 강제 매칭, 공랭/수랭 선택에
  따른 쿨러·케이스 매칭.
- **부품 업그레이드(2.5절)**: CPU/GPU를 6장 순서표 기준 한 단계 위로 올리고 전체 재탐색 — 다른 부품이
  원래 견적보다 다운그레이드되면 무효 처리(`upgrade_cpu_gpu`). RAM은 전체를 다시 안 돌리고 RAM 단계부터만
  재탐색(`upgrade_ram_capacity`) — `search()`에 `start_stage`/`fixed_parts` 옵션을 추가해서 구현.
- **저장장치(SSD/HDD) 선택**: `select_storage()` — 순차 결정 체인과 독립적으로, 요구 용량을 만족하는
  최저가를 고르는 후처리 단계로 잠정 구현(아래 "단순화한 것" 참고, 위치는 확인 필요 항목으로 남아있음).

## 프로토타입 단계에서 단순화한 것 (프로덕션 전환 시 반영 필요)

- **Gemini 검수(밸런스·병목 판단, 기획서 1.4/2.4절)는 실제 연동하지 않고, `check_bottleneck()`
  함수의 임시 규칙(CPU/GPU 등급 격차가 크면 병목으로 간주)으로 대체했습니다.** 실제로는 PC 용도까지
  감안한 Gemini 동적 프롬프트 검수가 필요합니다.
- **성능 모드의 다운그레이드는 완전한 최적해를 보장하지 않는 그리디(탐욕) 방식입니다** — 각 단계에서
  예산 안에 들어오는 첫 지점을 찾으면 그 단계는 더 낮추지 않고 다음 단계로 넘어갑니다. "예산에 가장
  근접한 조합"을 전역적으로 찾으려면 더 정교한 탐색(여러 후보를 끝까지 만들어 비교)이 필요합니다.
- **쿨러↔RAM 간섭(호환성 조건 9번)은 아직 구현하지 않았습니다** — 이 프로토타입 데이터셋에는 RAM
  히트싱크 높이/쿨러 하단 클리어런스 데이터가 없습니다.
- **API 서버는 Django+DRF가 아니라 Flask입니다** — 기획서 3장은 Django+DRF를 명시하지만, 프로토타입
  단계에서 빠른 데모를 위해 Flask로 감쌌습니다. `core/` 모듈은 프레임워크와 무관하게 짜여 있어서,
  나중에 Django+DRF로 옮길 때 view 레이어만 새로 만들면 됩니다.
- **빌드 결과는 세션/DB에 저장하지 않고 요청-응답에 그대로 실어 나릅니다(stateless)** — 프론트가
  "현재 견적" 전체를 업그레이드 API 호출 시 그대로 돌려보내면 그걸 기준으로 재계산합니다. 실제
  운영 시에는 세션/사용자별 저장이 필요합니다.
- **데이터는 전부 목업입니다** — 실제 운영 시에는 Danawa-DB 저장소의 크롤러(`spec_scraper.py`,
  `danawa_crawler.py`)로 실제 데이터를 수집해서 CSV로 만들고, 그걸 저장소 원본
  `danawa_only_load.sql`(staging 테이블 포함 전체 버전)로 적재해야 합니다. 이 프로토타입은 그
  단계를 건너뛰고 최종 테이블 구조에 목업 데이터를 바로 넣었습니다.
- **저장장치(SSD/HDD)는 순차 결정 체인 밖에서 별도로 선택합니다** — 기획서 10장에서 확인 필요
  항목으로 남겨둔 부분이라, 다른 부품과의 호환성 제약이 없다는 전제로 독립 후처리 단계로 잠정
  구현했습니다. 알고리즘 설계에서 정식 위치가 정해지면 옮겨야 합니다.
- **게임/용도 데이터가 예시로 일부만 들어있습니다**(`game_requirements`, `usage_profiles` 테이블) —
  기획서에서 정한 10~15개 전체는 아직 채우지 않았습니다.
