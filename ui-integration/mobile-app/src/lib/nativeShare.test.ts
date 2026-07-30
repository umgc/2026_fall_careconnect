import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import {
  canUseNativeShare,
  copyTextToClipboard,
  nativeShareResultMessage,
  shareNative,
} from "./nativeShare";

describe("nativeShare", () => {
  const originalShare = navigator.share;
  const originalCanShare = navigator.canShare;
  const originalClipboard = navigator.clipboard;

  beforeEach(() => {
    Object.defineProperty(navigator, "share", {
      configurable: true,
      value: undefined,
      writable: true,
    });
    Object.defineProperty(navigator, "canShare", {
      configurable: true,
      value: undefined,
      writable: true,
    });
  });

  afterEach(() => {
    Object.defineProperty(navigator, "share", {
      configurable: true,
      value: originalShare,
      writable: true,
    });
    Object.defineProperty(navigator, "canShare", {
      configurable: true,
      value: originalCanShare,
      writable: true,
    });
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: originalClipboard,
      writable: true,
    });
    vi.restoreAllMocks();
  });

  it("reports when native share is unavailable", () => {
    expect(canUseNativeShare()).toBe(false);
  });

  it("copies text when native share is missing", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText },
    });
    const result = await shareNative({
      title: "CareConnect",
      text: "Hello",
      url: "https://example.com/share",
    });
    expect(result).toBe("copied");
    expect(writeText).toHaveBeenCalled();
    const arg = writeText.mock.calls[0][0] as string;
    expect(arg).toContain("Hello");
    expect(arg).toContain("https://example.com/share");
  });

  it("opens navigator.share when available", async () => {
    const share = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "share", {
      configurable: true,
      value: share,
    });
    const result = await shareNative({
      title: "Invite",
      text: "Join my Care Circle",
      url: "https://careconnect.local/invite/abc",
    });
    expect(result).toBe("shared");
    expect(share).toHaveBeenCalled();
    const data = share.mock.calls[0][0] as ShareData;
    expect(data.title).toBe("Invite");
    expect(data.url).toBe("https://careconnect.local/invite/abc");
  });

  it("returns cancelled on AbortError", async () => {
    const share = vi.fn().mockRejectedValue(new DOMException("User cancelled", "AbortError"));
    Object.defineProperty(navigator, "share", {
      configurable: true,
      value: share,
    });
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn() },
    });
    const result = await shareNative({ title: "X", text: "Y", url: "https://z.test" });
    expect(result).toBe("cancelled");
  });

  it("maps result messages", () => {
    expect(nativeShareResultMessage("shared")).toMatch(/share sheet/i);
    expect(nativeShareResultMessage("copied")).toMatch(/clipboard/i);
    expect(nativeShareResultMessage("unsupported")).toMatch(/not supported/i);
    expect(nativeShareResultMessage("cancelled")).toBe("");
  });

  it("copyTextToClipboard uses clipboard API", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText },
    });
    await expect(copyTextToClipboard("abc")).resolves.toBe(true);
    expect(writeText).toHaveBeenCalledWith("abc");
  });
});
