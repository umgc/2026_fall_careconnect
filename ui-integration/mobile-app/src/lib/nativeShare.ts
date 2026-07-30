/**
 * Web Share API helper — opens the OS native share sheet when available
 * (iOS UIActivityViewController / Android ACTION_SEND via the browser),
 * with clipboard + download fallbacks when native sharing is unavailable.
 */

export type NativeShareResult =
  | "shared"
  | "copied"
  | "downloaded"
  | "cancelled"
  | "unsupported";

export interface NativeShareFileInput {
  /** data: URL (e.g. canvas / QR PNG) */
  dataUrl?: string;
  blob?: Blob;
  file?: File;
  fileName?: string;
  mimeType?: string;
}

export interface NativeSharePayload {
  title?: string;
  text?: string;
  url?: string;
  files?: NativeShareFileInput[];
}

export function canUseNativeShare(): boolean {
  return typeof navigator !== "undefined" && typeof navigator.share === "function";
}

export function canShareFiles(): boolean {
  return (
    canUseNativeShare() &&
    typeof navigator.canShare === "function"
  );
}

export async function dataUrlToFile(
  dataUrl: string,
  fileName: string,
  mimeType = "image/png",
): Promise<File> {
  const res = await fetch(dataUrl);
  const blob = await res.blob();
  return new File([blob], fileName, { type: blob.type || mimeType });
}

async function resolveFiles(inputs: NativeShareFileInput[] = []): Promise<File[]> {
  const files: File[] = [];
  for (const input of inputs) {
    if (input.file) {
      files.push(input.file);
      continue;
    }
    if (input.blob) {
      files.push(
        new File([input.blob], input.fileName || "share.bin", {
          type: input.mimeType || input.blob.type || "application/octet-stream",
        }),
      );
      continue;
    }
    if (input.dataUrl) {
      files.push(
        await dataUrlToFile(
          input.dataUrl,
          input.fileName || "share.png",
          input.mimeType || "image/png",
        ),
      );
    }
  }
  return files;
}

export async function copyTextToClipboard(text: string): Promise<boolean> {
  if (!text) return false;
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    // fall through
  }
  try {
    const ok = window.prompt("Copy this content:", text);
    return ok !== null;
  } catch {
    return false;
  }
}

export function downloadBlob(blob: Blob, fileName: string): void {
  const href = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = href;
  a.download = fileName;
  a.rel = "noopener";
  document.body.appendChild(a);
  a.click();
  a.remove();
  window.setTimeout(() => URL.revokeObjectURL(href), 1500);
}

export async function downloadShareFiles(inputs: NativeShareFileInput[]): Promise<boolean> {
  const files = await resolveFiles(inputs);
  if (!files.length) return false;
  for (const file of files) {
    downloadBlob(file, file.name);
  }
  return true;
}

function buildClipboardText(payload: NativeSharePayload): string {
  const parts: string[] = [];
  if (payload.text?.trim()) parts.push(payload.text.trim());
  if (payload.url?.trim() && !parts.some(p => p.includes(payload.url!))) {
    parts.push(payload.url.trim());
  }
  return parts.join("\n");
}

/**
 * Opens the device native share sheet when supported.
 * On failure / unsupported browsers: copies text/url, or downloads files.
 */
export async function shareNative(payload: NativeSharePayload): Promise<NativeShareResult> {
  const title = payload.title?.trim() || "CareConnect";
  const text = payload.text?.trim() || "";
  const url = payload.url?.trim() || "";
  const clipboardText = buildClipboardText(payload);

  let files: File[] = [];
  try {
    files = await resolveFiles(payload.files);
  } catch {
    files = [];
  }

  if (canUseNativeShare()) {
    try {
      const data: ShareData = { title };
      if (text) data.text = url && !text.includes(url) ? `${text}\n${url}` : text;
      else if (url) data.text = url;
      if (url) data.url = url;

      if (files.length && typeof navigator.canShare === "function") {
        try {
          if (navigator.canShare({ files })) {
            data.files = files;
          }
        } catch {
          // Share without files
        }
      }

      // Some browsers reject empty ShareData — ensure at least text or url or files
      if (!data.text && !data.url && !data.files?.length) {
        data.text = title;
      }

      await navigator.share(data);
      return "shared";
    } catch (err) {
      const name = err instanceof DOMException ? err.name : "";
      if (name === "AbortError") return "cancelled";
      // Fall through to graceful fallback
    }
  }

  if (files.length) {
    try {
      await downloadShareFiles(payload.files || []);
      if (clipboardText) await copyTextToClipboard(clipboardText);
      return clipboardText ? "copied" : "downloaded";
    } catch {
      // continue to copy-only
    }
  }

  if (clipboardText) {
    const ok = await copyTextToClipboard(clipboardText);
    return ok ? "copied" : "unsupported";
  }

  return "unsupported";
}

export function nativeShareResultMessage(result: NativeShareResult): string {
  switch (result) {
    case "shared":
      return "Opened your device share sheet";
    case "copied":
      return "Sharing unavailable — content copied to clipboard";
    case "downloaded":
      return "Sharing unavailable — file downloaded";
    case "cancelled":
      return "";
    case "unsupported":
      return "Sharing is not supported on this device. Try Copy or Download.";
  }
}
