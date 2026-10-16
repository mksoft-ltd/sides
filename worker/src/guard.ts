// Port of pipeline/sides_pipeline/guard.py (SEC-1): model-written text that carries a URL, an @handle or an
// instruction-shaped phrase is dropped. Keep the patterns in step with guard.py.

const URL_RE =
  /(?:\bhttps?:\/\/|\bwww\.|\b[a-z0-9-]{2,}\.(?:com|org|net|io|ai|co|uk|ru|cn|info|xyz|ly|me|tv|news|gov)(?:\/|\b))/i;
const HANDLE_RE = /(?<![\w.])@[A-Za-z0-9_]{2,}/;
const INSTRUCTION_RE = new RegExp(
  [
    String.raw`\b(?:ignore|disregard|forget|override)\W+(?:(?:all|any|the|your|of|these)\W+){0,3}(?:previous|prior|above|earlier|preceding|system)\W+(?:\w+\W+){0,2}?(?:instructions?|prompts?|rules|directions|messages|context)\b`,
    String.raw`\bsystem\s+prompt\b`,
    String.raw`\bdeveloper\s+message\b`,
    String.raw`\bas\s+an?\s+(?:ai\s+(?:language\s+)?model|large\s+language\s+model|language\s+model|llm)\b`,
    String.raw`\byou\s+are\s+now\s+(?:an?|the|my)\s+\w+`,
    String.raw`\byou\s+are\s+(?:an?\s+)?(?:ai\s+model|chatgpt|claude|gpt|llm|language\s+model)\b`,
    String.raw`\bsummari[sz]e\s+this\s+(?:as|story\s+as)\b`,
    String.raw`\b(?:all|every)\s+(?:outlets|sources)\s+(?:agree|confirm)\b`,
    String.raw`<\/?\s*(?:system|instructions?|articles?|assistant|user)\s*>`,
    String.raw`^\s*(?:assistant|system|user)\s*:`,
  ].join("|"),
  "im",
);

/** "url" / "handle" / "instruction" when the text should not reach a reader, else null. */
export function suspectText(text: string): "url" | "handle" | "instruction" | null {
  if (!text) return null;
  if (URL_RE.test(text)) return "url";
  if (HANDLE_RE.test(text)) return "handle";
  if (INSTRUCTION_RE.test(text)) return "instruction";
  return null;
}
