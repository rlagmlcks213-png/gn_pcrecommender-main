import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import LoadingBar from "../components/LoadingBar";
import {
  fetchGames, fetchUsageProfiles, createBuild,
  type GameOption, type UsageProfileOption, type BuildResponse,
} from "../api";
import { isMockMode, MOCK_GAMES, MOCK_USAGE_PROFILES, MOCK_BUILD_RESULT } from "../mockData";

const BUDGET_STEP = 100_000;

const BUDGET_QUICK_STEPS: { label: string; amount: number }[] = [
  { label: "1만원", amount: 10_000 },
  { label: "10만원", amount: 100_000 },
  { label: "100만원", amount: 1_000_000 },
];

const PLACEMENT_EXPLAIN: Record<string, string> = {
  "책상 위": "케이스를 미니타워·미들타워 크기 위주로 선택합니다.",
  "책상 아래": "케이스를 미들타워·빅타워 크기 위주로 선택합니다.",
  "미니 PC": "Mini-ITX 메인보드·케이스, SFX 파워로 초소형 구성을 만듭니다(가성비는 다소 낮아질 수 있어요).",
  "상관없음": "폼팩터 제한 없이 전체 카탈로그에서 선택합니다.",
};

const RGB_EXPLAIN: Record<string, string> = {
  "화려": "RGB 조명이 있는 케이스를 우선 선택합니다.",
  "없음": "RGB 조명이 없는 케이스만 선택합니다.",
  "상관없음": "RGB 유무와 무관하게 선택합니다.",
};

