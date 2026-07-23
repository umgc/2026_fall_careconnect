import { describe, expect, it } from "vitest";
import {
  classifyMail,
  classifyMailImportance,
  searchMailPieces,
  PRIORITY_META,
  CATEGORY_META,
  type MailPiece,
} from "../app/MailDigest";

describe("classifyMail priority & categories", () => {
  it("flags legal summons as immediate critical", () => {
    const c = classifyMail("County Court summons appearance required", false);
    expect(c.priority).toBe("immediate");
    expect(c.category).toBe("critical");
    expect(c.subcategory).toBe("legal");
  });

  it("classifies utility bills as financial action soon", () => {
    const c = classifyMail("City Power monthly utility bill payment due", false);
    expect(c.category).toBe("financial");
    expect(c.subcategory).toBe("bills");
    expect(["immediate", "action_soon"]).toContain(c.priority);
  });

  it("classifies coupons as promotional low value", () => {
    const c = classifyMail("Weekend sale! Coupons and sweepstakes inside", false);
    expect(c.priority).toBe("promotional");
    expect(c.category).toBe("promotional");
  });

  it("classifies missed delivery notices", () => {
    const c = classifyMail("USPS we missed you redelivery pickup notice", false);
    expect(c.category).toBe("deliveries");
    expect(c.subcategory).toBe("missed_delivery");
    expect(c.priority).toBe("action_soon");
  });

  it("AI assist can boost medical wording", () => {
    const c = classifyMail("member benefit notice available", true);
    expect(c.source).toBe("ai_assist");
    expect(c.subcategory).toBe("medical");
  });

  it("legacy importance mapper still works", () => {
    const r = classifyMailImportance("final notice collections past due", false);
    expect(r.importance).toBe("critical");
  });
});

describe("searchMailPieces", () => {
  const pieces: MailPiece[] = [
    {
      id: "1",
      digestDate: "2026-07-22",
      senderHint: "Clinic",
      subjectHint: "Lab results",
      ocrText: "medical appointment",
      ocrSource: "textract",
      imageMissing: false,
      priority: "action_soon",
      category: "critical",
      subcategory: "medical",
      importanceSource: "rules",
      embeddingTokens: ["clinic", "lab", "results", "medical"],
      receivedAt: new Date().toISOString(),
    },
    {
      id: "2",
      digestDate: "2026-07-22",
      senderHint: "Promo Co",
      subjectHint: "Coupon book",
      ocrText: "sale coupon",
      ocrSource: "textract",
      imageMissing: true,
      priority: "promotional",
      category: "promotional",
      subcategory: "coupons",
      importanceSource: "rules",
      embeddingTokens: ["promo", "coupon", "sale"],
      receivedAt: new Date().toISOString(),
    },
  ];

  it("ranks by priority when query empty", () => {
    const r = searchMailPieces(pieces, "");
    expect(r[0].priority).toBe("action_soon");
  });

  it("finds medical mail via NL query", () => {
    const r = searchMailPieces(pieces, "urgent medical");
    expect(r.some(p => p.id === "1")).toBe(true);
  });

  it("finds missing image pieces", () => {
    const r = searchMailPieces(pieces, "missing image");
    expect(r[0].id).toBe("2");
  });
});

describe("taxonomy completeness", () => {
  it("defines all five well-being priorities", () => {
    expect(Object.keys(PRIORITY_META)).toHaveLength(5);
  });

  it("defines seven top-level categories", () => {
    expect(Object.keys(CATEGORY_META)).toHaveLength(7);
  });
});
