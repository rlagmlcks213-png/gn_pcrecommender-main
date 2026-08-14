/**
 * DB/백엔드 없이 프론트엔드 디자인 작업을 할 수 있도록 만든 가짜(mock) 데이터.
 *
 * 사용법:
 *   - http://localhost:5173/?mock=1        → 홈 화면에 가짜 게임/용도 칩이 채워짐,
 *                                             견적 생성도 API 호출 없이 가짜 결과로 이동
 *   - http://localhost:5173/result?mock=1  → 결과 화면을 바로 가짜 데이터로 미리보기
 *   - http://localhost:5173/confirm?mock=1 → 확정 화면을 바로 가짜 데이터로 미리보기
 *
 * 실제 DB가 연결되면 이 파일은 그대로 둬도 무해합니다(쿼리스트링 ?mock=1을 안 붙이면
 * 평소처럼 실제 API를 호출합니다). 나중에 필요 없어지면 지워도 됩니다.
 */
import type { BuildResponse, GameOption, UsageProfileOption } from "./api";
import type { Selection } from "./pages/Result";

export function isMockMode(): boolean {
  return new URLSearchParams(window.location.search).get("mock") === "1";
}

export const MOCK_GAMES: GameOption[] = [
  { id: 1, title: "리그 오브 레전드" },
  { id: 2, title: "발로란트" },
  { id: 3, title: "배틀그라운드" },
  { id: 4, title: "사이버펑크 2077" },
  { id: 5, title: "젤다의 전설: 왕국의 눈물(에뮬)" },
];

export const MOCK_USAGE_PROFILES: UsageProfileOption[] = [
  { id: 101, code: "office", display_name: "사무/문서작업" },
  { id: 102, code: "video_edit", display_name: "영상 편집" },
  { id: 103, code: "3d_render", display_name: "3D 렌더링" },
  { id: 104, code: "streaming", display_name: "방송/스트리밍" },
];

export const MOCK_BUILD_RESULT: BuildResponse = {
  status: "ok",
  message: "정상적으로 견적이 생성되었습니다.",
  total_price_krw: 2_187_000,
  review_notes: [
    "CPU와 GPU 성능 등급 격차가 크지 않아 병목 위험이 낮습니다.",
    "선택하신 게임 기준 권장 사양을 모두 충족합니다.",
  ],
  parts: {
    cpu: {
      product_id: 1001,
      name: "인텔 코어i5-14600K (랩터레이크-R)",
      price_krw: 349_000,
      image_url: null,
      product_url: "https://prod.danawa.com/info/?pcode=example1",
    },
    gpu: {
      product_id: 1002,
      name: "MSI 지포스 RTX 4070 슈퍼 벤투스 3X OC D6X 12GB",
      price_krw: 799_000,
      image_url: null,
      product_url: "https://prod.danawa.com/info/?pcode=example2",
    },
    mboard: {
      product_id: 1003,
      name: "MSI MAG B760M 마운틴에어 WIFI 디앤디컴",
      price_krw: 179_000,
      image_url: null,
      product_url: "https://prod.danawa.com/info/?pcode=example3",
    },
    ram: {
      product_id: 1004,
      name: "삼성전자 DDR5-5600 (16GB)",
      price_krw: 79_000,
      image_url: null,
      product_url: "https://prod.danawa.com/info/?pcode=example4",
      quantity: 2,
      unit_price_krw: 79_000,
    },
    ssd: {
      product_id: 1005,
      name: "삼성전자 990 PRO M.2 NVMe (1TB)",
      price_krw: 139_000,
      image_url: null,
      product_url: "https://prod.danawa.com/info/?pcode=example5",
    },
    cooler: {
      product_id: 1006,
      name: "DEEPCOOL AK400",
      price_krw: 39_000,
      image_url: null,
      product_url: "https://prod.danawa.com/info/?pcode=example6",
    },
    psu: {
      product_id: 1007,
      name: "마이크로닉스 Classic II 650W 80PLUS 브론즈",
      price_krw: 69_000,
      image_url: null,
      product_url: "https://prod.danawa.com/info/?pcode=example7",
    },
    case: {
      product_id: 1008,
      name: "darkFlash DLM22 메시 화이트",
      price_krw: 59_000,
      image_url: null,
      product_url: "https://prod.danawa.com/info/?pcode=example8",
    },
  },
  _requirements: { cpu_tier_min: 5, gpu_tier_min: 6, ram_gb_min: 32, ssd_gb_min: 1000, hdd_gb_min: 0 },
  _options: { placement: "책상 위", rgb: "상관없음" },
};

export const MOCK_SELECTION: Selection = {
  budgetKrw: 2_200_000,
  gameTitles: ["사이버펑크 2077"],
  usageNames: ["영상 편집"],
  placement: "책상 위",
  rgb: "상관없음",
  mode: "cost",
};
