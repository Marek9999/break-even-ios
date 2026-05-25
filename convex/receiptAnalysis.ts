import { v } from "convex/values";
import { action } from "./_generated/server";

const GEMINI_MODEL = "gemini-2.5-flash";
const GEMINI_ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

const receiptItemValidator = v.object({
  name: v.string(),
  quantity: v.number(),
  unitPrice: v.number(),
});

const receiptAnalysisValidator = v.object({
  isReceipt: v.optional(v.boolean()),
  merchantName: v.optional(v.string()),
  emoji: v.optional(v.string()),
  items: v.optional(v.array(receiptItemValidator)),
  subtotal: v.optional(v.number()),
  tax: v.optional(v.number()),
  tip: v.optional(v.number()),
  total: v.optional(v.number()),
  date: v.optional(v.string()),
});

type ReceiptItem = {
  name: string;
  quantity: number;
  unitPrice: number;
};

type ReceiptAnalysis = {
  isReceipt?: boolean;
  merchantName?: string;
  emoji?: string;
  items?: ReceiptItem[];
  subtotal?: number;
  tax?: number;
  tip?: number;
  total?: number;
  date?: string;
};

function extractJson(text: string): string {
  const startIndex = text.indexOf("{");
  const endIndex = text.lastIndexOf("}");

  if (startIndex === -1 || endIndex === -1 || endIndex < startIndex) {
    return text;
  }

  return text.slice(startIndex, endIndex + 1);
}

function numberOrUndefined(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }

  return undefined;
}

function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;
}

function normalizeReceiptAnalysis(value: unknown): ReceiptAnalysis {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Gemini response was not a receipt object");
  }

  const record = value as Record<string, unknown>;
  const items = Array.isArray(record.items)
    ? record.items.map((item): ReceiptItem => {
        const itemRecord =
          item && typeof item === "object" && !Array.isArray(item)
            ? (item as Record<string, unknown>)
            : {};

        return {
          name: stringOrUndefined(itemRecord.name) ?? "Unknown Item",
          quantity: numberOrUndefined(itemRecord.quantity) ?? 1,
          unitPrice: numberOrUndefined(itemRecord.unitPrice) ?? 0,
        };
      })
    : undefined;

  return {
    isReceipt: typeof record.isReceipt === "boolean" ? record.isReceipt : undefined,
    merchantName: stringOrUndefined(record.merchantName),
    emoji: stringOrUndefined(record.emoji),
    items,
    subtotal: numberOrUndefined(record.subtotal),
    tax: numberOrUndefined(record.tax),
    tip: numberOrUndefined(record.tip),
    total: numberOrUndefined(record.total),
    date: stringOrUndefined(record.date),
  };
}

export const analyzeReceipt = action({
  args: {
    imageBase64: v.string(),
    mimeType: v.optional(v.string()),
  },
  returns: receiptAnalysisValidator,
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (!identity) {
      throw new Error("Not authenticated");
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      throw new Error("GEMINI_API_KEY is not configured");
    }

    const requestBody = {
      contents: [
        {
          parts: [
            {
              text: `
Look at this image. First determine if it is a receipt, invoice, or bill of any kind.

If the image is NOT a receipt/invoice/bill, return ONLY this JSON and nothing else:
{"isReceipt": false}

If the image IS a receipt/invoice/bill, extract the information in JSON format following these rules:

IMPORTANT RULES:
1. Return ONLY valid JSON, no markdown, no code blocks, no explanations
2. All prices must be numbers (not strings), without currency symbols
3. quantity must be a number (can be decimal like 1.0)
4. If you cannot read a value, use these defaults:
   - merchantName: "Receipt"
   - emoji: "🧾"
   - items: [] (empty array)
   - quantity: 1
   - unitPrice: 0
   - subtotal: 0
   - tax: 0
   - tip: 0
   - total: 0
   - date: "" (empty string)
5. NEVER use null - use empty string "" or 0 instead
6. emoji must be a single emoji that best represents the merchant or category (e.g. 🍕 for pizza, 🛒 for grocery, ☕ for coffee shop, 🍺 for bar, ⛽ for gas station, 💊 for pharmacy)

Expected JSON structure:
{
  "isReceipt": true,
  "merchantName": "Store Name",
  "emoji": "🛒",
  "items": [
    {
      "name": "Item description",
      "quantity": 1,
      "unitPrice": 9.99
    }
  ],
  "subtotal": 9.99,
  "tax": 0.80,
  "tip": 0,
  "total": 10.79,
  "date": "2025-01-18"
}

Now analyze the image and return the JSON:
              `.trim(),
            },
            {
              inline_data: {
                mime_type: args.mimeType ?? "image/jpeg",
                data: args.imageBase64,
              },
            },
          ],
        },
      ],
    };

    const response = await fetch(`${GEMINI_ENDPOINT}?key=${apiKey}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody),
    });

    const responseText = await response.text();

    if (!response.ok) {
      throw new Error(`Gemini API error (${response.status}): ${responseText}`);
    }

    let geminiResponse: unknown;
    try {
      geminiResponse = JSON.parse(responseText);
    } catch {
      throw new Error("Failed to parse Gemini API response");
    }

    const textContent = (
      geminiResponse as {
        candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
      }
    ).candidates?.[0]?.content?.parts?.[0]?.text;

    if (!textContent) {
      throw new Error("No content in Gemini response");
    }

    let parsedReceipt: unknown;
    try {
      parsedReceipt = JSON.parse(extractJson(textContent));
    } catch {
      throw new Error("Failed to parse receipt JSON from Gemini response");
    }

    const receipt = normalizeReceiptAnalysis(parsedReceipt);
    if (receipt.isReceipt === false) {
      throw new Error("The image does not appear to be a receipt");
    }

    return receipt;
  },
});
