import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("background opacity is adjustable", () => {
  assert.match(source, /function Addon\.GetOpacity\(\)/);
  assert.match(source, /function Addon\.SetOpacity\(value\)/);
  assert.match(source, /WordHunterWoWDB\.settings\.opacity/);
  assert.match(source, /opacityLabel/);
  assert.match(source, /WordHunterWoWOpacitySlider/);
  assert.match(source, /SetMinMaxValues\(0, 1\.0\)/);
});

test("opacity is applied to all backdrops", () => {
  assert.match(source, /local alpha = alphaOverride or Addon\.GetOpacity\(\)/);
  assert.match(source, /frame:SetBackdropColor\(c\[1\], c\[2\], c\[3\], alpha\)/);
});

test("slash command handles opacity", () => {
  assert.match(source, /command:match\("\^opacity/);
  assert.match(source, /Addon\.SetOpacity\(val\)/);
});

test("integrated quest window setting exists", () => {
  assert.match(source, /function Addon\.GetIntegratedLayout\(\)/);
  assert.match(source, /function Addon\.SetIntegratedLayout\(value\)/);
  assert.match(source, /integratedLayout/);
  assert.match(source, /function Addon\.ApplyIntegratedLayout\(\)/);
  assert.match(source, /WordHunterWoWIntegratedCheck/);
});

test("target language is selectable for European locales", () => {
  assert.match(source, /SUPPORTED_LOCALES/);
  assert.match(source, /SUPPORTED_LOCALE_LIST/);
  assert.match(source, /WH_LANGUAGE_MAP/);
  assert.match(source, /function Addon\.GetTargetLocale\(\)/);
  assert.match(source, /function Addon\.SetTargetLocale\(locale\)/);
  assert.match(source, /WordHunterWoWLanguage/);
  assert.match(source, /WordHunterWoWLanguageDropdown/);
  assert.match(source, /command:match\("\^lang/);
});
