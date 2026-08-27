import { readFileSync, readdirSync } from "node:fs";

export const source = readdirSync(new URL("..", import.meta.url))
  .filter((name) => name.endsWith(".lua"))
  .sort()
  .map((name) => readFileSync(new URL(`../${name}`, import.meta.url), "utf8"))
  .join("\n");
