export default function LoadingBar({ text }: { text?: string }) {
  return (
    <>
      <div className="loading-bar-track">
        <div className="loading-bar-fill" />
      </div>
      {text && <p className="loading-status-text">{text}</p>}
    </>
  );
}
