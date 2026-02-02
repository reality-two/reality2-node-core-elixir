const REPO = "reality-two/reality2-definitions";
const RAW_BASE = `https://raw.githubusercontent.com/${REPO}/main`;
const API_BASE = `https://api.github.com/repos/${REPO}/contents`;

export interface LibraryEntry {
  name: string;
  shortName: string;
  description: string;
  format: "yaml" | "json";
}

export interface LibraryCategory {
  dir: string;
  label: string;
  extension: string;
}

export const LIBRARY_CATEGORIES: LibraryCategory[] = [
  { dir: "bees", label: "Bees", extension: "bee" },
  { dir: "swarms", label: "Swarms", extension: "swarm" },
  { dir: "antennae", label: "Antennae", extension: "antenna" },
  { dir: "behaviours", label: "Behaviours", extension: "behaviour" },
];

async function fetchText(url: string): Promise<string> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Fetch failed: ${res.status} ${res.statusText}`);
  return res.text();
}

// Cache of filename → format per category, so we only fetch the right URL
const fileFormatCache = new Map();

async function getFileFormats(category: LibraryCategory): Promise<Map<string, "yaml" | "json">> {
  const key = category.dir;
  if (fileFormatCache.has(key)) return fileFormatCache.get(key);

  const formats = new Map();
  try {
    const res = await fetch(`${API_BASE}/${category.dir}`);
    if (res.ok) {
      const files = await res.json();
      for (const f of files) {
        const name = f.name as string;
        const ext = `.${category.extension}`;
        if (name.endsWith(`${ext}.yaml`)) {
          const short = name.slice(0, -(ext.length + 5)); // remove .ext.yaml
          formats.set(short, "yaml");
        } else if (name.endsWith(`${ext}.json`) && !formats.has(name.slice(0, -(ext.length + 5)))) {
          const short = name.slice(0, -(ext.length + 5)); // remove .ext.json
          formats.set(short, "json");
        }
      }
    }
  } catch {
    // Fall back to trying both on fetch
  }
  fileFormatCache.set(key, formats);
  return formats;
}

export async function getLibraryEntries(category: LibraryCategory): Promise<LibraryEntry[]> {
  // Fetch info.json and file listing in parallel
  const [infoText, formats] = await Promise.all([
    fetchText(`${RAW_BASE}/${category.dir}/info.json`),
    getFileFormats(category),
  ]);
  const info = JSON.parse(infoText);

  const entries: LibraryEntry[] = [];
  for (const [shortName, meta] of Object.entries<any>(info)) {
    entries.push({
      name: meta?.name || shortName,
      shortName,
      description: meta?.description || "",
      format: formats.get(shortName) || "yaml",
    });
  }

  return entries.sort((a, b) => a.name.localeCompare(b.name));
}

export async function getDefinitionContent(
  category: LibraryCategory,
  entry: LibraryEntry
): Promise<{ content: string; format: "yaml" | "json" }> {
  // Use the known format to fetch directly — no 404s
  const ext = entry.format === "json" ? "json" : "yaml";
  const url = `${RAW_BASE}/${category.dir}/${entry.shortName}.${category.extension}.${ext}`;
  const res = await fetch(url);
  if (res.ok) {
    return { content: await res.text(), format: entry.format };
  }

  // Fallback: try the other format
  const altExt = ext === "yaml" ? "json" : "yaml";
  const altUrl = `${RAW_BASE}/${category.dir}/${entry.shortName}.${category.extension}.${altExt}`;
  const altRes = await fetch(altUrl);
  if (altRes.ok) {
    return { content: await altRes.text(), format: altExt as "yaml" | "json" };
  }

  throw new Error(`Definition not found: ${entry.shortName}`);
}
