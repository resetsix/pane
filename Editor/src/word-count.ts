/*
 * The number in the footer.
 *
 * Counts include the first-line title. Intl.Segmenter supplies language-aware word boundaries and
 * visible-character boundaries, so Chinese does not need spaces and a combined emoji counts once.
 * Safari 17, the minimum WebKit target, supports it natively. Reuse the segmenters while typing.
 */

const wordSegmenter = new Intl.Segmenter(undefined, { granularity: "word" });
const characterSegmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });

/** Strips the markdown that would otherwise be counted as words. */
function toPlainText(markdown: string): string {
  return (
    markdown
      // Fenced code: keep the contents, drop the fences and any language tag.
      .replace(/^[ \t]*(`{3,}|~{3,}).*$/gm, "")
      // Block markers at the start of a line: heading hashes, quote arrows, bullets, numbers, tasks.
      .replace(/^[ \t]*>+[ \t]?/gm, "")
      .replace(/^[ \t]*#{1,6}[ \t]+/gm, "")
      .replace(/^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+(?:\[[ xX]\][ \t]+)?/gm, "")
      // Horizontal rules leave nothing behind.
      .replace(/^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$/gm, "")
      // Images and links collapse to their label.
      .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
      .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
      // Inline emphasis, code and strike markers.
      .replace(/(\*{1,3}|_{1,3}|~{1,2}|`+)/g, "")
      // Escapes: keep the character, drop the backslash.
      .replace(/\\([\\`*_{}[\]()#+\-.!~>])/g, "$1")
  );
}

/**
 * Characters of the note as it reads, which is the other half of the number in the footer.
 *
 * Over the same plain text `countWords` counts, for the same reason: markdown punctuation is not
 * something anybody typed *at* the note, and a count that moves when you make a word bold is
 * counting the wrong document.
 *
 * Spaces included, matching every word processor's "characters (with spaces)" — the count is a
 * measure of how much note there is, and a space is part of that. Line breaks are not: they are
 * structure rather than text, and a note broken into more paragraphs is not a longer one.
 */
export function countCharacters(markdown: string): number {
  const plain = toPlainText(markdown).replace(/[\r\n]/g, "");
  return Array.from(characterSegmenter.segment(plain)).length;
}

export function countWords(markdown: string): number {
  const plain = toPlainText(markdown);
  let count = 0;
  for (const segment of wordSegmenter.segment(plain)) {
    // Some WebKit versions mark numeric segments as non-word-like. Keep counting numbers,
    // including IP addresses and ports, using the boundaries Segmenter already supplied.
    if (segment.isWordLike || /\p{N}/u.test(segment.segment)) count++;
  }
  return count;
}
