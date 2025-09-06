// Minimal taxonomy. Add more leaves/parents/aliases over time (or load from /categories).
const ALIAS_TO_CANON: Record<string, string> = {
  'logo_design': 'logo_branding',
  'logo&branding': 'logo_branding',
  'branding_logo': 'logo_branding',
  'math_tutor': 'tutoring_math',
  'maths_tutor': 'tutoring_math',
  'mathematics_tutor': 'tutoring_math',
};

const PARENT_OF: Record<string, string> = {
  'tutoring_math': 'tutoring',
  'tutoring_physics': 'tutoring',
  'logo_branding': 'design',
  // …
};

function slugify(raw?: string | null): string {
  if (!raw) return '';
  return raw.toLowerCase()
    .normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '_').replace(/_{2,}/g, '_')
    .replace(/^_|_$/g, '');
}

export function normalizeCategoryId(raw?: string | null): string {
  const s = slugify(raw);
  return ALIAS_TO_CANON[s] ?? s;
}

export function computeMetaForCategories(rawIds?: unknown) {
  // Accept: string | string[] | null
  const list = Array.isArray(rawIds) ? rawIds as string[] : (rawIds ? [String(rawIds)] : []);
  const canon = new Set<string>();
  const roots = new Set<string>();
  const tokens = new Set<string>();

  for (const r of list) {
    const c = normalizeCategoryId(r);
    if (!c) continue;
    canon.add(c);

    const root = PARENT_OF[c] ?? c;
    roots.add(root);

    tokens.add(c);
    tokens.add(root);
    // include aliases that map to this canonical id
    Object.entries(ALIAS_TO_CANON).forEach(([alias, target]) => {
      if (target === c) tokens.add(alias);
    });
  }

  // Fallbacks for single-category tasks (legacy)
  if (canon.size === 0) {
    const c = normalizeCategoryId(null);
    if (c) { canon.add(c); roots.add(PARENT_OF[c] ?? c); tokens.add(c); }
  }

  return {
    categoryIds: Array.from(canon),           // new: array
    categoryRootIds: Array.from(roots),       // new: array
    categoryTokens: Array.from(tokens),       // union for matching
    categoryId: Array.from(canon)[0] ?? null, // keep legacy single field (optional)
  };
}
