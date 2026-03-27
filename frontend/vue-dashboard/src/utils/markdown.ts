import MarkdownIt from "markdown-it";

const markdown = new MarkdownIt({
  html: true,
  breaks: true,
  linkify: true,
});

type RenderMarkdownOptions = {
  /**
   * For streaming scenarios: the content may end mid-block (e.g. an unclosed code fence).
   * We try to "balance" common fences so the preview stays stable.
   */
  streaming?: boolean;
};

function balanceCodeFences(input: string): string {
  let text = String(input ?? "");

  // Balance triple-backtick fenced code blocks.
  const backtickCount = (text.match(/```/g) ?? []).length;
  if (backtickCount % 2 === 1) {
    text = text + "\n```\n";
  }

  // Balance triple-tilde fenced code blocks.
  const tildeCount = (text.match(/~~~/g) ?? []).length;
  if (tildeCount % 2 === 1) {
    text = `${text}\n~~~\n`;
  }

  return text;
}

/**
 * Normalizes common LLM markdown quirks, especially for tables.
 */
function normalizeMarkdown(input: string): string {
  let text = String(input ?? "");

  // 1. Remove emulated "horizontal lines" or extra dashes that often break table detection
  // if they are directly glued to the table pipe.
  // e.g. "-------------------|| 1 |" -> "\n\n| 1 |"
  text = text.replace(/^-{3,}(\|{1,2})/gm, "\n\n|");

  // 2. Ensure blank lines before and after tables, as markdown-it is strict about this.
  // Detect header row | ... | followed by separator | --- | ... |
  // We look for the pattern and put newlines before it.
  text = text.replace(/([^\n])\n(\|.*\|[ \t]*\n[ \t]*\|[ \t]*:?-+:?[ \t]*\|)/g, "$1\n\n$2");

  // 3. Fix double pipes at start of line which confuse standard parsers
  text = text.replace(/^\|\|/gm, "|");

  return text;
}

export function renderMarkdown(content: string, options: RenderMarkdownOptions = {}): string {
  const text = String(content ?? "");
  const trimmed = text.trim();
  if (!trimmed) return "";

  // Normalize before balancing fences
  let processed = normalizeMarkdown(trimmed);
  if (options.streaming) {
    processed = balanceCodeFences(processed);
  }

  return markdown.render(processed);
}
