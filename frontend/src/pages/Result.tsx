import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { upgradeCpuGpu, upgradeRam, type BuildResponse, type Part } from "../api";
import LoadingBar from "../components/LoadingBar";
import { isMockMode, MOCK_BUILD_RESULT, MOCK_SELECTION } from "../mockData";

const CATEGORY_LABELS: Record<string, string> = {
  cpu: "CPU", gpu: "GPU", mboard: "메인보드", ram: "RAM",
  cooler: "쿨러", psu: "PSU", case: "케이스", ssd: "저장장치(SSD)", hdd: "보조 저장장치(HDD)",
};
const CATEGORY_ORDER = ["cpu", "mboard", "gpu", "ram", "ssd", "hdd", "psu", "cooler", "case"];

export interface Selection {
  budgetKrw: number;
  gameTitles: string[];
  usageNames: string[];
  placement: string;
  rgb: string;
  mode: "cost" | "perf";
}

function PartThumbnail({ part, onEnlarge }: { part: Part; onEnlarge: (url: string, name: string) => void }) {
  if (!part.image_url) {
    return <div className="part-thumb part-thumb-empty">?</div>;
  }
  return (
    <img
      src={part.image_url}
      alt={part.name}
      className="part-thumb"
      onClick={() => onEnlarge(part.image_url!, part.name)}
    />
  );
}

function ImageLightbox({ url, name, onClose }: { url: string; name: string; onClose: () => void }) {
  return (
    <div className="lightbox-backdrop" onClick={onClose}>
      <div className="lightbox-content" onClick={(e) => e.stopPropagation()}>
        <img src={url} alt={name} />
        <p className="lightbox-caption">{name}</p>
        <button type="button" className="lightbox-close" onClick={onClose}>닫기 ✕</button>
      </div>
    </div>
  );
}

