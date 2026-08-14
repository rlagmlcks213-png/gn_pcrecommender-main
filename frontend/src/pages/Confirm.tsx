import { useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import type { BuildResponse, Part } from "../api";
import type { Selection } from "./Result";
import { isMockMode, MOCK_BUILD_RESULT, MOCK_SELECTION } from "../mockData";

const CATEGORY_LABELS: Record<string, string> = {
  cpu: "CPU", gpu: "GPU", mboard: "메인보드", ram: "RAM",
  cooler: "쿨러", psu: "PSU", case: "케이스", ssd: "저장장치(SSD)", hdd: "보조 저장장치(HDD)",
};
const CATEGORY_ORDER = ["cpu", "mboard", "gpu", "ram", "ssd", "hdd", "psu", "cooler", "case"];

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

export default function Confirm() {
  const location = useLocation();
  const navigate = useNavigate();
  const state = location.state as { result?: BuildResponse; selection?: Selection } | null;
  // /confirm?mock=1 로 바로 들어온 경우(홈→결과를 거치지 않은 경우)에도 목 데이터로 채운다.
  const result = state?.result ?? (isMockMode() ? MOCK_BUILD_RESULT : undefined);
  const selection = state?.selection ?? (isMockMode() ? MOCK_SELECTION : undefined);
  const [lightbox, setLightbox] = useState<{ url: string; name: string } | null>(null);

  if (!result || result.status !== "ok") {
    return (
      <div className="app-shell">
        <div className="error-banner">불러올 견적 정보가 없습니다.</div>
        <Link to="/">← 새 견적 만들기</Link>
      </div>
    );
  }

  const parts = result.parts!;
  const purposeText = [...(selection?.gameTitles ?? []), ...(selection?.usageNames ?? [])].join(", ") || "-";

  return (
    <div className="app-shell">
      <h1>✅ 견적 확정</h1>
      <p className="form-hint" style={{ marginBottom: "1.5rem" }}>
        아래 견적으로 최종 확정하셨습니다. 사진을 클릭하면 크게 볼 수 있고, 부품명을 클릭하면 다나와 상품 페이지로 이동합니다.
      </p>

      <div className="result-section">
        <h3>PC 용도</h3>
        <p style={{ margin: 0 }}>{purposeText}</p>
      </div>

      <div className="result-section">
        <h3>부품 목록</h3>
        <ul className="parts-list">
          {CATEGORY_ORDER.filter((k) => parts[k]).map((key) => {
            const part = parts[key];
            return (
              <li key={key} className="part-item part-item-with-thumb">
                <PartThumbnail part={part} onEnlarge={(url, name) => setLightbox({ url, name })} />
                <span className="part-name-block">
                  <strong>{CATEGORY_LABELS[key] ?? key}:</strong>{" "}
                  {part.product_url ? (
                    <a href={part.product_url} target="_blank" rel="noopener noreferrer">
                      {part.name} ↗
                    </a>
                  ) : (
                    part.name
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

      <button type="button" className="submit-button" onClick={() => navigate("/")}>
        새 견적 만들기
      </button>

      {lightbox && (
        <ImageLightbox url={lightbox.url} name={lightbox.name} onClose={() => setLightbox(null)} />
      )}
    </div>
  );
}