// 숫자로 변환하지 않고 콤마만 붙여서, 편집 중간에 있는 "0"들이 사라지지 않게 한다.
// (예: 200,000에서 앞의 2를 지우면 00,000 형태를 그대로 유지 -> 사용자가 이어서 자리를 채울 수 있음)
function formatDigits(digits: string): string {
  if (!digits) return "";
  return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// 커서 위치를 기준으로 "커서 앞에 숫자가 몇 개 있었는지" 센다.
function countDigitsBefore(text: string, cursorPos: number): number {
  return text.slice(0, cursorPos).replace(/[^0-9]/g, "").length;
}

// 포맷된 문자열에서 "앞에서부터 숫자 n개가 지난 지점"의 커서 위치를 찾는다.
function cursorPosForDigitCount(formatted: string, digitCount: number): number {
  if (digitCount <= 0) return 0;
  let count = 0;
  for (let i = 0; i < formatted.length; i++) {
    if (/[0-9]/.test(formatted[i])) {
      count++;
      if (count === digitCount) return i + 1;
    }
  }
  return formatted.length;
}

export default function Home() {
  const navigate = useNavigate();
  const [games, setGames] = useState<GameOption[]>([]);
  const [usageProfiles, setUsageProfiles] = useState<UsageProfileOption[]>([]);
  const [selectedGameIds, setSelectedGameIds] = useState<number[]>([]);
  const [selectedUsageIds, setSelectedUsageIds] = useState<number[]>([]);
  // 입력창에 보여줄 원본 숫자 "문자열"을 실제 상태로 두고, 계산에 쓸 숫자는 그때그때 파생시킨다.
  // (state를 곧바로 숫자로 바꿔버리면 편집 중간에 앞자리 0들이 뭉개져서 전체 값이 0이 되는 버그가 생김)
  const [budgetDigits, setBudgetDigits] = useState("2000000");
  const budget = Number(budgetDigits || "0");
  const budgetInputRef = useRef<HTMLInputElement>(null);
  const [placement, setPlacement] = useState("상관없음");
  const [rgb, setRgb] = useState("상관없음");
  const [mode, setMode] = useState<"cost" | "perf">("cost");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  // 유효성 검사 실패 시 어느 섹션으로 스크롤/강조할지 표시. nonce를 넣어서
  // 같은 섹션에서 연속으로 검증 실패해도(예: 제출을 두 번 누름) 매번 다시 스크롤/강조되게 한다.
  const [invalidSection, setInvalidSection] = useState<{ section: "selection" | "budget"; nonce: number } | null>(null);
  const selectionSectionRef = useRef<HTMLDivElement>(null);
  const budgetSectionRef = useRef<HTMLDivElement>(null);

  const mockActive = isMockMode();

  useEffect(() => {
    // ?mock=1 로 접속한 경우: 백엔드 서버 없이도 화면을 그대로 확인할 수 있도록
    // 실제 API 호출 없이 가짜 게임/용도 목록으로 즉시 채운다.
    if (mockActive) {
      setGames(MOCK_GAMES);
      setUsageProfiles(MOCK_USAGE_PROFILES);
      return;
    }
    fetchGames()
      .then(setGames)
      .catch(() => setError("게임 목록을 불러오지 못했습니다 — API 서버(http://127.0.0.1:5000)가 실행 중인지 확인해주세요."));
    fetchUsageProfiles().catch(() => {
      // 게임 목록 에러 메시지와 중복 노출하지 않도록 별도 처리는 생략(같은 서버 문제일 가능성이 큼)
    }).then((data) => {
      if (data) setUsageProfiles(data);
    });
  }, [mockActive]);

  // 검증 실패로 invalidSection이 설정되면 해당 섹션으로 스크롤하고, 잠시 반짝인 뒤 강조를 해제한다.
  useEffect(() => {
    if (!invalidSection) return;
    const target = invalidSection.section === "budget" ? budgetSectionRef.current : selectionSectionRef.current;
    target?.scrollIntoView({ behavior: "smooth", block: "center" });
    const timer = setTimeout(() => setInvalidSection(null), 1600);
    return () => clearTimeout(timer);
  }, [invalidSection]);

  const toggleGame = (id: number) => {
    setSelectedGameIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };
  const toggleUsage = (id: number) => {
    setSelectedUsageIds((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  };

  const handleBudgetChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const input = e.target;
    const rawValue = input.value;
    const cursorPos = input.selectionStart ?? rawValue.length;

    // 이번 입력으로 커서 "앞"에 숫자가 몇 개 있었는지 먼저 기억해둔다.
    const digitsBeforeCursor = countDigitsBefore(rawValue, cursorPos);
    // 최대 9자리(9억 9999만)까지만 허용해서 입력이 지나치게 길어지는 것을 막는다.
    const nextDigits = rawValue.replace(/[^0-9]/g, "").slice(0, 9);

    setBudgetDigits(nextDigits);

    // 리렌더링으로 값이 바뀐 뒤, 사용자가 편집하던 바로 그 자리에 커서를 되돌려놓는다.
    requestAnimationFrame(() => {
      const el = budgetInputRef.current;
      if (!el) return;
      const formatted = formatDigits(nextDigits);
      const pos = cursorPosForDigitCount(formatted, digitsBeforeCursor);
      el.setSelectionRange(pos, pos);
    });
  };
  const handleBudgetBlur = () => {
    // 입력을 마치면 편집 중 남아있던 불필요한 앞자리 0을 정리한다 (예: "007000" -> "7000").
    setBudgetDigits((prev) => (prev ? String(Number(prev)) : ""));
  };
  const stepBudget = (delta: number) => {
    setBudgetDigits((prev) => String(Math.max(0, Number(prev || "0") + delta)));
  };
  // 우클릭 시 브라우저 기본 컨텍스트 메뉴가 뜨지 않도록 막고, 해당 금액만큼 예산을 차감한다.
  const handleQuickStepContextMenu = (e: React.MouseEvent, amount: number) => {
    e.preventDefault();
    stepBudget(-amount);
  };

  const handleSubmit = async () => {
    if (selectedGameIds.length === 0 && selectedUsageIds.length === 0) {
      setError("게임 또는 PC 용도를 하나 이상 선택해주세요.");
      setInvalidSection({ section: "selection", nonce: Date.now() });
      return;
    }
    if (!budget || budget <= 0) {
      setError("예산을 입력해주세요.");
      setInvalidSection({ section: "budget", nonce: Date.now() });
      return;
    }
    setLoading(true);
    setError("");
    try {
      const selection = {
        budgetKrw: budget,
        gameTitles: games.filter((g) => selectedGameIds.includes(g.id)).map((g) => g.title),
        usageNames: usageProfiles.filter((u) => selectedUsageIds.includes(u.id)).map((u) => u.display_name),
        placement,
        rgb,
        mode,
      };
      let result: BuildResponse;
      if (mockActive) {
        // 목업 모드에서는 API 서버 없이 가짜 결과를 그대로 사용한다(네트워크 호출 자체를 하지 않음).
        result = MOCK_BUILD_RESULT;
      } else {
        result = await createBuild({
          game_ids: selectedGameIds,
          usage_profile_ids: selectedUsageIds,
          budget_krw: budget,
          placement,
          rgb,
          mode,
        });
      }
      navigate(mockActive ? "/result?mock=1" : "/result", { state: { result, selection } });
    } catch {
      setError("견적 생성 중 문제가 발생했습니다. API 서버가 실행 중인지 확인해주세요.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="app-shell">
      <h1>개인 PC 사양 추천 시스템</h1>

      {error && <div className="error-banner">{error}</div>}

      <div ref={selectionSectionRef} className={invalidSection?.section === "selection" ? "section-invalid" : ""}>
        <div className="result-section">
          <h3>플레이할 게임 (여러 개 선택 가능)</h3>
          <div className="option-row">
            {games.map((g) => (
              <button
                key={g.id}
                type="button"
                className={`option-chip ${selectedGameIds.includes(g.id) ? "active" : ""}`}
                onClick={() => toggleGame(g.id)}
              >
                {g.title}
              </button>
            ))}
          </div>
          <p className="form-hint">2개 이상 선택하면 항목별로 더 높은 사양을 채택합니다.</p>
        </div>

        <div className="result-section">
          <h3>PC 용도 (여러 개 선택 가능, 게임과 함께 선택해도 됩니다)</h3>
          <div className="option-row">
            {usageProfiles.map((u) => (
              <button
                key={u.id}
                type="button"
                className={`option-chip ${selectedUsageIds.includes(u.id) ? "active" : ""}`}
                onClick={() => toggleUsage(u.id)}
              >
                {u.display_name}
              </button>
            ))}
          </div>
          <p className="form-hint">게임을 선택하지 않고 용도만 골라도 됩니다 — 이 경우 입력하신 예산을 최대한 잘 쓴 견적을 보여드립니다.</p>
        </div>
      </div>

      <div className="result-section" ref={budgetSectionRef}>
        <h3>예산</h3>
        <div className={`form-group ${invalidSection?.section === "budget" ? "section-invalid" : ""}`}>
          <div className="budget-input-group">
            <input
              ref={budgetInputRef}
              type="text"
              inputMode="numeric"
              className="form-input"
              value={formatDigits(budgetDigits)}
              onChange={handleBudgetChange}
              onBlur={handleBudgetBlur}
              placeholder="예: 2,000,000"
            />
            <div className="budget-stepper">
              <button type="button" onClick={() => stepBudget(BUDGET_STEP)} aria-label="예산 10만원 증가">▲</button>
              <button type="button" onClick={() => stepBudget(-BUDGET_STEP)} aria-label="예산 10만원 감소">▼</button>
            </div>
          </div>
          <div className="budget-quick-steps">
            {BUDGET_QUICK_STEPS.map(({ label, amount }) => (
              <button
                key={label}
                type="button"
                className="budget-quick-step"
                onClick={() => stepBudget(amount)}
                onContextMenu={(e) => handleQuickStepContextMenu(e, amount)}
                aria-label={`예산 ${label} 조정 (좌클릭: 추가, 우클릭: 차감)`}
                title="좌클릭: 추가 / 우클릭: 차감"
              >
                {label}
              </button>
            ))}
          </div>
          <p className="form-hint">원 단위로 입력해주세요. 화살표를 누르면 10만원 단위로 조정됩니다. 아래 버튼은 좌클릭 시 추가, 우클릭 시 차감됩니다.</p>
        </div>
      </div>

      <div className="result-section">
        <h3>견적 유형</h3>
        <div className="mode-card-row">
          <div
            className={`mode-card ${mode === "cost" ? "active" : ""}`}
            onClick={() => setMode("cost")}
          >
            <div className="mode-title">가성비</div>
            <div className="mode-desc">요구 사양을 만족하는 최저가 조합</div>
          </div>
          <div
            className={`mode-card ${mode === "perf" ? "active" : ""}`}
            onClick={() => setMode("perf")}
          >
            <div className="mode-title">성능</div>
            <div className="mode-desc">예산 내 최대한 높은 사양 조합</div>
          </div>
        </div>
      </div>

      <div className="result-section">
        <h3>배치할 위치</h3>
        <div className="option-row">
          {["책상 위", "책상 아래", "미니 PC", "상관없음"].map((p) => (
            <button
              key={p}
              type="button"
              className={`option-chip ${placement === p ? "active" : ""}`}
              onClick={() => setPlacement(p)}
            >
              {p}
            </button>
          ))}
        </div>
        <p className="option-explain">{PLACEMENT_EXPLAIN[placement]}</p>
      </div>

      <div className="result-section">
        <h3>RGB 선호도</h3>
        <div className="option-row">
          {["화려", "없음", "상관없음"].map((r) => (
            <button
              key={r}
              type="button"
              className={`option-chip ${rgb === r ? "active" : ""}`}
              onClick={() => setRgb(r)}
            >
              {r}
            </button>
          ))}
        </div>
        <p className="option-explain">{RGB_EXPLAIN[rgb]}</p>
      </div>

      {loading && <LoadingBar text="부품 조합을 찾는 중입니다..." />}

      <button type="button" className="submit-button" disabled={loading} onClick={handleSubmit}>
        {loading && <span className="spinner" />}
        견적 생성
      </button>
    </div>
  );
}