export default function Result() {
  const location = useLocation();
  const navigate = useNavigate();
  const state = location.state as { result?: BuildResponse; selection?: Selection } | null;
  // 홈을 거치지 않고 /result?mock=1 로 바로 들어온 경우(예: 이 화면만 디자인 미리보기)에도
  // 목 데이터로 채운다. state가 이미 있으면(홈에서 넘어온 경우) 그걸 우선한다.
  const mockActive = isMockMode();
  const initial = state?.result ?? (mockActive ? MOCK_BUILD_RESULT : undefined);
  const selection = state?.selection ?? (mockActive ? MOCK_SELECTION : undefined);

  const [result, setResult] = useState<BuildResponse | undefined>(initial);
  const [history, setHistory] = useState<BuildResponse[]>([]);
  const [actionLoading, setActionLoading] = useState(false);
  const [actionError, setActionError] = useState("");
  const [lightbox, setLightbox] = useState<{ url: string; name: string } | null>(null);

  if (!result) {
    return (
      <div className="app-shell">
        <div className="error-banner">불러올 견적 정보가 없습니다.</div>
        <Link to="/">← 새 견적 만들기</Link>
      </div>
    );
  }

  const runAction = async (fn: () => Promise<BuildResponse>, failMessage: string) => {
    if (mockActive) {
      // 목업 모드에서는 백엔드가 없으므로 업그레이드 API를 호출하지 않고 안내만 표시한다.
      setActionError("목업 모드(?mock=1)에서는 업그레이드 기능을 사용할 수 없습니다. 실제 API 서버 연결 후 확인해주세요.");
      return;
    }
    setActionLoading(true);
    setActionError("");
    try {
      const next = await fn();
      if (next.status !== "ok") {
        setActionError(next.message || failMessage);
        return;
      }
      setHistory((h) => [...h, result]);
      setResult(next);
    } catch {
      setActionError(failMessage);
    } finally {
      setActionLoading(false);
    }
  };

  const handleRevert = () => {
    if (history.length === 0) return;
    setResult(history[history.length - 1]);
    setHistory((h) => h.slice(0, -1));
    setActionError("");
  };

  const handleConfirm = () => {
    navigate(mockActive ? "/confirm?mock=1" : "/confirm", { state: { result, selection } });
  };

  if (result.status !== "ok") {
    return (
      <div className="app-shell">
        <h1>견적 결과</h1>
        <div className="error-banner">{result.message || "해당하는 상품을 찾을 수 없습니다."}</div>
        <Link to="/">← 새 견적 만들기</Link>
      </div>
    );
  }

  const parts = result.parts!;

  return (
    <div className="app-shell">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "1rem" }}>
        <h1>견적 결과</h1>
        <Link to="/">← 새 견적 만들기</Link>
      </div>

      {actionError && <div className="error-banner">{actionError}</div>}

      {selection && (
        <div className="result-section">
          <h3>📋 선택하신 옵션</h3>
          <ul className="parts-list">
            <li className="part-item">
              <span><strong>예산:</strong> {selection.budgetKrw.toLocaleString()}원</span>
            </li>
            <li className="part-item">
              <span><strong>견적 유형:</strong> {selection.mode === "cost" ? "가성비" : "성능"}</span>
            </li>
            {selection.gameTitles.length > 0 && (
              <li className="part-item">
                <span><strong>게임:</strong> {selection.gameTitles.join(", ")}</span>
              </li>
            )}
            {selection.usageNames.length > 0 && (
              <li className="part-item">
                <span><strong>PC 용도:</strong> {selection.usageNames.join(", ")}</span>
              </li>
            )}
            <li className="part-item">
              <span><strong>배치할 위치:</strong> {selection.placement}</span>
            </li>
            <li className="part-item">
              <span><strong>RGB 선호도:</strong> {selection.rgb}</span>
            </li>
          </ul>
        </div>
      )}

      {result.review_notes && result.review_notes.length > 0 && (
        <div className="result-section review-notes-section">
          <h3>🤖 AI 검수 결과</h3>
          <ul className="parts-list">
            {result.review_notes.map((note, i) => (
              <li key={i} className="part-item">
                <span>{note}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="result-section">
        <h3>부품 목록</h3>
        <ul className="parts-list">
          {CATEGORY_ORDER.filter((k) => parts[k]).map((key) => {
            const part = parts[key];
            const qty = part.quantity ?? 1;
            return (
              <li key={key} className="part-item part-item-with-thumb">
                <PartThumbnail part={part} onEnlarge={(url, name) => setLightbox({ url, name })} />
                <span className="part-name-block">
                  <strong>{CATEGORY_LABELS[key] ?? key}:</strong> {part.name}
                  {qty > 1 && part.unit_price_krw != null && (
                    <span className="part-unit-price"> (개당 {part.unit_price_krw.toLocaleString()}원 × {qty}개)</span>
                  )}
                </span>
                <span className="part-price">{part.price_krw.toLocaleString()}원</span>
              </li>
            );
          })}
        </ul>
      </div>

      <div className="result-section">
        <h3>총 견적 금액</h3>
        <div className="total-price">{result.total_price_krw!.toLocaleString()}원</div>
      </div>

      <div className="result-section">
        <h3>⬆️ 업그레이드</h3>
        {actionLoading && <LoadingBar text="새 조합을 찾는 중입니다..." />}
        <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
          <button
            type="button"
            className="submit-button"
            style={{ width: "auto" }}
            disabled={actionLoading}
            onClick={() =>
              runAction(() => upgradeCpuGpu(result), "CPU/GPU를 한 단계 위로 올릴 수 없습니다(다른 부품 다운그레이드 발생 또는 최고 등급).")
            }
          >
            CPU/GPU 성능 개선
          </button>
          <button
            type="button"
            className="submit-button secondary"
            style={{ width: "auto" }}
            disabled={actionLoading}
            onClick={() => runAction(() => upgradeRam(result), "RAM 용량 개선은 현재 지원되지 않습니다(실제 데이터에 RAM 용량 정보가 아직 없습니다).")}
            title="실제 데이터에 RAM 용량 정보가 채워지면 지원될 예정입니다"
          >
            RAM 용량 개선 (준비중)
          </button>
        </div>
      </div>

      <div className="result-section" style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
        <button
          type="button"
          className="submit-button secondary"
          style={{ width: "auto" }}
          disabled={actionLoading || history.length === 0}
          onClick={handleRevert}
        >
          이전 단계로 되돌리기
        </button>
        <button
          type="button"
          className="submit-button"
          style={{ width: "auto" }}
          disabled={actionLoading}
          onClick={handleConfirm}
        >
          이 견적으로 확정
        </button>
      </div>

      {lightbox && (
        <ImageLightbox url={lightbox.url} name={lightbox.name} onClose={() => setLightbox(null)} />
      )}
    </div>
  );
}
