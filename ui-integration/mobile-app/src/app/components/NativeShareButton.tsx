import React, { useState } from "react";
import { Check, Copy, Download, Share2, X } from "lucide-react";
import {
  canUseNativeShare,
  copyTextToClipboard,
  downloadShareFiles,
  nativeShareResultMessage,
  shareNative,
  type NativeSharePayload,
  type NativeShareResult,
} from "../../lib/nativeShare";

type ShareButtonVariant = "primary" | "secondary" | "icon";

export function NativeShareButton({
  payload,
  getPayload,
  label = "Share",
  color = "#00A7C8",
  variant = "primary",
  className = "",
  disabled = false,
  onResult,
  ariaLabel,
}: {
  /** Static payload, or use getPayload for async/lazy content (images, QR). */
  payload?: NativeSharePayload;
  getPayload?: () => NativeSharePayload | Promise<NativeSharePayload>;
  label?: string;
  color?: string;
  variant?: ShareButtonVariant;
  className?: string;
  disabled?: boolean;
  onResult?: (result: NativeShareResult) => void;
  ariaLabel?: string;
}) {
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);
  const [fallbackOpen, setFallbackOpen] = useState(false);
  const [lastPayload, setLastPayload] = useState<NativeSharePayload | null>(null);
  const [copied, setCopied] = useState(false);

  const flash = (msg: string) => {
    if (!msg) return;
    setFeedback(msg);
    window.setTimeout(() => setFeedback(null), 2800);
  };

  const resolvePayload = async (): Promise<NativeSharePayload | null> => {
    if (getPayload) return await getPayload();
    return payload ?? null;
  };

  const handleShare = async () => {
    if (busy || disabled) return;
    setBusy(true);
    try {
      const p = await resolvePayload();
      if (!p) return;
      setLastPayload(p);

      // Prefer OS sheet; if clearly unavailable, open fallback sheet first.
      if (!canUseNativeShare()) {
        setFallbackOpen(true);
        return;
      }

      const result = await shareNative(p);
      onResult?.(result);
      if (result === "shared") {
        flash(nativeShareResultMessage(result));
        return;
      }
      if (result === "cancelled") return;
      // Native share failed — show graceful fallback options
      setFallbackOpen(true);
      flash(nativeShareResultMessage(result));
    } finally {
      setBusy(false);
    }
  };

  const fallbackCopy = async () => {
    const p = lastPayload || (await resolvePayload());
    if (!p) return;
    const text = [p.text, p.url].filter(Boolean).join("\n");
    const ok = await copyTextToClipboard(text || p.title || "");
    setCopied(ok);
    if (ok) {
      onResult?.("copied");
      flash("Copied to clipboard");
      window.setTimeout(() => setCopied(false), 2000);
    }
  };

  const fallbackDownload = async () => {
    const p = lastPayload || (await resolvePayload());
    if (!p?.files?.length) return;
    const ok = await downloadShareFiles(p.files);
    if (ok) {
      onResult?.("downloaded");
      flash("Downloaded");
      setFallbackOpen(false);
    }
  };

  const baseClass =
    variant === "icon"
      ? "w-10 h-10 rounded-full flex items-center justify-center"
      : "flex items-center justify-center gap-1.5 font-bold rounded-xl transition-all";

  const style: React.CSSProperties =
    variant === "primary"
      ? { background: color, color: "white", minHeight: 44, opacity: disabled || busy ? 0.55 : 1 }
      : variant === "secondary"
        ? {
            background: "white",
            color: "#374151",
            border: "1.5px solid #E5E7EB",
            minHeight: 40,
            opacity: disabled || busy ? 0.55 : 1,
          }
        : { background: `${color}18`, color, opacity: disabled || busy ? 0.55 : 1 };

  return (
    <>
      <div className={`flex flex-col gap-1 ${className}`}>
        <button
          type="button"
          onClick={handleShare}
          disabled={disabled || busy}
          aria-label={ariaLabel || label}
          title="Share via your device apps (Messages, Email, WhatsApp, and more)"
          className={`${baseClass} ${variant !== "icon" ? "px-3 py-2.5 text-[13px]" : ""}`}
          style={style}
        >
          <Share2 size={variant === "icon" ? 18 : 16} aria-hidden />
          {variant !== "icon" && <span>{busy ? "Sharing…" : label}</span>}
        </button>
        {feedback && (
          <p className="text-[11px] font-semibold text-center" style={{ color }}>
            {feedback}
          </p>
        )}
      </div>

      {fallbackOpen && (
        <div className="fixed inset-0 z-[80] flex flex-col justify-end bg-black/40" role="dialog" aria-modal="true" aria-label="Share options">
          <div className="bg-white rounded-t-3xl px-5 pt-4 pb-8 max-h-[70%] overflow-y-auto">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <Share2 size={18} style={{ color }} />
                <div>
                  <p className="text-[16px] font-bold text-[#0F172A]">Share</p>
                  <p className="text-[12px] text-[#9CA3AF]">
                    Native share sheet unavailable — use a fallback
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setFallbackOpen(false)}
                className="w-8 h-8 rounded-full bg-[#F3F4F6] flex items-center justify-center"
                aria-label="Close"
              >
                <X size={16} className="text-[#6B7280]" />
              </button>
            </div>

            <p className="text-[13px] text-[#6B7280] mb-4 leading-relaxed">
              On supported phones and tablets, Share opens your system sheet with SMS, Email,
              WhatsApp, Messenger, Slack, Teams, AirDrop, Nearby Share, and other installed apps.
            </p>

            <div className="flex flex-col gap-2">
              <button
                type="button"
                onClick={fallbackCopy}
                className="w-full py-3.5 rounded-xl text-[14px] font-bold flex items-center justify-center gap-2 border"
                style={{
                  background: copied ? "#ECFDF5" : "white",
                  color: copied ? "#047857" : "#374151",
                  borderColor: "#E5E7EB",
                }}
              >
                {copied ? <Check size={16} /> : <Copy size={16} />}
                {copied ? "Copied" : "Copy link / text"}
              </button>
              {!!(lastPayload?.files?.length || payload?.files?.length) && (
                <button
                  type="button"
                  onClick={fallbackDownload}
                  className="w-full py-3.5 rounded-xl text-[14px] font-bold text-white flex items-center justify-center gap-2"
                  style={{ background: color }}
                >
                  <Download size={16} /> Download file
                </button>
              )}
              {canUseNativeShare() && (
                <button
                  type="button"
                  onClick={async () => {
                    setFallbackOpen(false);
                    await handleShare();
                  }}
                  className="w-full py-3 rounded-xl text-[13px] font-bold flex items-center justify-center gap-2"
                  style={{ background: `${color}18`, color }}
                >
                  <Share2 size={15} /> Try device share sheet again
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
